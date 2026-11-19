class_name ChunkManager
extends Node3D
## Streams chunks around the player. Generation, lighting and meshing run on worker threads
## (WorkerThreadPool) so the game never stutters on a phone: each job works on its own
## copy of the data it needs, and only finished results come back to the main thread.

signal chunk_ready(key: Vector2i)

var world: WorldData
var render_distance := 4
var materials := {}                 # group name -> Material
var views := {}                     # Vector2i -> Node3D (the chunk's meshes + collision)
var version := {}                   # Vector2i -> int, newest mesh request (older results are dropped)
var _generating := {}               # Vector2i -> true while a generation job runs
var _meshing := {}                  # Vector2i -> true while a mesh job runs
var _dirty := {}                    # Vector2i -> true: needs a (re)mesh
var _urgent := {}                   # edited chunks, meshed before anything else
var _results: Array = []            # finished jobs, filled by worker threads
var _lock := Mutex.new()
var _center := Vector2i(999999, 999999)
var max_jobs := 2


func setup(w: WorldData, mats: Dictionary, distance: int) -> void:
	world = w
	materials = mats
	render_distance = distance
	max_jobs = clampi(OS.get_processor_count() - 1, 1, 3)


func _exit_tree() -> void:
	set_process(false)
	# let running jobs finish before the world goes away
	while not (_generating.is_empty() and _meshing.is_empty()):
		OS.delay_msec(5)
		_collect()


## Edited chunks: re-mesh them first.
func rebuild(keys: Array) -> void:
	for k in keys:
		if views.has(k) or _dirty.has(k):
			_dirty[k] = true
			_urgent[k] = true


func update_center(position: Vector3, force := false) -> void:
	var c := WorldData.chunk_key(floori(position.x + 0.5), floori(position.z + 0.5))
	if c == _center and not force:
		return
	_center = c
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not views.has(k):
				_dirty[k] = true
	for k in views.keys():
		if _dist(k, c) > render_distance + 1:
			views[k].queue_free()
			views.erase(k)
			_dirty.erase(k)
	for k in world.chunks.keys():
		if _dist(k, c) > render_distance + 3 and not _generating.has(k):
			world.unload_chunk(k)
	for k in _dirty.keys():
		if _dist(k, c) > render_distance:
			_dirty.erase(k)


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func is_ready_at(position: Vector3) -> bool:
	return views.has(WorldData.chunk_key(floori(position.x + 0.5), floori(position.z + 0.5)))


func _process(_delta: float) -> void:
	_collect()
	_schedule()


func _jobs() -> int:
	return _generating.size() + _meshing.size()


func _schedule() -> void:
	if _dirty.is_empty():
		return
	var order: Array = _dirty.keys()
	order.sort_custom(func(a, b):
		var ua := _urgent.has(a)
		var ub := _urgent.has(b)
		if ua != ub:
			return ua
		return (a - _center).length_squared() < (b - _center).length_squared())
	for key in order:
		if _jobs() >= max_jobs and not _urgent.has(key):
			return
		if _meshing.has(key):
			continue
		# all 9 chunks around it must exist before it can be meshed
		var missing := []
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := Vector2i(key.x + dx, key.y + dz)
				if not world.chunks.has(k):
					missing.append(k)
		if missing.is_empty():
			_start_mesh(key)
		else:
			for k in missing:
				if not _generating.has(k) and _jobs() < max_jobs:
					_start_generation(k)


func _start_generation(key: Vector2i) -> void:
	_generating[key] = true
	var edits: Dictionary = world.changes.get(key, {}).duplicate()
	WorkerThreadPool.add_task(_generate_job.bind(world.seed, key, edits))


func _generate_job(seed: int, key: Vector2i, edits: Dictionary) -> void:
	var g := WorldData.new(seed)
	if not edits.is_empty():
		g.changes[key] = edits
	g.ensure_chunk(key)
	_lock.lock()
	_results.append(["chunk", key, g.chunks[key], g.emitters.get(key, {})])
	_lock.unlock()


func _start_mesh(key: Vector2i) -> void:
	_meshing[key] = true
	_dirty.erase(key)
	_urgent.erase(key)
	version[key] = version.get(key, 0) + 1
	# a private copy of the 3x3 chunks for the worker
	var snap := WorldData.new(world.seed)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(key.x + dx, key.y + dz)
			var c := WorldData.Chunk.new()
			c.b = world.chunks[k].b.duplicate()
			snap.chunks[k] = c
			if world.emitters.has(k):
				snap.emitters[k] = world.emitters[k].duplicate()
	WorkerThreadPool.add_task(_mesh_job.bind(snap, key, version[key]))


func _mesh_job(snap: WorldData, key: Vector2i, v: int) -> void:
	var groups := Mesher.new(snap).build(key)
	_lock.lock()
	_results.append(["mesh", key, groups, v])
	_lock.unlock()


func _collect() -> void:
	_lock.lock()
	var done := _results
	_results = []
	_lock.unlock()
	for r in done:
		var key: Vector2i = r[1]
		if r[0] == "chunk":
			_generating.erase(key)
			if not world.chunks.has(key):
				world.chunks[key] = r[2]
				if not r[3].is_empty():
					world.emitters[key] = r[3]
		else:
			_meshing.erase(key)
			if r[3] == version.get(key, 0) and _dist(key, _center) <= render_distance + 1:
				_apply(key, r[2])
				chunk_ready.emit(key)


func _apply(key: Vector2i, groups: Dictionary) -> void:
	if views.has(key):
		views[key].queue_free()
	var root := Node3D.new()
	root.name = "chunk_%d_%d" % [key.x, key.y]
	var collision_faces := PackedVector3Array()
	for name in groups:
		var g = groups[name]
		if g.verts.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.verts
		arrays[Mesh.ARRAY_COLOR] = g.colors
		arrays[Mesh.ARRAY_TEX_UV] = g.uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = materials[name]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		if name == "solid" or name == "translucent":
			collision_faces.append_array(g.verts)
	if not collision_faces.is_empty():
		var body := StaticBody3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(collision_faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
	add_child(root)
	views[key] = root
