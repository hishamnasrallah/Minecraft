class_name Mesher
extends RefCounted
## Builds the mesh data of a chunk (port of World.compute_light / chunk_mesh / shape_boxes).
## Light is baked into vertex colours: r = sky light, g = block light, b = face shade.
## The block shader combines them with the time of day.

const CS := 16
const H := 64
const R := 48                     # light region: the chunk and its 8 neighbours
const WATER := 10

# (normal, shade); corner order matches world.py so triangles face outwards
const FACES := [
	[Vector3i(0, 1, 0), 1.00], [Vector3i(0, -1, 0), 0.55], [Vector3i(1, 0, 0), 0.82],
	[Vector3i(-1, 0, 0), 0.82], [Vector3i(0, 0, 1), 0.68], [Vector3i(0, 0, -1), 0.68],
]
static var face_corners := []     # per face: 6 corners (two triangles) of a unit cube
static var face_uvs := []         # per face: 6 local (u, v), v upwards

var world: WorldData
var x_lo: int
var z_lo: int
var sky := PackedByteArray()
var lamp := PackedByteArray()
var tops := PackedInt32Array()    # per region column
var waters := PackedInt32Array()


static func _static_setup() -> void:
	if not face_corners.is_empty():
		return
	for f in FACES:
		var n: Vector3i = f[0]
		var axes := []
		for a in 3:
			if n[a] == 0:
				axes.append(a)
		var corners := []
		for duv in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var c := Vector3(n) * 0.5
			c[axes[0]] = duv.x * 0.5
			c[axes[1]] = duv.y * 0.5
			corners.append(c)
		var normal := Vector3(n)
		if (corners[1] - corners[0]).cross(corners[2] - corners[0]).dot(normal) > 0:
			corners.reverse()
		var tri := []
		var uv := []
		for i in [0, 1, 2, 2, 3, 0]:
			var c: Vector3 = corners[i]
			tri.append(c)
			if n.y != 0:
				uv.append(Vector2(c.x + 0.5, c.z + 0.5))
			else:
				uv.append(Vector2((c.z if n.x != 0 else c.x) + 0.5, c.y + 0.5))
		face_corners.append(tri)
		face_uvs.append(uv)


func _init(w: WorldData) -> void:
	_static_setup()
	world = w


# ---------------------------------------------------------------- light
func _ri(x: int, y: int, z: int) -> int:
	return ((x - x_lo) * H + y) * R + (z - z_lo)


func _in_region(x: int, z: int) -> bool:
	return x >= x_lo and x < x_lo + R and z >= z_lo and z < z_lo + R


func compute_light(key: Vector2i) -> void:
	x_lo = (key.x - 1) * CS
	z_lo = (key.y - 1) * CS
	sky.resize(R * H * R)
	sky.fill(0)
	lamp.resize(R * H * R)
	lamp.fill(0)
	tops.resize(R * R)
	waters.resize(R * R)
	for dx in 3:
		for dz in 3:
			var k := Vector2i(key.x - 1 + dx, key.y - 1 + dz)
			var info := world.column_info(k)
			for lx in CS:
				for lz in CS:
					var ci := (dx * CS + lx) * R + dz * CS + lz
					tops[ci] = info[0][lx * CS + lz]
					waters[ci] = info[1][lx * CS + lz]
	# sky light: seed from open-sky cells next to a taller neighbour column, then spread
	var q := PackedInt32Array()
	for rx in R:
		for rz in R:
			var top := tops[rx * R + rz]
			var highest := top
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = rx + d.x
				var nz: int = rz + d.y
				if nx >= 0 and nx < R and nz >= 0 and nz < R:
					highest = maxi(highest, tops[nx * R + nz])
			for y in range(top + 1, mini(highest, H - 1) + 1):
				q.append(((rx * H + y) * R + rz) * 16 + WorldData.open_sky(y, waters[rx * R + rz]))
	_spread(q, true)
	var lq := PackedInt32Array()
	for dx in 3:
		for dz in 3:
			var e: Dictionary = world.emitters.get(Vector2i(key.x - 1 + dx, key.y - 1 + dz), {})
			for p in e:
				# +1: the lamp cell itself, so its neighbours get the lamp's level
				var level: int = mini(Blocks.emit[world.get_block(p.x, p.y, p.z)] + 1, 15)
				lq.append((((p.x - x_lo) * H + p.y) * R + p.z - z_lo) * 16 + level)
	_spread(lq, false)


## BFS: light drops by 1 per block (2 through water). Queue entries are index * 16 + level.
func _spread(q: PackedInt32Array, is_sky: bool) -> void:
	# works on the member arrays directly: a packed array passed as an argument is copied on write
	var head := 0
	while head < q.size():
		var e := q[head]
		head += 1
		var level := e & 15
		var i := e >> 4
		var rz := i % R
		var y := (i / R) % H
		var rx := i / (R * H)
		for n in 6:
			var nx := rx
			var ny := y
			var nz := rz
			match n:
				0: nx += 1
				1: nx -= 1
				2: ny += 1
				3: ny -= 1
				4: nz += 1
				5: nz -= 1
			if nx < 0 or nx >= R or nz < 0 or nz >= R or ny <= 0 or ny >= H:
				continue
			if is_sky and ny > tops[nx * R + nz]:
				continue                      # already fully lit by the open sky
			var b := world.get_block(x_lo + nx, ny, z_lo + nz)
			if b != 0 and Blocks.transparent[b] == 0:
				continue
			var new_level := level - (2 if b == WATER else 1)
			var ni := (nx * H + ny) * R + nz
			var current := sky[ni] if is_sky else lamp[ni]
			if new_level > current:
				if is_sky:
					sky[ni] = new_level
				else:
					lamp[ni] = new_level
				if new_level > 1:
					q.append(ni * 16 + new_level)


func light_at(x: int, y: int, z: int) -> Vector2i:
	if not _in_region(x, z) or y < 0:
		return Vector2i(15, 0)
	var ci := (x - x_lo) * R + (z - z_lo)
	var s: int
	if y >= H or y > tops[ci]:
		s = WorldData.open_sky(y, waters[ci])
	else:
		s = sky[_ri(x, y, z)]
	return Vector2i(s, lamp[_ri(x, y, z)] if y < H else 0)


# ---------------------------------------------------------------- meshing
class Group:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()


## Returns {"solid", "translucent", "water", "plants"} -> Group.
func build(key: Vector2i) -> Dictionary:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			world.ensure_chunk(Vector2i(key.x + dx, key.y + dz))
	compute_light(key)
	var out := {"solid": Group.new(), "translucent": Group.new(), "water": Group.new(), "plants": Group.new()}
	var data: PackedInt32Array = world.chunks[key].b
	var x0 := key.x * CS
	var z0 := key.y * CS
	for lx in CS:
		for y in H:
			var base := (lx * H + y) * CS
			for lz in CS:
				var id := data[base + lz]
				if id == 0:
					continue
				var x := x0 + lx
				var z := z0 + lz
				if Blocks.shape[id] != "cube":
					_shape(out, id, x, y, z)
					continue
				var water := id == WATER
				var g: Group = out["water"] if water else (out["translucent"] if Blocks.translucent[id] else out["solid"])
				var lowered := water and world.get_block(x, y + 1, z) != WATER
				for f in 6:
					var n: Vector3i = FACES[f][0]
					var nb := world.get_block(x + n.x, y + n.y, z + n.z)
					if water:
						if nb == WATER or (nb != 0 and Blocks.transparent[nb] == 0):
							continue
					elif (nb != 0 and (Blocks.transparent[nb] == 0 or nb == id)) or (n.y == -1 and y == 0):
						continue
					var l := light_at(x + n.x, y + n.y, z + n.z)
					var lmp := 15 if Blocks.emit[id] else l.y
					var col := Color(l.x / 15.0, lmp / 15.0, FACES[f][1], 1.0)
					var tile := Blocks.tile_top[id] if n.y > 0 else (Blocks.tile_bottom[id] if n.y < 0 else Blocks.tile_side[id])
					for i in 6:
						var c: Vector3 = face_corners[f][i]
						if lowered and c.y > 0:
							c.y = 0.4
						g.verts.append(Vector3(x, y, z) + c)
						g.colors.append(col)
						var uv: Vector2 = face_uvs[f][i]
						g.uvs.append(Blocks.tile_uv(tile, uv.x, uv.y))
	return out


## The boxes (min, max within -0.5..0.5) a non-cube block is made of.
func shape_boxes(id: int, x: int, y: int, z: int) -> Array:
	var d: Dictionary = Blocks.defs[id]
	match d["shape"]:
		"slab":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, 0, .5)]]
		"stair":
			var uppers := [[Vector3(-.5, 0, 0), Vector3(.5, .5, .5)], [Vector3(0, 0, -.5), Vector3(.5, .5, .5)],
				[Vector3(-.5, 0, -.5), Vector3(.5, .5, 0)], [Vector3(-.5, 0, -.5), Vector3(0, .5, .5)]]
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, 0, .5)], uppers[int(d["facing"])]]
		"bed":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, .06, .5)]]
		"torch":
			return [[Vector3(-.0625, -.5, -.0625), Vector3(.0625, .3, .0625)]]
		"ladder":
			var sides := [[Vector3(-.5, -.5, .42), Vector3(.5, .5, .5)], [Vector3(.42, -.5, -.5), Vector3(.5, .5, .5)],
				[Vector3(-.5, -.5, -.5), Vector3(.5, .5, -.42)], [Vector3(-.5, -.5, -.5), Vector3(-.42, .5, .5)]]
			return [sides[int(d["facing"])]]
		"door":
			var door: Dictionary = d["door"]
			if int(door["axis"]) == 0:
				return [[Vector3(-.5, -.5, -.5), Vector3(-.32, .5, .5)]] if door["open"] else [[Vector3(-.5, -.5, -.09), Vector3(.5, .5, .09)]]
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, .5, -.32)]] if door["open"] else [[Vector3(-.09, -.5, -.5), Vector3(.09, .5, .5)]]
		"fence":
			var boxes := [[Vector3(-.125, -.5, -.125), Vector3(.125, .5, .125)]]
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb := world.get_block(x + dd.x, y, z + dd.y)
				if nb == id or (nb != 0 and Blocks.transparent[nb] == 0):
					for ys in [[.1, .32], [-.25, -.05]]:
						if dd.x != 0:
							var a := .125 if dd.x > 0 else -.5
							var b := .5 if dd.x > 0 else -.125
							boxes.append([Vector3(a, ys[0], -.06), Vector3(b, ys[1], .06)])
						else:
							var a := .125 if dd.y > 0 else -.5
							var b := .5 if dd.y > 0 else -.125
							boxes.append([Vector3(-.06, ys[0], a), Vector3(.06, ys[1], b)])
			return boxes
	return [[Vector3(-.5, -.5, -.5), Vector3(.5, .5, .5)]]


func _shape(out: Dictionary, id: int, x: int, y: int, z: int) -> void:
	var l := light_at(x, y, z)
	var lmp := 15 if Blocks.emit[id] else l.y
	var shape: String = Blocks.shape[id]
	var origin := Vector3(x, y, z)
	if shape == "cross":                          # two crossed, double-sided quads
		var g: Group = out["plants"]
		var col := Color(l.x / 15.0, lmp / 15.0, 0.9, 1.0)
		var tile := Blocks.tile_side[id]
		for diag in [[Vector2(-.45, -.45), Vector2(.45, .45)], [Vector2(-.45, .45), Vector2(.45, -.45)]]:
			var a: Vector2 = diag[0]
			var b: Vector2 = diag[1]
			var quad := [Vector3(a.x, -.5, a.y), Vector3(b.x, -.5, b.y), Vector3(b.x, .5, b.y), Vector3(a.x, .5, a.y)]
			var quv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for order in [[0, 1, 2, 2, 3, 0], [0, 3, 2, 2, 1, 0]]:
				for i in order:
					g.verts.append(origin + quad[i])
					g.colors.append(col)
					g.uvs.append(Blocks.tile_uv(tile, quv[i].x, quv[i].y))
		return
	var g: Group = out["plants"] if shape in ["ladder", "torch"] else out["solid"]
	for box in shape_boxes(id, x, y, z):
		var lo: Vector3 = box[0]
		var hi: Vector3 = box[1]
		for f in 6:
			var n: Vector3i = FACES[f][0]
			var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
			var edge := hi[axis] == 0.5 if n[axis] > 0 else lo[axis] == -0.5
			if edge:
				var nb := world.get_block(x + n.x, y + n.y, z + n.z)
				if nb != 0 and Blocks.transparent[nb] == 0:
					continue                      # flush against an opaque block
			var tile := Blocks.tile_top[id] if n.y > 0 else (Blocks.tile_bottom[id] if n.y < 0 else Blocks.tile_side[id])
			var col := Color(l.x / 15.0, lmp / 15.0, FACES[f][1], 1.0)
			for i in 6:
				var c: Vector3 = face_corners[f][i]
				var p := Vector3(lo.x if c.x < 0 else hi.x, lo.y if c.y < 0 else hi.y, lo.z if c.z < 0 else hi.z)
				g.verts.append(origin + p)
				g.colors.append(col)
				var u := p.x + .5
				var v := p.z + .5
				if n.y == 0:
					u = (p.z if n.x != 0 else p.x) + .5
					v = p.y + .5
				g.uvs.append(Blocks.tile_uv(tile, u, v))
