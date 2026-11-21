extends RefCounted
## Flowing water and lava, and what they make when they meet (stone generators).

const Y := 60


## An empty world with a stone floor at y = Y - 1; returns [world, fluids].
func _world() -> Array:
	var w := WorldData.new(5)
	for cx in range(-2, 3):
		for cz in range(-2, 3):
			w.chunks[Vector2i(cx, cz)] = WorldData.Chunk.new()
	var floor := {}
	for x in range(-30, 31):
		for z in range(-30, 31):
			floor[Vector3i(x, Y - 1, z)] = 3
	w.bulk_set(floor)
	var f := Fluids.new()
	f.world = w
	f.set_block = func(p: Vector3i, id: int) -> void: w.set_block(p.x, p.y, p.z, id, true, false)
	w.on_edit = func(p: Vector3i, _id: int) -> void: f.note(p)
	return [w, f]


func _run(f: Fluids, seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		f.update(0.05)
		t += 0.05


func _b(w: WorldData, x: int, y: int, z: int) -> int:
	return w.get_block(x, y, z)


func test_water_spreads_seven_and_dries_up() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	w.set_block(0, Y, 0, Blocks.WATER, true, false)
	_run(f, 4.0)
	for i in range(1, 8):
		if _b(w, i, Y, 0) != Blocks.water_id(i):
			return "%d blocks away: %d, expected flowing water level %d" % [i, _b(w, i, Y, 0), i]
	if _b(w, 8, Y, 0) != 0:
		return "water ran further than 7 blocks"
	if not Blocks.is_water(_b(w, 3, Y, 3)):
		return "water should spread in a diamond (3, 3 is 6 steps away)"
	w.set_block(0, Y, 0, 0, true, false)          # take the source away
	_run(f, 6.0)
	for i in range(0, 9):
		if _b(w, i, Y, 0) != 0:
			return "water left %d blocks away after the source was taken" % i
	return "" if not f.busy() else "fluids still busy after drying up"


func test_water_falls_down_and_spreads_below() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	var tower := {}
	for y in range(Y, Y + 4):
		tower[Vector3i(0, y, 0)] = 3
	w.bulk_set(tower)
	w.set_block(0, Y + 4, 0, Blocks.WATER, true, false)  # on top of a pillar 4 high
	_run(f, 6.0)
	for y in range(Y, Y + 4):
		if not Blocks.is_water(_b(w, 1, y, 0)):
			return "no falling water beside the pillar at y %d" % y
	if _b(w, 5, Y, 0) != Blocks.water_id(5):
		return "the stream should spread on the ground: %d" % _b(w, 5, Y, 0)
	return ""


func test_lava_spreads_three_slowly() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	w.set_block(0, Y, 0, Blocks.LAVA, true, false)
	_run(f, 1.1)
	if _b(w, 2, Y, 0) != 0:
		return "lava is slow: after one second it is only one block out"
	_run(f, 4.0)
	for i in range(1, 4):
		if _b(w, i, Y, 0) != Blocks.lava_id(i):
			return "%d blocks away: %d" % [i, _b(w, i, Y, 0)]
	return "" if _b(w, 4, Y, 0) == 0 else "lava ran further than 3 blocks"


## Water reaching a lava source makes obsidian; water reaching flowing lava makes cobblestone
## (and the cobblestone then stops the water, like in the original).
func test_water_on_lava_makes_obsidian_or_cobblestone() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	var walls := {}
	for z in [-1, 1]:
		for x in range(-1, 8):
			walls[Vector3i(x, Y, z)] = 3
	walls[Vector3i(-1, Y, 0)] = 3
	w.bulk_set(walls)
	w.set_block(0, Y, 0, Blocks.LAVA, true, false)
	_run(f, 3.5)                                    # the lava runs to x = 1..3
	w.set_block(6, Y, 0, Blocks.WATER, true, false)
	_run(f, 3.0)
	var first := _b(w, 3, Y, 0)
	if first != 22:
		return "water meeting flowing lava should make cobblestone: %d" % first
	if _b(w, 0, Y, 0) != Blocks.LAVA:
		return "the source stays lava behind the cobblestone"
	# pour water straight onto the source
	w.set_block(0, Y + 1, 0, Blocks.WATER, true, false)
	_run(f, 2.0)
	return "" if _b(w, 0, Y, 0) == Blocks.OBSIDIAN else "the lava source should turn to obsidian: %d" % _b(w, 0, Y, 0)


func test_lava_falling_on_water_makes_stone() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	w.set_block(0, Y, 0, Blocks.WATER, true, false)
	var shelf := {Vector3i(1, Y + 2, 0): 3}
	w.bulk_set(shelf)
	w.set_block(1, Y + 3, 0, Blocks.LAVA, true, false)   # lava on a shelf, runs off and drops
	_run(f, 8.0)
	var stone := 0
	for x in range(-3, 4):
		for z in range(-3, 4):
			for y in range(Y, Y + 2):
				var b := _b(w, x, y, z)
				if b == 3 or b == 22:
					stone += 1
	return "" if stone > 0 else "no stone or cobblestone where lava met water"


## The classic cobblestone generator: a lava source runs into a gap with water under it, the
## lava hardens into cobblestone; break it and it comes back.
func test_cobblestone_generator() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	var box := {}
	for x in range(-2, 4):
		for z in range(-2, 3):
			for y in range(Y - 1, Y + 2):
				box[Vector3i(x, y, z)] = 3
	box[Vector3i(0, Y, 0)] = 0                       # the lava's cell
	box[Vector3i(1, Y, 0)] = 0                       # the gap
	box[Vector3i(1, Y - 1, 0)] = 0                   # water under the gap
	w.bulk_set(box)
	w.set_block(1, Y - 1, 0, Blocks.WATER, true, false)
	w.set_block(0, Y, 0, Blocks.LAVA, true, false)
	var made := 0
	for i in 5:
		_run(f, 1.5)
		if _b(w, 1, Y, 0) != 22:
			return "round %d: the gap holds %d, not cobblestone" % [i + 1, _b(w, 1, Y, 0)]
		made += 1
		w.set_block(1, Y, 0, 0, true, false)        # mined
	if _b(w, 0, Y, 0) != Blocks.LAVA or _b(w, 1, Y - 1, 0) != Blocks.WATER:
		return "the lava and the water should stay as they are"
	return ""


func test_fluids_wash_away_crops_and_drop_them() -> String:
	var s := _world()
	var w: WorldData = s[0]
	var f: Fluids = s[1]
	var washed := []
	f.wash = func(p: Vector3i, id: int) -> void: washed.append(id)
	w.set_block(2, Y - 1, 0, 970, true, false)
	w.set_block(2, Y, 0, 974, true, false)
	w.set_block(0, Y, 0, Blocks.WATER, true, false)
	_run(f, 2.0)
	return "" if washed == [974] and Blocks.is_water(_b(w, 2, Y, 0)) else "washed %s, cell %d" % [washed, _b(w, 2, Y, 0)]
