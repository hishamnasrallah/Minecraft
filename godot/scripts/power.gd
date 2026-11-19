class_name Power
extends RefCounted
## Machines and logic. Only the blocks the player built are looked at (a registry filled from
## world edits), ten times a second, so a world without machines costs nothing.
##
## Power: sources (switch on, power cell, pressed button, pressure plate with something on it,
## light sensor by day) power all 6 neighbours. Copper wire carries it, losing 1 per wire
## (15 -> 0). A logic gate reads its inputs and, one tick later, powers the block in front:
##   not: back input off            delay: back input, 3 ticks later
##   and: left and right            or: left or right or back        xor: left != right
## Users: powered lamps light up, doors open, pushers push and breakers break (on the moment
## they get power). Conveyors move what stands on them; collectors take items lying on them or
## from the container above and put them into the container below; the auto-smelter smelts.

const TICK := 0.1
const PUSH_LIMIT := 12
const DIRS := [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]

var world: WorldData
var set_block: Callable            # func(pos: Vector3i, id: int) -> void   (the game's edit, remeshes)
var spawn_drop: Callable           # func(stack: Array, pos: Vector3) -> void
var break_drops: Callable          # func(id: int) -> Array of stacks a broken block gives

var parts := {}                    # Vector3i -> kind ("wire", "switch", "and", "pusher", ...)
var level := {}                    # wire Vector3i -> 0..15
var gate_on := {}                  # gate Vector3i -> bool (output)
var was_powered := {}              # users: Vector3i -> bool, to act on the moment power arrives
var button_until := {}             # Vector3i -> time the press ends
var pressed := {}                  # pressure plates with something on them (set by the game)
var delay_line := {}               # delay gate Vector3i -> [bool, bool, bool]
var is_day := true
var now := 0.0
var _acc := 0.0
var _slow := 0.0
var _info := {}                    # block id -> [kind, facing, on]
var _emit := {}                    # this tick: positions that power all neighbours


func _init(w: WorldData) -> void:
	world = w
	for id in Blocks.defs:
		var lg = Blocks.defs[id].get("logic")
		if lg is Dictionary:
			_info[int(id)] = [str(lg["kind"]), int(lg.get("facing", 0)), bool(lg.get("on", false))]
	# logic blocks only exist where the player put them: they are all in the saved edits
	for key in world.changes:
		var edits: Dictionary = world.changes[key]
		for p in edits:
			note(p, int(edits[p]))


static func is_logic(id: int) -> bool:
	return Blocks.defs.get(id, {}).has("logic")


func kind_of(id: int) -> String:
	return _info[id][0] if _info.has(id) else ""


func facing_of(id: int) -> int:
	return _info[id][1] if _info.has(id) else 0


## The game tells us about every block change.
func note(pos: Vector3i, id: int) -> void:
	if _info.has(id):
		parts[pos] = _info[id][0]
	elif parts.has(pos):
		parts.erase(pos)
		level.erase(pos)
		gate_on.erase(pos)
		was_powered.erase(pos)
		delay_line.erase(pos)


func press_button(pos: Vector3i) -> void:
	button_until[pos] = now + 1.0


## Runs the machines; call every frame.
func update(delta: float) -> void:
	if parts.is_empty():
		return
	now += delta
	_acc += delta
	if _acc < TICK:
		return
	_acc = minf(_acc - TICK, TICK)
	_tick()
	_slow += TICK
	if _slow >= 0.4:
		_slow = 0.0
		_move_items()


func _front(pos: Vector3i) -> Vector3i:
	return pos + DIRS[facing_of(world.get_block(pos.x, pos.y, pos.z))]


func _tick() -> void:
	# 1. sources
	_emit = {}
	for p in parts:
		var k: String = parts[p]
		var id := world.get_block(p.x, p.y, p.z)
		var on := false
		match k:
			"switch":
				on = _info.has(id) and _info[id][2]
			"cell":
				on = true
			"button":
				on = button_until.get(p, 0.0) > now
			"plate":
				on = pressed.has(p)
			"sensor":
				on = is_day
		if on:
			_emit[p] = true
	# 2. wires: spread from everything that powers them
	var new_level := {}
	var queue: Array = []
	for p in parts:
		if parts[p] != "wire":
			continue
		var best := 0
		for d in DIRS:
			var n: Vector3i = p + d
			if _emit.has(n) or (gate_on.get(n, false) and _front(n) == p):
				best = 15
				break
		if best > 0:
			new_level[p] = best
			queue.append(p)
	var head := 0
	while head < queue.size():
		var p: Vector3i = queue[head]
		head += 1
		var l: int = new_level[p] - 1
		if l <= 0:
			continue
		for d in DIRS:
			var n: Vector3i = p + d
			if parts.get(n, "") == "wire" and new_level.get(n, 0) < l:
				new_level[n] = l
				queue.append(n)
	# wires show whether they carry power
	for p in parts:
		if parts[p] == "wire":
			var on: bool = new_level.get(p, 0) > 0
			var id := world.get_block(p.x, p.y, p.z)
			if on != _info[id][2]:
				set_block.call(p, 1701 if on else 1700)
	level = new_level
	# 3. gates (their new output shows next tick)
	var next_gate := {}
	for p in parts:
		var k: String = parts[p]
		if not k in ["not", "and", "or", "xor", "delay"]:
			continue
		var f := facing_of(world.get_block(p.x, p.y, p.z))
		var back: Vector3i = p - DIRS[f]
		var left: Vector3i = p + DIRS[(f + 1) % 4]
		var right: Vector3i = p + DIRS[(f + 3) % 4]
		var b := _feeds(back, p)
		var l := _feeds(left, p)
		var r := _feeds(right, p)
		match k:
			"not":
				next_gate[p] = not b
			"and":
				next_gate[p] = l and r
			"or":
				next_gate[p] = l or r or b
			"xor":
				next_gate[p] = l != r
			"delay":
				var line: Array = delay_line.get(p, [false, false, false])
				next_gate[p] = line[0]
				delay_line[p] = [line[1], line[2], b]
	# 4. users
	var users := {}
	for p in parts:
		if parts[p] in ["lamp", "pusher", "breaker"]:
			users[p] = parts[p]
	for p in _emit.keys() + level.keys() + gate_on.keys():   # doors next to anything powered
		for d in DIRS:
			var n: Vector3i = p + d
			if Blocks.defs.get(world.get_block(n.x, n.y, n.z), {}).has("door"):
				users[n] = "door"
	for p in users:
		var on := _powered(p)
		var before: bool = was_powered.get(p, false)
		was_powered[p] = on
		var id := world.get_block(p.x, p.y, p.z)
		match users[p]:
			"lamp":
				if on != _info[id][2]:
					set_block.call(p, 1709 if on else 1708)
			"door":
				var d: Dictionary = Blocks.defs[id]["door"]
				if bool(d["open"]) != on and on != before:
					_toggle_door(p, id)
			"pusher":
				if on and not before:
					_push(p, DIRS[facing_of(id)])
			"breaker":
				if on and not before:
					_break(p + DIRS[facing_of(id)])
	gate_on = next_gate


## Does the block at `from` give power into `to`?
func _feeds(from: Vector3i, to: Vector3i) -> bool:
	if _emit.has(from) or level.get(from, 0) > 0:
		return true
	return gate_on.get(from, false) and _front(from) == to


func _powered(p: Vector3i) -> bool:
	for d in DIRS:
		if _feeds(p + d, p):
			return true
	return false


func _toggle_door(p: Vector3i, id: int) -> void:
	var top: bool = Blocks.defs[id]["door"]["top"]
	var other := p + (Vector3i(0, -1, 0) if top else Vector3i(0, 1, 0))
	for q in [p, other]:
		var b := world.get_block(q.x, q.y, q.z)
		if Blocks.defs.get(b, {}).has("door"):
			set_block.call(q, b - 2 if Blocks.defs[b]["door"]["open"] else b + 2)


static func _movable(id: int) -> bool:
	return id != 0 and id != WorldData.WATER and Blocks.hardness[id] >= 0 \
		and not Blocks.defs.get(id, {}).get("container", false) and not Blocks.defs.get(id, {}).has("door")


## Shift the row of blocks in front by one (up to 12 blocks, stops at unbreakable ones).
func _push(p: Vector3i, d: Vector3i) -> void:
	var line := []
	var q := p + d
	while true:
		var b := world.get_block(q.x, q.y, q.z)
		if b == 0 or b == WorldData.WATER or Blocks.plants_need_soil.has(b):
			break
		if not _movable(b) or line.size() >= PUSH_LIMIT or q.y + d.y < 0 or q.y + d.y >= WorldData.H:
			return
		line.append(q)
		q += d
	for i in range(line.size() - 1, -1, -1):
		var from: Vector3i = line[i]
		set_block.call(from + d, world.get_block(from.x, from.y, from.z))
	if not line.is_empty():
		set_block.call(line[0], 0)
	Sfx.play("place", -8.0, 0.7)


func _break(q: Vector3i) -> void:
	var b := world.get_block(q.x, q.y, q.z)
	if b == 0 or b == WorldData.WATER or Blocks.hardness[b] < 0:
		return
	for st in break_drops.call(b):
		spawn_drop.call(st, Vector3(q))
	set_block.call(q, 0)
	Sfx.play(Sfx.dig_sound(b), -6.0)


# ---------------------------------------------------------------- items: collectors, smelters
func _container(p: Vector3i) -> Inventory:
	return Inventory.from_data(world.containers.get(p), 27)


func _move_items() -> void:
	for p in parts:
		match parts[p]:
			"collector":
				_collect(p)
			"smelter":
				_smelt(p)


func _collect(p: Vector3i) -> void:
	var mine := _container(p)
	var changed := false
	# from the container above (from a smelter: only its finished items)
	var above := p + Vector3i(0, 1, 0)
	if world.containers.has(above) or parts.get(above, "") == "smelter":
		var src := _container(above)
		var first := 18 if parts.get(above, "") == "smelter" else 0
		for i in range(first, 27):
			if src.slots[i] != null and mine.can_take([src.slots[i][0], 1]):
				mine.add(int(src.slots[i][0]), 1)
				src.use_one(i)
				world.containers[above] = src.to_data()
				changed = true
				break
	# into the container below (a smelter takes it into its input slots)
	var below := p + Vector3i(0, -1, 0)
	if world.containers.has(below) or parts.get(below, "") == "smelter" or Blocks.defs.get(world.get_block(below.x, below.y, below.z), {}).get("container", false):
		var dst := _container(below)
		var last := 18 if parts.get(below, "") == "smelter" else 27
		for i in 27:
			if mine.slots[i] == null:
				continue
			var item := int(mine.slots[i][0])
			var slot := _slot_for(dst, item, last)
			if slot != -1:
				if dst.slots[slot] == null:
					dst.slots[slot] = [item, 1]
				else:
					dst.slots[slot][1] += 1
				mine.use_one(i)
				world.containers[below] = dst.to_data()
				changed = true
				break
	if changed:
		world.containers[p] = mine.to_data()


func _slot_for(inv: Inventory, item: int, last: int) -> int:
	for i in last:
		var s = inv.slots[i]
		if s != null and int(s[0]) == item and s.size() < 3 and int(s[1]) < Items.max_stack(item):
			return i
	for i in last:
		if inv.slots[i] == null:
			return i
	return -1


## Items lying on a collector: the game hands them over (see take_drops).
func wants_drop(p: Vector3i) -> bool:
	return parts.get(p, "") == "collector" and _container(p).slots.has(null)


func take_drop(p: Vector3i, stack: Array):
	var inv := _container(p)
	var left = inv.give(stack)
	world.containers[p] = inv.to_data()
	return left


func _smelt(p: Vector3i) -> void:
	var inv := _container(p)
	for r in Items.recipes:
		if str(r.get("station", "")) != "furnace":
			continue
		var ok := true
		for k in r["in"]:
			if _count(inv, k, 18) < int(r["in"][k]):
				ok = false
				break
		if not ok:
			continue
		var out_slot := _slot_for(inv, int(r["out"][0]), 27)
		if out_slot < 18:
			out_slot = -1
			for i in range(18, 27):
				var s = inv.slots[i]
				if s == null or (int(s[0]) == int(r["out"][0]) and int(s[1]) < Items.max_stack(int(s[0]))):
					out_slot = i
					break
		if out_slot == -1:
			return                                  # output full
		for k in r["in"]:
			_take(inv, k, int(r["in"][k]), 18)
		var cur = inv.slots[out_slot]
		inv.slots[out_slot] = [int(r["out"][0]), int(r["out"][1]) + (int(cur[1]) if cur != null else 0)]
		world.containers[p] = inv.to_data()
		return


func _matches(key, item: int) -> bool:
	if key is String:
		return Items.groups.get(key, []).has(item)
	return int(key) == item


func _count(inv: Inventory, key, last: int) -> int:
	var n := 0
	for i in last:
		var s = inv.slots[i]
		if s != null and _matches(key, int(s[0])):
			n += int(s[1])
	return n


func _take(inv: Inventory, key, amount: int, last: int) -> void:
	for i in last:
		while amount > 0 and inv.slots[i] != null and _matches(key, int(inv.slots[i][0])):
			inv.use_one(i)
			amount -= 1
