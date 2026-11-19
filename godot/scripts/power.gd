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
var changed_containers := {}       # chests the machines changed (sent to friends by the host)
var _ids := {}                     # Vector3i -> block id of every part (no world lookups per tick)
var _by_kind := {}                 # kind -> [positions]
var _lists_dirty := true
var _dirty := true                 # something changed: run the next tick (a still circuit costs nothing)


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
		var kind: String = _info[id][0]
		if parts.get(pos, "") != kind:
			_lists_dirty = true
		parts[pos] = kind
		_ids[pos] = id
		_dirty = true
	elif parts.has(pos):
		parts.erase(pos)
		_ids.erase(pos)
		level.erase(pos)
		gate_on.erase(pos)
		was_powered.erase(pos)
		delay_line.erase(pos)
		_lists_dirty = true
		_dirty = true
	elif not _dirty:
		# a plain block placed or removed next to a machine (a pusher's row, a door) counts too
		for d in DIRS:
			if parts.has(pos + d):
				_dirty = true
				break


func _rebuild_lists() -> void:
	_lists_dirty = false
	_by_kind = {}
	for p in parts:
		var k: String = parts[p]
		if not _by_kind.has(k):
			_by_kind[k] = []
		_by_kind[k].append(p)


func _list(kind: String) -> Array:
	return _by_kind.get(kind, [])


func press_button(pos: Vector3i) -> void:
	button_until[pos] = now + 1.0
	_dirty = true


## The game sets these every frame; only a real change wakes the machines up.
func set_inputs(new_pressed: Dictionary, day: bool) -> void:
	if day != is_day:
		is_day = day
		if not _list("sensor").is_empty():
			_dirty = true
	for p in _list("plate"):
		if new_pressed.has(p) != pressed.has(p):
			_dirty = true
			break
	pressed = new_pressed


## Runs the machines; call every frame.
func update(delta: float) -> void:
	if parts.is_empty():
		return
	now += delta
	_acc += delta
	if _acc < TICK:
		return
	_acc = minf(_acc - TICK, TICK)
	if _lists_dirty:
		_rebuild_lists()
	for b in button_until:
		if button_until[b] > now - TICK * 2:
			_dirty = true                          # a button just pressed or just released
	if _dirty:
		_dirty = false
		_tick()
	_slow += TICK
	if _slow >= 0.4:
		_slow = 0.0
		_move_items()


func _front(pos: Vector3i) -> Vector3i:
	return pos + DIRS[_info[_ids[pos]][1]] if _ids.has(pos) else pos


func _tick() -> void:
	# 1. sources
	_emit = {}
	for p in _list("switch"):
		if _info[_ids[p]][2]:
			_emit[p] = true
	for p in _list("cell"):
		_emit[p] = true
	for p in _list("button"):
		if button_until.get(p, 0.0) > now:
			_emit[p] = true
	for p in _list("plate"):
		if pressed.has(p):
			_emit[p] = true
	if is_day:
		for p in _list("sensor"):
			_emit[p] = true
	# 2. wires: spread from everything that powers them
	var new_level := {}
	var queue: Array = []
	for p in _list("wire"):
		for d in DIRS:
			var n: Vector3i = p + d
			if _emit.has(n) or (gate_on.get(n, false) and _front(n) == p):
				new_level[p] = 15
				queue.append(p)
				break
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
	var changed := new_level.size() != level.size()
	# wires show whether they carry power
	for p in _list("wire"):
		var on: bool = new_level.get(p, 0) > 0
		if on != (level.get(p, 0) > 0):
			changed = true
		if on != _info[_ids[p]][2]:
			set_block.call(p, 1701 if on else 1700)
	level = new_level
	# 3. gates (their new output shows next tick)
	var next_gate := {}
	for k in ["not", "and", "or", "xor", "delay"]:
		for p in _list(k):
			var f: int = _info[_ids[p]][1]
			var b := _feeds(p - DIRS[f], p)
			var l := _feeds(p + DIRS[(f + 1) % 4], p)
			var r := _feeds(p + DIRS[(f + 3) % 4], p)
			var out := false
			match k:
				"not":
					out = not b
				"and":
					out = l and r
				"or":
					out = l or r or b
				"xor":
					out = l != r
				"delay":
					var line: Array = delay_line.get(p, [false, false, false])
					out = line[0]
					delay_line[p] = [line[1], line[2], b]
					if line[0] != line[1] or line[1] != line[2] or line[2] != b:
						changed = true           # a signal is still on its way through
			next_gate[p] = out
			if out != gate_on.get(p, false):
				changed = true
	# 4. users
	var users := {}
	for k in ["lamp", "pusher", "breaker"]:
		for p in _list(k):
			users[p] = k
	for p in was_powered:                                    # doors we opened: watch them to close
		if was_powered[p] and Blocks.defs.get(world.get_block(p.x, p.y, p.z), {}).has("door"):
			users[p] = "door"
	for p in _emit.keys() + level.keys() + gate_on.keys():   # doors next to anything powered
		for d in DIRS:
			var n: Vector3i = p + d
			if not users.has(n) and Blocks.defs.get(world.get_block(n.x, n.y, n.z), {}).has("door"):
				users[n] = "door"
	for p in users:
		var on := _powered(p)
		var before: bool = was_powered.get(p, false)
		was_powered[p] = on
		if on != before:
			changed = true
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
					_push(p, DIRS[_info[id][1]])
			"breaker":
				if on and not before:
					_break(p + DIRS[_info[id][1]])
	gate_on = next_gate
	if changed:
		_dirty = true                                # keep going until everything settles


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
	for p in _list("collector"):
		_collect(p)
	for p in _list("smelter"):
		if _has_items(p):
			_smelt(p)


func _has_items(p: Vector3i) -> bool:
	var data = world.containers.get(p)
	if not data is Array:
		return false
	for slot in data:
		if slot != null:
			return true
	return false


func _collect(p: Vector3i) -> void:
	var above_p := p + Vector3i(0, 1, 0)
	if not _has_items(p) and not _has_items(above_p):
		return                                     # nothing to move: costs nothing
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
				changed_containers[above] = true
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
				changed_containers[below] = true
				changed = true
				break
	if changed:
		world.containers[p] = mine.to_data()
		changed_containers[p] = true


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
	changed_containers[p] = true
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
		changed_containers[p] = true
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
