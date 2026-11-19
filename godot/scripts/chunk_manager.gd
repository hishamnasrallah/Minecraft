class_name ChunkManager
extends Node3D
## Streams the world around the player. Generation, lighting and meshing run on a worker
## thread (WorkerThreadPool) so the game never stutters: each job works on its own copy of
## the data it needs, and only finished results come back to the main thread.
##
## Chunks are meshed in vertical sections of 32 rows. Only the sections that can be seen are
## meshed: the surface band of each chunk (from its lowest ground up to its highest block)
## and the sections near the player's height when going underground. Deep stone that nobody
## sees costs nothing, which is what lets the world be hundreds of blocks deep on a phone.

signal chunk_ready(key: Vector2i)

const SEC := Mesher.SEC
const APPLY_PER_FRAME := 2
const COLLISION_RANGE := 1          # chunks around the player that need collision
const BELOW := 24                   # rows under the player that are kept meshed
const ABOVE := 40                   # ... and above (caves, a ceiling)

var world: WorldData
var render_distance := 4
var materials := {}                 # group name -> Material
var views := {}                     # Vector2i -> Node3D (the chunk's section nodes)
var sections := {}                  # Vector3i(cx, section, cz) -> Node3D (meshes + collision)
var version := {}                   # Vector3i section -> newest mesh request
var shown_version := {}             # Vector3i section -> version on screen now. A result newer than
                                    # that is shown even if a later one is on its way: when you keep
                                    # breaking blocks, every change still appears at once
var max_jobs := 1
var last_usec := 0                  # main-thread time this manager took last frame

var _heights := {}                  # Vector2i -> [lowest ground, highest block] of the chunk
var _generating := {}               # Vector2i -> true while a generation job runs
var _meshing := {}                  # Vector2i -> true while a mesh job runs
var _dirty := {}                    # Vector2i -> {section: true} to (re)mesh ({} = decide after generation)
var _urgent := {}                   # edited chunks, meshed before anything else
var _results: Array = []            # finished jobs, filled by worker threads
var _lock := Mutex.new()
var _center := Vector2i(999999, 999999)
var _player_y := 0
var _player_sec := -1
var _pending := []                  # finished meshes waiting to be shown (a few per frame)
var _faces := {}                    # Vector3i section -> PackedVector3Array collision faces
var _bodies := {}                   # Vector3i section -> StaticBody3D (only near the player)
var _tasks := {}                    # WorkerThreadPool task id -> true, waited for once finished
var _transparent: PackedByteArray


func setup(w: WorldData, mats: Dictionary, distance: int) -> void:
	world = w
	materials = mats
	render_distance = distance
	# shared tables must exist before any worker thread uses them
	Mesher._static_setup()
	_transparent = Blocks.transparent.duplicate()
	# one background thread: enough to keep up, and nothing for two workers to fight over
	max_jobs = 0 if Boot.safe_mode else 1


func _exit_tree() -> void:
	set_process(false)
	for t in _tasks.keys():
		WorkerThreadPool.wait_for_task_completion(t)
	_tasks.clear()
	_collect()


static func _dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


static func section_key(key: Vector2i, s: int) -> Vector3i:
	return Vector3i(key.x, s, key.y)


# ---------------------------------------------------------------- which sections are wanted
## Lowest ground and highest block of a chunk (scans its columns once; the generation job
## does this on the worker thread for new chunks).
static func scan_heights(c: WorldData.Chunk, transparent: PackedByteArray) -> Array:
	var H := WorldData.H
	var lowest := H
	var highest := 0
	for lx in 16:
		for lz in 16:
			for y in range(H - 1, -1, -1):
				var b := c.b[(lx * H + y) * 16 + lz]
				if b == 0:
					continue
				highest = maxi(highest, y)
				if transparent[b] == 0 or b == WorldData.WATER:
					lowest = mini(lowest, y)
					break
	return [mini(lowest, highest), highest]


func _heights_of(key: Vector2i) -> Array:
	if not _heights.has(key) and world.chunks.has(key):
		_heights[key] = scan_heights(world.chunks[key], _transparent)
	return _heights.get(key, [])


func wanted(key: Vector2i) -> Array:
	var h := _heights_of(key)
	if h.is_empty():
		return []
	var lo := mini(int(h[0]) - 6, _player_y - BELOW)
	var hi := int(h[1]) + 1
	if _player_y + ABOVE < int(h[0]):          # deep underground: the player's band only
		hi = mini(hi, _player_y + ABOVE)
	lo = clampi(lo, 0, WorldData.H - 1)
	hi = clampi(hi, lo, WorldData.H - 1)
	var out := []
	for s in range(lo / SEC, hi / SEC + 1):
		out.append(s)
	return out


func _mark(key: Vector2i) -> void:
	if not world.chunks.has(key):
		if not _dirty.has(key):
			_dirty[key] = {}
		return
	for s in wanted(key):
		if not sections.has(section_key(key, s)):
			var d: Dictionary = _dirty.get(key, {})
			d[s] = true
			_dirty[key] = d


## Edited chunks: re-mesh their sections around the edited rows first.
## No rows given (building tools, growing trees): every shown section of those chunks.
func rebuild(keys: Array, y_lo := -1, y_hi := -1) -> void:
	for k in keys:
		if not (views.has(k) or _dirty.has(k)):
			continue
		var h := _heights_of(k)
		if y_lo < 0:
			_heights.erase(k)                    # blocks may have been added anywhere
			h = _heights_of(k)
		elif not h.is_empty():
			h[0] = mini(int(h[0]), y_lo)
			h[1] = maxi(int(h[1]), y_hi)
		var d: Dictionary = _dirty.get(k, {})
		var s_lo := 0
		var s_hi := (WorldData.H - 1) / SEC
		if y_lo >= 0:
			s_lo = maxi(y_lo - 1, 0) / SEC
			s_hi = mini(y_hi + 1, WorldData.H - 1) / SEC
		var want := wanted(k)
		for s in range(s_lo, s_hi + 1):
			if sections.has(section_key(k, s)) or s in want:
				d[s] = true
		_dirty[k] = d
		_urgent[k] = true


func update_center(position: Vector3, force := false) -> void:
	var c := WorldData.chunk_key(floori(position.x + 0.5), floori(position.z + 0.5))
	var py := clampi(floori(position.y), 0, WorldData.H - 1)
	var ps := py / 8                            # re-check every 8 rows of height
	var moved := c != _center or force
	if not moved and ps == _player_sec:
		return
	_player_y = py
	_player_sec = ps
	_center = c
	for dx in range(-render_distance, render_distance + 1):
		for dz in range(-render_distance, render_distance + 1):
			_mark(Vector2i(c.x + dx, c.y + dz))
	if moved:
		for k in views.keys():
			if _dist(k, c) > render_distance + 1:
				_drop_chunk(k)
		for k in world.chunks.keys():
			if _dist(k, c) > render_distance + 3 and not _generating.has(k) and not _meshing.has(k):
				world.unload_chunk(k)
				_heights.erase(k)
		for k in _dirty.keys():
			if _dist(k, c) > render_distance:
				_dirty.erase(k)
	_update_collision()


func _drop_chunk(k: Vector2i) -> void:
	views[k].queue_free()
	views.erase(k)
	_dirty.erase(k)
	for s in range(WorldData.H / SEC + 1):
		var sk := section_key(k, s)
		sections.erase(sk)
		_faces.erase(sk)
		_bodies.erase(sk)


func is_ready_at(position: Vector3) -> bool:
	var k := WorldData.chunk_key(floori(position.x + 0.5), floori(position.z + 0.5))
	if not views.has(k):
		return false
	var y := floori(position.y)
	for s in wanted(k):
		if s * SEC <= y and not sections.has(section_key(k, s)):
			return false
	return true


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_collect()
	_schedule()
	# show a few finished meshes per frame: many at once would make the game stutter
	var n := 0
	while not _pending.is_empty() and n < APPLY_PER_FRAME:
		var r: Array = _pending.pop_front()
		var key: Vector2i = r[1]
		if _dist(key, _center) > render_distance + 1:
			continue
		var shown := false
		for s in r[2]:
			var sk := section_key(key, s)
			if r[3][s] > shown_version.get(sk, 0):
				shown_version[sk] = r[3][s]
				_apply(key, s, r[2][s])
				shown = true
		if shown:
			chunk_ready.emit(key)
			n += 1
	last_usec = Time.get_ticks_usec() - t0


# ---------------------------------------------------------------- collision
## Collision shapes cost time to build and to simulate: only the sections around the player
## get them (the player is the only thing that uses them; animals and aiming read the blocks).
func _near(sk: Vector3i) -> bool:
	return _dist(Vector2i(sk.x, sk.z), _center) <= COLLISION_RANGE and absi(sk.y * SEC + SEC / 2 - _player_y) <= SEC + SEC / 2


func _update_collision() -> void:
	for sk in _bodies.keys():
		if not _near(sk):
			if is_instance_valid(_bodies[sk]):
				_bodies[sk].queue_free()
			_bodies.erase(sk)
	for sk in _faces:
		if _near(sk) and not _bodies.has(sk) and sections.has(sk):
			_add_body(sk)


func _add_body(sk: Vector3i) -> void:
	var faces: PackedVector3Array = _faces[sk]
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	sections[sk].add_child(body)
	_bodies[sk] = body


# ---------------------------------------------------------------- scheduling
func _jobs() -> int:
	return _generating.size() + _meshing.size()


func _sorted_dirty() -> Array:
	var order: Array = _dirty.keys()
	order.sort_custom(func(a, b):
		if _urgent.has(a) != _urgent.has(b):
			return _urgent.has(a)
		return (a - _center).length_squared() < (b - _center).length_squared())
	return order


## The sections to mesh for a dirty chunk ({} from before it existed: decide now).
func _sections_for(key: Vector2i) -> Array:
	var d: Dictionary = _dirty[key]
	if d.is_empty():
		for s in wanted(key):
			if not sections.has(section_key(key, s)):
				d[s] = true
	return d.keys()


func _missing_around(key: Vector2i) -> Array:
	var missing := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(key.x + dx, key.y + dz)
			if not world.chunks.has(k):
				missing.append(k)
	return missing


func _schedule() -> void:
	if _dirty.is_empty():
		return
	if max_jobs == 0:
		_schedule_inline()
		return
	for key in _sorted_dirty():
		if _jobs() >= max_jobs and not _urgent.has(key):
			return
		if _meshing.has(key) and not _urgent.has(key):
			continue                                # an edited chunk may start again at once
		var missing := _missing_around(key)
		if missing.is_empty():
			var secs := _sections_for(key)
			if secs.is_empty():
				_dirty.erase(key)
				_urgent.erase(key)
			else:
				_start_mesh(key, secs)
		else:
			for k in missing:
				if not _generating.has(k) and _jobs() < max_jobs:
					_start_generation(k)


## Safe mode: no threads. One piece of work per frame on the main thread.
func _schedule_inline() -> void:
	var key: Vector2i = _sorted_dirty()[0]
	var missing := _missing_around(key)
	if not missing.is_empty():
		world.ensure_chunk(missing[0])
		return                                  # one chunk generated this frame is enough
	var secs := _sections_for(key)
	_dirty.erase(key)
	_urgent.erase(key)
	if secs.is_empty():
		return
	var m := Mesher.new(world)
	m.max_y = _max_y_around(key)
	var result := m.build_sections(key, secs)
	for s in result:
		var sk := section_key(key, s)
		version[sk] = version.get(sk, 0) + 1
		shown_version[sk] = version[sk]
		_apply(key, s, result[s])
	chunk_ready.emit(key)


func _max_y_around(key: Vector2i) -> int:
	var m := 0
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var h := _heights_of(Vector2i(key.x + dx, key.y + dz))
			m = maxi(m, int(h[1]) if not h.is_empty() else WorldData.H - 1)
	return mini(m + 1, WorldData.H - 1)


func _start_generation(key: Vector2i) -> void:
	_generating[key] = true
	# everything the job needs is made here, on the main thread, and only the job uses it
	var g := WorldData.new(world.seed, world.dimension)
	var edits: Dictionary = world.changes.get(key, {}).duplicate(true)
	if not edits.is_empty():
		g.changes[key] = edits
	_tasks[WorkerThreadPool.add_task(_generate_job.bind(g, key, _transparent.duplicate()))] = true


func _generate_job(g: WorldData, key: Vector2i, transparent: PackedByteArray) -> void:
	g.ensure_chunk(key)
	var heights := scan_heights(g.chunks[key], transparent)
	_lock.lock()
	_results.append(["chunk", key, g.chunks[key], g.emitters.get(key, {}), heights])
	_lock.unlock()


func _start_mesh(key: Vector2i, secs: Array) -> void:
	_meshing[key] = int(_meshing.get(key, 0)) + 1     # how many jobs for it are running
	_dirty.erase(key)
	_urgent.erase(key)
	var versions := {}
	for s in secs:
		var sk := section_key(key, s)
		version[sk] = version.get(sk, 0) + 1
		versions[s] = version[sk]
	# a private copy of the 3x3 chunks for the worker
	var snap := WorldData.new(world.seed, world.dimension)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var k := Vector2i(key.x + dx, key.y + dz)
			var c := WorldData.Chunk.new()
			c.b = world.chunks[k].b.duplicate()
			snap.chunks[k] = c
			if world.emitters.has(k):
				snap.emitters[k] = world.emitters[k].duplicate(true)
	var mesher := Mesher.new(snap)
	mesher.max_y = _max_y_around(key)
	_tasks[WorkerThreadPool.add_task(_mesh_job.bind(mesher, key, secs.duplicate(), versions))] = true


func _mesh_job(mesher: Mesher, key: Vector2i, secs: Array, versions: Dictionary) -> void:
	var groups := mesher.build_sections(key, secs)
	_lock.lock()
	_results.append(["mesh", key, groups, versions])
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
				_heights[key] = r[4]
				if not r[3].is_empty():
					world.emitters[key] = r[3]
		else:
			_meshing[key] = int(_meshing.get(key, 1)) - 1
			if _meshing[key] <= 0:
				_meshing.erase(key)
			# near chunks first (you see your own block at once), the rest a few per frame
			if _dist(key, _center) <= COLLISION_RANGE:
				_pending.push_front(r)
			else:
				_pending.append(r)


func _apply(key: Vector2i, s: int, groups: Dictionary) -> void:
	var sk := section_key(key, s)
	if sections.has(sk):
		sections[sk].queue_free()
	_bodies.erase(sk)
	if not views.has(key):
		var root := Node3D.new()
		root.name = "chunk_%d_%d" % [key.x, key.y]
		add_child(root)
		views[key] = root
	var node := Node3D.new()
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
		node.add_child(mi)
		if name == "solid" or name == "translucent":
			collision_faces.append_array(g.verts)
	views[key].add_child(node)
	sections[sk] = node
	_faces[sk] = collision_faces
	if _near(sk):
		_add_body(sk)
