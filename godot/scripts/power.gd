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
var feed_animal: Callable          # func(at: Vector3, item: int) -> int: 1 an animal there ate it, -1 one is there but full
var spawn_drop: Callable           # func(stack: Array, pos: Vector3) -> void
var break_drops: Callable          # func(id: int) -> Array of stacks a broken block gives

var parts := {}                    # Vector3i -> kind ("wire", "switch", "and", "pusher", ...)
var level := {}                    # wire Vector3i -> 0..15
var gate_on := {}                  # gate Vector3i -> bool (output)
var was_powered := {}              # users: Vector3i -> bool, to act on the moment power arrives
var button_until := {}             # Vector3i -> time the press ends
var pressed := {}                  # pressure plates with something on them (set by the game)
var delay_line := {}               # delay gate Vector3i -> [bool, bool, bool]
var pulse_until := {}              # observer Vector3i -> time its pulse ends
var comp_out := {}                 # comparator Vector3i -> the strength it gives out (0..15)
var _comparators := []             # every comparator (they re-read their chests now and then)
var _cmp_t := 0.0
var _watch := {}                   # watched cell -> [observers looking at it]
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
			_lists_dirty = true                     # a new machine: the circuits are worked out again
		elif _info.has(_ids.get(pos, -1)) and _info[_ids[pos]][1] != _info[id][1]:
			_lists_dirty = true                     # turned to face another way (an observer looks elsewhere)
		parts[pos] = kind
		_ids[pos] = id
		_wake(pos)
	elif parts.has(pos):
		parts.erase(pos)
		_ids.erase(pos)
		level.erase(pos)
		gate_on.erase(pos)
		comp_out.erase(pos)
		torch_on.erase(pos)
		was_powered.erase(pos)
		delay_line.erase(pos)
		_lists_dirty = true
	if _watch.has(pos):
		for o in _watch[pos]:                  # an observer saw the block at its eye change
			if o != pos:
				pulse_until[o] = now + PULSE
				_wake(o)
	if _info.has(id) or parts.has(pos):
		return
	if true:
		# a plain block placed or removed next to a machine (a pusher's row, a door) counts too
		for d in DIRS:
			if parts.has(pos + d):
				_wake(pos + d)
				_lists_dirty = true                 # a block or door next to a circuit can join it to another
				break


## Circuits: groups of machine blocks that touch. Each is worked out on its own, and only
## when something in it changed, so a blinking clock does not make a whole factory town
## recompute ten times a second. Circuits in chunks that are not loaded wait.
var _comps: Array = []             # [{"by_kind": {kind: [pos]}, "doors": [pos], "keys": [chunk], "dirty": bool}]
var _comp_of := {}                 # Vector3i -> index into _comps


func _wake(pos: Vector3i) -> void:
	var i: int = _comp_of.get(pos, -1)
	if i >= 0 and i < _comps.size():
		_comps[i]["dirty"] = true


func _rebuild_lists() -> void:
	_lists_dirty = false
	_comps = []
	_comp_of = {}
	_item_movers = {"collector": [], "smelter": [], "crafter": []}
	_watch = {}
	_comparators = []
	for p in parts:
		if parts[p] == "comparator":
			_comparators.append(p)
		if parts[p] == "observer" and _ids.has(p) and _info.has(_ids[p]):
			var seen: Vector3i = p - DIRS[_info[_ids[p]][1]]
			if not _watch.has(seen):
				_watch[seen] = []
			_watch[seen].append(p)
		if _item_movers.has(parts[p]):
			_item_movers[parts[p]].append(p)
	for start in parts:
		if _comp_of.has(start):
			continue
		var idx := _comps.size()
		var comp := {"by_kind": {}, "doors": [], "keys": [], "dirty": true}
		var queue: Array = [start]
		_comp_of[start] = idx
		var keys := {}
		var doors := {}
		var head := 0
		while head < queue.size():
			var p: Vector3i = queue[head]
			head += 1
			var k: String = parts[p]
			if not comp["by_kind"].has(k):
				comp["by_kind"][k] = []
			comp["by_kind"][k].append(p)
			keys[WorldData.chunk_key(p.x, p.z)] = true
			for d in DIRS:
				var n: Vector3i = p + d
				if parts.has(n):
					if not _comp_of.has(n):
						_comp_of[n] = idx
						queue.append(n)
				elif _conductor(n):
					# power goes through solid blocks: machines on its other sides are in this circuit
					for d3 in DIRS:
						var m3: Vector3i = n + d3
						if parts.has(m3) and not _comp_of.has(m3):
							_comp_of[m3] = idx
							queue.append(m3)
						elif Blocks.defs.get(world.get_block(m3.x, m3.y, m3.z), {}).has("door"):
							doors[m3] = true             # a door beside a powered block opens too
				elif Blocks.defs.get(world.get_block(n.x, n.y, n.z), {}).has("door"):
					doors[n] = true
					# a door joins the machines on both its sides into one circuit
					var door: Dictionary = Blocks.defs[world.get_block(n.x, n.y, n.z)]["door"]
					var other: Vector3i = n + (Vector3i(0, -1, 0) if door["top"] else Vector3i(0, 1, 0))
					for half in [n, other]:
						for d2 in DIRS:
							var m: Vector3i = half + d2
							if parts.has(m) and not _comp_of.has(m):
								_comp_of[m] = idx
								queue.append(m)
		comp["doors"] = doors.keys()
		comp["keys"] = keys.keys()
		_comps.append(comp)


func _list(kind: String) -> Array:
	return _by_kind.get(kind, [])


func press_button(pos: Vector3i) -> void:
	button_until[pos] = now + 1.0
	_wake(pos)


## The game sets these every frame; only a real change wakes the machines up.
func set_inputs(new_pressed: Dictionary, day: bool) -> void:
	var day_changed := day != is_day
	is_day = day
	for c in _comps:
		if day_changed and c["by_kind"].has("sensor"):
			c["dirty"] = true
		for p in c["by_kind"].get("plate", []):
			if new_pressed.has(p) != pressed.has(p):
				c["dirty"] = true
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
			_wake(b)                                # a button just pressed or just released
	for c in _comps:
		if not c["dirty"]:
			continue
		var loaded := true
		for k in c["keys"]:
			if not world.chunks.has(k):
				loaded = false                      # part of it is far away: it waits for you
				break
		if not loaded:
			continue
		c["dirty"] = false
		_by_kind = c["by_kind"]
		if _tick(c):
			c["dirty"] = true                       # still settling (a signal on its way, a clock)
	_by_kind = {}
	_cmp_t += TICK
	if _cmp_t >= 0.5:                          # chests fill and empty without telling anyone
		_cmp_t = 0.0
		for c in _comparators:
			_wake(c)
	_slow += TICK
	if _slow >= 0.4:
		_slow = 0.0
		_move_items()


func _front(pos: Vector3i) -> Vector3i:
	return pos + DIRS[_info[_ids[pos]][1]] if _ids.has(pos) else pos


## One circuit, one step. Returns true if anything changed (it runs again next tick).
func _tick(comp: Dictionary) -> bool:
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
	# 1b. blocks: a switch, button or plate strongly powers the block it sits on; a gate (and an
	# observer, comparator) the block in front of it. A strongly powered block powers the dust
	# and the machines around it.
	_strong = {}
	_weak = {}
	for k in ["switch", "button", "plate"]:
		for p in _list(k):
			if not _emit.has(p):
				continue
			var sf: int = _info[_ids[p]][1]
			var held: Vector3i = p + (DOWN if k == "plate" or sf >= 4 else DIRS[sf])   # floor, or the wall it is on
			if _conductor(held):
				_strong[held] = 15
	for p in gate_on:
		if gate_on[p] and parts.has(p):
			var fb := _front(p)
			if _conductor(fb):
				_strong[fb] = maxi(int(_strong.get(fb, 0)), int(comp_out[p]) if comp_out.has(p) else 15)
	for p in _list("torch"):
		if _torch_lit(p) and _conductor(p + UP):
			_strong[p + UP] = 15                   # a lit power torch strongly powers the block above it
	# 2. wires: spread from everything that powers them
	var wires := _list("wire")
	var new_level := {}
	var queue: Array = []
	for p in wires:
		var seed := 0
		for d in DIRS:
			var n: Vector3i = p + d
			if _emit.has(n) or (gate_on.get(n, false) and _front(n) == p):
				seed = maxi(seed, int(comp_out[n]) if comp_out.has(n) else 15)   # a comparator gives its own strength
			elif _strong.has(n):
				seed = maxi(seed, int(_strong[n]))   # dust on, under or beside a strongly powered block
			elif _torch_lit(n):
				seed = 15
		if seed > 0:
			new_level[p] = seed
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
	var changed := false
	for p in wires:
		var l: int = new_level.get(p, 0)
		var on := l > 0
		if on != (level.get(p, 0) > 0):
			changed = true
		if l > 0:
			level[p] = l
		else:
			level.erase(p)
		# wires show how strong the signal is: dark, dim, medium, bright
		var shown: int = 1700 if l <= 0 else (1790 if l <= 5 else (1791 if l <= 10 else 1701))
		var cur: int = _ids.get(p, 0)
		if _info.has(cur) and cur != shown:
			set_block.call(p, shown)
	# 2b. dust weakly powers the block under it and the blocks it points into: those run the
	# machines beside them (lamps, pushers, doors, gates) but do not power more dust
	for p in level:
		if not parts.has(p) or parts[p] != "wire" or int(level[p]) <= 0:
			continue
		if _conductor(p + DOWN):
			_weak[p + DOWN] = true
		for d in _points_into(p):
			if _conductor(p + d):
				_weak[p + d] = true
	# 3. gates (their new output shows next tick)
	var next_gate := {}
	var next_torch := {}
	for p in _list("torch"):
		var tf: int = _info[_ids[p]][1]
		var held: Vector3i = p + (DOWN if tf >= 4 else DIRS[tf])   # the block it stands on or hangs from
		var lit_now := not (_strong.has(held) or _weak.has(held))
		if lit_now != _torch_lit(p):
			changed = true
		next_torch[p] = lit_now
	for p in _list("comparator"):
		var f: int = _info[_ids[p]][1]
		var back := _strength(p - DIRS[f], p, true)
		var side := maxi(_strength(p + DIRS[(f + 1) % 4], p, false), _strength(p + DIRS[(f + 3) % 4], p, false))
		var out := 0
		if str(world.settings.get(p, {}).get("mode", "compare")) == "subtract":
			out = maxi(back - side, 0)
		else:
			out = back if back >= side else 0
		if out != int(comp_out.get(p, 0)):
			changed = true
		comp_out[p] = out
		next_gate[p] = out > 0
	for p in _list("observer"):
		var pulsing: bool = pulse_until.get(p, 0.0) > now
		next_gate[p] = pulsing
		if pulsing or gate_on.get(p, false):
			changed = true                       # keep ticking until the pulse is over
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
					# a queue as long as the delay chosen in the gate's panel (3 ticks unless set)
					var ticks: int = clampi(int(world.settings.get(p, {}).get("delay", 3)), 1, 20)
					var line: Array = delay_line.get(p, [])
					while line.size() < ticks:
						line.push_front(line[0] if not line.is_empty() else false)
					while line.size() > ticks:
						line.pop_front()
					out = line[0]
					var moving := false
					for v in line:
						if v != b:
							moving = true
					line.pop_front()
					line.push_back(b)
					delay_line[p] = line
					if moving:
						changed = true           # a signal is still on its way through
			next_gate[p] = out
			if out != gate_on.get(p, false):
				changed = true
	# 4. users: lamps, pushers, breakers and the doors next to this circuit
	var users := {}
	for k in ["lamp", "pusher", "sticky", "breaker", "booster", "thrower"]:
		for p in _list(k):
			users[p] = k
	for p in comp["doors"]:
		users[p] = "door"
	for p in users:
		var id := world.get_block(p.x, p.y, p.z)
		var kind: String = users[p]
		if kind == "door":
			if not Blocks.defs.get(id, {}).has("door"):
				continue                         # the door is gone
		elif not _info.has(id):
			continue                             # not loaded or replaced: nothing to do
		var on := _powered(p)
		var before: bool = was_powered.get(p, false)
		was_powered[p] = on
		if on != before:
			changed = true
		match kind:
			"lamp":
				if on != _info[id][2]:
					set_block.call(p, 1709 if on else 1708)
			"booster":                               # a boost track glows and pushes while powered
				if on != _info[id][2]:
					set_block.call(p, 1756 + _info[id][1] + (2 if on else 0))
			"door":
				var d: Dictionary = Blocks.defs[id]["door"]
				if bool(d["open"]) != on and on != before:
					_toggle_door(p, id)
			"pusher", "sticky":
				var pd: Vector3i = DIRS[_info[id][1]]
				var head_at: Vector3i = p + pd
				if on and not before:
					_push(p, pd)
					var there := world.get_block(head_at.x, head_at.y, head_at.z)
					if there == 0 or Blocks.fluid[there] != 0 or Blocks.plants_need_soil.has(there):
						set_block.call(head_at, PUSHER_HEAD + _info[id][1])   # the head sticks out
				elif not on and before:
					var hid := world.get_block(head_at.x, head_at.y, head_at.z)
					if hid >= PUSHER_HEAD and hid <= PUSHER_HEAD + 5:
						set_block.call(head_at, 0)                         # and comes back
						if kind == "sticky":
							var stuck: Vector3i = head_at + pd            # the sticky one brings its block along
							var b := world.get_block(stuck.x, stuck.y, stuck.z)
							if _movable(b) and not Blocks.plants_need_soil.has(b):
								set_block.call(stuck, 0)
								set_block.call(head_at, b)
			"breaker":
				if on and not before:
					_break(p + DIRS[_info[id][1]])
			"thrower":
				if on and not before:
					_throw(p, DIRS[_info[id][1]])
	for p in next_torch:
		torch_on[p] = next_torch[p]
		var tid := world.get_block(p.x, p.y, p.z)
		if _info.has(tid) and bool(_info[tid][2]) != bool(next_torch[p]):
			var step: int = 1 if _info[tid][1] >= 4 else 4          # floor: 1846/1847, wall: 1848+f / 1852+f
			set_block.call(p, tid + step if next_torch[p] else tid - step)
	for p in next_gate:
		gate_on[p] = next_gate[p]
		# show it: a gate giving power swaps to its lit twin (1770+), and back
		var gid := world.get_block(p.x, p.y, p.z)
		if _info.has(gid) and bool(_info[gid][2]) != bool(next_gate[p]):
			var off: int = {"observer": OBSERVER_LIT, "comparator": 4}.get(_info[gid][0], GATE_LIT)
			set_block.call(p, gid + off if next_gate[p] else gid - off)
	return changed


const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)
var _strong := {}                  # this tick: opaque blocks a source or a gate powers (-> strength)
var _weak := {}                    # this tick: opaque blocks powered dust lies on or points into
var torch_on := {}                 # power torch Vector3i -> lit


func _torch_lit(p: Vector3i) -> bool:
	if parts.get(p, "") != "torch":
		return false
	if torch_on.has(p):
		return torch_on[p]
	return _info.has(_ids.get(p, -1)) and bool(_info[_ids[p]][2])


## A full, opaque block that carries power (stone, planks...): not glass, not a machine.
func _conductor(p: Vector3i) -> bool:
	if parts.has(p):
		return false
	var id := world.get_block(p.x, p.y, p.z)
	return id != 0 and Blocks.solid[id] == 1 and Blocks.transparent[id] == 0


## The sides a piece of dust points into: towards what it connects to; a lone dot points all
## round, a dust with one link runs straight through both ways.
func _points_into(p: Vector3i) -> Array:
	var arms := []
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var n: Vector3i = p + d
		if parts.has(n) or parts.get(n + UP, "") == "wire" or parts.get(n + DOWN, "") == "wire":
			arms.append(d)
	if arms.is_empty():
		return [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	if arms.size() == 1:
		arms.append(-arms[0])
	return arms


## Does the block at `from` give power into `to`?
func _feeds(from: Vector3i, to: Vector3i) -> bool:
	if _emit.has(from) or level.get(from, 0) > 0:
		return true
	if _strong.has(from) or _weak.has(from):
		return true                              # a powered block runs the machines touching it
	if _torch_lit(from):
		return true                              # a lit torch powers the machines all round it
	return gate_on.get(from, false) and _front(from) == to


## How strong the power coming from `from` into `to` is (0..15). A container counts by how
## full it is when `boxes` is set (the comparator's back).
func _strength(from: Vector3i, to: Vector3i, boxes: bool) -> int:
	if boxes and (world.containers.has(from) or Blocks.defs.get(world.get_block(from.x, from.y, from.z), {}).get("container", false)):
		var inv := _container(from)
		var fill := 0.0
		for st in inv.slots:
			if st != null:
				fill += float(st[1]) / float(Items.max_stack(int(st[0])))
		return 0 if fill <= 0.0 else 1 + floori(fill / 27.0 * 14.0)
	if level.has(from):
		return int(level[from])
	if _emit.has(from):
		return 15
	if gate_on.get(from, false) and _front(from) == to:
		return int(comp_out[from]) if comp_out.has(from) else 15
	return 0


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


const PUSHER_HEAD := 1760
const GATE_LIT := 60                 # a gate's lit twin is 60 ids further (1710 -> 1770)
const OBSERVER_LIT := 6              # an observer's pulsing twin (1820 -> 1826)
const PULSE := 0.25                  # how long an observer's pulse lasts (seconds)


static func _movable(id: int) -> bool:
	return id != 0 and Blocks.fluid[id] == 0 and Blocks.hardness[id] >= 0 \
		and (id < PUSHER_HEAD or id > PUSHER_HEAD + 5) \
		and not Blocks.defs.get(id, {}).get("container", false) and not Blocks.defs.get(id, {}).has("door")


## Shift the row of blocks in front by one (up to 12 blocks, stops at unbreakable ones).
func _push(p: Vector3i, d: Vector3i) -> void:
	var line := []
	var q := p + d
	while true:
		var b := world.get_block(q.x, q.y, q.z)
		if b == 0 or Blocks.fluid[b] != 0 or Blocks.plants_need_soil.has(b):
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


## One item out of the thrower's front: into a container there, or thrown onto the ground.
func _throw(p: Vector3i, d: Vector3i) -> void:
	var mine := _container(p)
	var q := p + d
	var into_box: bool = world.containers.has(q) or Blocks.defs.get(world.get_block(q.x, q.y, q.z), {}).get("container", false)
	var front := world.get_block(q.x, q.y, q.z)
	for i in 27:
		if mine.slots[i] == null:
			continue
		var item := int(mine.slots[i][0])
		# buckets: a full one pours its water or lava out in front, an empty one scoops a source up
		if item == _bucket("WATER_BUCKET") or item == _bucket("LAVA_BUCKET"):
			if into_box or not (front == 0 or Blocks.plants_need_soil.has(front) or (Blocks.fluid[front] != 0 and Blocks.flow[front] > 0)):
				continue
			set_block.call(q, WorldData.WATER if item == _bucket("WATER_BUCKET") else Blocks.LAVA)
			mine.slots[i] = [_bucket("BUCKET"), 1]
			world.containers[p] = mine.to_data()
			changed_containers[p] = true
			Sfx.play("dig_soft", -6.0)
			return
		if item == _bucket("BUCKET"):
			var full := 0
			if front == WorldData.WATER or front == Blocks.LAVA:
				full = _bucket("WATER_BUCKET") if front == WorldData.WATER else _bucket("LAVA_BUCKET")
			elif not into_box and feed_animal.is_valid() and int(feed_animal.call(Vector3(q), item)) == 2:
				full = _bucket("MILK_BUCKET")           # a cow in front: milk
				front = -1
			if full == 0:
				continue
			if int(mine.slots[i][1]) > 1 and mine.add(full, 1) > 0:
				continue                               # no room for the full bucket
			if int(mine.slots[i][1]) > 1:
				mine.use_one(i)
			else:
				mine.slots[i] = [full, 1]
			if front != -1:
				set_block.call(q, 0)
			world.containers[p] = mine.to_data()
			changed_containers[p] = true
			Sfx.play("dig_soft", -6.0)
			return
		if item == _bucket("MILK_BUCKET"):
			continue                                   # milk stays in (a collector below takes it)
		# food for an animal standing in front: it eats it (and wants to breed); one that is
		# full is left alone and the food stays in
		if not into_box and feed_animal.is_valid():
			var fed: int = feed_animal.call(Vector3(q), item)
			if fed < 0:
				return
			if fed > 0:
				mine.use_one(i)
				world.containers[p] = mine.to_data()
				changed_containers[p] = true
				return
		if into_box:
			var dst := _container(q)
			var slot := _slot_for(dst, item, 18 if _is_maker(q) else 27)
			if slot == -1:
				return                                 # the box in front is full
			if dst.slots[slot] == null:
				dst.slots[slot] = [item, 1]
			else:
				dst.slots[slot][1] += 1
			world.containers[q] = dst.to_data()
			changed_containers[q] = true
		elif world.get_block(q.x, q.y, q.z) == 0 or Blocks.fluid[world.get_block(q.x, q.y, q.z)] != 0:
			spawn_drop.call([item, 1], Vector3(q))
		else:
			return                                     # a wall in front: nothing comes out
		mine.use_one(i)
		world.containers[p] = mine.to_data()
		changed_containers[p] = true
		Sfx.play("pop", -6.0, 1.3)
		return


func _break(q: Vector3i) -> void:
	var b := world.get_block(q.x, q.y, q.z)
	if b == 0 or Blocks.fluid[b] != 0 or Blocks.hardness[b] < 0:
		return
	var crop = Blocks.defs[b].get("crop")
	if crop is Dictionary:
		# a harvester: it leaves a growing crop alone, takes a ripe one and plants the seed again
		if int(crop["next"]) != 0:
			return
		var stacks: Array = break_drops.call(b)
		if stacks.size() > 1 and int(stacks[1][1]) > 0:
			stacks[1][1] = int(stacks[1][1]) - 1          # one seed goes back into the ground
		for st in stacks:
			if int(st[1]) > 0:
				spawn_drop.call(st, Vector3(q))
		set_block.call(q, b - int(crop["stage"]))
		Sfx.play("dig_soft", -8.0)
		return
	for st in break_drops.call(b):
		spawn_drop.call(st, Vector3(q))
	set_block.call(q, 0)
	Sfx.play(Sfx.dig_sound(b), -6.0)


# ---------------------------------------------------------------- items: collectors, smelters
func _container(p: Vector3i) -> Inventory:
	return Inventory.from_data(world.containers.get(p), 27)


var _item_movers := {"collector": [], "smelter": [], "crafter": []}
var _turn := {}                      # collector -> the slot above it takes from next
var busy_until := {}                 # smelter / crafter Vector3i -> time it stops showing it works
const LIT_TWIN := {1747: 1748, 1748: 1748, 1868: 1869, 1869: 1869}
const COLD_TWIN := {1747: 1747, 1748: 1747, 1868: 1868, 1869: 1868}


func _move_items() -> void:
	for p in _item_movers["collector"]:
		if world.is_loaded(p.x, p.z):
			_collect(p)
	for kind in ["smelter", "crafter"]:
		for p in _item_movers[kind]:
			if not world.is_loaded(p.x, p.z):
				continue
			if _has_items(p) and (_smelt(p) if kind == "smelter" else _craft(p)):
				busy_until[p] = now + 1.3
			# a working machine shows it: the fire burns, the crafting grid glows
			var id := world.get_block(p.x, p.y, p.z)
			var show: int = (LIT_TWIN if busy_until.get(p, 0.0) > now else COLD_TWIN).get(id, id)
			if show != id:
				set_block.call(p, show)


static func _bucket(name: String) -> int:
	return int(Items.S[name])


## Smelters and crafters take things in at the top (slots 0-17) and give them out below (18-26).
func _is_maker(q: Vector3i) -> bool:
	var k: String = parts.get(q, "")
	return k == "smelter" or k == "crafter"


func _has_items(p: Vector3i) -> bool:
	var data = world.containers.get(p)
	if not data is Array:
		return false
	for slot in data:
		if slot != null:
			return true
	return false


## A collector set to one item (a tap chooses it) only takes that item.
func passes(p: Vector3i, item: int) -> bool:
	var s = world.settings.get(p)
	return not (s is Dictionary and int(s.get("filter", 0)) != 0 and int(s["filter"]) != item)


## What a collector's filter could be set to: what is in it, above it and lying on it.
func filter_options(p: Vector3i) -> Array:
	var out := []
	for q in [p, p + Vector3i(0, 1, 0)]:
		for s in _container(q).slots:
			if s != null and not int(s[0]) in out:
				out.append(int(s[0]))
	return out.slice(0, 8)


func _collect(p: Vector3i) -> void:
	var above_p := p + Vector3i(0, 1, 0)
	if not _has_items(p) and not _has_items(above_p):
		return                                     # nothing to move: costs nothing
	var mine := _container(p)
	var changed := false
	# from the container above (from a smelter: only its finished items)
	var above := p + Vector3i(0, 1, 0)
	if world.containers.has(above) or _is_maker(above):
		var src := _container(above)
		var first := 18 if _is_maker(above) else 0
		# take turns between the slots, so ore and coal (or eggs and wheat) come down mixed
		var start: int = _turn.get(p, 0)
		for k in 27 - first:
			var i := first + (start + k) % (27 - first)
			if src.slots[i] != null and passes(p, int(src.slots[i][0])) and mine.can_take([src.slots[i][0], 1]):
				mine.add(int(src.slots[i][0]), 1)
				src.use_one(i)
				world.containers[above] = src.to_data()
				changed_containers[above] = true
				changed = true
				_turn[p] = (i - first + 1) % (27 - first)
				break
	# into the container below (a smelter takes it into its input slots)
	var below := p + Vector3i(0, -1, 0)
	if world.containers.has(below) or _is_maker(below) or Blocks.defs.get(world.get_block(below.x, below.y, below.z), {}).get("container", false):
		var dst := _container(below)
		var last := 18 if _is_maker(below) else 27
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
	if not passes(p, int(stack[0])):
		return stack                               # a filter: other things stay lying there
	var inv := _container(p)
	var left = inv.give(stack)
	world.containers[p] = inv.to_data()
	changed_containers[p] = true
	return left


func _smelt(p: Vector3i) -> bool:
	var inv := _container(p)
	for r in Items.recipes:
		if str(r.get("station", "")) == "furnace" and _can_make(inv, r):
			return _make(p, inv, r)
	return false


## Recipes made at the crafting table, the ones a crafter picks by itself first: food, then
## the ones that need the fewest things.
static var _table: Array = []


static func table_recipes() -> Array:
	if _table.is_empty():
		for r in Items.recipes:
			if str(r.get("station", "")) != "furnace":
				_table.append(r)
		var size := func(r) -> int:
			var n := 0
			for k in r["in"]:
				n += int(r["in"][k])
			return n + (0 if Items.food.has(int(r["out"][0])) else 1000)
		_table.sort_custom(func(a, b): return size.call(a) < size.call(b))
	return _table


## What a crafter could make from what is in it now (item ids, best first).
func craft_options(p: Vector3i) -> Array:
	var inv := _container(p)
	var out := []
	for r in table_recipes():
		var item := int(r["out"][0])
		if not item in out and _can_make(inv, r):
			out.append(item)
			if out.size() >= 8:
				break
	return out


func _craft(p: Vector3i) -> bool:
	var inv := _container(p)
	var want := int(world.settings.get(p, {}).get("craft", 0)) if world.settings.get(p) is Dictionary else 0
	for r in table_recipes():
		if want != 0 and int(r["out"][0]) != want:
			continue
		if _can_make(inv, r):
			return _make(p, inv, r)
	return false


func _can_make(inv: Inventory, r: Dictionary) -> bool:
	for k in r["in"]:
		if _count(inv, k, 18) < int(r["in"][k]):
			return false
	return true


## Take a recipe's things from the input slots and put what it makes in the output slots.
func _make(p: Vector3i, inv: Inventory, r: Dictionary) -> bool:
	var item := int(r["out"][0])
	var out_slot := -1
	for i in range(18, 27):
		var s = inv.slots[i]
		if s == null or (int(s[0]) == item and int(s[1]) + int(r["out"][1]) <= Items.max_stack(item)):
			out_slot = i
			break
	if out_slot == -1:
		return false                                # output full
	for k in r["in"]:
		_take(inv, k, int(r["in"][k]), 18)
	var cur = inv.slots[out_slot]
	inv.slots[out_slot] = [item, int(r["out"][1]) + (int(cur[1]) if cur != null else 0)]
	for k in r["in"]:
		if not k is String and Items.returns.has(int(k)):
			# the empty bucket goes out with what was made
			for n in int(r["in"][k]):
				for i in range(18, 27):
					var s = inv.slots[i]
					if s == null or (int(s[0]) == Items.returns[int(k)] and int(s[1]) < Items.max_stack(int(s[0]))):
						inv.slots[i] = [Items.returns[int(k)], 1 + (int(s[1]) if s != null else 0)]
						break
	world.containers[p] = inv.to_data()
	changed_containers[p] = true
	return true


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
