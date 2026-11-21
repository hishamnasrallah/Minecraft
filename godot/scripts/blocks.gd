extends Node
## Block registry (autoload "Blocks"), loaded from data/blocks.json which is exported
## from the Python version (tools/export_godot.py). Lookups are arrays indexed by id.

const MAX_ID := 2048
const WATER := 10
const CUBE := "cube"

var C := {}                      # world constants (CHUNK_SIZE, WATER_LEVEL, ...)
var tiles: Array = []
var atlas_cols := 12
var defs := {}                   # id -> Dictionary (raw registry entry)
var name_of := []
var tile_top := PackedInt32Array()
var tile_side := PackedInt32Array()
var tile_bottom := PackedInt32Array()
var shape := []                  # id -> String
var transparent := PackedByteArray()
var translucent := PackedByteArray()
var solid := PackedByteArray()
var emit := PackedByteArray()
var hardness := PackedFloat32Array()
var shapes := PackedStringArray()   # the same as `shape`, packed: safe to copy for worker threads
var facing := PackedByteArray()      # stairs / ladders
var machine := PackedByteArray()     # 1: a powered part (wires connect to it) or a door
var lit := PackedByteArray()         # 1: the "on" look of a machine (a gate giving power, ...)
var door_axis := PackedByteArray()
var door_open := PackedByteArray()
var plants_need_soil := {}
var ores := []
var dyes := []


func _init() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/blocks.json"))
	C = data["constants"]
	tiles = data["tiles"]
	atlas_cols = int(C["ATLAS_COLS"])
	ores = C["ORES"]
	dyes = data["dyes"]
	for k in data["plants_need_soil"]:
		plants_need_soil[int(k)] = true
	name_of.resize(MAX_ID)
	shape.resize(MAX_ID)
	for arr in [tile_top, tile_side, tile_bottom]:
		arr.resize(MAX_ID)
	for arr in [transparent, translucent, solid, emit]:
		arr.resize(MAX_ID)
	hardness.resize(MAX_ID)
	shapes.resize(MAX_ID)
	for arr in [facing, door_axis, door_open, machine, lit]:
		arr.resize(MAX_ID)
	solid[0] = 0
	for key in data["blocks"]:
		var id := int(key)
		var d: Dictionary = data["blocks"][key]
		defs[id] = d
		name_of[id] = d["name"]
		tile_top[id] = int(d["tiles"][0])
		tile_side[id] = int(d["tiles"][1])
		tile_bottom[id] = int(d["tiles"][2])
		shape[id] = d["shape"]
		transparent[id] = 1 if d["transparent"] else 0
		translucent[id] = 1 if d["translucent"] else 0
		solid[id] = 1 if d["solid"] else 0
		emit[id] = int(d["emit"])
		hardness[id] = float(d["hardness"])
		shapes[id] = d["shape"]
		var lg = d.get("logic")
		# machines keep their direction in "logic" (0-3 sides, 4 up / on the floor, 5 down)
		facing[id] = int(d.get("facing", lg.get("facing", 0) if lg is Dictionary else 0))
		machine[id] = 1 if (d.get("logic") is Dictionary or d.has("door")) else 0
		lit[id] = 1 if (d.get("logic") is Dictionary and bool(d["logic"].get("on", false))) else 0
		if d.get("door") is Dictionary:
			door_axis[id] = int(d["door"]["axis"])
			door_open[id] = int(d["door"]["open"])


func exists(id: int) -> bool:
	return defs.has(id)


func is_opaque(id: int) -> bool:
	return id != 0 and transparent[id] == 0


## Atlas UV of point (u, v) inside a tile, v measured upwards (Godot's UV v points down).
func tile_uv(tile: int, u: float, v: float, inset := 0.01) -> Vector2:
	var col := tile % atlas_cols
	var row := tile / atlas_cols
	u = inset + u * (1.0 - 2.0 * inset)
	v = inset + v * (1.0 - 2.0 * inset)
	return Vector2((col + u) / atlas_cols, (row + 1.0 - v) / atlas_cols)


func tile_region(tile: int) -> Rect2:
	var size := 16
	return Rect2((tile % atlas_cols) * size, (tile / atlas_cols) * size, size, size)
