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
var max_jobs := 1
var _pending := []                  # finished meshes waiting to be shown (a few per frame)
var _faces := {}                    # Vector2i -> PackedVector3Array: collision faces, kept for later
var _bodies := {}                   # Vector2i -> StaticBody3D, only for chunks next to the player
const APPLY_PER_FRAME := 2
const COLLISION_RANGE := 1          # chunks around the player that need collision
var _tasks := {}                    # WorkerThreadPool task id -> true, waited for once finished


func setup(w: WorldData, mats: Dictionary, distance: int) -> void:
	world = w
	materials = mats
	render_distance = distance
	# shared tables must exist before any worker thread uses them (two threads building
	# them at the same moment could corrupt memory and crash the app)
	Mesher._static_setup()
	# one background thread: enough to keep up, and nothing for two workers to fight over
	max_jobs = 0 if Boot.safe_mode else 1


func _exit_tree() -> void:
	set_process(false)
	# let running jobs finish before the world goes away
	for t in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
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
			_faces.erase(k)
			_bodies.erase(k)
	_update_collision()
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


var last_usec := 0                  # main-thread time this manager took last frame


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_collect()
	_schedule()
	# show a few finished meshes per frame: many at once would make the game stutter
	var n := 0
	while not _pending.is_empty() and n < APPLY_PER_FRAME:
		var r: Array = _pending.pop_front()
		var key: Vector2i = r[1]
		if r[3] == version.get(key, 0) and _dist(key, _center) <= render_distance + 1:
			_apply(key, r[2])
			chunk_ready.emit(key)
			n += 1
	last_usec = Time.get_ticks_usec() - t0


## Collision shapes cost time to build and to simulate: only the chunks around the player
## get them (the player is the only thing that uses them; animals and aiming read the blocks).
func _update_collision() -> void:
	for k in _bodies.keys():
		if _dist(k, _center) > COLLISION_RANGE:
			if is_instance_valid(_bodies[k]):
				_bodies[k].queue_free()
			_bodies.erase(k)
	for k in _faces:
		if _dist(k, _center) <= COLLISION_RANGE and not _bodies.has(k) and views.has(k):
			_add_body(k)


func _add_body(key: Vector2i) -> void:
	var faces: PackedVector3Array = _faces[key]
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	views[key].add_child(body)
	_bodies[key] = body


func _jobs() -> int:
	return _generating.size() + _meshing.size()


func _schedule() -> void:
	if _dirty.is_empty():
		return
	if max_jobs == 0:
		_schedule_inline()
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


## Safe mode: no threads. One piece of work per frame on the main thread.
func _schedule_inline() -> void:
	var order: Array = _dirty.keys()
	order.sort_custom(func(a, b):
		if _urgent.has(a) != _urgent.has(b):
			return _urgent.has(a)
		return (a - _center).length_squared() < (b - _center).length_squared())
	var key: Vector2i = order[0]
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(key.x + dx, key.y + dz)
			if not world.chunks.has(k):
				world.ensure_chunk(k)
				return                         # one chunk generated this frame is enough
	_dirty.erase(key)
	_urgent.erase(key)
	version[key] = version.get(key, 0) + 1
	_apply(key, Mesher.new(world).build(key))
	chunk_ready.emit(key)


func _start_generation(key: Vector2i) -> void:
	_generating[key] = true
	# everything the job needs is made here, on the main thread, and only the job uses it
	var g := WorldData.new(world.seed)
	var edits: Dictionary = world.changes.get(key, {}).duplicate(true)
	if not edits.is_empty():
		g.changes[key] = edits
	_tasks[WorkerThreadPool.add_task(_generate_job.bind(g, key))] = true


func _generate_job(g: WorldData, key: Vector2i) -> void:
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
				snap.emitters[k] = world.emitters[k].duplicate(true)
	var mesher := Mesher.new(snap)
	_tasks[WorkerThreadPool.add_task(_mesh_job.bind(mesher, key, version[key]))] = true


func _mesh_job(mesher: Mesher, key: Vector2i, v: int) -> void:
	var groups := mesher.build(key)
	_lock.lock()
	_results.append(["mesh", key, groups, v])
	_lock.unlock()


func _collect() -> void:
	_lock.lock()
	var done := _results
	_results = []
	_lock.unlock()
	# finished tasks must be waited for once, or the pool keeps them forever
	for t in _tasks.keys():
		if WorkerThreadPool.is_task_completed(t):
			WorkerThreadPool.wait_for_task_completion(t)
			_tasks.erase(t)
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
			# edited chunks first (you see your own block at once), the rest a few per frame
			if _dist(key, _center) <= COLLISION_RANGE:
				_pending.push_front(r)
			else:
				_pending.append(r)


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
	add_child(root)
	views[key] = root
	_faces[key] = collision_faces
	_bodies.erase(key)
	if _dist(key, _center) <= COLLISION_RANGE:
		_add_body(key)
