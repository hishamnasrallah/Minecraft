extends RefCounted
## Machines and logic: wires, switches, gates, users, collectors and the auto-smelter.


func _setup() -> Array:
	var w := WorldData.new(7)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			w.ensure_chunk(Vector2i(dx, dz))
	var p := Power.new(w)
	w.on_edit = p.note
	p.set_block = func(pos: Vector3i, id: int) -> void: w.set_block(pos.x, pos.y, pos.z, id, true, false)
	var dropped := []
	p.spawn_drop = func(st: Array, _pos: Vector3) -> void: dropped.append(st)
	p.break_drops = func(id: int) -> Array: return [[id, 1]]
	# a clear, flat work area at y 40
	for x in range(-2, 12):
		for z in range(-4, 5):
			for y in range(40, 46):
				w.set_block(x, y, z, 0, true, false)
			w.set_block(x, 39, z, 3, true, false)
	return [w, p, dropped]


func _run(p: Power, ticks := 5) -> void:
	for i in ticks:
		p.update(Power.TICK + 0.001)


func _id(w: WorldData, x: int, y: int, z: int) -> int:
	return w.get_block(x, y, z)


func test_switch_wire_lamp() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 40, 0, 1702, true, false)       # switch, off
	for x in range(1, 6):
		w.set_block(x, 40, 0, 1700, true, false)   # wire
	w.set_block(6, 40, 0, 1708, true, false)       # lamp
	_run(p)
	if _id(w, 6, 40, 0) != 1708 or _id(w, 3, 40, 0) != 1700:
		return "nothing should be powered yet"
	w.set_block(0, 40, 0, 1703, true, false)       # switch on
	_run(p)
	if _id(w, 3, 40, 0) != 1701:
		return "wire should carry power"
	if _id(w, 6, 40, 0) != 1709:
		return "lamp should light: %d" % _id(w, 6, 40, 0)
	w.set_block(0, 40, 0, 1702, true, false)
	_run(p)
	if _id(w, 6, 40, 0) != 1708:
		return "lamp should go out"
	return ""


func test_wire_fades_after_15() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(-1, 40, 1, 1705, true, false)      # power cell
	for x in range(0, 11):
		w.set_block(x, 40, 1, 1700, true, false)
	for x in range(0, 11):
		w.set_block(x, 40, 2, 1700, true, false)   # a second row, joined at the end: 22 wires in a U
	_run(p)
	if p.level.get(Vector3i(0, 40, 1), 0) != 15 or p.level.get(Vector3i(10, 40, 1), 0) != 5:
		return "levels: %s %s" % [p.level.get(Vector3i(0, 40, 1), 0), p.level.get(Vector3i(10, 40, 1), 0)]
	if p.level.get(Vector3i(0, 40, 2), 0) != 14:
		return "side wire: %s" % p.level.get(Vector3i(0, 40, 2), 0)
	return ""


func test_gates() -> String:
	# inputs: two switches on the sides of a gate facing +z; a lamp in front of it
	var results := {}
	for gate in [["and", 1714], ["or", 1718], ["xor", 1722]]:
		var row := []
		for inputs in [[false, false], [true, false], [true, true]]:
			var s := _setup()
			var w: WorldData = s[0]
			var p: Power = s[1]
			w.set_block(5, 40, 0, gate[1], true, false)                         # facing 0 = +z
			w.set_block(6, 40, 0, 1703 if inputs[0] else 1702, true, false)     # left (+x)
			w.set_block(4, 40, 0, 1703 if inputs[1] else 1702, true, false)     # right (-x)
			w.set_block(5, 40, 1, 1708, true, false)                            # lamp in front
			_run(p, 6)
			row.append(1 if _id(w, 5, 40, 1) == 1709 else 0)
		results[gate[0]] = row
	var want := {"and": [0, 0, 1], "or": [0, 1, 1], "xor": [0, 1, 0]}
	if results != want:
		return "gate truth tables: %s" % results
	# not: lit with nothing behind, dark with power behind
	var s2 := _setup()
	var w2: WorldData = s2[0]
	var p2: Power = s2[1]
	w2.set_block(5, 40, 0, 1710, true, false)
	w2.set_block(5, 40, 1, 1708, true, false)
	_run(p2, 6)
	var lit := _id(w2, 5, 40, 1) == 1709
	w2.set_block(5, 40, -1, 1705, true, false)    # power cell behind
	_run(p2, 6)
	if not lit or _id(w2, 5, 40, 1) != 1708:
		return "not gate wrong"
	return ""


func test_pusher_and_breaker() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	var dropped: Array = s[2]
	w.set_block(0, 41, 0, 1731, true, false)      # pusher facing +x
	w.set_block(1, 41, 0, 7, true, false)
	w.set_block(2, 41, 0, 8, true, false)
	w.set_block(0, 41, 1, 1702, true, false)
	_run(p)
	w.set_block(0, 41, 1, 1703, true, false)      # power arrives: push once
	_run(p)
	if _id(w, 1, 41, 0) != 0 or _id(w, 2, 41, 0) != 7 or _id(w, 3, 41, 0) != 8:
		return "push: %d %d %d" % [_id(w, 1, 41, 0), _id(w, 2, 41, 0), _id(w, 3, 41, 0)]
	w.set_block(0, 43, 3, 1737, true, false)      # breaker facing +x
	w.set_block(1, 43, 3, 22, true, false)
	w.set_block(0, 43, 4, 1704, true, false)      # a push button
	p.press_button(Vector3i(0, 43, 4))
	_run(p)
	if _id(w, 1, 43, 3) != 0 or dropped.is_empty():
		return "breaker should break and drop"
	return ""


func test_collector_feeds_smelter() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 43, 0, 48, true, false)        # chest on top
	w.set_block(0, 42, 0, 1746, true, false)      # collector
	w.set_block(0, 41, 0, 1747, true, false)      # auto-smelter
	w.containers[Vector3i(0, 43, 0)] = [[25, 2], [102, 2]]     # 2 iron ore, 2 coal
	_run(p, 60)                                    # 6 s
	var out := Inventory.from_data(w.containers.get(Vector3i(0, 41, 0)), 27)
	var ingots := 0
	for i in range(18, 27):
		if out.slots[i] != null and int(out.slots[i][0]) == 106:
			ingots += int(out.slots[i][1])
	if ingots != 2:
		return "smelter should make 2 iron ingots, made %d (%s)" % [ingots, out.slots]
	return ""
