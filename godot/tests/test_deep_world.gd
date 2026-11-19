extends RefCounted
## The deep world (H = 320, surface SURFACE_OFFSET higher than the old 64-high world): constants,
## underground layers, caverns, the cave noise grid and moving old saves up.

var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/worldgen.json"))


func test_deep_world_constants_match_python() -> String:
	if int(Blocks.C["MAX_HEIGHT"]) != WorldData.H or int(Blocks.C["SURFACE_OFFSET"]) != WorldData.SURFACE_OFFSET \
			or int(Blocks.C["SAVE_VERSION"]) != WorldData.SAVE_VERSION:
		return "WorldData constants differ from blocks.json: %s %s %s" % [Blocks.C["MAX_HEIGHT"], Blocks.C["SURFACE_OFFSET"], Blocks.C["SAVE_VERSION"]]
	var w := WorldData.new(1)
	if w.BASALT_LINE % 4 != 0 or w.LIMESTONE_LINE % 4 != 0 or w.BEDROCK_TOP % 4 != 0:
		return "the bulk generator needs BASALT_LINE, LIMESTONE_LINE and BEDROCK_TOP to be multiples of 4"
	return ""


func test_cave_noise_grid_matches_value_noise3() -> String:
	var seed: int = fixtures["seed"]
	for row in fixtures["noise3_cavern"]:
		var v := VNoise.value_noise3(int(row[0]) / 32.0, int(row[1]) / 16.0, int(row[2]) / 32.0, seed + 900)
		if absf(v - float(row[3])) > 1e-12:
			return "cavern noise differs at %s: %s" % [row, v]
	var w := WorldData.new(seed)
	for key in [Vector2i(0, 0), Vector2i(-3, 5)]:
		var ny := 20
		var grid := w._noise_grid(seed + 300, 14.0, 9.0, key.x * 16, key.y * 16, ny)
		for i in 5:
			for j in ny:
				for k in 5:
					var want := VNoise.value_noise3((key.x * 16 + i * 4) / 14.0, (j * 4) / 9.0, (key.y * 16 + k * 4) / 14.0, seed + 300)
					if grid[(i * ny + j) * 5 + k] != want:
						return "noise grid differs at %s %d %d %d" % [key, i, j, k]
	for row in fixtures["slate_lines"]:
		if w._slate_line(int(row[0]), int(row[1])) != int(row[2]):
			return "slate line differs at %s" % [row]
	return ""


func test_world_is_deep_with_layers_ores_and_caverns() -> String:
	var w := WorldData.new(int(fixtures["seed"]))
	var parts: Array = fixtures["cavern_chunk"]
	var key := Vector2i(int(parts[0]), int(parts[1]))
	w.ensure_chunk(key)
	var count := {}
	var bedrock_above_floor := 0
	var deep_air := 0
	for lx in 16:
		for lz in 16:
			var x := key.x * 16 + lx
			var z := key.y * 16 + lz
			if w.get_block(x, 0, z) != 9:
				return "no bedrock floor at %d,%d" % [x, z]
			if w.height_at(x, z) <= WorldData.SURFACE_OFFSET:
				return "surface too low at %d,%d" % [x, z]
			for y in range(1, WorldData.H):
				var b := w.get_block(x, y, z)
				if b == 9:
					if y >= w.BEDROCK_TOP:
						return "bedrock at y=%d" % y
					bedrock_above_floor += 1
				if b == 0 and y < w.CAVERN_TOP:
					deep_air += 1
				var band := "deep" if y < w.SLATE_LINE - 6 else ("mid" if y > w.SLATE_LINE + 6 and y < 170 else "")
				if band != "":
					count[[band, b]] = count.get([band, b], 0) + 1
	if bedrock_above_floor == 0 or bedrock_above_floor >= 3 * 256:
		return "bedrock in y 1..3 should be ragged: %d" % bedrock_above_floor
	var slate: int = w.G["SLATE"]
	if count.get(["deep", 3], 0) != 0 or count.get(["mid", slate], 0) != 0:
		return "stone below the slate line or slate above it"
	if count.get(["deep", slate], 0) < 10000 or count.get(["mid", 3], 0) < 5000:
		return "expected slate deep down and stone above it: %s" % count
	if deep_air < 3000:
		return "expected a big cavern below CAVERN_TOP, only %d air cells" % deep_air
	return ""


func test_old_save_is_moved_up_to_the_deep_world() -> String:
	# a version 3 save from the 64-high world: everything stored 180 lower than it now belongs
	var old := {"version": 3, "seed": 7, "time_of_day": 0.3,
		"changes": [[3, 20, 3, 8], [4, 1, 4, 0]],
		"containers": [[[5, 21, 6], [[2, 5], null]]],
		"player": {"position": [8.5, 22.1, 8.5], "spawn": [8, 21.5, 8], "growing": [[1, 15, 2]], "mode": "survival"}}
	var path := "user://test_old_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	var w := WorldData.load_from(path)
	var off := WorldData.SURFACE_OFFSET
	if w.changes.get(Vector2i(0, 0), {}).get(Vector3i(3, 20 + off, 3)) != 8 or not w.changes[Vector2i(0, 0)].has(Vector3i(4, 1 + off, 4)):
		return "edits not moved up: %s" % [w.changes]
	if not w.containers.has(Vector3i(5, 21 + off, 6)):
		return "chest not moved up: %s" % [w.containers.keys()]
	var pd := w.player_data
	if float(pd["position"][1]) != 22.1 + off or float(pd["spawn"][1]) != 21.5 + off or int(pd["growing"][0][1]) != 15 + off:
		return "player positions not moved up: %s" % [pd]
	if pd["position"][0] != 8.5 or pd["mode"] != "survival":
		return "other player data changed: %s" % [pd]
	# saved again it is a current save, and loading that moves nothing
	w.save(path, pd)
	var again := WorldData.load_from(path)
	DirAccess.remove_absolute(path)
	if not again.changes[Vector2i(0, 0)].has(Vector3i(3, 20 + off, 3)) or float(again.player_data["spawn"][1]) != 21.5 + off:
		return "a current save was moved again"
	return ""


func test_sky_realm_islands_pillars_and_portal_home() -> String:
	var w := WorldData.new(99, "sky")
	for dx in range(-3, 3):
		for dz in range(-3, 3):
			w.ensure_chunk(Vector2i(dx, dz))
	var top := w.top_y(0, 0)
	if top != WorldData.SKY_BASE + 6:
		return "main island should be flat at %d, top is %d" % [WorldData.SKY_BASE + 6, top]
	if w.get_block(0, top, 0) != 1801 or w.get_block(0, top - 10, 0) != 1800:
		return "grass on top, sky stone below"
	if w.get_block(0, 1, 0) != 0:
		return "below the islands there is only sky"
	for pc in WorldData.PILLARS:
		var cy := WorldData.SKY_BASE + 6 + WorldData.PILLAR_HEIGHT + 1
		if w.get_block(pc.x, cy, pc.y) != 1806 or w.get_block(pc.x, cy - 1, pc.y) != 1807:
			return "pillar with a storm crystal missing at %s" % pc
	if w.get_block(-1, WorldData.SKY_BASE + 8, -12) != 1805 or w.get_block(-2, WorldData.SKY_BASE + 8, -12) != 906:
		return "the portal home is missing"
	var sp := w.spawn_point()
	if w.get_block(floori(sp.x + 0.5), floori(sp.y + 0.6), floori(sp.z + 0.5)) != 0:
		return "spawn must be in the open"
	return ""
