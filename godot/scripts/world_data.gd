class_name WorldData
extends RefCounted
## The voxel world: infinite chunked terrain generation, editing, lighting, voxel raycasts
## and saving. A faithful port of world.py — the same seed generates the same world, and
## save files use the same format.
##
## Each chunk is a flat PackedInt32Array of block ids (16 x H x 16), index (lx*H + y)*16 + lz.

const CS := 16
const H := 320                  # world height (world.py MAX_HEIGHT)
const SURFACE_OFFSET := 180     # the surface sits this far above the bedrock (world.py SURFACE_OFFSET)
const SAVE_VERSION := 4         # saves before 4 were made when the surface was SURFACE_OFFSET lower
const WATER := 10
const NEIGHBOURS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

## Block ids of one chunk. Wrapped in an object so edits change the array in place
## (a PackedInt32Array taken out of a Dictionary would be copied on every write).
class Chunk:
	var b := PackedInt32Array()

	func _init(allocate := true) -> void:
		if allocate:
			b.resize(16 * H * 16)


var seed: int
var chunks := {}            # Vector2i -> Chunk
var changes := {}           # Vector2i -> {Vector3i: id} player edits, re-applied when a chunk regenerates
var containers := {}        # Vector3i -> Array of slots (chests)
var settings := {}          # Vector3i -> {"delay": ticks}: what you chose in a machine's panel
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
var CAVE_FLOOR: int
var BEDROCK_TOP: int
var SLATE_LINE: int
var BASALT_LINE: int
var LIMESTONE_LINE: int
var CAVERN_TOP: int
var CAVERN_MID: int
var CAVERN_LIMIT: float
var ORE_IDS: PackedInt32Array          # World.ORES as typed arrays for the generator's inner loops
var ORE_BANDS: PackedFloat64Array
var ORE_MAX_Y: PackedInt32Array
var TREE_KINDS: Array          # kind index -> name ("oak", "birch", "pine", "maple", ...)
var TREES: Array               # kind index -> [log, leaves, trunk height, [[dy, radius, reach], ...]]
var FLOWERS: Array
var ORE_LIMIT: float
var G := {}
var on_edit: Callable          # main thread only: told about every edit (machines keep a registry)
var ORES: Array                # private copies, so a generation thread shares nothing
var TRANSPARENT: PackedByteArray                    # generation block ids (SLATE, LIMESTONE, bushes, ...)


var dimension := "overworld"   # or "sky": floating islands (the second world)
## Terrain generator version. 1: the original gentle land (old saves keep it, the Python
## version matches it exactly). 2: new worlds: continents and deep seas, real mountain ranges.
var gen := 1


func _init(world_seed: int = -1, dim := "overworld") -> void:
	seed = world_seed if world_seed >= 0 else randi() % 1000000
	dimension = dim
	WATER_LEVEL = int(Blocks.C["WATER_LEVEL"])
	SNOW_LINE = int(Blocks.C["SNOW_LINE"])
	TREE_CHANCE = float(Blocks.C["TREE_CHANCE"])
	CAVE_THRESHOLD = float(Blocks.C["CAVE_THRESHOLD"])
	CAVE_GRID = int(Blocks.C["CAVE_GRID"])
	CAVE_FLOOR = int(Blocks.C["CAVE_FLOOR"])
	BEDROCK_TOP = int(Blocks.C["BEDROCK_TOP"])
	SLATE_LINE = int(Blocks.C["SLATE_LINE"])
	BASALT_LINE = int(Blocks.C["BASALT_LINE"])
	LIMESTONE_LINE = int(Blocks.C["LIMESTONE_LINE"])
	CAVERN_TOP = int(Blocks.C["CAVERN_TOP"])
	CAVERN_MID = int(Blocks.C["CAVERN_MID"])
	CAVERN_LIMIT = float(Blocks.C["CAVERN_LIMIT"])
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
	for ore in ORES:
		ORE_IDS.append(int(ore[0]))
		ORE_BANDS.append(float(ore[1]))
		ORE_MAX_Y.append(int(ore[2]))
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
		if door != null and not door.get("single", false):   # a door is two blocks: remove the other half too
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
	if on_edit.is_valid():
		on_edit.call(Vector3i(x, y, z), id)
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
	var h := int(3 + hills * 12 + mountains * 22) + SURFACE_OFFSET
	if gen >= 2:
		h = _big_height(x, z, hills, mountains)
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


## Generator 2: wide continents and seas, and mountain ranges up to ~100 blocks high.
func _big_height(x: int, z: int, hills: float, mountains: float) -> int:
	var land := VNoise.fbm(x / 420.0, z / 420.0, seed + 101, 3)        # 0 deep sea .. 1 inland
	var f := 3.0 + hills * 12.0 + mountains * 22.0 + SURFACE_OFFSET
	if land < 0.42:
		f -= (0.42 - land) / 0.42 * 46.0                              # the further out, the deeper
	var ridge := VNoise.fbm(x / 230.0, z / 230.0, seed + 107, 3)
	var peak := maxf(0.0, ridge - 0.5) * 2.0                          # 0 .. 1 where ranges rise
	var inland := clampf((land - 0.45) / 0.15, 0.0, 1.0)
	f += pow(peak, 1.6) * 110.0 * inland
	return clampi(int(f), BEDROCK_TOP + 20, H - 45)


func height_at(x: int, z: int) -> int:
	return _column_climate(x, z)[0]


func has_tree(x: int, z: int) -> bool:
	return _column_climate(x, z)[2]


## Generate a chunk (and re-apply the player's edits in it) if it isn't loaded.
## Gives exactly the blocks of world.py's per-cell rules, but fills them in bulk (generation runs
## on phones): each column's slate / stone base is written in one pass, rock blobs are painted
## per 8x4x8 blob and ores per 2x2x2 cluster, so most of the ~50k underground cells cost one
## array write instead of a few noise calls. Priority, as in World._rock: ore > blob > slate/stone.
func ensure_chunk(key: Vector2i) -> bool:
	if chunks.has(key):
		return false
	if dimension == "sky":
		return _ensure_sky(key)
	if dimension == "fire":
		return _ensure_fire(key)
	var x0 := key.x * CS
	var z0 := key.y * CS
	var blk := PackedInt32Array()
	blk.resize(CS * H * CS)
	var rock_tops := PackedInt32Array()            # per column: rock fills BEDROCK_TOP .. rock_top - 1
	rock_tops.resize(CS * CS)
	var surface := []
	var slate_id: int = G["SLATE"]
	for lx in CS:
		for lz in CS:
			var x := x0 + lx
			var z := z0 + lz
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
			var rock_top := h - 6 if desert else h - 3  # deserts have sandstone under the sand
			rock_tops[lx * CS + lz] = rock_top
			var slate := _slate_line(x, z)
			var col := lx * H * CS + lz              # index of (lx, 0, lz); one block up is +CS
			blk[col] = 9
			for y in range(1, BEDROCK_TOP):          # ragged bedrock floor (cell by cell)
				if VNoise.hash3(x, y, z, seed + 5) < (BEDROCK_TOP - y) * 0.2:
					blk[col + y * CS] = 9
				elif y < rock_top:
					blk[col + y * CS] = _rock(x, y, z, slate)
			var split := clampi(slate, BEDROCK_TOP, rock_top)
			var i := col + BEDROCK_TOP * CS
			for y in range(BEDROCK_TOP, split):
				blk[i] = slate_id
				i += CS
			for y in range(split, rock_top):
				blk[i] = 3
				i += CS
			for y in range(rock_top, h - 3):
				blk[col + y * CS] = 20
			for y in range(maxi(rock_top, h - 3), h):
				blk[col + y * CS] = filler
			blk[col + h * CS] = top_block
			for y in range(h + 1, WATER_LEVEL + 1):
				blk[col + y * CS] = WATER
			surface.append([x, z, h, top_block, desert])
	blk = _paint_blobs(blk, rock_tops, x0, z0)     # (packed arrays are handed back, so this
	blk = _paint_ores(blk, rock_tops, x0, z0)      # works whether they pass by value or reference)
	blk = _carve_caves(key, blk)
	var chunk := Chunk.new(false)
	chunk.b = blk
	blk = PackedInt32Array()                        # drop our reference: later edits write in place
	chunks[key] = chunk                             # (no generated terrain block emits light)
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


## Below this y the rock is dark slate instead of stone (a wavy, ragged boundary).
func _slate_line(x: int, z: int) -> int:
	return SLATE_LINE - 6 + int(VNoise.value_noise(x / 16.0, z / 16.0, seed + 81) * 9) \
		+ int(VNoise.hash2(x, z, seed + 82) * 3)


## Underground block: stone (slate deep down) with patches of other rock, and ore clusters by
## depth. The per-cell reference (world.py World._rock); ensure_chunk only uses it below BEDROCK_TOP.
func _rock(x: int, y: int, z: int, slate: int) -> int:
	var r := VNoise.hash3(x >> 1, y >> 1, z >> 1, seed + 55)
	if r < ORE_LIMIT:
		for o in ORE_IDS.size():
			if r < ORE_BANDS[o]:
				if y <= ORE_MAX_Y[o] and VNoise.hash3(x, y, z, seed + 56) < 0.6:
					return ORE_IDS[o]
				break
	var v := VNoise.hash3(x >> 3, y >> 2, z >> 3, seed + 71)
	if v < 0.08:
		return 18
	if v < 0.15 and y < BASALT_LINE:
		return 19
	if v < 0.19:
		return 21
	if v < 0.25 and y >= LIMESTONE_LINE:
		return G["LIMESTONE"]
	if y < slate:
		return G["SLATE"]
	return 3


## Rock blobs (granite, basalt, marble, limestone): one hash per 8x4x8 blob. BASALT_LINE and
## LIMESTONE_LINE are multiples of 4, so a whole blob is on one side of them.
func _paint_blobs(blk: PackedInt32Array, rock_tops: PackedInt32Array, x0: int, z0: int) -> PackedInt32Array:
	var limestone: int = G["LIMESTONE"]
	for bi in 2:
		for bk in 2:
			var top := 0
			for lx in range(bi * 8, bi * 8 + 8):
				for lz in range(bk * 8, bk * 8 + 8):
					top = maxi(top, rock_tops[lx * CS + lz])
			for by in range(BEDROCK_TOP >> 2, ((top - 1) >> 2) + 1):
				var v := VNoise.hash3((x0 >> 3) + bi, by, (z0 >> 3) + bk, seed + 71)
				var y0 := by * 4
				var id := 0
				if v < 0.08:
					id = 18
				elif v < 0.15 and y0 < BASALT_LINE:
					id = 19
				elif v < 0.19:
					id = 21
				elif v < 0.25 and y0 >= LIMESTONE_LINE:
					id = limestone
				if id == 0:
					continue
				for lx in range(bi * 8, bi * 8 + 8):
					for lz in range(bk * 8, bk * 8 + 8):
						var i := (lx * H + y0) * CS + lz
						for y in range(y0, mini(y0 + 4, rock_tops[lx * CS + lz])):
							blk[i] = id
							i += CS
	return blk


## Ore clusters: one hash per 2x2x2 cell (inlined VNoise.hash3), then 60% of its cells.
func _paint_ores(blk: PackedInt32Array, rock_tops: PackedInt32Array, x0: int, z0: int) -> PackedInt32Array:
	var s55: int = (seed + 55) * 1442695041
	for oi in 8:
		for ok in 8:
			var c := (2 * oi) * CS + 2 * ok
			var top := maxi(maxi(rock_tops[c], rock_tops[c + 1]), maxi(rock_tops[c + CS], rock_tops[c + CS + 1]))
			var hb: int = ((x0 >> 1) + oi) * 374761393 + ((z0 >> 1) + ok) * 668265263 + s55
			for oy in range(BEDROCK_TOP >> 1, ((top - 1) >> 1) + 1):
				var n: int = (hb + oy * 1103515245) & 0xFFFFFFFF
				n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
				var r := float(n ^ (n >> 16)) / 4294967295.0
				if r >= ORE_LIMIT:
					continue
				var o := 0
				while r >= ORE_BANDS[o]:
					o += 1
				var id := ORE_IDS[o]
				var max_y := ORE_MAX_Y[o]
				for dx in 2:
					for dz in 2:
						var lx := 2 * oi + dx
						var lz := 2 * ok + dz
						var rt := rock_tops[lx * CS + lz]
						for dy in 2:
							var y := 2 * oy + dy
							if y <= max_y and y < rt and VNoise.hash3(x0 + lx, y, z0 + lz, seed + 56) < 0.6:
								blk[(lx * H + y) * CS + lz] = id
	return blk


## VNoise.value_noise3(X / sxz, Y / sy, Z / sxz, nseed) at the cave grid points X = x0 + i*g,
## Y = j*g (j < ny), Z = z0 + k*g, at index (i * ny + j) * (n + 1) + k. Bit-identical to calling
## value_noise3 per point (same lerps in the same order), but every lattice hash is made once
## and the z / y / x interpolations are shared between neighbouring points.
func _noise_grid(nseed: int, sxz: float, sy: float, x0: int, z0: int, ny: int) -> PackedFloat64Array:
	var g := CAVE_GRID
	var np := CS / g + 1
	var xi := PackedInt32Array()
	var xt := PackedFloat64Array()
	var zi := PackedInt32Array()
	var zt := PackedFloat64Array()
	var yi := PackedInt32Array()
	var yt := PackedFloat64Array()
	for i in np:
		var fx := (x0 + i * g) / sxz
		var fl := floori(fx)
		xi.append(fl)
		xt.append(VNoise._smooth(fx - fl))
		var fz := (z0 + i * g) / sxz
		fl = floori(fz)
		zi.append(fl)
		zt.append(VNoise._smooth(fz - fl))
	for j in ny:
		var fy := (j * g) / sy
		var fl := floori(fy)
		yi.append(fl)
		yt.append(VNoise._smooth(fy - fl))
	var lx0 := xi[0]
	var ly0 := yi[0]
	var lz0 := zi[0]
	var nlx := xi[np - 1] - lx0 + 2
	var nly := yi[ny - 1] - ly0 + 2
	var nlz := zi[np - 1] - lz0 + 2
	var hz := PackedFloat64Array()
	hz.resize(nlx * nly * nlz)
	for a in nlx:
		for b in nly:
			for c in nlz:
				hz[(a * nly + b) * nlz + c] = VNoise.hash3(lx0 + a, ly0 + b, lz0 + c, nseed)
	var ez := PackedFloat64Array()                 # along z: [(a * nly + b) * np + k]
	ez.resize(nlx * nly * np)
	for a in nlx:
		for b in nly:
			for k in np:
				var h := (a * nly + b) * nlz + zi[k] - lz0
				var h0 := hz[h]
				ez[(a * nly + b) * np + k] = h0 + (hz[h + 1] - h0) * zt[k]
	var ey := PackedFloat64Array()                 # then y: [(a * ny + j) * np + k]
	ey.resize(nlx * ny * np)
	for a in nlx:
		for j in ny:
			var e0i := (a * nly + yi[j] - ly0) * np
			var t := yt[j]
			for k in np:
				var e0 := ez[e0i + k]
				ey[(a * ny + j) * np + k] = e0 + (ez[e0i + np + k] - e0) * t
	var out := PackedFloat64Array()                # then x
	out.resize(np * ny * np)
	for i in np:
		var a := xi[i] - lx0
		var t := xt[i]
		for j in ny:
			var v0i := (a * ny + j) * np
			var v1i := ((a + 1) * ny + j) * np
			for k in np:
				var v0 := ey[v0i + k]
				out[(i * ny + j) * np + k] = v0 + (ey[v1i + k] - v0) * t
	return out


## Hollow out tunnels everywhere and big caverns below CAVERN_TOP (port of World._carve_caves).
## Noise is sampled on a coarse grid and interpolated; grid cells whose corners are all solid,
## and cells above the terrain, are skipped.
func _carve_caves(key: Vector2i, blk: PackedInt32Array) -> PackedInt32Array:
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
	var n := CS / g
	var np := n + 1
	var ny := ymax / g + 2
	var tunnel_a := _noise_grid(seed + 300, 14.0, 9.0, x0, z0, ny)
	var tunnel_b := _noise_grid(seed + 600, 14.0, 9.0, x0, z0, ny)
	var ncav := mini(ny, (CAVERN_TOP + g - 1) / g)  # grid levels with j * g < CAVERN_TOP
	var cavern := _noise_grid(seed + 900, 32.0, 16.0, x0, z0, ncav)
	var grid := PackedFloat64Array()
	grid.resize(np * ny * np)
	for i in np:
		for j in ny:
			var cav_t := (j * g - CAVERN_MID) / float(CAVERN_TOP - CAVERN_MID)
			var limit := CAVERN_LIMIT + 0.18 * cav_t * cav_t
			for k in np:
				var gi := (i * ny + j) * np + k
				var a := tunnel_a[gi] - 0.5
				var b := tunnel_b[gi] - 0.5
				var d := a * a + b * b                  # = VNoise.cave_density
				if j < ncav:                            # = world.py cavern_density
					d = minf(d, CAVE_THRESHOLD + (limit - cavern[(i * ncav + j) * np + k]) * 0.25)
				grid[gi] = d
	var c := PackedFloat64Array()
	c.resize(8)
	for i in n:
		for k in n:
			var top := -1
			for lx in g:
				for lz in g:
					top = maxi(top, cols[(i * g + lx) * CS + k * g + lz])
			for j in range(CAVE_FLOOR / g, top / g + 1):
				var lowest := 1e9
				var highest := -1e9
				for a in 2:
					for b in 2:
						for d in 2:
							var value := grid[((i + a) * ny + j + b) * np + k + d]
							c[a * 4 + b * 2 + d] = value
							lowest = minf(lowest, value)
							highest = maxf(highest, value)
				if lowest >= CAVE_THRESHOLD:
					continue                          # interpolation never goes below the lowest corner
				if highest < CAVE_THRESHOLD - 1e-9:   # ... nor above the highest: all hollow
					for lx in g:
						for lz in g:
							var cx := i * g + lx
							var cz := k * g + lz
							var y_end := mini(j * g + g - 1, cols[cx * CS + cz])
							for y in range(maxi(j * g, CAVE_FLOOR), y_end + 1):
								blk[(cx * H + y) * CS + cz] = 0
					continue
				for lz in g:
					var fz := lz / float(g)
					var c00 := c[0] + (c[1] - c[0]) * fz
					var c01 := c[2] + (c[3] - c[2]) * fz
					var c10 := c[4] + (c[5] - c[4]) * fz
					var c11 := c[6] + (c[7] - c[6]) * fz
					for ly in g:
						var y := j * g + ly
						if y < CAVE_FLOOR:
							continue
						var fy := ly / float(g)
						var c0 := c00 + (c01 - c00) * fy
						var c1 := c10 + (c11 - c10) * fy
						for lx in g:
							var cx := i * g + lx
							var cz := k * g + lz
							if y > cols[cx * CS + cz]:
								continue
							if c0 + (c1 - c0) * (lx / float(g)) < CAVE_THRESHOLD:
								blk[(cx * H + y) * CS + cz] = 0
	return blk


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
	if dimension == "sky":
		return Vector3(0, top_y(0, 4) + 1.5, 4)          # on the main island, by the way home
	if dimension == "fire":
		return Vector3(0, FIRE_HALL + 1.5, 3)            # in the hall by the portal home
	if gen >= 2:
		var land := _land_near_origin()               # the big seas can cover the middle of the map
		return Vector3(land.x, top_y(land.x, land.y) + 1.5, land.y)
	return Vector3(8, top_y(8, 8) + 1.5, 8)


var _land := Vector2i(-99999, 0)


## The nearest dry, not too steep land to the middle of the map (searched in growing rings).
func _land_near_origin() -> Vector2i:
	if _land.x != -99999:
		return _land
	_land = Vector2i(8, 8)
	for r in range(0, 2000, 24):
		var steps := maxi(1, r / 24 * 8)
		for i in steps:
			var a := TAU * i / steps
			var x := 8 + int(cos(a) * r)
			var z := 8 + int(sin(a) * r)
			var h := height_at(x, z)
			if h > WATER_LEVEL + 1 and h < SNOW_LINE and absi(height_at(x + 4, z) - h) < 3 and absi(height_at(x, z + 4) - h) < 3:
				_land = Vector2i(x, z)
				return _land
	return _land


# ---------------------------------------------------------------- the fire realm
const FIRE := {"ROCK": 1900, "PORTAL": 1902, "ORE": 1903, "ASH": 1904, "MAGMA": 1905, "FRAME": 1890,
	"CRYSTAL": 910}
const FIRE_SEA := 48                  # the lava sea's surface
const FIRE_HALL := 60                 # the floor of the hall you arrive in
const FIRE_ROOF := 150                # solid rock above this


## The cavern at a column: [floor, ceiling]. Rock below the floor and above the ceiling;
## where they meet there is a pillar. Lava fills the low places up to FIRE_SEA.
func fire_cave(x: int, z: int) -> Vector2i:
	var f := 36.0 + VNoise.fbm(x / 60.0, z / 60.0, seed + 600, 3) * 44.0
	var c := 104.0 + VNoise.fbm(x / 50.0, z / 50.0, seed + 601, 3) * 40.0
	var pillar := VNoise.fbm(x / 18.0, z / 18.0, seed + 602, 2)
	if pillar > 0.72:
		f = c                                      # a column from floor to roof
	var d := sqrt(float(x * x + z * z))
	if d < 10.0:                                   # the arrival hall: flat, dry, with room
		f = FIRE_HALL
		c = maxf(c, FIRE_HALL + 12.0)
	elif d < 18.0:
		f = lerpf(FIRE_HALL, f, (d - 10.0) / 8.0)
	return Vector2i(int(f), int(c))


func _ensure_fire(key: Vector2i) -> bool:
	var x0 := key.x * CS
	var z0 := key.y * CS
	var blk := PackedInt32Array()
	blk.resize(CS * H * CS)
	var e := {}
	var rock: int = FIRE["ROCK"]
	for lx in CS:
		for lz in CS:
			var x := x0 + lx
			var z := z0 + lz
			var cv := fire_cave(x, z)
			var fl := cv.x
			var ce := cv.y
			var base := (lx * H) * CS + lz
			blk[base] = 9                                          # bedrock at the bottom
			for y in range(1, FIRE_ROOF + 1):
				var i := base + y * CS
				if y <= fl or y >= ce:
					var id := rock
					var near := mini(absi(y - fl), absi(y - ce))
					if near <= 2 and VNoise.hash3(x, y, z, seed + 603) < 0.03:
						id = FIRE["ORE"]
						e[Vector3i(x, y, z)] = true
					blk[i] = id
				elif y <= FIRE_SEA:
					blk[i] = 1880                                  # the lava sea
					if y == FIRE_SEA:
						e[Vector3i(x, y, z)] = true
			blk[base + (FIRE_ROOF + 1) * CS] = 9                   # a bedrock lid
			if fl < ce and fl > FIRE_SEA:
				var top := base + fl * CS
				var h := VNoise.hash2(x, z, seed + 604)
				if h < 0.04:
					blk[top] = FIRE["MAGMA"]
					e[Vector3i(x, fl, z)] = true
				elif VNoise.fbm(x / 20.0, z / 20.0, seed + 605, 2) > 0.6:
					blk[top] = FIRE["ASH"]
			if fl < ce and VNoise.hash2(x, z, seed + 606) < 0.012 and ce - 1 > fl + 3:
				blk[base + (ce - 1) * CS] = FIRE["CRYSTAL"]            # glowing crystals hang from the roof
				e[Vector3i(x, ce - 1, z)] = true
	# the portal home: an obsidian frame across x at z = -6, on the hall floor
	for i in 4:
		for j in 5:
			var x := -2 + i
			var z := -6
			if (x >> 4) != key.x or (z >> 4) != key.y:
				continue
			var y := FIRE_HALL + 1 + j
			var frame := i == 0 or i == 3 or j == 0 or j == 4
			blk[((x - x0) * H + y) * CS + (z - z0)] = FIRE["FRAME"] if frame else FIRE["PORTAL"]
			if not frame:
				e[Vector3i(x, y, z)] = true
	var chunk := Chunk.new(false)
	chunk.b = blk
	chunks[key] = chunk
	if not e.is_empty():
		emitters[key] = e
	return true


# ---------------------------------------------------------------- the sky realm
const SKY := {"STONE": 1800, "GRASS": 1801, "CLOUD": 1802, "STAR_ORE": 1803, "PORTAL": 1805,
	"CRYSTAL": 1806, "PILLAR": 1807, "SOIL": 1809, "FRAME": 906}
const SKY_BASE := 172                 # island tops are around here
const MAIN_RADIUS := 40.0             # the main island (the boss's) at the centre
const PILLARS := [Vector2i(24, 0), Vector2i(-24, 0), Vector2i(0, 24), Vector2i(0, -24)]
const PILLAR_HEIGHT := 18


## Island shape at a column: 0 = empty sky; above 0 = how deep in the island.
func sky_island(x: int, z: int) -> float:
	var n := VNoise.fbm(x / 70.0, z / 70.0, seed + 500, 3)
	var d := sqrt(float(x * x + z * z))
	if d < MAIN_RADIUS:
		n = maxf(n, 0.6 + (MAIN_RADIUS - d) / MAIN_RADIUS * 0.4)
	elif d < MAIN_RADIUS + 24:
		n = minf(n, 0.5)                    # a clear ring of sky around the main island
	return maxf(0.0, (n - 0.58) / 0.42)


func sky_top(x: int, z: int) -> int:
	var t := sky_island(x, z)
	if t <= 0.0:
		return -1
	if sqrt(float(x * x + z * z)) < MAIN_RADIUS * 0.75:
		return SKY_BASE + 6                 # the main island is flat: room for the fight
	return SKY_BASE + int(t * 14.0 + VNoise.fbm(x / 14.0, z / 14.0, seed + 501, 2) * 5.0)


func _ensure_sky(key: Vector2i) -> bool:
	var x0 := key.x * CS
	var z0 := key.y * CS
	var blk := PackedInt32Array()
	blk.resize(CS * H * CS)
	var e := {}
	for lx in CS:
		for lz in CS:
			var x := x0 + lx
			var z := z0 + lz
			var t := sky_island(x, z)
			if t > 0.0:
				var top := sky_top(x, z)
				var bottom := top - int(4.0 + t * 42.0 + VNoise.hash2(x, z, seed + 502) * 3.0)
				for y in range(maxi(bottom, 1), top + 1):
					var id: int = SKY["STONE"]
					if y == top:
						id = SKY["GRASS"]
					elif y >= top - 2:
						id = SKY["SOIL"]
					elif VNoise.hash3(x, y, z, seed + 503) < 0.012:
						id = SKY["STAR_ORE"]
					blk[(lx * H + y) * CS + lz] = id
				var flower := VNoise.hash2(x, z, seed + 504)
				if flower < 0.03 and top + 1 < H:
					blk[(lx * H + top + 1) * CS + lz] = 1000 + int(flower * 1000.0) % 8
			elif VNoise.fbm(x / 40.0, z / 40.0, seed + 520, 2) > 0.66:
				for y in [SKY_BASE - 22, SKY_BASE - 21]:  # drifting clouds below the islands
					blk[(lx * H + y) * CS + lz] = SKY["CLOUD"]
	# the main island: four pillars with storm crystals, and the portal home
	for pc in PILLARS:
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var x: int = pc.x + dx
				var z: int = pc.y + dz
				if (x >> 4) != key.x or (z >> 4) != key.y:
					continue
				var top := SKY_BASE + 6
				for y in range(top + 1, top + PILLAR_HEIGHT + 1):
					blk[((x - x0) * H + y) * CS + (z - z0)] = SKY["PILLAR"]
				if dx == 0 and dz == 0:
					var cy := top + PILLAR_HEIGHT + 1
					blk[((x - x0) * H + cy) * CS + (z - z0)] = SKY["CRYSTAL"]
					e[Vector3i(x, cy, z)] = true
	# a ladder up the outer side of every pillar, so the crystals can be reached without towering
	for pc in PILLARS:
		var o := Vector2i(signi(pc.x), signi(pc.y))
		var lx: int = pc.x + o.x * 2
		var lz: int = pc.y + o.y * 2
		if (lx >> 4) != key.x or (lz >> 4) != key.y:
			continue
		var facing: int = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)].find(-o)
		for y in range(SKY_BASE + 7, SKY_BASE + 6 + PILLAR_HEIGHT + 1):
			blk[((lx - x0) * H + y) * CS + (lz - z0)] = 500 + facing
	for i in 4:                               # portal home: a 4 x 5 frame across x at z = -12
		for j in 5:
			var x := -2 + i
			var z := -12
			if (x >> 4) != key.x or (z >> 4) != key.y:
				continue
			var y := SKY_BASE + 7 + j
			var frame := i == 0 or i == 3 or j == 0 or j == 4
			blk[((x - x0) * H + y) * CS + (z - z0)] = SKY["FRAME"] if frame else SKY["PORTAL"]
			if not frame:
				e[Vector3i(x, y, z)] = true
	var chunk := Chunk.new(false)
	chunk.b = blk
	chunks[key] = chunk
	if not e.is_empty():
		emitters[key] = e
	var edits: Dictionary = changes.get(key, {})
	for pos in edits:
		_put(pos.x, pos.y, pos.z, edits[pos])
	return true


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
				if Blocks.fluid[b] == 1:
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
		if b != 0 and (Blocks.fluid[b] == 0 or hit_water):
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
	var data := {"player": player, "version": SAVE_VERSION, "seed": seed, "time_of_day": time_of_day,
		"containers": boxes, "changes": edits, "dimension": dimension, "gen": gen,
		"settings": settings.keys().map(func(p): return [p.x, p.y, p.z, settings[p]])}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


static func load_from(path: String) -> WorldData:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var data := migrate(parsed)
	var w := WorldData.new(int(data["seed"]), str(data.get("dimension", "overworld")))
	w.gen = int(data.get("gen", 1))
	w.time_of_day = float(data.get("time_of_day", 0.2))
	w.player_data = data.get("player", {})
	for c in data.get("containers", []):
		w.containers[Vector3i(int(c[0][0]), int(c[0][1]), int(c[0][2]))] = c[1]
	for st in data.get("settings", []):
		if st is Array and st.size() == 4 and st[3] is Dictionary:
			w.settings[Vector3i(int(st[0]), int(st[1]), int(st[2]))] = st[3]
	for e in data["changes"]:
		var p := Vector3i(int(e[0]), int(e[1]), int(e[2]))
		var key := chunk_key(p.x, p.z)
		var edits: Dictionary = w.changes.get(key, {})
		edits[p] = int(e[3])
		w.changes[key] = edits
	return w


## Positions the game keeps in the save's player data: single points and lists of block cells.
const PLAYER_POINTS := ["position", "spawn"]
const PLAYER_CELL_LISTS := ["growing"]


## Bring a loaded save up to SAVE_VERSION (same as world.py World.migrate). Saves before version 4
## come from the shallow world (64 high, surface ~180 lower): every stored y moves up by
## SURFACE_OFFSET so old builds, chests and the player stay on the same terrain.
static func migrate(data: Dictionary) -> Dictionary:
	if int(data.get("version", 0)) >= 4:
		return data
	var changes_up := []
	for e in data.get("changes", []):
		changes_up.append(_raised(e))
	data["changes"] = changes_up
	var boxes := []
	for c in data.get("containers", []):
		boxes.append([_raised(c[0]), c[1]])
	data["containers"] = boxes
	var player = data.get("player")
	if typeof(player) != TYPE_DICTIONARY:
		player = {}
	for k in PLAYER_POINTS:
		var p = player.get(k)
		if p is Array and p.size() >= 3:
			player[k] = _raised(p)
	for k in PLAYER_CELL_LISTS:
		var cells = player.get(k)
		if cells is Array:
			var up := []
			for p in cells:
				up.append(_raised(p))
			player[k] = up
	data["player"] = player
	data["version"] = SAVE_VERSION
	return data


static func _raised(p: Array) -> Array:
	var q := p.duplicate()
	q[1] = q[1] + SURFACE_OFFSET
	return q


## [top solid y, water surface y] of a loaded column, or null if its chunk isn't loaded.
func column(x: int, z: int):
	var key := chunk_key(x, z)
	if not chunks.has(key):
		return null
	var info := column_info(key)
	return [info[0][(x & 15) * CS + (z & 15)], info[1][(x & 15) * CS + (z & 15)]]
