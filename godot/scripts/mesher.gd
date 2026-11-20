class_name Mesher
extends RefCounted
## Builds the mesh data of a chunk (port of World.compute_light / chunk_mesh / shape_boxes).
## Light is baked into vertex colours: r = sky light, g = block light, b = face shade.
## The block shader combines them with the time of day.

const CS := 16
const H := WorldData.H
const R := 48                     # light region: the chunk and its 8 neighbours (x and z)
const SEC := 32                   # rows per section: chunks are meshed in slices of 32
const WATER := 10

# (normal, shade); corner order matches world.py so triangles face outwards
const FACES := [
	[Vector3i(0, 1, 0), 1.00], [Vector3i(0, -1, 0), 0.55], [Vector3i(1, 0, 0), 0.82],
	[Vector3i(-1, 0, 0), 0.82], [Vector3i(0, 0, 1), 0.68], [Vector3i(0, 0, -1), 0.68],
]
const AO_LEVELS := [0.52, 0.68, 0.84, 1.0]   # brightness for 0..3 open neighbours of a corner
const QUAD_INDEX := [0, 1, 2, 4]               # the 4 distinct corners within the 6 triangle vertices
const CORNERS_A := [0, 1, 2, 2, 3, 0]          # the two ways to split a quad into triangles
const CORNERS_B := [1, 2, 3, 3, 0, 1]
static var face_corners := []     # per face: 6 corners (two triangles) of a unit cube
static var face_uvs := []         # per face: 6 local (u, v), v upwards

var world: WorldData
var x_lo: int
var z_lo: int
var sky := PackedByteArray()
var lamp := PackedByteArray()
var y_lo := 0                     # light region rows (the meshed sections + 16 rows margin)
var y_hi := 0
var RH := 0
var max_y := H - 1                # highest block in the 3x3 chunks (set by the chunk manager)
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
				# u runs left-to-right as seen from outside the face, so text reads the right way
				var u: float = (c.z if n.x != 0 else c.x) + 0.5
				if n.x > 0 or n.z < 0:
					u = 1.0 - u
				uv.append(Vector2(u, c.y + 0.5))
		face_corners.append(tri)
		face_uvs.append(uv)


# private copies (made on the main thread in _init): a worker thread never touches an
# Array, Dictionary or table that another thread can see
var faces: Array
var ao_levels: PackedFloat32Array
var quad_index: PackedInt32Array
var corners_a: PackedInt32Array
var corners_b: PackedInt32Array
var corners: Array                # face_corners
var corner_uvs: Array             # face_uvs
var shapes: PackedStringArray
var transparent: PackedByteArray
var translucent: PackedByteArray
var emit: PackedByteArray
var tile_top: PackedInt32Array
var tile_side: PackedInt32Array
var tile_bottom: PackedInt32Array
const WALL_TORCH := 1810
const SWITCH_ON := 1703
const GATE_ON := 1770
const PUSHER_HEAD := 1760                   # gates 1770+ are the same gates while they give power
var machine: PackedByteArray
var facing: PackedByteArray
var door_axis: PackedByteArray
var door_open: PackedByteArray
var atlas_cols: int


func _init(w: WorldData) -> void:
	_static_setup()
	world = w
	faces = FACES.duplicate(true)
	ao_levels = PackedFloat32Array(AO_LEVELS)
	quad_index = PackedInt32Array(QUAD_INDEX)
	corners_a = PackedInt32Array(CORNERS_A)
	corners_b = PackedInt32Array(CORNERS_B)
	corners = face_corners.duplicate(true)
	corner_uvs = face_uvs.duplicate(true)
	shapes = Blocks.shapes.duplicate()
	transparent = Blocks.transparent.duplicate()
	translucent = Blocks.translucent.duplicate()
	emit = Blocks.emit.duplicate()
	tile_top = Blocks.tile_top.duplicate()
	tile_side = Blocks.tile_side.duplicate()
	tile_bottom = Blocks.tile_bottom.duplicate()
	facing = Blocks.facing.duplicate()
	machine = Blocks.machine.duplicate()
	door_axis = Blocks.door_axis.duplicate()
	door_open = Blocks.door_open.duplicate()
	atlas_cols = Blocks.atlas_cols


func _uv(tile: int, u: float, v: float) -> Vector2:
	var col := tile % atlas_cols
	var row := tile / atlas_cols
	u = 0.01 + u * 0.98
	v = 0.01 + v * 0.98
	return Vector2((col + u) / atlas_cols, (row + 1.0 - v) / atlas_cols)


# ---------------------------------------------------------------- light
func _ri(x: int, y: int, z: int) -> int:
	return ((x - x_lo) * RH + (y - y_lo)) * R + (z - z_lo)


func _in_region(x: int, z: int) -> bool:
	return x >= x_lo and x < x_lo + R and z >= z_lo and z < z_lo + R


## Highest opaque block and highest water of every column of the 3x3 chunks, scanning down
## from `max_y` (the highest block anywhere in them) instead of the top of the world.
func _column_tops(key: Vector2i) -> void:
	tops.resize(R * R)
	waters.resize(R * R)
	for dx in 3:
		for dz in 3:
			var k := Vector2i(key.x - 1 + dx, key.y - 1 + dz)
			var data: PackedInt32Array = world.chunks[k].b
			for lx in CS:
				for lz in CS:
					var top := -1
					var water := -1
					for y in range(mini(max_y, H - 1), -1, -1):
						var b := data[(lx * H + y) * CS + lz]
						if b == 0:
							continue
						if b == WATER:
							water = maxi(water, y)
						elif transparent[b] == 0:
							top = y
							break
					var ci := (dx * CS + lx) * R + dz * CS + lz
					tops[ci] = top
					waters[ci] = water


## Light for the rows y_lo..y_hi only (the sections being meshed plus 16 rows of margin:
## light never travels further than 15 blocks).
func compute_light(key: Vector2i, lo: int, hi: int) -> void:
	x_lo = (key.x - 1) * CS
	z_lo = (key.y - 1) * CS
	y_lo = maxi(0, lo - 16)
	y_hi = mini(H, hi + 16)
	RH = y_hi - y_lo
	sky.resize(R * RH * R)
	sky.fill(0)
	lamp.resize(R * RH * R)
	lamp.fill(0)
	_column_tops(key)
	# sky light: seed from open-sky cells next to a taller neighbour column, then spread
	var q := PackedInt32Array()
	for rx in R:
		for rz in R:
			var top := tops[rx * R + rz]
			var highest := top
			for d in 4:
				var nx: int = rx + (1 if d == 0 else (-1 if d == 1 else 0))
				var nz: int = rz + (1 if d == 2 else (-1 if d == 3 else 0))
				if nx >= 0 and nx < R and nz >= 0 and nz < R:
					highest = maxi(highest, tops[nx * R + nz])
			for y in range(maxi(top + 1, y_lo), mini(mini(highest, H - 1), y_hi - 1) + 1):
				q.append(((rx * RH + (y - y_lo)) * R + rz) * 16 + WorldData.open_sky(y, waters[rx * R + rz]))
	_spread(q, true)
	var lq := PackedInt32Array()
	for dx in 3:
		for dz in 3:
			var e: Dictionary = world.emitters.get(Vector2i(key.x - 1 + dx, key.y - 1 + dz), {})
			for p in e:
				if p.y < y_lo or p.y >= y_hi:
					continue
				# +1: the lamp cell itself, so its neighbours get the lamp's level
				var level: int = mini(emit[world.get_block(p.x, p.y, p.z)] + 1, 15)
				lq.append(_ri(p.x, p.y, p.z) * 16 + level)
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
		var ry := (i / R) % RH
		var rx := i / (R * RH)
		for n in 6:
			var nx := rx
			var ny := ry
			var nz := rz
			match n:
				0: nx += 1
				1: nx -= 1
				2: ny += 1
				3: ny -= 1
				4: nz += 1
				5: nz -= 1
			if nx < 0 or nx >= R or nz < 0 or nz >= R or ny < 0 or ny >= RH or ny + y_lo <= 0:
				continue
			var wy := ny + y_lo
			if is_sky and wy > tops[nx * R + nz]:
				continue                      # already fully lit by the open sky
			var b := world.get_block(x_lo + nx, wy, z_lo + nz)
			if b != 0 and transparent[b] == 0:
				continue
			var new_level := level - (2 if b == WATER else 1)
			var ni := (nx * RH + ny) * R + nz
			var current := sky[ni] if is_sky else lamp[ni]
			if new_level > current:
				if is_sky:
					sky[ni] = new_level
				else:
					lamp[ni] = new_level
				if new_level > 1:
					q.append(ni * 16 + new_level)


func _opaque(x: int, y: int, z: int) -> bool:
	var b := world.get_block(x, y, z)
	return b != 0 and transparent[b] == 0


## 0..3 for each of the face's 4 corners: how open the space around that corner is.
func _corner_ao(f: int, x: int, y: int, z: int) -> Array:
	var n: Vector3i = faces[f][0]
	var axes := []
	for a in 3:
		if n[a] == 0:
			axes.append(a)
	var out := []
	for q in 4:
		var c: Vector3 = corners[f][quad_index[q]]
		var d1 := Vector3i.ZERO
		var d2 := Vector3i.ZERO
		d1[axes[0]] = 1 if c[axes[0]] > 0 else -1
		d2[axes[1]] = 1 if c[axes[1]] > 0 else -1
		var base := Vector3i(x, y, z) + n
		var s1 := _opaque(base.x + d1.x, base.y + d1.y, base.z + d1.z)
		var s2 := _opaque(base.x + d2.x, base.y + d2.y, base.z + d2.z)
		var corner := _opaque(base.x + d1.x + d2.x, base.y + d1.y + d2.y, base.z + d1.z + d2.z)
		out.append(0 if (s1 and s2) else 3 - int(s1) - int(s2) - int(corner))
	return out


func light_at(x: int, y: int, z: int) -> Vector2i:
	if not _in_region(x, z) or y < 0:
		return Vector2i(15, 0)
	var ci := (x - x_lo) * R + (z - z_lo)
	if y >= H or y > tops[ci]:
		return Vector2i(WorldData.open_sky(y, waters[ci]), lamp[_ri(x, y, z)] if y >= y_lo and y < y_hi else 0)
	if y < y_lo or y >= y_hi:
		return Vector2i(0, 0)
	var i := _ri(x, y, z)
	return Vector2i(sky[i], lamp[i])


# ---------------------------------------------------------------- meshing
class Group:
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()


## Mesh the given sections (index = y / SEC). Returns {section: {"solid", "translucent",
## "water", "plants"} -> Group}. Light is computed once for all of them.
func build_sections(key: Vector2i, sections: Array) -> Dictionary:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			world.ensure_chunk(Vector2i(key.x + dx, key.y + dz))
	var lo := H
	var hi := 0
	for s in sections:
		lo = mini(lo, s * SEC)
		hi = maxi(hi, mini(H, s * SEC + SEC))
	compute_light(key, lo, hi)
	var result := {}
	for s in sections:
		result[s] = _mesh_rows(key, s * SEC, mini(H, s * SEC + SEC))
	return result


## Old entry point: the whole column as one mesh (tests and safe mode).
func build(key: Vector2i) -> Dictionary:
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			world.ensure_chunk(Vector2i(key.x + dx, key.y + dz))
	compute_light(key, 0, H)
	return _mesh_rows(key, 0, H)


func _mesh_rows(key: Vector2i, row_lo: int, row_hi: int) -> Dictionary:
	var out := {"solid": Group.new(), "translucent": Group.new(), "water": Group.new(), "plants": Group.new()}
	var data: PackedInt32Array = world.chunks[key].b
	var x0 := key.x * CS
	var z0 := key.y * CS
	for lx in CS:
		for y in range(row_lo, mini(row_hi, max_y + 2)):
			var base := (lx * H + y) * CS
			for lz in CS:
				var id := data[base + lz]
				if id == 0:
					continue
				var x := x0 + lx
				var z := z0 + lz
				if shapes[id] != "cube":
					_shape(out, id, x, y, z)
					continue
				var water := id == WATER
				var g: Group = out["water"] if water else (out["translucent"] if translucent[id] else out["solid"])
				var lowered := water and world.get_block(x, y + 1, z) != WATER
				for f in 6:
					var n: Vector3i = faces[f][0]
					var nb := world.get_block(x + n.x, y + n.y, z + n.z)
					if water:
						if nb == WATER or (nb != 0 and transparent[nb] == 0):
							continue
					elif (nb != 0 and (transparent[nb] == 0 or nb == id)) or (n.y == -1 and y == 0):
						continue
					var l := light_at(x + n.x, y + n.y, z + n.z)
					var lmp := 15 if emit[id] else l.y
					var col := Color(l.x / 15.0, lmp / 15.0, faces[f][1], 1.0)
					var tile := tile_top[id] if n.y > 0 else (tile_bottom[id] if n.y < 0 else tile_side[id])
					# ambient occlusion: each corner gets darker for every solid block around it
					# (water is left flat). The quad is split along the brighter diagonal so the
					# shading stays smooth instead of showing a crease.
					var ao := [3, 3, 3, 3] if water else _corner_ao(f, x, y, z)
					var order := corners_a
					if ao[0] + ao[2] < ao[1] + ao[3]:
						order = corners_b
					for k in 6:
						var q: int = order[k]
						var i: int = quad_index[q]
						var c: Vector3 = corners[f][i]
						if lowered and c.y > 0:
							c.y = 0.4
						g.verts.append(Vector3(x, y, z) + c)
						g.colors.append(Color(col.r, col.g, col.b * ao_levels[ao[q]], 1.0))
						var uv: Vector2 = corner_uvs[f][i]
						g.uvs.append(_uv(tile, uv.x, uv.y))
	return out


## The boxes (min, max within -0.5..0.5) a non-cube block is made of.
func shape_boxes(id: int, x: int, y: int, z: int) -> Array:
	match shapes[id]:
		"slab":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, 0, .5)]]
		"carpet":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, -.4375, .5)]]
		"stair":
			var uppers := [[Vector3(-.5, 0, 0), Vector3(.5, .5, .5)], [Vector3(0, 0, -.5), Vector3(.5, .5, .5)],
				[Vector3(-.5, 0, -.5), Vector3(.5, .5, 0)], [Vector3(-.5, 0, -.5), Vector3(0, .5, .5)]]
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, 0, .5)], uppers[facing[id]]]
		"bed":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, .06, .5)]]
		"torch":
			if id < WALL_TORCH:
				return [[Vector3(-.0625, -.5, -.0625), Vector3(.0625, .3, .0625)]]
			# on a wall: the stick a little up the wall, and a small bracket into it
			var d: Vector2 = [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1), Vector2(-1, 0)][facing[id]]
			var c := Vector3(d.x, 0, d.y) * .34
			var b := Vector3(d.x, 0, d.y) * .44
			return [[c + Vector3(-.0625, -.28, -.0625), c + Vector3(.0625, .46, .0625)],
				[b + Vector3(-.06, -.14, -.06), b + Vector3(.06, -.02, .06)]]
		"wire":
			# fine dust on the floor: a dot, and a thin trail towards every machine or wire beside
			# it (also one step up or down), so you see where the power goes
			var boxes := [[Vector3(-.1, -.5, -.1), Vector3(.1, -.48, .1)]]
			var arms := []
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for dy in [0, -1, 1]:
					var nb := world.get_block(x + dd.x, y + dy, z + dd.y)
					if nb != 0 and machine[nb] == 1 and (dy == 0 or shapes[nb] == "wire"):
						arms.append(dd)
						break
			if arms.size() == 1:
				arms.append(-arms[0])                 # one neighbour: a straight line right through
			for dd in arms:
				var a := Vector3(dd.x, 0, dd.y) * .1
				var b := Vector3(dd.x, 0, dd.y) * .5
				var w := Vector3(absf(dd.y), 0, absf(dd.x)) * .06
				boxes.append([Vector3(minf(a.x, b.x), -.5, minf(a.z, b.z)) - w, Vector3(maxf(a.x, b.x), -.48, maxf(a.z, b.z)) + w])
			return boxes
		"lever":
			# a wooden stick on a small stone base, leaning back when off and forward when on
			var lean := 1.0 if id == SWITCH_ON else -1.0
			var stone: int = tile_side[22]
			var wood: int = tile_side[7]
			var parts := [[Vector3(-.19, -.5, -.25), Vector3(.19, -.37, .25), stone]]
			for k in 7:                           # a thin stick leaning out of the base
				var y0 := -.37 + k * .08
				var zc: float = (.015 + k * .042) * lean
				parts.append([Vector3(-.035, y0, zc - .035), Vector3(.035, y0 + .08, zc + .035), wood])
			return parts
		"button":
			var stone2: int = tile_side[22]
			return [[Vector3(-.16, -.5, -.11), Vector3(.16, -.4, .11), stone2]]
		"gate":
			# a thin chip (its symbol and arrow on top), a stone nub at the back where the
			# input comes in, and a little light at the front that is lit while it gives power
			var gd: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)][facing[id] % 4]
			var lit: bool = id >= GATE_ON
			var cap: int = tile_side[1701 if lit else 1700]     # glowing red tip, or a dark one
			var stick: int = tile_side[7]
			var parts := [[Vector3(-.5, -.5, -.5), Vector3(.5, -.375, .5)]]
			for at in [gd * .25, -gd * .25]:          # two little torches: the output and the input
				parts.append([at + Vector3(-.04, -.375, -.04), at + Vector3(.04, -.16, .04), stick])
				parts.append([at + Vector3(-.055, -.16, -.055), at + Vector3(.055, -.07, .055), cap])
			return parts
		"pusher":
			# a stone body with a wooden pushing plate on its front; while the head is out the
			# plate has moved with it, so only the body shows
			var pv: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0),
				Vector3(0, 1, 0), Vector3(0, -1, 0)][mini(facing[id], 5)]
			var fx: int = x + int(pv.x)
			var fy: int = y + int(pv.y)
			var fz: int = z + int(pv.z)
			var nb := world.get_block(fx, fy, fz)
			var out := nb >= PUSHER_HEAD and nb <= PUSHER_HEAD + 5
			var body_lo := Vector3(-.5, -.5, -.5)
			var body_hi := Vector3(.5, .5, .5)
			var plate_lo := Vector3(-.5, -.5, -.5)
			var plate_hi := Vector3(.5, .5, .5)
			for a in 3:
				if pv[a] > 0:
					body_hi[a] = .25
					plate_lo[a] = .25
				elif pv[a] < 0:
					body_lo[a] = -.25
					plate_hi[a] = -.25
			if out:
				return [[Vector3(-.5, -.5, -.5), Vector3(.5, .5, .5), tile_side[22]]]
			return [[body_lo, body_hi, tile_side[22]], [plate_lo, plate_hi, tile_side[7]]]
		"funnel":
			# a wide bowl on top narrowing to a spout below: things go in at the top, out below
			var rim: int = tile_side[id]
			return [[Vector3(-.5, .12, -.5), Vector3(.5, .5, .5)],
				[Vector3(-.3, -.22, -.3), Vector3(.3, .12, .3), rim],
				[Vector3(-.12, -.5, -.12), Vector3(.12, -.22, .12), rim]]
		"plate":
			return [[Vector3(-.44, -.5, -.44), Vector3(.44, -.44, .44)]]
		"pusher_head":
			# a wooden plate at the far side of the cell, on a rod back to the pusher
			var dv: Vector3 = [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0),
				Vector3(0, 1, 0), Vector3(0, -1, 0)][mini(facing[id], 5)]
			var plate_lo := Vector3(-.5, -.5, -.5)
			var plate_hi := Vector3(.5, .5, .5)
			var rod_lo := Vector3(-.12, -.12, -.12)
			var rod_hi := Vector3(.12, .12, .12)
			for a in 3:
				if dv[a] > 0:
					plate_lo[a] = .25
					rod_lo[a] = -.5
					rod_hi[a] = .25
				elif dv[a] < 0:
					plate_hi[a] = -.25
					rod_lo[a] = -.25
					rod_hi[a] = .5
			return [[plate_lo, plate_hi, tile_side[7]], [rod_lo, rod_hi, tile_side[7]]]
		"track":
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, -.46, .5)]]
		"ladder":
			var sides := [[Vector3(-.5, -.5, .42), Vector3(.5, .5, .5)], [Vector3(.42, -.5, -.5), Vector3(.5, .5, .5)],
				[Vector3(-.5, -.5, -.5), Vector3(.5, .5, -.42)], [Vector3(-.5, -.5, -.5), Vector3(-.42, .5, .5)]]
			return [sides[facing[id]]]
		"door":
			if door_axis[id] == 0:
				return [[Vector3(-.5, -.5, -.5), Vector3(-.32, .5, .5)]] if door_open[id] else [[Vector3(-.5, -.5, -.09), Vector3(.5, .5, .09)]]
			return [[Vector3(-.5, -.5, -.5), Vector3(.5, .5, -.32)]] if door_open[id] else [[Vector3(-.09, -.5, -.5), Vector3(.09, .5, .5)]]
		"fence":
			var boxes := [[Vector3(-.125, -.5, -.125), Vector3(.125, .5, .125)]]
			for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nb := world.get_block(x + dd.x, y, z + dd.y)
				if nb == id or (nb != 0 and transparent[nb] == 0):
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
	var lmp := 15 if emit[id] else l.y
	var shape: String = shapes[id]
	var origin := Vector3(x, y, z)
	if shape == "cross":                          # two crossed, double-sided quads
		var g: Group = out["plants"]
		var col := Color(l.x / 15.0, lmp / 15.0, 0.9, 1.0)
		var tile := tile_side[id]
		for diag in [[Vector2(-.45, -.45), Vector2(.45, .45)], [Vector2(-.45, .45), Vector2(.45, -.45)]]:
			var a: Vector2 = diag[0]
			var b: Vector2 = diag[1]
			var quad := [Vector3(a.x, -.5, a.y), Vector3(b.x, -.5, b.y), Vector3(b.x, .5, b.y), Vector3(a.x, .5, a.y)]
			var quv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for order in [[0, 1, 2, 2, 3, 0], [0, 3, 2, 2, 1, 0]]:
				for i in order:
					g.verts.append(origin + quad[i])
					g.colors.append(col)
					g.uvs.append(_uv(tile, quv[i].x, quv[i].y))
		return
	var g: Group = out["plants"] if shape in ["ladder", "torch", "carpet", "wire", "lever", "button", "track", "plate"] else out["solid"]   # plants: no collision
	for box in shape_boxes(id, x, y, z):
		var lo: Vector3 = box[0]
		var hi: Vector3 = box[1]
		for f in 6:
			var n: Vector3i = faces[f][0]
			var axis := 0 if n.x != 0 else (1 if n.y != 0 else 2)
			var edge := hi[axis] == 0.5 if n[axis] > 0 else lo[axis] == -0.5
			if edge:
				var nb := world.get_block(x + n.x, y + n.y, z + n.z)
				if nb != 0 and transparent[nb] == 0:
					continue                      # flush against an opaque block
			var tile := tile_top[id] if n.y > 0 else (tile_bottom[id] if n.y < 0 else tile_side[id])
			if box.size() > 2:
				tile = int(box[2])                # this part has a picture of its own (stone base, wood stick)
			var col := Color(l.x / 15.0, lmp / 15.0, faces[f][1], 1.0)
			for i in 6:
				var c: Vector3 = corners[f][i]
				var p := Vector3(lo.x if c.x < 0 else hi.x, lo.y if c.y < 0 else hi.y, lo.z if c.z < 0 else hi.z)
				g.verts.append(origin + p)
				g.colors.append(col)
				var u := p.x + .5
				var v := p.z + .5
				if shape == "torch":
					u = p.x - (lo.x + hi.x) * .5 + .5
					v = p.z - (lo.z + hi.z) * .5 + .5
				if n.y == 0:
					u = (p.z if n.x != 0 else p.x) + .5
					v = p.y + .5
					if shape == "torch":                 # the torch picture, wherever the stick stands
						u = (p.z - (lo.z + hi.z) * .5 if n.x != 0 else p.x - (lo.x + hi.x) * .5) + .5
						v = p.y - lo.y
				g.uvs.append(_uv(tile, u, v))
