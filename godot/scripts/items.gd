extends Node
## Item registry (autoload "Items"), loaded from data/items.json exported from the Python
## version: names, icons, tools, food, recipes and the creative menu. Port of inventory.py.

var names := {}             # id -> name
var icons := {}             # id -> atlas tile
var tools := {}             # id -> {kind, speed, durability, name, level}
var food := {}              # id -> hunger points
var groups := {}            # "planks" -> [ids]
var returns := {}           # ingredient -> what is left of it after crafting (milk bucket -> bucket)
var recipes := []           # [{"in": {key: n}, "out": [id, count]}]
var tabs := []
var creative := []          # [[id, tab]]
var placeable := {}
var survival := {}
var S := {}                 # special ids and sizes (STICK, BUCKET, STACK_SIZE, ...)
var STACK_SIZE := 64
var families := {}          # "wool" -> [creative item ids in menu order]; the first one represents the family
var family_of := {}         # item id -> family name (only items that belong to a family)
var plant := {}             # seed item -> crop block (planted on farmland)
var farmland := 970
var sapling_trees := {}     # sapling -> [log, leaves]
var icons3d := {}           # block id -> index in data/icons3d.png (little 3D cubes)
var icon3d_size := 48
var icon3d_cols := 32
var family_names := {}      # family -> {"en": ..., "ar": ...}


func _init() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	for k in d["items"]:
		names[int(k)] = d["items"][k]
	for k in d["icons"]:
		icons[int(k)] = int(d["icons"][k])
	for k in d["tools"]:
		tools[int(k)] = d["tools"][k]
	for k in d["food"]:
		food[int(k)] = int(d["food"][k])
	for g in d["groups"]:
		groups[g] = d["groups"][g].map(func(v): return int(v))
	for k in d.get("returns", {}):
		returns[int(k)] = int(d["returns"][k])
	for r in d["recipes"]:
		var ins := {}
		for k in r["in"]:
			ins[k if groups.has(k) else int(k)] = int(r["in"][k])
		recipes.append({"in": ins, "out": [int(r["out"][0]), int(r["out"][1])], "station": str(r.get("station", ""))})
	for k in d.get("plant", {}):
		plant[int(k)] = int(d["plant"][k])
	farmland = int(d.get("farmland", 970))
	for k in d.get("sapling_trees", {}):
		sapling_trees[int(k)] = d["sapling_trees"][k].map(func(v): return int(v))
	if d.has("icons3d"):
		icon3d_size = int(d["icons3d"]["size"])
		icon3d_cols = int(d["icons3d"]["cols"])
		for k in d["icons3d"]["map"]:
			icons3d[int(k)] = int(d["icons3d"]["map"][k])
	tabs = d["tabs"]
	for c in d["creative_items"]:
		creative.append([int(c[0]), c[1]])
	for p in d["placeable"]:
		placeable[int(p)] = true
	survival = d["survival"]
	S = d["special"]
	STACK_SIZE = int(S["STACK_SIZE"])
	for f in d.get("families", {}):
		families[f] = d["families"][f].map(func(v): return int(v))
		for item in families[f]:
			family_of[item] = f
	family_names = d.get("family_names", {})


## The item's name in the current language.
func name_of(item: int) -> String:
	return I18n.item(item, names.get(item, "?"))


func max_stack(item: int) -> int:
	if tools.has(item) or item == int(S["WATER_BUCKET"]):
		return 1
	return 16 if item == int(S["BUCKET"]) else STACK_SIZE


## Tools carry their remaining durability as a third value.
func new_stack(item: int, amount: int) -> Array:
	return [item, 1, int(tools[item]["durability"])] if tools.has(item) else [item, amount]


## How breaking a block goes with what's in your hand: [seconds, drops?, wears the tool?]
func mining(block: int, tool_item: int) -> Array:
	var d: Dictionary = Blocks.defs.get(block, {})
	if d.is_empty():
		return [1.5, true, false]
	var hardness := float(d["hardness"])
	if hardness <= 0:
		return [0.05, true, false]
	var tool = tools.get(tool_item)
	var right_tool: bool = tool != null and d["tool"] == tool["kind"]
	var tier_ok: bool = int(d["level"]) == 0 or (right_tool and int(tool["level"]) >= int(d["level"]))
	if right_tool and tier_ok:
		return [hardness * 1.5 / float(tool["speed"]), true, true]
	if not tier_ok:
		return [hardness * 5, false, right_tool]
	return [hardness * 1.5, true, false]


func attack_damage(item: int) -> int:
	var tool = tools.get(item)
	if tool == null:
		return 1
	return {"sword": 4, "axe": 3, "pickaxe": 2, "shovel": 1}[tool["kind"]] + int(tool["level"]) - 1


## What you get for breaking a block (0 = nothing).
func drop_for(block: int) -> int:
	var d: Dictionary = Blocks.defs.get(block, {})
	if d.is_empty():
		return 0
	if block == 51 or block == 52:                 # tall grass and ferns sometimes hide seeds
		return int(S.get("SEEDS", 120)) if randf() < 0.15 else 0
	if d.get("leaves", false):
		var roll := randf()
		if roll >= 0.94:
			return int(d.get("sapling", 0))
		if roll < 0.2:
			return int(S["STICK"])
		return int(S["APPLE"]) if roll < 0.28 and block == 5 else 0
	return 0 if d["drop"] == null else int(d["drop"])


func ingredient_name(key) -> String:
	return I18n.f("any", I18n.group(key)) if key is String else name_of(key)


func recipe_text(r: Dictionary) -> String:
	var parts := []
	for k in r["in"]:
		parts.append("%d %s" % [r["in"][k], ingredient_name(k)])
	return "%d %s  =  %s" % [r["out"][1], name_of(r["out"][0]), " + ".join(parts)]


## The name of a variant family ("wool", "planks", "slabs", ...) in the current language.
func family_name(f: String) -> String:
	var n: Dictionary = family_names.get(f, {})
	return n.get(I18n.lang, n.get("en", f))


## The family's items for a creative list: the representative first, then its variants.
## Items without a family return [item].
func family_members(item: int) -> Array:
	var f = family_of.get(item)
	return [item] if f == null else families[f]


## Creative items with every family collapsed to its first member (the UI shows "+" on those
## where families[family_of[item]].size() > 1 and expands to family_members(item)).
func collapsed(items: Array) -> Array:
	var seen := {}
	var out := []
	for item in items:
		var f = family_of.get(item)
		if f == null:
			out.append(item)
		elif not seen.has(f):
			seen[f] = true
			out.append(item)
	return out


## Items for a creative tab; a search text searches every tab.
func creative_items(tab := "all", search := "") -> Array:
	var words := search.to_lower().split(" ", false)
	var out := []
	for c in creative:
		var item: int = c[0]
		if not words.is_empty():
			# match the English and the Arabic name, so search works in either language
			var name: String = (names.get(item, "") + " " + I18n.names_ar.get(item, "")).to_lower()
			var ok := true
			for w in words:
				if not w in name:
					ok = false
			if ok:
				out.append(item)
		elif tab == "all" or c[1] == tab:
			out.append(item)
	return out
