extends Node
## Worlds on this device (autoload "Session"). Each world lives in user://worlds/<id>/ with
## save.json (the same format as the Python version) and meta.json (name, mode, dates).
## The menu picks or creates a world here, then the game scene loads Session.save_path().

const ROOT := "user://worlds"

var world_dir := ""
var new_options := {}           # set when creating a world: {"seed": int, "creative": bool}
var remote := {}                # a friend's world we joined (from Net): not saved on this device


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)
	_migrate_old_save()


## The single save from before worlds existed becomes the first world.
func _migrate_old_save() -> void:
	if FileAccess.file_exists("user://save.json") and list_worlds().is_empty():
		var id := "world_1"
		DirAccess.make_dir_recursive_absolute(ROOT + "/" + id)
		DirAccess.rename_absolute("user://save.json", "%s/%s/save.json" % [ROOT, id])
		var data = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/save.json" % [ROOT, id]))
		var mode: String = data.get("player", {}).get("mode", "survival") if data is Dictionary else "survival"
		_write_meta(id, {"name": I18n.t("my_world"), "mode": mode, "created": Time.get_unix_time_from_system()})


func save_path() -> String:
	return world_dir + "/save.json" if world_dir != "" else "user://save.json"


## [{"id", "name", "mode", "last_played", "created"}], most recently played first.
## Worlds whose id starts with "_" (test worlds) are hidden.
func list_worlds() -> Array:
	var out := []
	for id in DirAccess.get_directories_at(ROOT):
		if id.begins_with("_"):
			continue
		var meta = JSON.parse_string(FileAccess.get_file_as_string("%s/%s/meta.json" % [ROOT, id]))
		if not meta is Dictionary:
			meta = {"name": id}
		meta["id"] = id
		out.append(meta)
	out.sort_custom(func(a, b): return float(a.get("last_played", 0)) > float(b.get("last_played", 0)))
	return out


func create_world(name: String, seed: int, creative: bool) -> void:
	var n := 1
	while DirAccess.dir_exists_absolute("%s/world_%d" % [ROOT, n]):
		n += 1
	var id := "world_%d" % n
	DirAccess.make_dir_recursive_absolute(ROOT + "/" + id)
	_write_meta(id, {"name": name, "mode": "creative" if creative else "survival",
		"created": Time.get_unix_time_from_system()})
	world_dir = ROOT + "/" + id
	new_options = {"seed": seed, "creative": creative}


func open_world(id: String) -> void:
	world_dir = ROOT + "/" + id
	new_options = {}


## A fresh hidden world for automated tests (--new / --selftest / --shot on the command line).
func use_test_world(fresh: bool, seed: int, creative: bool) -> void:
	var dir := ROOT + "/_test"
	if fresh:
		_delete_dir(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	world_dir = dir
	new_options = {"seed": seed, "creative": creative} if fresh else {}


func delete_world(id: String) -> void:
	_delete_dir(ROOT + "/" + id)


## Called by the game when it saves: remember when and in which mode it was played.
func touch(mode: String) -> void:
	if world_dir == "" or world_dir.ends_with("/_test"):
		return
	var id := world_dir.get_file()
	var meta = JSON.parse_string(FileAccess.get_file_as_string(world_dir + "/meta.json"))
	if not meta is Dictionary:
		meta = {"name": id}
	meta["mode"] = mode
	meta["last_played"] = Time.get_unix_time_from_system()
	_write_meta(id, meta)


func _write_meta(id: String, meta: Dictionary) -> void:
	var f := FileAccess.open("%s/%s/meta.json" % [ROOT, id], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(meta))


func _delete_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + "/" + file)
	for sub in DirAccess.get_directories_at(dir):
		_delete_dir(dir + "/" + sub)
	DirAccess.remove_absolute(dir)
