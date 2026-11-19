class_name WorldData
extends RefCounted
## The voxel world: infinite chunked terrain generation, editing, lighting, voxel raycasts
## and saving. A faithful port of world.py — the same seed generates the same world, and
## save files use the same format.
##
## Each chunk is a flat PackedInt32Array of block ids (16 x 64 x 16), index (lx*64 + y)*16 + lz.

const CS := 16
const H := 64
const WATER := 10
const NEIGHBOURS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Block ids of one chunk. Wrapped in an object so edits change the array in place
## (a PackedInt32Array taken out of a Dictionary would be copied on every write).
class Chunk:
	var b := PackedInt32Array()

	func _init() -> void:
		b.resize(16 * 64 * 16)


var seed: int
var chunks := {}            # Vector2i -> Chunk
var changes := {}           # Vector2i -> {Vector3i: id} player edits, re-applied when a chunk regenerates
var containers := {}        # Vector3i -> Array of slots (chests)
var emitters := {}          # Vector2i -> {Vector3i: true} light-emitting blocks per chunk
var time_of_day := 0.2
var player_data := {}
var _climate := {}          # Vector2i -> [height, desert, tree, kind, forest]
var _columns := {}          # Vector2i -> [PackedInt32Array top, PackedInt32Array water_top]

var WATER_LEVEL: int
var SNOW_LINE: int
var TREE_CHANCE: float
var CAVE_THRESHOLD: float
var CAVE_GRID: int
var TREE_KINDS: Array          # kind index -> name ("oak", "birch", "pine", "maple", ...)
var TREES: Array               # kind index -> [log, leaves, trunk height, [[dy, radius, reach], ...]]
var FLOWERS: Array
var ORE_LIMIT: float
var G := {}
var ORES: Array                # private copies, so a generation thread shares nothing
var TRANSPARENT: PackedByteArray                    # generation block ids (SLATE, LIMESTONE, bushes, ...)


func _init(world_seed: int = -1) -> void:
	seed = world_seed if world_seed >= 0 else randi() % 1000000
	WATER_LEVEL = int(Blocks.C["WATER_LEVEL"])
	SNOW_LINE = int(Blocks.C["SNOW_LINE"])
	TREE_CHANCE = float(Blocks.C["TREE_CHANCE"])
	CAVE_THRESHOLD = float(Blocks.C["CAVE_THRESHOLD"])
	CAVE_GRID = int(Blocks.C["CAVE_GRID"])
	TREE_KINDS = Blocks.C["TREE_KINDS"].duplicate(true)
	ORES = Blocks.ores.duplicate(true)
	TRANSPARENT = Blocks.transparent.duplicate()
	TREES = []
	for kind in TREE_KINDS:
		var t = Blocks.C["TREES"][kind]
		var layers := []
		for l in t[3]:
			layers.append([int(l[0]), int(l[1]), int(l[2])])
		TREES.append([int(t[0]), int(t[1]), int(t[2]), layers])
	FLOWERS = Blocks.C["FLOWERS"].map(func(v): return int(v))
	ORE_LIMIT = float(Blocks.ores[Blocks.ores.size() - 1][1])
	for k in Blocks.C["GEN_IDS"]:
		G[k] = int(Blocks.C["GEN_IDS"][k])


# ---------------------------------------------------------------- access
static func chunk_key(x: int, z: int) -> Vector2i:
	return Vector2i(x >> 4, z >> 4)


static func _index(x: int, y: int, z: int) -> int:
	return ((x & 15) * H + y) * CS + (z & 15)


func get_block(x: int, y: int, z: int) -> int:
	if y < 0 or y >= H:
		return 0
	var c = chunks.get(Vector2i(x >> 4, z >> 4))
	if c == null:
		return 0
	return c.b[_index(x, y, z)]


func is_loaded(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x >> 4, z >> 4))


func _put(x: int, y: int, z: int, id: int) -> void:
	var key := Vector2i(x >> 4, z >> 4)
	var c: Chunk = chunks[key]
	var i := _index(x, y, z)
	var old := c.b[i]
	c.b[i] = id
	if Blocks.emit[old] or Blocks.emit[id]:
		var e: Dictionary = emitters.get(key, {})
		if Blocks.emit[id]:
			e[Vector3i(x, y, z)] = true
		else:
			e.erase(Vector3i(x, y, z))
		emitters[key] = e


## Player edit. Returns the loaded chunk keys whose mesh must be rebuilt.
## force: allow removing unbreakable blocks. flood: let water flow into the gap.
func set_block(x: int, y: int, z: int, id: int, force := false, flood := true) -> Array:
	if y < 0 or y >= H or not is_loaded(x, z):
		return []
	var old := get_block(x, y, z)
	if id == 0 and Blocks.hardness[old] < 0 and not force:
		return []
	_edit(x, y, z, id)
	var touched := [Vector3i(x, y, z)]
	if id == 0:
		var door = Blocks.defs.get(old, {}).get("door")
		if door != null:                  # a door is two blocks: remove the other half too
			var oy := y - 1 if door["top"] else y + 1
			if Blocks.defs.get(get_block(x, oy, z), {}).has("door"):
				_edit(x, oy, z, 0)
				touched.append(Vector3i(x, oy, z))
		var ay := y + 1                   # plants, torches, cactus and reeds need something below
		while ay < H and (Blocks.plants_need_soil.has(get_block(x, ay, z)) or get_block(x, ay, z) in [50, 60]):
			_edit(x, ay, z, 0)
			touched.append(Vector3i(x, ay, z))
			ay += 1
		if flood:
			touched += _flood(Vector3i(x, y, z))
	return _keys_around(touched)


func _keys_around(cells: Array) -> Array:
	var keys := {}
	for c in cells:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var k := chunk_key(c.x + d.x, c.z + d.y)
			if chunks.has(k):
				keys[k] = true
	return keys.keys()


func _edit(x: int, y: int, z: int, id: int) -> void:
	_put(x, y, z, id)
	var key := chunk_key(x, z)
	_columns.erase(key)
	var edits: Dictionary = changes.get(key, {})
	edits[Vector3i(x, y, z)] = id
	changes[key] = edits


## Apply many edits at once (building tools). Returns [chunk keys, {pos: previous id}].
func bulk_set(edits: Dictionary) -> Array:
	var previous := {}
	for pos in edits:
		if pos.y < 0 or pos.y >= H or not is_loaded(pos.x, pos.z):
			continue
		var old := get_block(pos.x, pos.y, pos.z)
		if old == edits[pos]:
			continue
		previous[pos] = old
		_edit(pos.x, pos.y, pos.z, edits[pos])
	return [_keys_around(previous.keys()), previous]


## Let water flow into a freshly emptied space (sideways and down, never up).
func _flood(start: Vector3i, limit := 64) -> Array:
	var wet := false
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
		var n: Vector3i = start + d
		if get_block(n.x, n.y, n.z) == WATER:
			wet = true
	if not wet:
		return []
	var filled := []
	var queue := [start]
	while not queue.is_empty() and filled.size() < limit:
		var p: Vector3i = queue.pop_front()
		if get_block(p.x, p.y, p.z) != 0 or not is_loaded(p.x, p.z) or p.y <= 0 or p.y >= H:
			continue
		_edit(p.x, p.y, p.z, WATER)
		filled.append(p)
		queue += [p + Vector3i(0, -1, 0), p + Vector3i(1, 0, 0), p + Vector3i(-1, 0, 0), p + Vector3i(0, 0, 1), p + Vector3i(0, 0, -1)]
	return filled


func solid_at(x: int, y: int, z: int) -> bool:
	if not is_loaded(x, z):
		return true
	var b := get_block(x, y, z)
	return b != 0 and Blocks.solid[b] == 1


# ---------------------------------------------------------------- generation
func _column_climate(x: int, z: int) -> Array:
	var key := Vector2i(x, z)
	var cached = _climate.get(key)
	if cached != null:
		return cached
	var hills := VNoise.fbm(x / 28.0, z / 28.0, seed)
	var m := VNoise.fbm(x / 90.0, z / 90.0, seed + 7)
	var mountains := m * m
	var h := int(3 + hills * 12 + mountains * 22)
	var desert := h > WATER_LEVEL + 1 and h < SNOW_LINE - 3 and VNoise.fbm(x / 140.0, z / 140.0, seed + 31, 2) > 0.6
	var forest := VNoise.fbm(x / 60.0, z / 60.0, seed + 41, 2)
	var tree := not desert and h > WATER_LEVEL and VNoise.hash2(x, z, seed + 777) < TREE_CHANCE * (0.6 + 1.6 * forest)
	var kind := 0                                   # index into TREE_KINDS: 0 oak, 1 birch, 2 pine, ...
	if h >= SNOW_LINE - 3:
		kind = 2
	elif tree:
		kind = TREE_KINDS.find(_tree_species(x, z, h, forest))
	if _climate.size() > 400000:
		_climate.clear()
	var result := [h, desert, tree, kind, forest]
	_climate[key] = result
	return result


## Which broadleaf tree grows here (port of World._tree_species).
func _tree_species(x: int, z: int, h: int, forest: float) -> String:
	if h > WATER_LEVEL + 1 and h < SNOW_LINE - 3 and VNoise.fbm(x / 140.0, z / 140.0, seed + 31, 2) > 0.47:
		return "ashwood"
	if forest > 0.6 and VNoise.hash2(x, z, seed + 779) < 0.55:
		return "ebony"
	if VNoise.fbm(x / 50.0, z / 50.0, seed + 43, 2) > 0.56:
		return "birch"
	var patch := VNoise.fbm(x / 64.0, z / 64.0, seed + 47, 2)
	if patch > 0.58:
		return "maple"
	if patch < 0.4:
		return "cherry"
	return "oak"


func height_at(x: int, z: int) -> int:
	return _column_climate(x, z)[0]


func has_tree(x: int, z: int) -> bool:
	return _column_climate(x, z)[2]


## Generate a chunk (and re-apply the player's edits in it) if it isn't loaded.
func ensure_chunk(key: Vector2i) -> bool:
	if chunks.has(key):
		return false
	chunks[key] = Chunk.new()
	var x0 := key.x * CS
	var z0 := key.y * CS
	var surface := []
	for x in range(x0, x0 + CS):
		for z in range(z0, z0 + CS):
			var cl := _column_climate(x, z)
			var h: int = cl[0]
			var desert: bool = cl[1]
			var beach := h <= WATER_LEVEL + 1
			var snowy := h >= SNOW_LINE
			var top_block := 1
			var filler := 2
			if desert:
				top_block = 6
				filler = 6
			elif beach:
				top_block = 6
				filler = 6
				if h < WATER_LEVEL - 1:              # sea floor: patches of clay and gravel
					var r := VNoise.hash2(x >> 2, z >> 2, seed + 61)
					top_block = 15 if r < 0.25 else (14 if r < 0.4 else 6)
					filler = top_block
			else:
				top_block = 16 if snowy else 1
			for y in range(h + 1):
				var b: int
				if y == 0:
					b = 9
				elif y < h - 3:
					b = 20 if (desert and y >= h - 6) else _rock(x, y, z)
				elif y < h:
					b = filler
				else:
					b = top_block
				_put(x, y, z, b)
			for y in range(h + 1, WATER_LEVEL + 1):
				_put(x, y, z, WATER)
			surface.append([x, z, h, top_block, desert])
	_carve_caves(key)
	_plants(surface)
	# trees near the border overlap neighbouring chunks; each chunk keeps only its part
	for tx in range(x0 - 2, x0 + CS + 2):
		for tz in range(z0 - 2, z0 + CS + 2):
			if has_tree(tx, tz):
				_tree(tx, height_at(tx, tz) + 1, tz, key, _column_climate(tx, tz)[3])
	var edits: Dictionary = changes.get(key, {})
	for pos in edits:
		_put(pos.x, pos.y, pos.z, edits[pos])
	return true


## Underground block: stone with patches of other rock, and ore clusters by depth.
func _rock(x: int, y: int, z: int) -> int:
	var r := VNoise.hash3(x >> 1, y >> 1, z >> 1, seed + 55)
	if r < ORE_LIMIT:
		for ore in ORES:
			if r < float(ore[1]):
				if y <= int(ore[2]) and VNoise.hash3(x, y, z, seed + 56) < 0.6:
					return int(ore[0])
				break
	var v := VNoise.hash3(x >> 3, y >> 2, z >> 3, seed + 71)
	if v < 0.08:
		return 18
	if v < 0.15 and y < 20:
		return 19
	if v < 0.19:
		return 21
	if v < 0.25 and y > 14:
		return G["LIMESTONE"]
	if y < 4 + int(VNoise.hash2(x, z, seed + 81) * 3):
		return G["SLATE"]
	return 3


func _carve_caves(key: Vector2i) -> void:
	var g := CAVE_GRID
	var x0 := key.x * CS
	var z0 := key.y * CS
	var cols := PackedInt32Array()
	cols.resize(CS * CS)
	var ymax := -999
	for lx in CS:
		for lz in CS:
			var x := x0 + lx
			var z := z0 + lz
			var h := height_at(x, z)
			var top := h
			if h <= WATER_LEVEL + 2:
				top = h - 4                       # keep a roof under the sea and lakes
			elif has_tree(x, z):
				top = h - 1                       # and under tree trunks
			cols[lx * CS + lz] = top
			ymax = maxi(ymax, top)
	if ymax < 1:
		return
	var n := CS / g
	var ny := ymax / g + 2
	var grid := PackedFloat64Array()
	grid.resize((n + 1) * ny * (n + 1))
	for i in n + 1:
		for k in n + 1:
			for j in ny:
				grid[(i * ny + j) * (n + 1) + k] = VNoise.cave_density(x0 + i * g, j * g, z0 + k * g, seed)
	var c := PackedFloat64Array()
	c.resize(8)
	for i in n:
		for k in n:
			for j in ymax / g + 1:
				var lowest := 1e9
				for a in 2:
					for b in 2:
						for d in 2:
							var value := grid[((i + a) * ny + j + b) * (n + 1) + k + d]
							c[a * 4 + b * 2 + d] = value
							lowest = minf(lowest, value)
				if lowest >= CAVE_THRESHOLD:
					continue                          # interpolation never goes below the lowest corner
				for lx in g:
					var fx := lx / float(g)
					for ly in g:
						var y := j * g + ly
						if y < 1:
							continue
						var fy := ly / float(g)
						for lz in g:
							var x := x0 + i * g + lx
							var z := z0 + k * g + lz
							if y > cols[(i * g + lx) * CS + k * g + lz]:
								continue
							var fz := lz / float(g)
							var c00 := c[0] + (c[1] - c[0]) * fz
							var c01 := c[2] + (c[3] - c[2]) * fz
							var c10 := c[4] + (c[5] - c[4]) * fz
							var c11 := c[6] + (c[7] - c[6]) * fz
							var c0 := c00 + (c01 - c00) * fy
							var c1 := c10 + (c11 - c10) * fy
							if c0 + (c1 - c0) * fx < CAVE_THRESHOLD:
								_put(x, y, z, 0)


## Grass tufts, flowers, ferns, mushrooms, reeds by the water and cacti in deserts.
func _plants(surface: Array) -> void:
	var flowers := FLOWERS
	for s in surface:
		var x: int = s[0]
		var z: int = s[1]
		var h: int = s[2]
		var top_block: int = s[3]
		var desert: bool = s[4]
		var y := h + 1
		if get_block(x, h, z) != top_block or get_block(x, y, z) != 0 or has_tree(x, z):
			continue
		var r := VNoise.hash2(x, z, seed + 91)
		if desert:
			if r < 0.012:
				for dy in 1 + int(VNoise.hash2(x, z, seed + 92) * 3):
					_put(x, y + dy, z, 60)
			elif r < 0.03:
				_put(x, y, z, G["DRY_BUSH"])
			continue
		if top_block == 6 and h == WATER_LEVEL + 1 and r < 0.25:
			var near_water := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if height_at(x + d.x, z + d.y) <= WATER_LEVEL:
					near_water = true
			if near_water:
				for dy in 1 + int(VNoise.hash2(x, z, seed + 93) * 3):
					_put(x, y + dy, z, 59)
			continue
		if top_block != 1:
			continue
		var forest: float = _column_climate(x, z)[4]
		if r < 0.10:
			_put(x, y, z, 51)
		elif r < 0.135:
			# flowers grow in patches of one kind, with a few strays of any kind
			var pick := VNoise.hash2(x >> 3, z >> 3, seed + 96) if VNoise.hash2(x, z, seed + 94) < 0.75 else VNoise.hash2(x, z, seed + 97)
			_put(x, y, z, flowers[int(pick * flowers.size())])
		elif r < 0.135 + 0.05 * forest:
			_put(x, y, z, 52)
		elif r < 0.14 + 0.05 * forest and forest > 0.5:
			_put(x, y, z, 57 if VNoise.hash2(x, z, seed + 95) < 0.4 else 58)
		elif r < 0.155 + 0.05 * forest:
			_put(x, y, z, G["BERRY_BUSH"] if VNoise.hash2(x, z, seed + 98) < 0.3 else G["LEAFY_BUSH"])
		elif r < 0.16 + 0.05 * forest and forest < 0.45:
			_put(x, y, z, G["PUMPKIN"] if VNoise.hash2(x, z, seed + 99) < 0.5 else G["MELON"])


func _tree(x: int, y: int, z: int, key: Vector2i, kind: int) -> void:
	if kind == 2:                                     # pine: tall and cone shaped
		for dy in 6:
			_tree_put(x, y + dy, z, 38, key)
		for layer in [[2, 2], [3, 2], [4, 1], [5, 1], [6, 1], [7, 0]]:
			var r: int = layer[1]
			for dx in range(-r, r + 1):
				for dz in range(-r, r + 1):
					if absi(dx) + absi(dz) <= r + (1 if r == 2 else 0):
						_tree_put(x + dx, y + layer[0], z + dz, 40, key)
		return
	var t: Array = TREES[kind]
	var log_id: int = t[0]
	var leaves: int = t[1]
	for dy in int(t[2]):
		_tree_put(x, y + dy, z, log_id, key)
	for layer in t[3]:                               # [height, radius, max |dx| + |dz|]
		var r: int = layer[1]
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) + absi(dz) <= layer[2]:
					_tree_put(x + dx, y + layer[0], z + dz, leaves, key)


func _tree_put(x: int, y: int, z: int, id: int, key: Vector2i) -> void:
	if chunk_key(x, z) == key and y < H and get_block(x, y, z) in [0, WATER, 51, 52]:
		_put(x, y, z, id)


func unload_chunk(key: Vector2i) -> void:
	chunks.erase(key)
	emitters.erase(key)
	_columns.erase(key)


func top_y(x: int, z: int) -> int:
	ensure_chunk(chunk_key(x, z))
	for y in range(H - 1, -1, -1):
		if get_block(x, y, z) != 0:
			return y
	return 0


func spawn_point() -> Vector3:
	return Vector3(8, top_y(8, 8) + 1.5, 8)


# ---------------------------------------------------------------- lighting
## Per column: highest light-blocking block and highest water block (-1 if none).
func column_info(key: Vector2i) -> Array:
	var info = _columns.get(key)
	if info != null:
		return info
	var tops := PackedInt32Array()
	var waters := PackedInt32Array()
	tops.resize(CS * CS)
	waters.resize(CS * CS)
	var data: PackedInt32Array = chunks[key].b
	for lx in CS:
		for lz in CS:
			var top := -1
			var water := -1
			for y in range(H - 1, -1, -1):
				var b := data[(lx * H + y) * CS + lz]
				if b == 0:
					continue
				if b == WATER:
					water = maxi(water, y)
				elif TRANSPARENT[b] == 0:
					top = y
					break
			tops[lx * CS + lz] = top
			waters[lx * CS + lz] = water
	info = [tops, waters]
	_columns[key] = info
	return info


static func open_sky(y: int, water_top: int) -> int:
	if y > water_top:
		return 15
	return maxi(15 - 2 * (water_top - y + 1), 2)


# ---------------------------------------------------------------- raycast
## Walk the voxel grid (DDA). Returns {"pos": Vector3i, "normal": Vector3i, "distance": float}
## for the first block hit, or an empty Dictionary.
func raycast(origin: Vector3, direction: Vector3, max_distance := 6.0, hit_water := false) -> Dictionary:
	var o := origin + Vector3(0.5, 0.5, 0.5)            # blocks are centred on integers
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for a in 3:
		if direction[a] > 0:
			step[a] = 1
			t_max[a] = (floorf(o[a]) + 1.0 - o[a]) / direction[a]
			t_delta[a] = 1.0 / direction[a]
		elif direction[a] < 0:
			step[a] = -1
			t_max[a] = (o[a] - floorf(o[a])) / -direction[a]
			t_delta[a] = -1.0 / direction[a]
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_distance:
		var b := get_block(cell.x, cell.y, cell.z)
		if b != 0 and (b != WATER or hit_water):
			return {"pos": cell, "normal": normal, "distance": t}
		var a := 0
		if t_max.y < t_max[a]:
			a = 1
		if t_max.z < t_max[a]:
			a = 2
		t = t_max[a]
		t_max[a] += t_delta[a]
		cell[a] += step[a]
		normal = Vector3i.ZERO
		normal[a] = -step[a]
	return {}


# ---------------------------------------------------------------- saving (same format as world.py)
func save(path: String, player := {}) -> void:
	var edits := []
	for key in changes:
		for p in changes[key]:
			edits.append([p.x, p.y, p.z, changes[key][p]])
	var boxes := []
	for p in containers:
		boxes.append([[p.x, p.y, p.z], containers[p]])
	var data := {"player": player, "version": 3, "seed": seed, "time_of_day": time_of_day,
		"containers": boxes, "changes": edits}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


static func load_from(path: String) -> WorldData:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var w := WorldData.new(int(data["seed"]))
	w.time_of_day = float(data.get("time_of_day", 0.2))
	w.player_data = data.get("player", {})
	for c in data.get("containers", []):
		w.containers[Vector3i(int(c[0][0]), int(c[0][1]), int(c[0][2]))] = c[1]
	for e in data["changes"]:
		var p := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		var key := chunk_key(p.x, p.z)
		var edits: Dictionary = w.changes.get(key, {})
		edits[p] = int(e[3])
		w.changes[key] = edits
	return w


## [top solid y, water surface y] of a loaded column, or null if its chunk isn't loaded.
func column(x: int, z: int):
	var key := chunk_key(x, z)
	if not chunks.has(key):
		return null
	var info := column_info(key)
	return [info[0][(x & 15) * CS + (z & 15)], info[1][(x & 15) * CS + (z & 15)]]
