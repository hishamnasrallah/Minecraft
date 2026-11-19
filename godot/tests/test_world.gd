extends RefCounted

var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/worldgen.json"))


func test_noise_matches_python() -> String:
	var seed: int = fixtures["seed"]
	for row in fixtures["noise"]:
		var fbm := VNoise.fbm(row[0] / 28.0, row[1] / 28.0, seed)
		var h := VNoise.hash2(int(row[0]), int(row[1]), seed)
		if fbm != float(row[2]) or h != float(row[3]):
			return "noise differs at %s: %s vs %s / %s vs %s" % [row, fbm, row[2], h, row[3]]
	for row in fixtures["noise3"]:
		var d := VNoise.cave_density(int(row[0]), int(row[1]), int(row[2]), seed)
		if absf(d - float(row[3])) > 1e-12:
			return "cave noise differs at %s: %s" % [row, d]
	return ""


func test_heights_match_python() -> String:
	var w := WorldData.new(int(fixtures["seed"]))
	for row in fixtures["heights"]:
		if w.height_at(int(row[0]), int(row[1])) != int(row[2]):
			return "height differs at %s: %d" % [row, w.height_at(int(row[0]), int(row[1]))]
	return ""


func test_generated_chunks_match_python_exactly() -> String:
	if int(fixtures["height"]) != WorldData.H:
		return "fixture world height %s, WorldData.H %d: re-run tools/export_godot.py" % [fixtures["height"], WorldData.H]
	var w := WorldData.new(int(fixtures["seed"]))
	for key_text in fixtures["chunks"]:
		var parts: PackedStringArray = key_text.split(",")
		var key := Vector2i(int(parts[0]), int(parts[1]))
		w.ensure_chunk(key)
		var got: PackedInt32Array = w.chunks[key].b
		var runs: Array = fixtures["chunks"][key_text]     # [id, count, ...] in chunk index order
		var i := 0
		var mismatches := 0
		var first := ""
		for r in range(0, runs.size(), 2):
			var want := int(runs[r])
			for n in int(runs[r + 1]):
				if got[i] != want:
					mismatches += 1
					if first == "":
						var lx := i / (WorldData.H * 16)
						var p := Vector3i(key.x * 16 + lx, (i / 16) % WorldData.H, key.y * 16 + i % 16)
						first = "%s: godot %d, python %d" % [p, got[i], want]
				i += 1
		if i != got.size():
			return "chunk %s: fixture has %d cells, chunk %d" % [key_text, i, got.size()]
		if mismatches:
			return "chunk %s: %d blocks differ, first %s" % [key_text, mismatches, first]
	return ""


func test_generation_speed() -> String:
	var w := WorldData.new(5)
	var t := Time.get_ticks_usec()
	for x in 3:
		for z in 3:
			w.ensure_chunk(Vector2i(x, z))
	print("        %.1f ms per chunk" % ((Time.get_ticks_usec() - t) / 9000.0))
	return ""


func test_mesh_and_light() -> String:
	var w := WorldData.new(11)
	var m := Mesher.new(w)
	var t := Time.get_ticks_usec()
	var out := m.build(Vector2i(0, 0))
	print("        mesh + light %.1f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	var g = out["solid"]
	if g.verts.size() == 0 or g.verts.size() != g.colors.size() or g.verts.size() != g.uvs.size():
		return "bad mesh arrays %d %d %d" % [g.verts.size(), g.colors.size(), g.uvs.size()]
	if g.verts.size() % 3 != 0:
		return "not triangles"
	# surface is fully sky-lit, a sealed pocket underground is dark
	var top := w.top_y(5, 5)
	if m.light_at(5, top + 1, 5).x != 15:
		return "surface not lit: %s" % m.light_at(5, top + 1, 5)
	return ""


func test_lamp_light_spreads() -> String:
	var w := WorldData.new(1)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			w.chunks[Vector2i(dx, dz)] = WorldData.Chunk.new()
	for x in range(-16, 32):
		for z in range(-16, 32):
			for y in 5:
				w._put(x, y, z, 9 if y == 0 else 3)
	for x in range(3, 8):
		w._put(x, 2, 5, 0)
	w._put(3, 2, 5, 11)
	var m := Mesher.new(w)
	m.compute_light(Vector2i(0, 0), 0, WorldData.H)
	if m.light_at(4, 2, 5) != Vector2i(0, 14) or m.light_at(7, 2, 5) != Vector2i(0, 11):
		return "lamp light wrong: %s %s" % [m.light_at(4, 2, 5), m.light_at(7, 2, 5)]
	return ""


func test_raycast_and_edits() -> String:
	var w := WorldData.new(1)
	w.chunks[Vector2i(0, 0)] = WorldData.Chunk.new()
	w._put(5, 2, 2, 3)
	var hit := w.raycast(Vector3(0, 2, 2), Vector3(1, 0, 0), 10)
	if hit.is_empty() or hit["pos"] != Vector3i(5, 2, 2) or hit["normal"] != Vector3i(-1, 0, 0):
		return "raycast wrong: %s" % hit
	w._put(4, 1, 4, 6)
	for y in [2, 3]:
		w._put(4, y, 4, 59)
	w.set_block(4, 1, 4, 0)
	if w.get_block(4, 2, 4) != 0 or w.get_block(4, 3, 4) != 0:
		return "reeds should fall"
	return ""


func test_save_round_trip() -> String:
	var w := WorldData.new(7)
	w.ensure_chunk(Vector2i(0, 0))
	w.set_block(3, 50, 3, 8)
	w.time_of_day = 0.6
	var path := "user://test_save.json"
	w.save(path, {"mode": "creative"})
	var again := WorldData.load_from(path)
	again.ensure_chunk(Vector2i(0, 0))
	DirAccess.remove_absolute(path)
	if again.get_block(3, 50, 3) != 8 or again.time_of_day != 0.6 or again.player_data["mode"] != "creative":
		return "save lost data"
	return ""


func test_build_timing() -> String:
	var w := WorldData.new(11)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			w.ensure_chunk(Vector2i(dx, dz))
	var m := Mesher.new(w)
	var t := Time.get_ticks_usec()
	m.compute_light(Vector2i(0, 0), 0, WorldData.H)
	var light_ms := (Time.get_ticks_usec() - t) / 1000.0
	t = Time.get_ticks_usec()
	m.build(Vector2i(0, 0))
	print("        light %.1f ms, light + mesh %.1f ms" % [light_ms, (Time.get_ticks_usec() - t) / 1000.0])
	return ""



func test_ambient_occlusion() -> String:
	var w := WorldData.new(1)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			w.chunks[Vector2i(dx, dz)] = WorldData.Chunk.new()
	w._put(5, 1, 5, 3)
	var m := Mesher.new(w)
	m.compute_light(Vector2i(0, 0), 0, WorldData.H)
	if m._corner_ao(0, 5, 1, 5) != [3, 3, 3, 3]:
		return "a lone block's top should be fully open: %s" % [m._corner_ao(0, 5, 1, 5)]
	w._put(6, 2, 5, 3)                          # a block on top of the +x neighbour
	var ao := m._corner_ao(0, 5, 1, 5)
	if ao.min() != 2 or ao.max() != 3 or ao.count(2) != 2:
		return "the two corners next to the wall should be darker: %s" % [ao]
	return ""


## Breaking blocks without stopping: every few changes must show up while still breaking
## (before, each result was thrown away as out of date and nothing showed until you stopped).
func test_continuous_edits_show_while_editing() -> String:
	var w := WorldData.new(424242)
	var cm := ChunkManager.new()
	var mats := {}
	for n in ["solid", "translucent", "water", "plants"]:
		mats[n] = StandardMaterial3D.new()
	cm.setup(w, mats, 1)
	var pos := Vector3(8, 200, 8)
	cm.update_center(pos, true)
	for i in 600:                                # load the area
		cm._process(0.016)
		OS.delay_msec(2)
		if cm.is_ready_at(Vector3(8, w.top_y(8, 8) + 1, 8)):
			break
	var top := w.top_y(8, 8)
	var sk := ChunkManager.section_key(Vector2i(0, 0), top / ChunkManager.SEC)
	var before: int = cm.shown_version.get(sk, 0)
	var updates := 0
	var last := before
	for i in 120:                                 # dig a column: one block every 3 frames
		if i % 3 == 0:
			var y := top - i / 3
			var keys := w.set_block(8, y, 8, 0, false, false)
			cm.rebuild(keys, maxi(y - 16, 0), y + 16)
		cm._process(0.016)
		OS.delay_msec(4)
		var now: int = cm.shown_version.get(sk, 0)
		if now != last:
			updates += 1
			last = now
	cm._exit_tree()
	cm.free()
	return "" if updates >= 5 else "the view only changed %d times while digging 40 blocks" % updates
