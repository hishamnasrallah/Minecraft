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
	for x in range(-3, 12):
		for z in range(-4, 9):
			for y in range(40, 64):
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
	# the row moved one on, and the pusher's head (1760 + facing) sticks out where it was
	if _id(w, 1, 41, 0) != 1761 or _id(w, 2, 41, 0) != 7 or _id(w, 3, 41, 0) != 8:
		return "push: %d %d %d" % [_id(w, 1, 41, 0), _id(w, 2, 41, 0), _id(w, 3, 41, 0)]
	w.set_block(0, 41, 1, 1702, true, false)      # power off: the head comes back
	_run(p)
	if _id(w, 1, 41, 0) != 0:
		return "the head should go back when the power stops: %d" % _id(w, 1, 41, 0)
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


## A long wire shows its signal getting weaker: bright by the source, dim near the end.
func test_wire_shows_signal_strength() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 40, 5, 1705, true, false)       # power cell
	for x in range(1, 15):
		w.set_block(x, 40, 5, 1700, true, false)
	_run(p)
	var near := _id(w, 1, 40, 5)
	var mid := _id(w, 7, 40, 5)
	var far := _id(w, 13, 40, 5)
	if near != 1701 or mid != 1791 or far != 1790:
		return "wire looks: near %d, middle %d, far %d" % [near, mid, far]
	return ""


## The sticky pusher pushes out, and pulls the block back when the power stops.
func test_sticky_pusher_pulls_back() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 42, 8, 1793, true, false)      # sticky pusher facing +x
	w.set_block(1, 42, 8, 7, true, false)         # planks in front
	w.set_block(0, 42, 9, 1702, true, false)      # switch
	_run(p)
	w.set_block(0, 42, 9, 1703, true, false)
	_run(p)
	if _id(w, 1, 42, 8) != 1761 or _id(w, 2, 42, 8) != 7:
		return "out: head %d, block %d" % [_id(w, 1, 42, 8), _id(w, 2, 42, 8)]
	w.set_block(0, 42, 9, 1702, true, false)
	_run(p)
	if _id(w, 1, 42, 8) != 7 or _id(w, 2, 42, 8) != 0:
		return "back: %d %d (the planks should come back next to it)" % [_id(w, 1, 42, 8), _id(w, 2, 42, 8)]
	return ""


## An observer flashes a lamp in front of it when the block at its eye changes, then stops.
func test_observer_pulses_on_change() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 44, 0, 1821, true, false)      # observer: pulse goes out to +x, eye looks at -x
	w.set_block(1, 44, 0, 1708, true, false)      # lamp in front of its output
	_run(p)
	if _id(w, 1, 44, 0) != 1708:
		return "nothing changed yet: the lamp should be off"
	w.set_block(-1, 44, 0, 3, true, false)        # a block appears at its eye
	var lit := false
	for i in 3:
		p.update(Power.TICK + 0.001)
		if _id(w, 1, 44, 0) == 1709:
			lit = true
	if not lit:
		return "the lamp should flash when the observer sees the change"
	_run(p)
	if _id(w, 1, 44, 0) != 1708:
		return "the pulse should end: lamp %d" % _id(w, 1, 44, 0)
	return ""


## A thrower sends one item into the chest in front each time the button is pressed.
func test_thrower_sends_one_item_per_pulse() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 46, 0, 1833, true, false)      # thrower facing +x
	w.containers[Vector3i(0, 46, 0)] = [[22, 5]]
	w.set_block(1, 46, 0, 48, true, false)        # chest in front
	w.set_block(0, 46, 1, 1704, true, false)      # button
	_run(p)
	for i in 2:
		p.press_button(Vector3i(0, 46, 1))
		_run(p, 15)
	var got := 0
	for st in Inventory.from_data(w.containers.get(Vector3i(1, 46, 0)), 27).slots:
		if st != null:
			got += int(st[1])
	return "" if got == 2 else "two presses should send 2 items, the chest has %d" % got


## A comparator measures the chest behind it: empty gives nothing, some items light the lamp
## in front, and a half-full chest sends a medium signal down a wire.
func test_comparator_measures_a_chest() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 48, 0, 48, true, false)        # chest
	w.set_block(1, 48, 0, 1839, true, false)      # comparator facing +x: the chest is behind it
	w.set_block(2, 48, 0, 1708, true, false)      # lamp in front
	_run(p, 8)
	if _id(w, 2, 48, 0) != 1708:
		return "an empty chest gives no power"
	w.containers[Vector3i(0, 48, 0)] = [[22, 10]]
	_run(p, 12)
	if _id(w, 2, 48, 0) != 1709:
		return "a chest with items should light the lamp: %d" % _id(w, 2, 48, 0)
	# half full: 14 stacks of 64 out of 27 -> about level 8: a wire after it looks medium
	var half := []
	for i in 14:
		half.append([22, 64])
	w.containers[Vector3i(0, 48, 0)] = half
	w.set_block(2, 48, 0, 1700, true, false)
	_run(p, 12)
	var lv: int = p.level.get(Vector3i(2, 48, 0), 0)
	if lv < 6 or lv > 10 or _id(w, 2, 48, 0) != 1791:
		return "half full should give a medium signal: level %d, wire %d" % [lv, _id(w, 2, 48, 0)]
	return ""


# ---------------------------------------------------------------- power through blocks
## A switch on a stone block powers the block: the lamp beside the stone lights.
func test_switch_on_a_block_lights_the_lamp_beside_it() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 50, 0, 3, true, false)         # stone
	w.set_block(0, 51, 0, 1702, true, false)      # switch on top of it
	w.set_block(1, 50, 0, 1708, true, false)      # lamp beside the stone
	_run(p)
	if _id(w, 1, 50, 0) != 1708:
		return "off: the lamp should be dark"
	w.set_block(0, 51, 0, 1703, true, false)
	_run(p)
	return "" if _id(w, 1, 50, 0) == 1709 else "the switch powers its block, the lamp beside it should light"


## Dust running into a block powers it (weakly): a lamp on the other side lights, but dust on
## the other side does not.
func test_dust_into_a_block_powers_the_lamp_behind_not_more_dust() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 52, 0, 1705, true, false)      # power cell
	for x in range(1, 4):
		w.set_block(x, 52, 0, 1700, true, false)  # dust towards the stone
	w.set_block(4, 52, 0, 3, true, false)         # stone
	w.set_block(5, 52, 0, 1708, true, false)      # lamp behind it
	w.set_block(4, 52, 1, 1700, true, false)      # dust beside the stone (not in line)
	w.set_block(4, 52, 2, 1708, true, false)
	_run(p)
	if _id(w, 5, 52, 0) != 1709:
		return "the lamp behind the block should light"
	if _id(w, 4, 52, 1) != 1700:
		return "a weakly powered block must not power dust: %d" % _id(w, 4, 52, 1)
	return ""


## The power torch on the side of a block is a NOT: lit until the block is powered.
func test_power_torch_inverts() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 54, 0, 3, true, false)         # stone
	w.set_block(0, 55, 0, 1702, true, false)      # switch on top (off)
	w.set_block(1, 54, 0, 1851, true, false)      # power torch on the stone's +x side (hangs on -x: facing 3)
	w.set_block(2, 54, 0, 1708, true, false)      # lamp next to the torch
	_run(p)
	if _id(w, 2, 54, 0) != 1709 or _id(w, 1, 54, 0) != 1855:
		return "switch off: torch lit (%d) and lamp on (%d)" % [_id(w, 1, 54, 0), _id(w, 2, 54, 0)]
	w.set_block(0, 55, 0, 1703, true, false)
	_run(p)
	if _id(w, 2, 54, 0) != 1708 or _id(w, 1, 54, 0) != 1851:
		return "switch on: torch out (%d) and lamp off (%d)" % [_id(w, 1, 54, 0), _id(w, 2, 54, 0)]
	return ""


## A lit torch under a block powers it strongly: dust on top of that block carries power.
func test_power_torch_powers_the_block_above_and_its_dust() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 56, 4, 3, true, false)         # ground
	w.set_block(0, 57, 4, 1846, true, false)      # torch standing on it
	w.set_block(0, 58, 4, 3, true, false)         # stone above the torch
	w.set_block(0, 59, 4, 1700, true, false)      # dust on top of that stone
	w.set_block(1, 59, 4, 1708, true, false)      # lamp at the end of the dust
	_run(p)
	return "" if _id(w, 1, 59, 4) == 1709 else "torch -> block above -> dust -> lamp: lamp %d, dust %d" % [_id(w, 1, 59, 4), _id(w, 0, 59, 4)]


## A pusher and a door next to a powered block work too.
func test_powered_block_runs_pusher_and_door() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 60, 0, 3, true, false)         # stone with a switch on it
	w.set_block(0, 61, 0, 1703, true, false)
	w.set_block(1, 60, 0, 1731, true, false)      # pusher facing +x beside the stone
	w.set_block(2, 60, 0, 7, true, false)
	w.set_block(0, 60, -1, 510, true, false)      # a door on another side (not touching the switch)
	w.set_block(0, 61, -1, 511, true, false)
	_run(p)
	if _id(w, 3, 60, 0) != 7:
		return "the pusher should push: row %d %d %d" % [_id(w, 1, 60, 0), _id(w, 2, 60, 0), _id(w, 3, 60, 0)]
	if not Blocks.defs[_id(w, 0, 60, -1)]["door"]["open"]:
		return "the door should open"
	return ""


func test_timer_pulses_and_counter_passes_every_third() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 40, 0, 1906, true, false)        # timer, every 1 s
	w.settings[Vector3i(0, 40, 0)] = {"period": 1.0}
	w.set_block(1, 40, 0, 1700, true, false)        # wire
	w.set_block(2, 40, 0, 1908, true, false)        # counter, every 3rd
	w.settings[Vector3i(2, 40, 0)] = {"count": 3}
	w.set_block(3, 40, 0, 1708, true, false)        # lamp on the counter
	w.set_block(0, 40, 2, 1906, true, false)        # a second timer with its own lamp
	w.settings[Vector3i(0, 40, 2)] = {"period": 1.0}
	w.set_block(1, 40, 2, 1708, true, false)
	var timer_lit := 0
	var counter_lit := 0
	var last_t := false
	var last_c := false
	for i in 95:                                     # about 9.6 s
		_run(p, 1)
		var t := _id(w, 1, 40, 2) == 1709
		var c := _id(w, 3, 40, 0) == 1709
		if t and not last_t:
			timer_lit += 1
		if c and not last_c:
			counter_lit += 1
		last_t = t
		last_c = c
	if timer_lit < 8 or timer_lit > 10:
		return "timer lamp lit %d times in 9.6 s (every 1 s)" % timer_lit
	return "" if counter_lit == 3 else "counter lamp lit %d times for %d pulses (every 3rd)" % [counter_lit, timer_lit]


func test_note_block_and_fan() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	w.set_block(0, 40, 0, 1910, true, false)        # note block
	w.set_block(1, 40, 0, 1704, true, false)        # button beside it
	w.set_block(0, 40, 3, 1915, true, false)        # fan facing up (1911 + 4)
	w.set_block(1, 40, 3, 1702, true, false)        # switch beside it
	_run(p, 3)
	p.press_button(Vector3i(1, 40, 0))
	_run(p, 5)
	if p.notes_played != 1:
		return "the note block played %d notes for one press" % p.notes_played
	if not p.fans_on.is_empty():
		return "the fan should be off"
	w.set_block(1, 40, 3, 1703, true, false)
	_run(p, 3)
	if p.fans_on.get(Vector3i(0, 40, 3)) != Vector3i(0, 1, 0):
		return "the fan should blow up: %s" % [p.fans_on]
	return "" if _id(w, 0, 40, 3) == 1921 else "the fan should show it spins: %d" % _id(w, 0, 40, 3)


func test_tnt_trapdoor_iron_door_by_power() -> String:
	var s := _setup()
	var w: WorldData = s[0]
	var p: Power = s[1]
	var boom := []
	p.explode = func(q: Vector3i) -> void: boom.append(q)
	w.set_block(0, 40, 0, 1951, true, false)        # TNT
	w.set_block(1, 40, 0, 1704, true, false)        # a button beside it
	w.set_block(0, 40, 3, 1932, true, false)        # a trapdoor, shut
	w.set_block(1, 40, 3, 1702, true, false)        # a switch beside it
	w.set_block(0, 40, 6, 1924, true, false)        # an iron door (bottom, top)
	w.set_block(0, 41, 6, 1925, true, false)
	w.set_block(1, 40, 6, 1706, true, false)        # a plate beside it
	_run(p, 3)
	p.press_button(Vector3i(1, 40, 0))
	_run(p, 5)
	if not p.fuses.has(Vector3i(0, 40, 0)):
		return "the button should light the TNT"
	_run(p, 30)
	if boom != [Vector3i(0, 40, 0)]:
		return "the TNT should blow up about 3 s after it was lit: %s" % [boom]
	w.set_block(1, 40, 3, 1703, true, false)
	_run(p, 4)
	if not Blocks.defs[_id(w, 0, 40, 3)]["door"]["open"]:
		return "the switch should open the trapdoor"
	p.set_inputs({Vector3i(1, 40, 6): true}, p.is_day)
	_run(p, 4)
	var bottom: bool = Blocks.defs[_id(w, 0, 40, 6)]["door"]["open"]
	var top: bool = Blocks.defs[_id(w, 0, 41, 6)]["door"]["open"]
	return "" if bottom and top else "the plate should open both halves of the iron door"
