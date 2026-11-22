extends RefCounted
## Every factory in the library is pasted into an empty test world and must really work.

const Y := 60


func _world(clip_file: String) -> Array:
	var w := WorldData.new(3)
	var clip := Schematics.load_file("res://data/schematics/" + clip_file)
	var size := Vector3i.ZERO
	for p in clip:
		size = Vector3i(maxi(size.x, p.x), maxi(size.y, p.y), maxi(size.z, p.z))
	for cx in range(-1, size.x / 16 + 2):
		for cz in range(-1, size.z / 16 + 2):
			w.chunks[Vector2i(cx, cz)] = WorldData.Chunk.new()      # empty air chunks
	var p := Power.new(w)
	w.on_edit = p.note
	p.set_block = func(pos: Vector3i, id: int) -> void: w.set_block(pos.x, pos.y, pos.z, id, true, false)
	var dropped := []
	p.spawn_drop = func(st: Array, _pos: Vector3) -> void: dropped.append(st)
	p.break_drops = func(id: int) -> Array: return [[id, 1]]
	var edits := {}
	for q in clip:
		if clip[q] != 0:
			edits[Vector3i(0, Y, 0) + q] = clip[q]
	w.bulk_set(edits)
	return [w, p, dropped, clip]


func _run(p: Power, ticks: int) -> void:
	for i in ticks:
		p.update(Power.TICK + 0.001)


func _find(w: WorldData, id: int) -> Array:
	var out := []
	for k in w.changes:
		for pos in w.changes[k]:
			if w.get_block(pos.x, pos.y, pos.z) == id:
				out.append(pos)
	return out


func _count_in(w: WorldData, pos: Vector3i, item: int) -> int:
	var n := 0
	for s in Inventory.from_data(w.containers.get(pos), 27).slots:
		if s != null and int(s[0]) == item:
			n += int(s[1])
	return n


func _smelting_works(file: String, lines: int) -> String:
	var s := _world(file)
	var w: WorldData = s[0]
	var p: Power = s[1]
	var smelters := _find(w, 1747)
	if smelters.size() != lines:
		return "%s: %d smelters, expected %d" % [file, smelters.size(), lines]
	for sm in smelters:
		w.containers[sm + Vector3i(0, 2, 0)] = [[25, 2], [102, 2]]      # input chest on top
	_run(p, 80)
	for sm in smelters:
		var got := _count_in(w, sm + Vector3i(0, -2, 0), 106)
		if got != 2:
			return "%s: line at %s made %d iron ingots" % [file, sm, got]
	return ""


func test_auto_smelter() -> String:
	return _smelting_works("auto_smelter.json", 3)


func test_smelter_hall() -> String:
	return _smelting_works("smelter_hall.json", 8)


func test_lamp_clock_blinks() -> String:
	var s := _world("lamp_clock.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var lamp: Vector3i = (_find(w, 1708) + _find(w, 1709))[0]
	var changes := 0
	var last := w.get_block(lamp.x, lamp.y, lamp.z)
	for i in 60:
		_run(p, 1)
		var now := w.get_block(lamp.x, lamp.y, lamp.z)
		if now != last:
			changes += 1
			last = now
	return "" if changes >= 4 else "clock lamp changed only %d times in 6 s" % changes


func test_auto_door_opens_on_plate() -> String:
	var s := _world("auto_door.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var plate: Vector3i = _find(w, 1706)[0]
	var door := _find(w, 510)[0] as Vector3i
	p.set_inputs({plate: true}, p.is_day)
	_run(p, 5)
	if not Blocks.defs[w.get_block(door.x, door.y, door.z)]["door"]["open"]:
		return "door should open while someone stands on the plate"
	p.set_inputs({}, p.is_day)
	_run(p, 5)
	if Blocks.defs[w.get_block(door.x, door.y, door.z)]["door"]["open"]:
		return "door should close again"
	return ""


func test_logic_board() -> String:
	var s := _world("logic_board.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var and_gate: Vector3i = _find(w, 1714)[0]
	var lamp := and_gate + Vector3i(0, 0, 1)
	var left := and_gate + Vector3i(1, 0, 0)
	var right := and_gate + Vector3i(-1, 0, 0)
	_run(p, 6)
	var off := w.get_block(lamp.x, lamp.y, lamp.z) == 1708
	w.set_block(left.x, left.y, left.z, 1703, true, false)
	_run(p, 6)
	var one := w.get_block(lamp.x, lamp.y, lamp.z) == 1708
	w.set_block(right.x, right.y, right.z, 1703, true, false)
	_run(p, 6)
	var both := w.get_block(lamp.x, lamp.y, lamp.z) == 1709
	var not_lamp: Vector3i = (_find(w, 1710) + _find(w, 1770))[0] + Vector3i(0, 0, 1)   # off or lit
	var not_lit := w.get_block(not_lamp.x, not_lamp.y, not_lamp.z) == 1709
	return "" if off and one and both and not_lit else "AND board: %s %s %s, NOT lamp lit %s" % [off, one, both, not_lit]


## The farms harvest by themselves: ripen every crop the observers do not watch (nothing
## happens), then let a watched crop grow: the row's breakers take every ripe crop and plant it
## again. Twice, to see it keeps going. The button still harvests at once.
func _harvest(file: String, button := true) -> String:
	var s := _world(file)
	var w: WorldData = s[0]
	var p: Power = s[1]
	var dropped: Array = s[2]
	var crops := []
	for k in w.changes:
		for pos in w.changes[k]:
			if Blocks.defs.get(w.get_block(pos.x, pos.y, pos.z), {}).has("crop"):
				crops.append(pos)
	if crops.is_empty():
		return "%s: nothing planted" % file
	var watched := {}
	for o in _find(w, 1824):
		watched[o + Vector3i(0, -1, 0)] = true
	if watched.is_empty():
		return "%s: no observer watches a crop" % file
	var ripe := func(pos: Vector3i) -> void:
		var b := w.get_block(pos.x, pos.y, pos.z)
		w.set_block(pos.x, pos.y, pos.z, b - int(Blocks.defs[b]["crop"]["stage"]) + 3, true, false)
	_run(p, 3)
	for round in 2:
		for c in crops:
			if not watched.has(c):
				ripe.call(c)
		_run(p, 10)
		if dropped.size() != round * crops.size():
			return "%s: harvested before anything was watched growing (%d drops)" % [file, dropped.size()]
		for c in watched:
			ripe.call(c)                      # the watched crops grow: the rows fire
		_run(p, 25)
		var unripe := 0
		for c in crops:
			var b := w.get_block(c.x, c.y, c.z)
			if not Blocks.defs.get(b, {}).has("crop") or int(Blocks.defs[b]["crop"]["stage"]) != 0:
				unripe += 1
		if unripe != 0:
			return "%s round %d: %d of %d crops not harvested and planted again" % [file, round + 1, unripe, crops.size()]
		if dropped.size() != (round + 1) * crops.size():
			return "%s round %d: %d drops for %d crops" % [file, round + 1, dropped.size(), crops.size()]
	if not button:
		return ""
	# the button harvests ripe crops at once
	for c in crops:
		ripe.call(c)
	_run(p, 3)
	p.press_button(_find(w, 1704)[0])
	_run(p, 25)
	if dropped.size() != 3 * crops.size():
		return "%s: the button harvested %d of %d" % [file, dropped.size() - 2 * crops.size(), crops.size()]
	return ""


func test_wheat_harvester() -> String:
	return _harvest("wheat_harvester.json")


func test_giant_farm_one_button() -> String:
	return _harvest("giant_farm.json")


func test_night_street_lights() -> String:
	var s := _world("night_street.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	p.set_inputs(p.pressed, true)
	_run(p, 6)
	var day_lit := _find(w, 1709).size()
	p.set_inputs(p.pressed, false)
	_run(p, 6)
	var night_lit := _find(w, 1709).size()
	return "" if day_lit == 0 and night_lit == 6 else "street lamps lit by day %d, by night %d" % [day_lit, night_lit]


func test_storage_tower_fills_from_the_bottom() -> String:
	var s := _world("storage_tower.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var collectors := _find(w, 1746)
	collectors.sort_custom(func(a, b): return a.y > b.y)
	p.take_drop(collectors[0], [22, 10])                 # 10 cobblestone lying on the top collector
	_run(p, 200)
	var chests := _find(w, 48)
	chests.sort_custom(func(a, b): return a.y < b.y)
	var bottom := _count_in(w, chests[0], 22)
	return "" if bottom == 10 else "bottom chest has %d of 10" % bottom


func test_mega_complex_pastes_and_works() -> String:
	var s := _world("mega_complex.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	if p.parts.size() < 300:
		return "the complex should be full of machines: %d" % p.parts.size()
	p.set_inputs(p.pressed, false)
	_run(p, 6)
	var t := Time.get_ticks_usec()
	_run(p, 20)
	print("        machines: %d parts, %.2f ms per tick" % [p.parts.size(), (Time.get_ticks_usec() - t) / 20000.0])
	if _find(w, 1709).size() < 20:
		return "night lights and the power plant should light lamps: %d" % _find(w, 1709).size()
	return ""


## A blinking clock next to the whole industrial town: only the clock's own circuit works
## every tick, so the cost stays tiny. And machines in a chunk that is unloaded just wait.
func test_clock_next_to_the_town_stays_cheap() -> String:
	var s := _world("mega_complex.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var clock := Schematics.load_file("res://data/schematics/lamp_clock.json")
	var edits := {}
	for q in clock:
		if clock[q] != 0:
			edits[Vector3i(2, Y + 20, 2) + q] = clock[q]
	w.bulk_set(edits)
	_run(p, 30)                                   # everything settles, the clock keeps going
	var t := Time.get_ticks_usec()
	_run(p, 50)
	var per := (Time.get_ticks_usec() - t) / 50000.0
	print("        town + clock: %d parts in %d circuits, %.3f ms per tick" % [p.parts.size(), p._comps.size(), per])
	if per > 0.6:
		return "a clock should not make the whole town recompute: %.2f ms per tick" % per
	# unload the chunk with the clock: no errors, it just waits
	w.unload_chunk(Vector2i(0, 0))
	_run(p, 20)
	return ""


## A library building with its extras (filled chests, crafter choices) and fluids running.
func _world_full(clip_file: String) -> Array:
	var w := WorldData.new(3)
	var clip := Schematics.load_file("res://data/schematics/" + clip_file)
	var extras := Schematics.last_extras.duplicate()
	var size := Vector3i.ZERO
	for q in clip:
		size = Vector3i(maxi(size.x, q.x), maxi(size.y, q.y), maxi(size.z, q.z))
	for cx in range(-1, size.x / 16 + 2):
		for cz in range(-1, size.z / 16 + 2):
			w.chunks[Vector2i(cx, cz)] = WorldData.Chunk.new()
	var p := Power.new(w)
	var f := Fluids.new()
	f.world = w
	f.set_block = func(pos: Vector3i, id: int) -> void: w.set_block(pos.x, pos.y, pos.z, id, true, false)
	w.on_edit = func(pos: Vector3i, id: int) -> void:
		p.note(pos, id)
		f.note(pos)
	p.set_block = func(pos: Vector3i, id: int) -> void: w.set_block(pos.x, pos.y, pos.z, id, true, false)
	var dropped := []
	p.spawn_drop = func(st: Array, _pos: Vector3) -> void: dropped.append(st)
	p.break_drops = func(id: int) -> Array: return [[Items.drop_for(id), 1]]
	var edits := {}
	for q in clip:
		if clip[q] != 0:
			edits[Vector3i(0, Y, 0) + q] = clip[q]
	w.bulk_set(edits)
	for q in extras:
		var at: Vector3i = Vector3i(0, Y, 0) + q
		var e: Dictionary = extras[q]
		if e.has("items"):
			w.containers[at] = (e["items"] as Array).map(func(st): return [int(st[0]), int(st[1])])
		if e.has("craft"):
			w.settings[at] = {"craft": int(e["craft"])}
		if e.has("filter"):
			w.settings[at] = {"filter": int(e["filter"])}
		if e.get("settings") is Dictionary:
			w.settings[at] = (e["settings"] as Dictionary).duplicate()
	return [w, p, dropped, f]


func _run_all(p: Power, f: Fluids, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		p.update(Power.TICK + 0.001)
		f.update(Power.TICK + 0.001)
		t += Power.TICK + 0.001


func _dropped_count(dropped: Array, item: int) -> int:
	var n := 0
	for st in dropped:
		if int(st[0]) == item:
			n += int(st[1])
	return n


func test_cobble_generator_runs_by_itself() -> String:
	var s := _world_full("cobble_generator.json")
	_run_all(s[1], s[3], 12.0)
	var n := _dropped_count(s[2], 22)
	return "" if n >= 5 else "cobblestone mined in 12 s: %d" % n


func test_stone_factory() -> String:
	var s := _world_full("stone_factory.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	_run_all(p, s[3], 12.0)
	var n := _dropped_count(s[2], 22)
	if n < 10:
		return "two generators mined only %d cobblestone in 12 s" % n
	# what the conveyor brings: cobblestone on the collector over the smelter
	var smelter: Vector3i = _find(w, 1747)[0] if not _find(w, 1747).is_empty() else _find(w, 1748)[0]
	p.take_drop(smelter + Vector3i(0, 1, 0), [22, 8])
	_run_all(p, s[3], 12.0)
	var stone := _count_in(w, smelter + Vector3i(0, -2, 0), 3)
	return "" if stone == 8 else "smooth stone in the chest: %d of 8" % stone


func test_obsidian_factory() -> String:
	var s := _world_full("obsidian_factory.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var thrower: Vector3i = _find(w, 1833)[0]
	_run_all(p, s[3], 25.0)
	var n := _dropped_count(s[2], 1890)
	var empty := _count_in(w, thrower, int(Items.S["BUCKET"]))
	if n < 4:
		return "obsidian made in 25 s: %d" % n
	return "" if empty == n else "empty buckets back in the thrower %d for %d obsidian" % [empty, n]


func _line_output(file: String, item: int, lines: int, seconds: float) -> String:
	var s := _world_full(file)
	var w: WorldData = s[0]
	var p: Power = s[1]
	_run_all(p, s[3], seconds)
	var chests := _find(w, 48)
	chests.sort_custom(func(a, b): return a.y < b.y)
	var got := 0
	var lines_with := 0
	for ch in chests.slice(0, lines):
		var n := _count_in(w, ch, item)
		got += n
		lines_with += int(n > 0)
	return "" if lines_with == lines else "%s: %d of %d lines made item %d (%d in all)" % [file, lines_with, lines, item, got]


func test_bakery_bakes_bread() -> String:
	return _line_output("bakery.json", 122, 3, 30.0)


func test_grill_house_cooks() -> String:
	var s := _world_full("grill_house.json")
	var w: WorldData = s[0]
	_run_all(s[1], s[3], 30.0)
	var chests := _find(w, 48)
	chests.sort_custom(func(a, b): return a.y < b.y)
	var meat := 0
	var fish := 0
	for ch in chests.slice(0, 3):
		meat += int(_count_in(w, ch, 104) > 0)
		fish += int(_count_in(w, ch, 127) > 0)
	return "" if meat == 2 and fish == 1 else "lines cooking meat %d of 2, fish %d of 1" % [meat, fish]


func test_metal_works_makes_blocks() -> String:
	var s := _world_full("metal_works.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	_run_all(p, s[3], 90.0)
	var chests := _find(w, 48)
	chests.sort_custom(func(a, b): return a.y < b.y)
	var made := []
	for item in [30, 32, 31, 908]:
		var n := 0
		for ch in chests.slice(0, 4):
			n += _count_in(w, ch, item)
		made.append(n)
	return "" if made.min() > 0 else "metal blocks made (iron, gold, copper, tin): %s" % [made]


func test_bakery_makes_cake_and_gives_buckets_back() -> String:
	var s := _world_full("bakery.json")
	var w: WorldData = s[0]
	_run_all(s[1], s[3], 40.0)
	var cakes := 0
	var buckets := 0
	for ch in _find(w, 48):
		cakes += _count_in(w, ch, 128)
		buckets += _count_in(w, ch, 112)
	return "" if cakes >= 2 and buckets == cakes else "cakes %d, empty buckets back %d" % [cakes, buckets]


func test_filter_collector_takes_only_its_item() -> String:
	var s := _world_full("animal_farm.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var col: Vector3i = Vector3i.ZERO
	for q in _find(w, 1746):
		if w.settings.get(q) is Dictionary:
			col = q
	if col == Vector3i.ZERO:
		return "no filter collector in the cow pen"
	var th := col + Vector3i(0, 1, 0)
	w.containers[th] = [[112, 5], [119, 1], [119, 1]]       # the thrower: empty buckets and two milk
	_run_all(p, s[3], 4.0)
	var milk := _count_in(w, col + Vector3i(0, -1, 0), 119)
	var empty := _count_in(w, th, 112)
	return "" if milk == 2 and empty == 5 else "milk below %d of 2, empty buckets left above %d of 5" % [milk, empty]


func test_potion_lab_brews_all_six() -> String:
	var s := _world_full("potion_lab.json")
	var w: WorldData = s[0]
	_run_all(s[1], s[3], 30.0)
	var made := []
	for potion in [135, 136, 137, 138, 139, 142]:
		var n := 0
		for ch in _find(w, 48):
			n += _count_in(w, ch, potion)
		made.append(n)
	return "" if made.min() > 0 else "potions made (swift, heal, night, leap, fire, water): %s" % [made]


func test_market_garden_six_crops_harvest_themselves() -> String:
	return _harvest("market_garden.json", false)


func test_music_box_plays_its_tune() -> String:
	var s := _world_full("music_box.json")
	var p: Power = s[1]
	_run_all(p, s[3], 8.5)
	return "" if p.notes_played >= 16 else "notes played in 8.5 s: %d (two tunes of 8)" % p.notes_played


func test_food_factory_field_to_bread() -> String:
	var s := _world_full("food_factory.json")
	var w: WorldData = s[0]
	var p: Power = s[1]
	var dropped: Array = s[2]
	# what the field gives arrives in the row chests (the game's conveyors do that): put it there
	var chests := _find(w, 48)
	chests.sort_custom(func(a, b): return a.y > b.y)
	w.containers[chests[0]] = [[121, 12], [120, 20]]           # wheat and seeds
	w.containers[chests[1]] = [[144, 6], [120, 3]]             # potatoes (and stray seeds)
	_run_all(p, s[3], 30.0)
	var bread := 0
	var baked := 0
	var seeds_left := 0
	for ch in _find(w, 48):
		bread += _count_in(w, ch, 122)
		baked += _count_in(w, ch, 145)
		if ch.y == chests[0].y:
			seeds_left += _count_in(w, ch, 120)
	return "" if bread == 4 and baked == 6 and seeds_left == 23 else "bread %d of 4, baked potatoes %d of 6, seeds kept %d of 23" % [bread, baked, seeds_left]
