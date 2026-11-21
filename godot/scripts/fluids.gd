class_name Fluids
extends RefCounted
## Flowing water and lava. A source (level 0) spreads one level weaker into the open cells
## beside it (water 7 steps, lava 3) and falls straight down as a stream; a flowing cell dries
## up when nothing feeds it any more. Water runs four times a second, lava once a second.
## Lava meeting water hardens: a lava source into obsidian, flowing lava into cobblestone and
## lava falling onto water into stone. That is what makes stone generators work.
##
## Only cells near a change are looked at (`note` is called for every block edit), so a still
## sea costs nothing.

const WATER_REACH := 7
const LAVA_REACH := 3
const WATER_EVERY := 0.25
const LAVA_EVERY := 1.0
const MAX_CELLS := 400                  # cells looked at per tick; the rest wait for the next one
const COBBLE := 22
const STONE := 3
const SIDES := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)

var world: WorldData
var set_block: Callable                 # func(pos: Vector3i, id: int) -> void   (the game's edit)
var wash: Callable                      # func(pos: Vector3i, id: int) -> void   a plant washed away drops
var _active := [{}, {}, {}]             # by fluid kind (1 water, 2 lava): Vector3i -> true
var _timer := [0.0, 0.0, 0.0]
var _busy := false                      # our own edits do not wake cells twice


## The game tells us about every block change: the fluid cells at and around it wake up.
func note(p: Vector3i) -> void:
	_wake(p)
	_wake(p + UP)
	_wake(p + DOWN)
	for d in SIDES:
		_wake(p + d)


func _wake(p: Vector3i) -> void:
	if p.y <= 0 or p.y >= WorldData.H:
		return
	var f := Blocks.fluid[world.get_block(p.x, p.y, p.z)]
	if f != 0:
		_active[f][p] = true


func busy() -> bool:
	return not (_active[1].is_empty() and _active[2].is_empty())


func update(delta: float) -> void:
	for f in [1, 2]:
		_timer[f] += delta
		if _timer[f] >= (WATER_EVERY if f == 1 else LAVA_EVERY):
			_timer[f] = 0.0
			_step(f)


func _step(f: int) -> void:
	var cells: Array = _active[f].keys()
	if cells.is_empty():
		return
	_active[f] = {}
	# lower cells first: streams reach the ground before they spread
	cells.sort_custom(func(a, b): return a.y < b.y)
	var n := 0
	for p in cells:
		n += 1
		if n > MAX_CELLS:
			_active[f][p] = true
			continue
		if world.is_loaded(p.x, p.z):
			_settle(p, f)


func _block(p: Vector3i) -> int:
	return world.get_block(p.x, p.y, p.z)


## Can fluid run into a cell holding `b`? Air, and plants, wires and tracks (washed away).
func _open(b: int) -> bool:
	return b == 0 or (Blocks.plants_need_soil.has(b) and Blocks.fluid[b] == 0)


func _id(f: int, level: int) -> int:
	return Blocks.water_id(level) if f == 1 else Blocks.lava_id(level)


func _settle(p: Vector3i, f: int) -> void:
	var id := _block(p)
	if Blocks.fluid[id] != f:
		return
	var other := 3 - f
	# 1. lava touching water hardens (water beside or above it; lava above water is handled below)
	for d in [UP, SIDES[0], SIDES[1], SIDES[2], SIDES[3]]:
		var q: Vector3i = p + d
		var nb := _block(q)
		if Blocks.fluid[nb] == other:
			if f == 2:
				set_block.call(p, Blocks.OBSIDIAN if Blocks.flow[id] == 0 else COBBLE)
				return
			elif d != UP:
				# water reaching lava: the lava hardens
				set_block.call(q, Blocks.OBSIDIAN if Blocks.flow[nb] == 0 else COBBLE)
	if f == 1 and Blocks.fluid[_block(p + DOWN)] == 2:
		var lb := _block(p + DOWN)
		set_block.call(p + DOWN, Blocks.OBSIDIAN if Blocks.flow[lb] == 0 else COBBLE)
	var reach := WATER_REACH if f == 1 else LAVA_REACH
	var level := int(Blocks.flow[id])
	# 2. a flowing cell lives on what feeds it: fluid above, or a stronger neighbour
	if level > 0:
		var want := 99
		if Blocks.fluid[_block(p + UP)] == f:
			want = 1
		var sources := 0
		for d in SIDES:
			var nb := _block(p + d)
			if Blocks.fluid[nb] == f:
				want = mini(want, int(Blocks.flow[nb]) + 1)
				if nb == Blocks.WATER:
					sources += 1
		if f == 1 and sources >= 2:
			var under := _block(p + DOWN)
			if under == Blocks.WATER or (under != 0 and Blocks.solid[under] == 1):
				want = 0                        # between two sources: a new source (an endless pool)
		if want > reach:
			set_block.call(p, 0)                # nothing feeds it: it dries up
			return
		if want != level:
			set_block.call(p, _id(f, want))
			level = want
	# 3. down first
	var below := p + DOWN
	var bb := _block(below)
	if below.y > 0 and _open(bb):
		_put(below, f, 1)
		if level > 0:
			return                              # a stream falls; only a source also spreads
	elif f == 2 and Blocks.fluid[bb] == 1:
		set_block.call(below, STONE)            # lava pouring onto water
		return
	elif Blocks.fluid[bb] == f and level > 0:
		return                                  # running into the same fluid below
	if level >= reach:
		return
	# 4. then to the sides, one level weaker
	for d in SIDES:
		var q: Vector3i = p + d
		var nb := _block(q)
		if _open(nb):
			_put(q, f, level + 1)
		elif Blocks.fluid[nb] == f and int(Blocks.flow[nb]) > level + 1:
			set_block.call(q, _id(f, level + 1))


func _put(q: Vector3i, f: int, level: int) -> void:
	var cur := _block(q)
	if cur != 0 and wash.is_valid():
		wash.call(q, cur)                       # a crop, flower or wire is washed away
	if f == 2:
		# lava running next to water hardens where it arrives
		for d in [UP, DOWN, SIDES[0], SIDES[1], SIDES[2], SIDES[3]]:
			if Blocks.fluid[_block(q + d)] == 1:
				set_block.call(q, COBBLE)
				return
	set_block.call(q, _id(f, level))
