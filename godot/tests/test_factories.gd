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


func _harvest(file: String) -> String:
	var s := _world(file)
	var w: WorldData = s[0]
	var p: Power = s[1]
	var dropped: Array = s[2]
	var wheat := _find(w, 971)
	if wheat.is_empty():
		return "%s: no wheat planted" % file
	var button: Vector3i = _find(w, 1704)[0]
	_run(p, 3)
	p.press_button(button)
	_run(p, 25)
	var left := _find(w, 971).size()
	if left != 0:
		return "%s: %d of %d crops not harvested" % [file, left, wheat.size()]
	if dropped.size() != wheat.size():
		return "%s: %d drops for %d crops" % [file, dropped.size(), wheat.size()]
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
