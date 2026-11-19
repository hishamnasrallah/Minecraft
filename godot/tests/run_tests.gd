extends SceneTree
## Headless test runner:  godot --headless --path godot -s res://tests/run_tests.gd
## Each test_* function in the test files returns "" when it passes, or a failure message.

const TEST_FILES := ["res://tests/test_world.gd", "res://tests/test_gameplay.gd", "res://tests/test_weather.gd",
	"res://tests/test_animals.gd", "res://tests/test_power.gd"]


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()      # godot ... -s run_tests.gd -- test_name
	var passed := 0
	var failed := 0
	for path in TEST_FILES:
		var suite = load(path).new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (not only.is_empty() and not name in only):
				continue
			var t := Time.get_ticks_msec()
			var result = suite.call(name)
			var ms := Time.get_ticks_msec() - t
			if result == "" or result == null:
				passed += 1
				print("  ok    %s (%d ms)" % [name, ms])
			else:
				failed += 1
				print("  FAIL  %s: %s" % [name, result])
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
