extends Node
## Crash "black box" (autoload "Boot", loaded first). Records how far startup got in
## user://boot.json. If the app closed by surprise last time, this run starts in safe mode
## (no background threads, short view distance) and tells the player where it stopped,
## so the problem can be reported. A run counts as fine once it has played for 15 seconds.

const PATH := "user://boot.json"
const OK_AFTER := 15.0
## Bump with every release: a new version starts without the safe mode a crash of the old
## version switched on (the fix is probably in the new one).
const BUILD := "2026-11-25e"

var crashed_last_time := false
var last_stage := ""            # where the previous run stopped (shown if it crashed)
var current_stage := ""
var safe_mode := false
var _running_time := 0.0
var _ok := false


func _init() -> void:
	if FileAccess.file_exists(PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if d is Dictionary:
			crashed_last_time = d.get("state", "ok") != "ok"
			last_stage = d.get("stage", "")
			safe_mode = bool(d.get("safe_mode", false)) or crashed_last_time
			if d.get("build", "") != BUILD:
				crashed_last_time = false
				safe_mode = false
	stage("start")


func stage(name: String) -> void:
	current_stage = name
	_ok = false                       # a new load (e.g. through the portal): watch it again
	_running_time = 0.0
	_write({"state": "starting", "stage": name, "safe_mode": safe_mode})


func set_safe_mode(on: bool) -> void:
	safe_mode = on
	_write({"state": "ok" if _ok else "starting", "stage": "settings", "safe_mode": on})


func _process(delta: float) -> void:
	if _ok:
		return
	_running_time += delta
	if _running_time >= OK_AFTER:
		_ok = true
		_write({"state": "ok", "stage": "running", "safe_mode": safe_mode})


func _write(d: Dictionary) -> void:
	d["build"] = BUILD
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(d))
		f.flush()


## Called when the app quits normally (back button, quit()). A real crash never gets here.
func _exit_tree() -> void:
	_write({"state": "ok", "stage": current_stage if not _ok else "running", "safe_mode": safe_mode})


func _notification(what: int) -> void:
	# closing the app or switching away is a normal end, not a crash
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_write({"state": "ok", "stage": current_stage if not _ok else "running", "safe_mode": safe_mode})
