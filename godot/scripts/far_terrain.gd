class_name FarTerrain
extends Node3D
## The land beyond the loaded chunks: a light, low-detail sheet of the world's shape, worked
## out from the terrain generator's heights alone (no blocks are generated for it). Mountains,
## seas, snow and deserts on the horizon cost one small mesh, rebuilt in the background when
## you move a chunk away. The real chunks cover its middle; it is cut out there.

const STEP := 8                         # blocks between points
const DROP := 1.5                       # sits a little lower, so the real ground always wins

var world: WorldData
var distance := 512                     # blocks from you to the edge (0 = off)
var near_chunks := 6                    # the loaded square's half width in chunks (cut out)
var _mesh_node: MeshInstance3D
var _mat: StandardMaterial3D
var _task := -1
var _result = null
var _lock := Mutex.new()
var _built_for := []                    # [center, distance, near] of what is shown
var covered := {}                       # chunk keys drawn by the real chunks (the far land skips them)
var _covered_built := {}
var _since := 0.0
# what you built, seen from afar: per chunk with edits, one coloured column per (x, z) up to its
# highest built block, so whole buildings and cities stay visible beyond the real chunks
var color_of: Callable                  # block id -> Color (the minimap's colours)
var _builds := {}                       # chunk key -> {"n": edits counted, "cols": [[x, z, top, bottom, color]]}
var _builds_changed := false
var _scan_keys: Array = []


func _ready() -> void:
	_mesh_node = MeshInstance3D.new()
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh_node.material_override = _mat
	add_child(_mesh_node)


## Every frame: start a rebuild when you moved to another chunk, show it when it is ready.
func update(player_pos: Vector3, light: float) -> void:
	_mat.albedo_color = Color(light, light, light)
	_lock.lock()
	var done = _result
	_result = null
	_lock.unlock()
	if done != null:
		if _task != -1:
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
		var mesh := ArrayMesh.new()                  # made here, on the main thread
		if not (done[0] as PackedVector3Array).is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = done[0]
			arrays[Mesh.ARRAY_COLOR] = done[1]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_mesh_node.mesh = mesh
		_built_for = done[2]
	if distance <= 0 or world == null or world.dimension != "overworld":
		_mesh_node.visible = false
		return
	_mesh_node.visible = true
	var c := Vector2i(floori(player_pos.x + 0.5) >> 4, floori(player_pos.z + 0.5) >> 4)
	var want := [c, distance, near_chunks]
	_since += get_process_delta_time()
	_scan_builds()
	if _task != -1:
		return
	var holes_changed := covered.size() != _covered_built.size() or not covered.keys().all(func(k): return _covered_built.has(k))
	holes_changed = holes_changed or _builds_changed
	if want == _built_for and not (holes_changed and _since > 1.0):
		return
	if _built_for.size() == 3 and _built_for[1] == distance and _built_for[2] == near_chunks and not (holes_changed and _since > 1.0):
		var was: Vector2i = _built_for[0]
		if maxi(absi(c.x - was.x), absi(c.y - was.y)) < 2:
			return                                   # it overlaps the real ground by two chunks
	_since = 0.0
	_covered_built = covered.duplicate()
	# a private copy of the generator, so the worker shares nothing with the game
	var g := WorldData.new(world.seed, world.dimension)
	g.gen = world.gen
	_builds_changed = false
	var near_builds := {}
	var reach := distance / 16 + 1
	for k in _builds:
		if maxi(absi(k.x - c.x), absi(k.y - c.y)) <= reach and not _covered_built.has(k):
			near_builds[k] = _builds[k]["cols"]
	_task = WorkerThreadPool.add_task(_build.bind(g, want, _covered_built.duplicate(), near_builds))


## A few chunks per frame: is what was built there still the same? (Re-worked out if not.)
func _scan_builds() -> void:
	if not color_of.is_valid():
		return
	if _scan_keys.is_empty():
		_scan_keys = world.changes.keys()
		for k in _builds.keys():
			if not world.changes.has(k):
				_builds.erase(k)
				_builds_changed = true
	for i in mini(4, _scan_keys.size()):
		var k: Vector2i = _scan_keys.pop_back()
		var edits = world.changes.get(k)
		if edits == null:
			continue
		var n: int = edits.size()
		if _builds.has(k) and int(_builds[k]["n"]) == n:
			continue
		_builds[k] = {"n": n, "cols": _columns_of(edits)}
		_builds_changed = true


## The built columns of one chunk's edits: [x, z, highest block, lowest block, colour].
func _columns_of(edits: Dictionary) -> Array:
	var tops := {}
	for p in edits:
		var id: int = edits[p]
		if id == 0 or (Blocks.solid[id] == 0 and Blocks.fluid[id] != 1):
			continue                                 # air, plants, wires, torches: too small to see
		var cc := Vector2i(p.x, p.z)
		var t = tops.get(cc)
		if t == null:
			tops[cc] = [p.y, p.y, id]
		else:
			if p.y > int(t[0]):
				t[0] = p.y
				t[2] = id
			if p.y < int(t[1]):
				t[1] = p.y
	var out := []
	for cc in tops:
		var t: Array = tops[cc]
		out.append([cc.x, cc.y, int(t[0]), int(t[1]), color_of.call(int(t[2]))])
	return out


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _build(g: WorldData, want: Array, cov: Dictionary, builds: Dictionary = {}) -> void:
	var c: Vector2i = want[0]
	var dist: int = want[1]
	var near: int = want[2]
	var cx := c.x * 16 + 8
	var cz := c.y * 16 + 8
	var n := dist / STEP
	var size := n * 2 + 1
	var heights := PackedFloat32Array()
	var colors := PackedColorArray()
	heights.resize(size * size)
	colors.resize(size * size)
	var water: int = g.WATER_LEVEL
	var snow: int = g.SNOW_LINE
	for iz in size:
		for ix in size:
			var x := cx + (ix - n) * STEP
			var z := cz + (iz - n) * STEP
			var cl := g._column_climate(x, z)
			var h: int = cl[0]
			var col: Color
			if h < water:
				col = Color(0.2, 0.36, 0.7).lerp(Color(0.1, 0.18, 0.45), clampf((water - h) / 30.0, 0.0, 1.0))
			elif h >= snow:
				col = Color(0.93, 0.95, 0.98)
			elif cl[1] or h <= water + 1:
				col = Color(0.85, 0.79, 0.55)                 # desert or beach sand
			else:
				var forest: float = cl[4]
				col = Color(0.36, 0.6, 0.24).lerp(Color(0.18, 0.38, 0.14), clampf((forest - 0.35) * 2.5, 0.0, 1.0))
				if h > snow - 12:
					col = col.lerp(Color(0.5, 0.5, 0.5), 0.5)       # high up: bare rock shows through
			heights[iz * size + ix] = maxf(h, water) + 0.5 - DROP
			colors[iz * size + ix] = col
	# a sheet of quads, skipping the middle where the real chunks are
	var cut := maxi(near - 2, 1) * 16 + 8
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for iz in size - 1:
		for ix in size - 1:
			var x0 := (ix - n) * STEP
			var z0 := (iz - n) * STEP
			if cov.is_empty():
				if absi(x0 + STEP / 2) < cut and absi(z0 + STEP / 2) < cut:
					continue
			elif cov.has(Vector2i(floori(float(cx + x0 + STEP / 2) / 16.0), floori(float(cz + z0 + STEP / 2) / 16.0))):
				continue                                 # a real chunk is drawn here
			var i00 := iz * size + ix
			var h00 := heights[i00]
			var h10 := heights[i00 + 1]
			var h01 := heights[i00 + size]
			var h11 := heights[i00 + size + 1]
			# light from one side: slopes facing it are brighter, the others darker
			var shade := clampf(1.0 + ((h00 - h10) + (h00 - h01)) * 0.035, 0.7, 1.15)
			var col: Color = colors[i00] * shade
			col.a = 1.0
			var p00 := Vector3(cx + x0, h00, cz + z0)
			var p10 := Vector3(cx + x0 + STEP, h10, cz + z0)
			var p01 := Vector3(cx + x0, h01, cz + z0 + STEP)
			var p11 := Vector3(cx + x0 + STEP, h11, cz + z0 + STEP)
			for v in [p00, p10, p11, p00, p11, p01]:
				verts.append(v)
				cols.append(col)
	# skirts: where a real chunk meets the far land, a short wall along the edge of the hole.
	# A real chunk does not draw its outer sides (the blocks next to them exist), so without
	# this you would look through the gap under its edge and see the sky.
	if not cov.is_empty():
		var hole := func(ix: int, iz: int) -> bool:
			if ix < 0 or iz < 0 or ix >= size - 1 or iz >= size - 1:
				return false
			var qx := (ix - n) * STEP
			var qz := (iz - n) * STEP
			return cov.has(Vector2i(floori(float(cx + qx + STEP / 2) / 16.0), floori(float(cz + qz + STEP / 2) / 16.0)))
		# per side: neighbour quad offset, then the two grid points of the shared edge
		var sides := [[1, 0, 1, 0, 1, 1], [-1, 0, 0, 0, 0, 1], [0, 1, 0, 1, 1, 1], [0, -1, 0, 0, 1, 0]]
		for iz in size - 1:
			for ix in size - 1:
				if not hole.call(ix, iz):
					continue
				for sd in sides:
					var nx: int = ix + sd[0]
					var nz: int = iz + sd[1]
					if nx < 0 or nz < 0 or nx >= size - 1 or nz >= size - 1 or hole.call(nx, nz):
						continue
					var ax: int = ix + sd[2]
					var az: int = iz + sd[3]
					var bx: int = ix + sd[4]
					var bz: int = iz + sd[5]
					var ha := heights[az * size + ax]
					var hb := heights[bz * size + bx]
					var top := maxf(ha, hb) + DROP + 1.5
					var bottom := minf(ha, hb) - 3.0
					var pa := Vector3(cx + (ax - n) * STEP, 0, cz + (az - n) * STEP)
					var pb := Vector3(cx + (bx - n) * STEP, 0, cz + (bz - n) * STEP)
					var col: Color = colors[iz * size + ix] * 0.55
					col.a = 1.0
					var a0 := Vector3(pa.x, bottom, pa.z)
					var b0 := Vector3(pb.x, bottom, pb.z)
					var a1 := Vector3(pa.x, top, pa.z)
					var b1 := Vector3(pb.x, top, pb.z)
					for v in [a0, b0, b1, a0, b1, a1, a0, b1, b0, a0, a1, b1]:     # both sides
						verts.append(v)
						cols.append(col)
	_add_builds(g, builds, verts, cols)
	_lock.lock()
	_result = [verts, cols, want]
	_lock.unlock()


## Buildings far away: a coloured top on every built column and walls where it stands above
## its neighbour (another built column, or the ground).
func _add_builds(g: WorldData, builds: Dictionary, verts: PackedVector3Array, cols: PackedColorArray) -> void:
	var topmap := {}
	for k in builds:
		for col in builds[k]:
			topmap[Vector2i(col[0], col[1])] = int(col[2])
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for k in builds:
		for col in builds[k]:
			var x: int = col[0]
			var z: int = col[1]
			var y: float = float(col[2]) + 0.5
			var bottom: float = float(col[3]) - 0.5
			var c: Color = col[4]
			c.a = 1.0
			var a := Vector3(x - 0.5, y, z - 0.5)
			var b := Vector3(x + 0.5, y, z - 0.5)
			var cc := Vector3(x + 0.5, y, z + 0.5)
			var d := Vector3(x - 0.5, y, z + 0.5)
			for v in [a, b, cc, a, cc, d]:
				verts.append(v)
				cols.append(c)
			for dd in dirs:
				var nb: Vector2i = Vector2i(x, z) + dd
				var low: float
				if topmap.has(nb):
					low = float(topmap[nb]) + 0.5
				else:
					low = minf(bottom, float(g._column_climate(nb.x, nb.y)[0]) + 0.5)
				if low >= y:
					continue
				var side: Color = c * (0.82 if dd.x != 0 else 0.68)
				side.a = 1.0
				var ex: float = 0.5 * dd.x
				var ez: float = 0.5 * dd.y
				# the edge of the column top on this side
				var p0 := Vector3(x + ex + (0.0 if dd.x != 0 else -0.5), 0, z + ez + (0.0 if dd.y != 0 else -0.5))
				var p1 := Vector3(x + ex + (0.0 if dd.x != 0 else 0.5), 0, z + ez + (0.0 if dd.y != 0 else 0.5))
				if dd.x != 0:
					p0.z = z - 0.5
					p1.z = z + 0.5
				var q0 := Vector3(p0.x, low, p0.z)
				var q1 := Vector3(p1.x, low, p1.z)
				var r0 := Vector3(p0.x, y, p0.z)
				var r1 := Vector3(p1.x, y, p1.z)
				for v in [q0, q1, r1, q0, r1, r0]:
					verts.append(v)
					cols.append(side)
