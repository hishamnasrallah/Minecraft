extends RefCounted
## Inventory, crafting, tools, survival, building tools, schematics and animals
## (ports of the Python tests).


func _empty_world() -> WorldData:
	var w := WorldData.new(1)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			w.chunks[Vector2i(dx, dz)] = WorldData.Chunk.new()
	return w


func _flat(ground := 3) -> WorldData:
	var w := _empty_world()
	for x in range(-16, 32):
		for z in range(-16, 32):
			for y in ground + 1:
				w._put(x, y, z, 9 if y == 0 else (1 if y == ground else 2))
	return w


func test_inventory_stacks_and_groups() -> String:
	var inv := Inventory.new(3)
	if inv.add(2, 70) != 0 or inv.slots[0] != [2, 64] or inv.slots[1] != [2, 6]:
		return "stacking: %s" % [inv.slots]
	var p := Inventory.new()
	p.add(36, 1)
	p.add(39, 1)
	if p.count("planks") != 2:
		return "group count"
	var sticks: Dictionary = Items.recipes.filter(func(r): return r["out"][0] == int(Items.S["STICK"]))[0]
	if not p.craft(sticks) or p.count(int(Items.S["STICK"])) != 4 or p.count("planks") != 0:
		return "crafting sticks from mixed planks"
	return ""


func test_clicks_tools_and_wear() -> String:
	var inv := Inventory.new()
	inv.slots[0] = [2, 10]
	inv.slots[1] = [2, 60]
	var cursor = inv.click(0, null)
	cursor = inv.click(1, cursor)
	if inv.slots[1] != [2, 64] or cursor != [2, 6]:
		return "merge: %s %s" % [inv.slots[1], cursor]
	var pick := 201
	inv.add(pick, 2)
	var i := inv.slots.find([pick, 1, 60])
	if i < 0 or inv.slots.count([pick, 1, 60]) != 2:
		return "tools must not stack"
	inv.wear(i)
	if inv.slots[i] != [pick, 1, 59]:
		return "wear"
	var taken = inv.click(i, null, true)
	if taken != [pick, 1, 59]:
		return "right-click a tool takes it whole: %s" % [taken]
	return ""


func test_mining_rules() -> String:
	var hand: Array = Items.mining(4, 0)
	var axe: Array = Items.mining(4, 203)
	if not (axe[0] < hand[0] and axe[1] and axe[2]):
		return "axe on wood"
	if Items.mining(3, 0)[1] or not Items.mining(3, 201)[1]:
		return "stone needs a pickaxe"
	if Items.mining(25, 201)[1] or not Items.mining(25, 202)[1]:
		return "iron ore needs stone tier"
	if Items.drop_for(3) != 22 or Items.drop_for(1) != 2:
		return "drops"
	if Items.attack_damage(0) != 1 or Items.attack_damage(216) <= Items.attack_damage(203):
		return "weapons"
	return ""


func test_creative_menu() -> String:
	var all := Items.creative_items()
	if all.size() < 130:
		return "only %d creative items" % all.size()
	var stairs := Items.creative_items("plants", "stairs")
	if stairs.size() != 9:
		return "search should cover every tab: %d" % stairs.size()
	if Items.creative_items("colored").size() != 32:
		return "colours"
	return ""


func test_survival() -> String:
	var s := Survival.new()
	s.damage(5, "x")
	for i in 20:
		s.tick(1.0)
	if s.health != 20:
		return "regen: %d" % s.health
	for y in [20.0, 21.0, 15.0, 12.0]:
		s.track_fall(y, false, false)
	if s.track_fall(11.5, true, false) != 6:
		return "fall damage"
	var d := Survival.new()
	d.hunger = 10
	for i in 14:
		d.tick(1.0, 0.0, true)
	if d.health >= 20:
		return "drowning"
	if Survival.icons(7, 20) != ["full", "full", "full", "half", "empty", "empty", "empty", "empty", "empty", "empty"]:
		return "icons"
	return ""


func test_building_tools() -> String:
	var w := _empty_world()
	var b := Builder.new()
	b.corner1 = Vector3i(5, 4, 2)
	b.corner2 = Vector3i(2, 1, 3)
	if b.volume() != 32:
		return "volume %d" % b.volume()
	b.fill(w, 3, true)
	b.fill(w, 41, false, 3)
	if w.get_block(2, 1, 2) != 41:
		return "replace"
	b.undo(w)
	if w.get_block(2, 1, 2) != 3:
		return "undo"
	w._put(0, 10, 0, 3)
	w._put(0, 10, 1, 328)                           # oak stairs facing +z
	b.corner1 = Vector3i(0, 10, 0)
	b.corner2 = Vector3i(1, 10, 1)
	b.copy(w)
	b.rotate()
	b.paste(w, Vector3i(10, 10, 10))
	if w.get_block(11, 10, 11) != 329:
		return "rotated stair: %d" % w.get_block(11, 10, 11)
	for id in [320, 331, 501, 510, 513]:
		var r: int = id
		for i in 4:
			r = Builder.rotate_block(r)
		if r != id or Builder.mirror_block(Builder.mirror_block(id)) != id:
			return "rotate/mirror identity for %d" % id
	return ""


func test_schematics() -> String:
	var clip := {}
	for x in 3:
		for y in 2:
			for z in 4:
				clip[Vector3i(x, y, z)] = 41 if y == 0 else 0
	clip[Vector3i(1, 1, 2)] = 329
	var again := Schematics.from_data(JSON.parse_string(JSON.stringify(Schematics.to_data(clip, "t"))))
	if again != clip:
		return "round trip"
	if Schematics.clean_name("  ../../evil name!! ") != "evil_name" or Schematics.clean_name("بيت صغير") != "بيت_صغير":
		return "names: %s / %s" % [Schematics.clean_name("  ../../evil name!! "), Schematics.clean_name("بيت صغير")]
	var house := Schematics.load_file("res://data/schematics/small_house.json")
	if house.size() != 9 * 5 * 8:
		return "bundled example: %d" % house.size()
	return ""


func test_animals() -> String:
	var w := _flat()
	var a := Wildlife.Animal.new("deer", Vector3(5, 10, 5))
	for i in 40:
		a.update(0.05, w, Vector3(1000, 0, 1000))
	if not a.on_ground or a.pos.y != 3.5:
		return "landing: %s" % a.pos
	var r := Wildlife.Animal.new("rabbit", Vector3(8, 3.5, 8))
	for i in 20:
		r.update(0.05, w, Vector3(10, 3.5, 8))
	if r.state != "flee" or r.pos.x >= 8:
		return "fleeing"
	var drop := []
	var deer := Wildlife.Animal.new("deer", Vector3(8, 3.5, 8))
	while not deer.dead:
		drop = deer.hit(Vector3(0, 0, 8), 3)
	if drop.is_empty() or drop[0] != 103 or drop[1] < 2:
		return "deer should drop 2-3 raw meat: %s" % [drop]
	var life := Wildlife.new(WorldData.new(11))
	for cx in range(-4, 4):
		for cz in range(-4, 4):
			life.world.ensure_chunk(Vector2i(cx, cz))
	for i in 300:
		life.update(0.1, Vector3(0, 20, 0))
	if life.animals.is_empty():
		return "nothing spawned"
	return ""


func test_glooms_chase_attack_and_fade() -> String:
	var w := _flat()
	var life := Wildlife.new(w)
	var g := Wildlife.Animal.new("gloom", Vector3(8, 3.5, 8))
	life.animals.append(g)
	var player := Vector3(14, 3.5, 8)
	var damage := 0
	for i in 100:
		damage += life.update(0.05, player, 0.1, true, true)
	if g.pos.x < 12 or damage < 3:
		return "should chase and hit: at %s, damage %d" % [g.pos, damage]
	var calm := Wildlife.Animal.new("gloom", Vector3(8, 3.5, 2))
	life.animals = [calm]
	for i in 40:
		damage = life.update(0.05, player, 0.1, true, false)       # creative: ignores you
	if calm.state == "chase" or damage > 0:
		return "should ignore a creative player"
	for i in 60:
		life.update(0.05, player, 1.0, true, true)                 # noon on open ground
	if not life.animals.is_empty():
		return "should fade away in sunlight"
	var lit := _flat()
	lit._put(20, 4, 8, 50)                                        # a torch
	var near := Wildlife.new(lit)
	if not near._near_light(Vector3i(22, 4, 8)) or near._near_light(Vector3i(40, 4, 8)):
		return "torch light check"
	return ""
