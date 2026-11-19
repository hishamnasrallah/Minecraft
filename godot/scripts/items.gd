extends Node
## Item registry (autoload "Items"), loaded from data/items.json exported from the Python
## version: names, icons, tools, food, recipes and the creative menu. Port of inventory.py.

var names := {}             # id -> name
var icons := {}             # id -> atlas tile
var tools := {}             # id -> {kind, speed, durability, name, level}
var food := {}              # id -> hunger points
var groups := {}            # "planks" -> [ids]
var recipes := []           # [{"in": {key: n}, "out": [id, count]}]
var tabs := []
var creative := []          # [[id, tab]]
var placeable := {}
var survival := {}
var S := {}                 # special ids and sizes (STICK, BUCKET, STACK_SIZE, ...)
var STACK_SIZE := 64


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
	for r in d["recipes"]:
		var ins := {}
		for k in r["in"]:
			ins[k if groups.has(k) else int(k)] = int(r["in"][k])
		recipes.append({"in": ins, "out": [int(r["out"][0]), int(r["out"][1])]})
	tabs = d["tabs"]
	for c in d["creative_items"]:
		creative.append([int(c[0]), c[1]])
	for p in d["placeable"]:
		placeable[int(p)] = true
	survival = d["survival"]
	S = d["special"]
	STACK_SIZE = int(S["STACK_SIZE"])


func name_of(item: int) -> String:
	return names.get(item, "?")


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
	if d.get("leaves", false):
		var roll := randf()
		if roll < 0.2:
			return int(S["STICK"])
		return int(S["APPLE"]) if roll < 0.28 and block == 5 else 0
	return 0 if d["drop"] == null else int(d["drop"])


func ingredient_name(key) -> String:
	return "any " + key if key is String else name_of(key)


func recipe_text(r: Dictionary) -> String:
	var parts := []
	for k in r["in"]:
		parts.append("%d %s" % [r["in"][k], ingredient_name(k)])
	return "%d %s  =  %s" % [r["out"][1], name_of(r["out"][0]), " + ".join(parts)]


## Items for a creative tab; a search text searches every tab.
func creative_items(tab := "all", search := "") -> Array:
	var words := search.to_lower().split(" ", false)
	var out := []
	for c in creative:
		var item: int = c[0]
		if not words.is_empty():
			var name := name_of(item).to_lower()
			var ok := true
			for w in words:
				if not w in name:
					ok = false
			if ok:
				out.append(item)
		elif tab == "all" or c[1] == tab:
			out.append(item)
	return out
