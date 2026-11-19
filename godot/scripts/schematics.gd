class_name Schematics
extends RefCounted
## Building files, same format as schematics.py, so files move between the two versions.
## Your own files live in user://schematics; examples ship in res://data/schematics.

const FORMAT := "blockworld-schematic"
const USER_DIR := "user://schematics"
const BUILTIN_DIR := "res://data/schematics"


static func clean_name(text: String) -> String:
	var out := ""
	for ch in text.strip_edges().left(40):
		if ch == " " or ch == "-" or ch == "_" or ch.is_valid_identifier() or ch.is_valid_int() or ch.unicode_at(0) > 127:
			out += ch
	var words := out.strip_edges().split(" ", false)
	return "_".join(words)


static func to_data(clip: Dictionary, name: String) -> Dictionary:
	var s := Vector3i.ZERO
	for p in clip:
		s = Vector3i(maxi(s.x, p.x + 1), maxi(s.y, p.y + 1), maxi(s.z, p.z + 1))
	var palette := []
	var index := {}
	var runs := []
	for x in s.x:
		for y in s.y:
			for z in s.z:
				var b: int = clip.get(Vector3i(x, y, z), 0)
				if not index.has(b):
					index[b] = palette.size()
					palette.append([Blocks.name_of[b] if b != 0 else "air", b])
				var i: int = index[b]
				if not runs.is_empty() and runs[-1][0] == i:
					runs[-1][1] += 1
				else:
					runs.append([i, 1])
	return {"format": FORMAT, "version": 1, "name": name, "size": [s.x, s.y, s.z], "palette": palette, "blocks": runs}


## Back to a clipboard. Unknown blocks become air. Returns {} for a bad file.
static func from_data(data) -> Dictionary:
	if not data is Dictionary or data.get("format") != FORMAT:
		return {}
	var s := Vector3i(int(data["size"][0]), int(data["size"][1]), int(data["size"][2]))
	var ids := []
	for entry in data["palette"]:
		var id := int(entry[1])
		if id != 0 and Blocks.exists(id) and Blocks.name_of[id] == entry[0]:
			ids.append(id)
		else:
			ids.append(_by_name(entry[0]))
	var cells := []
	for run in data["blocks"]:
		for k in int(run[1]):
			cells.append(ids[int(run[0])])
	if cells.size() != s.x * s.y * s.z:
		return {}
	var clip := {}
	var n := 0
	for x in s.x:
		for y in s.y:
			for z in s.z:
				clip[Vector3i(x, y, z)] = cells[n]
				n += 1
	return clip


static func _by_name(name: String) -> int:
	if name == "air":
		return 0
	for id in Blocks.defs:
		if Blocks.name_of[id] == name:
			return id
	return 0


static func save(clip: Dictionary, name: String) -> String:
	var file := clean_name(name)
	if file == "":
		return I18n.t("name_it")
	if clip.is_empty():
		return I18n.t("nothing_copied")
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open("%s/%s.json" % [USER_DIR, file], FileAccess.WRITE)
	f.store_string(JSON.stringify(to_data(clip, name.strip_edges())))
	return ""


static func load_file(path: String) -> Dictionary:
	return from_data(JSON.parse_string(FileAccess.get_file_as_string(path)))


## [[path, name, size, built-in?]] for the examples and your own files.
## [path, name, size, built-in, category, blocks]. Built-ins come from index.json, so even big
## factories are listed without reading their files; your own files are read (they are small).
static func list_saved() -> Array:
	var found := []
	var index = JSON.parse_string(FileAccess.get_file_as_string(BUILTIN_DIR + "/index.json")) \
		if FileAccess.file_exists(BUILTIN_DIR + "/index.json") else null
	if index is Array:
		for e in index:
			var name: String = e["name_ar"] if I18n.is_arabic() else e["name"]
			found.append([BUILTIN_DIR + "/" + e["file"], name, e["size"], true, e["category"], int(e["blocks"])])
	if DirAccess.dir_exists_absolute(USER_DIR):
		for file in DirAccess.get_files_at(USER_DIR):
			if not file.ends_with(".json"):
				continue
			var path: String = USER_DIR + "/" + file
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary and data.get("format") == FORMAT:
				found.append([path, data.get("name", file.get_basename()), data["size"], false, "mine", 0])
	return found


static func delete(path: String) -> void:
	if path.begins_with(USER_DIR):
		DirAccess.remove_absolute(path)
