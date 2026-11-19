extends RefCounted
## Creatures: every species, biome spawning, feeding / breeding, eggs, fish, flyers,
## night creatures, far-away culling and the update cost.


func _flat(ground := 3) -> WorldData:
	var w := WorldData.new(1)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			w.chunks[Vector2i(dx, dz)] = WorldData.Chunk.new()
	for x in range(-16, 32):
		for z in range(-16, 32):
			for y in range(maxi(ground - 4, 0), ground + 1):   # (just the top layers of a high field)
				w._put(x, y, z, 9 if y == 0 else (1 if y == ground else 2))
	return w


func _pond(w: WorldData, ground := 3, depth := 3) -> void:
	for x in range(4, 12):
		for z in range(4, 12):
			for y in range(ground - depth + 1, ground + 1):
				w._put(x, y, z, WorldData.WATER)


func _run(a: Wildlife.Animal, w: WorldData, seconds: float, player := Vector3(1000, 0, 1000)) -> void:
	for i in int(seconds / 0.05):
		a.update(0.05, w, player)


func test_every_species_has_a_model_and_valid_drops() -> String:
	var w := _flat()
	for kind: String in Wildlife.SPECIES:
		if not AnimalView.MODELS.has(AnimalView.SAME_AS.get(kind, kind)):
			return "no model for " + kind
		var d: Array = Wildlife.DROPS[kind]
		if d[0] != 0 and not Items.names.has(int(d[0])):
			return "unknown drop for " + kind
		var a := Wildlife.Animal.new(kind, Vector3(8, 5, 8))
		var v := AnimalView.new(a)
		v.sync(0.016, 1.0, w)
		if v.get_child_count() == 0 or v.body.get_child_count() == 0:
			return "empty view for " + kind
		v.free()
	for item in [Wildlife.EGG, Wildlife.FEATHER, Wildlife.RAW_FISH, 127]:
		if not Items.names.has(item):
			return "missing item %d" % item
	if not Items.food.has(Wildlife.RAW_FISH) or not Items.food.has(127):
		return "fish should be food"
	var smelts := false
	for r in Items.recipes:
		if r.get("station", "") == "furnace" and int(r["out"][0]) == 127:
			smelts = true
	return "" if smelts else "raw fish should cook in the furnace"


func test_shared_meshes_keep_views_cheap() -> String:
	var a := Wildlife.Animal.new("woolly", Vector3(0, 4, 0))
	var b := Wildlife.Animal.new("woolly", Vector3(2, 4, 0))
	b.variant = a.variant
	var va := AnimalView.new(a)
	var vb := AnimalView.new(b)
	var ok: bool = va._still.mesh == vb._still.mesh and va.legs.size() == 4
	var parts := va._shaded.size() + (1 if va._glow != null else 0)
	va.free()
	vb.free()
	if not ok:
		return "same species and colour should share one mesh"
	return "" if parts <= 5 else "a woolly should be at most 5 draw calls, is %d" % parts


func test_woolly_drops_wool_of_its_colour_and_food_feeds() -> String:
	var a := Wildlife.Animal.new("woolly", Vector3(8, 3.5, 8))
	a.variant = 5
	Wildlife.held_item = Wildlife.WHEAT
	var fed := a.hit(Vector3(0, 0, 8), 3)
	Wildlife.held_item = 0
	if not fed.is_empty() or a.health != a.spec["health"] or a.love <= 0:
		return "holding wheat should feed, not hurt"
	var drop := []
	while not a.dead:
		drop = a.hit(Vector3(0, 0, 8), 3)
	return "" if drop.size() == 2 and drop[0] == 75 and drop[1] >= 1 else "wool drop: %s" % [drop]


func test_food_tempts_and_two_fed_adults_make_a_baby() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var a := Wildlife.Animal.new("goat", Vector3(6, 3.5, 6))
	var b := Wildlife.Animal.new("goat", Vector3(11, 3.5, 6))
	life.animals = [a, b]
	Wildlife.held_item = Wildlife.WHEAT
	var player := Vector3(8.5, 3.5, 12)
	for i in 20:
		life.update(0.05, player)
	var following: bool = a.state == "follow" and b.state == "follow"
	a.hit(player, 1)
	b.hit(player, 1)
	Wildlife.held_item = 0
	if not following:
		return "goats should follow wheat: %s %s" % [a.state, b.state]
	for i in 200:
		life.update(0.05, Vector3(1000, 3.5, 1000))
	var babies := life.animals.filter(func(x): return x.age > 0)
	if babies.size() != 1 or a.breed_cd <= 0:
		return "expected one baby, got %d" % babies.size()
	var baby: Wildlife.Animal = babies[0]
	for i in int(Wildlife.GROW_TIME / 0.1) + 5:
		baby.age = maxf(0.0, baby.age - 0.1)
	return "" if baby.size() == 1.0 else "baby should grow up"


func test_hens_lay_eggs_and_flutter() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var hen := Wildlife.Animal.new("hen", Vector3(8, 9, 8))
	hen.egg_timer = 0.3
	life.animals.append(hen)
	var max_fall := 0.0
	for i in 40:
		life.update(0.05, Vector3(8, 3.5, 20))
		max_fall = minf(max_fall, hen.vy)
	if life.laid.is_empty() or life.laid[0][0] != [Wildlife.EGG, 1]:
		return "no egg laid"
	return "" if max_fall >= -2.6 else "hens should glide down (vy %.1f)" % max_fall


func test_fish_swim_in_water_and_die_on_land() -> String:
	var w := _flat()
	_pond(w)
	var fish := Wildlife.Animal.new("fish", Vector3(8, 1.5, 8))
	_run(fish, w, 20)
	var b := w.get_block(Wildlife.cell(fish.pos.x), Wildlife.cell(fish.pos.y + 0.15), Wildlife.cell(fish.pos.z))
	if b != WorldData.WATER or fish.pos.x < 3.5 or fish.pos.x > 11.5:
		return "fish left the water: %s" % fish.pos
	var dry := Wildlife.Animal.new("fish", Vector3(20, 3.5, 20))
	_run(dry, w, 14)
	return "" if dry.dead else "a fish on land should die"


func test_flyers_and_hoppers() -> String:
	var w := _flat()
	for kind in ["bird", "butterfly", "firefly"]:
		var f := Wildlife.Animal.new(kind, Vector3(8, 7, 8))
		_run(f, w, 10)
		if f.pos.y <= 3.5 or w.solid_at(Wildlife.cell(f.pos.x), Wildlife.cell(f.pos.y), Wildlife.cell(f.pos.z)):
			return "%s should fly: %s" % [kind, f.pos]
	var frog := Wildlife.Animal.new("frog", Vector3(8, 3.5, 8))
	var top := 0.0
	var start := frog.pos
	for i in 400:
		frog.state = "walk"
		frog.timer = 5.0
		frog.target = Vector2(20, 8)
		frog.update(0.05, w, Vector3(1000, 0, 1000))
		top = maxf(top, frog.pos.y)
	if top < 4.0 or frog.pos.x - start.x < 3:
		return "frogs should hop along: top %.2f, at %s" % [top, frog.pos]
	return ""


func test_goats_jump_two_blocks() -> String:
	var w := _flat()
	for z in range(-5, 20):
		for x in range(10, 15):
			w._put(x, 4, z, 2)
			w._put(x, 5, z, 2)
	var goat := Wildlife.Animal.new("goat", Vector3(8, 3.5, 5))
	var deer := Wildlife.Animal.new("deer", Vector3(8, 3.5, 5))
	for a: Wildlife.Animal in [goat, deer]:
		for i in 200:
			a.state = "walk"
			a.timer = 20
			a.target = Vector2(14, a.pos.z)
			a.update(0.05, w, Vector3(1000, 0, 1000))
	if goat.pos.y != 5.5:
		return "goat should be on the ledge: %s" % goat.pos
	return "" if deer.pos.y == 3.5 else "deer can't climb two blocks"


func test_biome_spawning() -> String:
	var g := WorldData.SURFACE_OFFSET + 14              # a little above the sea
	var meadow := Wildlife.new(_flat(g))
	var seen := {}
	for i in 60:
		seen[meadow.pick_kind(5, 5)[0]] = true
	for k in seen:
		if not k in ["woolly", "hen", "rabbit", "deer"]:
			return "odd meadow creature " + k
	var sand := _flat(g)
	for x in range(-16, 32):
		for z in range(-16, 32):
			sand._put(x, g, z, 6)
	if Wildlife.new(sand).pick_kind(5, 5)[0] != "lizard":
		return "deserts have lizards"
	var lake := _flat(g)
	_pond(lake, g, 3)
	var wet := {}
	for i in 40:
		wet[Wildlife.new(lake).pick_kind(8, 8)[0]] = true
	if not wet.has("fish") or wet.size() > 2:
		return "water: %s" % [wet.keys()]
	# a generated world: spawns stay within the caps, nothing inside blocks
	var life := Wildlife.new(WorldData.new(11))
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			life.world.ensure_chunk(Vector2i(cx, cz))
	for i in 300:
		life.update(0.1, Vector3(0, 20, 0), 1.0, false)
	var c := life._count()
	if c["land"] == 0 or c["land"] > Wildlife.MAX_ANIMALS or c["fish"] > Wildlife.MAX_FISH \
			or c["ambient"] > Wildlife.MAX_AMBIENT or c["hostile"] > 0:
		return "caps: %s" % c
	return ""


func test_night_creatures() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var glob := Wildlife.Animal.new("glob", Vector3(8, 3.5, 8))
	life.animals = [glob]
	while not glob.dead:
		glob.hit(Vector3(0, 3.5, 8), 3)
	life.update(0.05, Vector3(1000, 3.5, 1000), 0.1)
	var kids := life.animals.filter(func(x): return x.kind == "globlet")
	if kids.size() != 2:
		return "a glob should burst into 2 globlets, got %d" % kids.size()
	var bramble := Wildlife.Animal.new("bramble", Vector3(8, 3.5, 8))
	life.animals = [bramble]
	var damage := 0
	for i in 60:
		damage += life.update(0.05, Vector3(9.2, 3.5, 8), 0.1)
	if damage < 5:
		return "brambles hit hard: %d" % damage
	for i in 40:
		damage = life.update(0.05, Vector3(9.2, 3.5, 8), 1.0)
	if not bramble.dormant or damage > 0 or bramble.dead:
		return "brambles doze in daylight"
	life.update(0.05, Vector3(9.2, 3.5, 8), 0.1, false)
	return "" if life.animals.is_empty() else "monsters off removes them"


func test_ambient_by_day_and_night() -> String:
	var life := Wildlife.new(_flat())
	var day := []
	for i in 80:
		day.append_array(life.try_spawn_ambient(Vector3(8, 3.5, 8), 1.0))
	for a: Wildlife.Animal in day:
		if not a.kind in ["bird", "butterfly"]:
			return "by day: " + a.kind
	life.animals.clear()
	var night := []
	for i in 80:
		night.append_array(life.try_spawn_ambient(Vector3(8, 3.5, 8), 0.1))
	if night.is_empty() or night.size() > Wildlife.MAX_AMBIENT:
		return "fireflies at night: %d" % night.size()
	for a: Wildlife.Animal in night:
		if a.kind != "firefly":
			return "by night: " + a.kind
	life.update(0.05, Vector3(8, 3.5, 8), 1.0)
	return "" if life.animals.is_empty() else "fireflies go at dawn"


func test_far_animals_are_hidden_and_update_less() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var near := Wildlife.Animal.new("woolly", Vector3(2, 3.5, 2))
	var far := Wildlife.Animal.new("woolly", Vector3(25, 3.5, 25))
	life.animals = [near, far]
	var player := Vector3(-14, 3.5, -14)        # far one is ~55 blocks away (beyond FAR)
	var updates := 0
	for i in 60:
		life.update(0.016, player)
		if far.acc == 0.0:
			updates += 1
	if not far.hidden or near.hidden:
		return "far one should be hidden"
	var v := AnimalView.new(far)
	v.sync(0.016, 1.0, w)
	var vis := v.visible
	v.free()
	if vis:
		return "hidden view should not draw"
	return "" if updates <= 12 else "far animal updated %d times in 60 frames" % updates


func test_update_cost() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var kinds := ["woolly", "hen", "goat", "rabbit", "deer", "frog", "fish", "bird", "butterfly", "firefly", "gloom"]
	_pond(w)
	for i in 30:
		var k: String = kinds[i % kinds.size()]
		var p := Vector3(randf_range(-12, 28), 3.5, randf_range(-12, 28))
		if k == "fish":
			p = Vector3(randf_range(5, 11), 1.5, randf_range(5, 11))
		life.animals.append(Wildlife.Animal.new(k, p))
	life._spawn_timer = 1e9
	var player := Vector3(8, 3.5, 8)
	for i in 30:
		life.update(0.016, player, 0.1, true, false)
	var per := 1e9                     # best of 3 runs: a busy machine must not fail the test
	for run in 3:
		var t := Time.get_ticks_usec()
		for i in 100:
			life.update(0.016, player, 0.1, true, false)
		per = minf(per, (Time.get_ticks_usec() - t) / 100.0)
	print("        wildlife update with %d creatures: %.0f us/frame" % [life.animals.size(), per])
	return "" if per < 600.0 else "too slow: %.0f us" % per
