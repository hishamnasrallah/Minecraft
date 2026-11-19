extends Node3D
## BlockWorld (Godot version): survival and creative, for phones and desktop.
##
## Phone:   joystick (left), drag to look (right), JUMP / BREAK (hold) / PLACE / ITEMS buttons,
##          tap the hotbar; FLY and BUILD in creative.
## Desktop: WASD + mouse, Space jump (double-tap: fly in creative), Shift down, Ctrl fast,
##          hold left break / hit, right click place / use / eat, middle click pick block,
##          1-9 / wheel hotbar, E inventory, G creative/survival, N noclip, T fast time, F1 HUD,
##          F5 save, Esc close / release the mouse. Creative building: Z X corners, F fill
##          (Shift+F replace), H hollow, Delete clear, C copy, hold V paste, R rotate, M mirror,
##          U undo, Q deselect, L buildings library, Alt+1-9 load / Alt+Shift+1-9 save a hotbar.
## Command line (after --): --new, --creative, --touch, --seed=N, --shot=file.png, --selftest

var SAVE_PATH := "user://save.json"    # set from Session (the chosen world)
const DAY_LENGTH := 600.0
const AUTOSAVE_EVERY := 60.0
const DAY_SKY := Color(0.62, 0.78, 0.95)
const NIGHT_SKY := Color(0.02, 0.03, 0.09)
const DUSK_SKY := Color(0.95, 0.55, 0.32)
const MOUSE_SENSITIVITY := 0.0025

var world: WorldData
var chunks: ChunkManager
var player: Player
var hud: Hud
var touch: TouchControls
var screen: InventoryScreen
var build_panel: BuildPanel
var settings: SettingsScreen
var env: Environment
var materials := {}
var sun: MeshInstance3D
var moon: MeshInstance3D
var highlight: MeshInstance3D
var crack: MeshInstance3D
var selection_box: MeshInstance3D
var paste_preview: MeshInstance3D
var crack_textures := []
var atlas: Texture2D

var inv: Inventory
var health: Survival
var wildlife: Wildlife
var animal_views := {}
var builder := Builder.new()
var saved_hotbars := []
var creative := false
var selected := 0
var spawn_point := Vector3.ZERO
var chest_pos = null
var chest_inv: Inventory = null
var daylight := 1.0

var mine_pos = null
var mine_progress := 0.0
var _break_was_held := false
var spawned := false
var time_speed := 1.0
var _autosave := AUTOSAVE_EVERY
var use_touch := false
var _last_space := -1.0
var _last_position = null
var _previewing_paste := false
var _shot_path := ""            # --shot=file.png: take a screenshot once the world is ready, then quit
var _shot_frames := 30
var _initial_look := Vector2.ZERO


func _ready() -> void:
	Boot.stage("world")
	var args := OS.get_cmdline_user_args()
	SAVE_PATH = Session.save_path()
	var fresh: Dictionary = Session.new_options
	if FileAccess.file_exists(SAVE_PATH) and fresh.is_empty():
		world = WorldData.load_from(SAVE_PATH)
	if world == null:
		world = WorldData.new(int(fresh.get("seed", -1)))
		if fresh.get("creative", false):
			world.player_data["mode"] = "creative"
	Session.new_options = {}
	use_touch = DisplayServer.is_touchscreen_available() or "--touch" in args or OS.has_feature("mobile")
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--look="):
			var parts := a.substr(7).split(",")
			_initial_look = Vector2(float(parts[0]), float(parts[1]))

	for a in args:
		if a.begins_with("--lang="):                 # for testing: a language without saving it
			I18n.lang = a.substr(7)
	var pd := world.player_data
	creative = "--creative" in args or pd.get("mode") == "creative"
	inv = Inventory.from_data(pd.get("inventory"))
	if not pd.has("inventory"):
		_fill_starter(creative)
	health = Survival.from_data(pd.get("survival"))
	saved_hotbars = pd.get("hotbars", [])
	for g in pd.get("growing", []):
		growing[Vector3i(int(g[0]), int(g[1]), int(g[2]))] = true
	saved_hotbars.resize(9)
	var sp = pd.get("spawn")
	spawn_point = Vector3(sp[0], sp[1], sp[2]) if sp is Array else world.spawn_point()

	Boot.stage("materials")
	atlas = load("res://data/atlas.png")
	var solid := ShaderMaterial.new()
	solid.shader = load("res://shaders/block.gdshader")
	solid.set_shader_parameter("atlas", atlas)
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/block_alpha.gdshader")
	glass.set_shader_parameter("atlas", atlas)
	var water := glass.duplicate()
	water.set_shader_parameter("opacity", 0.72)
	materials = {"solid": solid, "translucent": glass, "water": water, "plants": solid.duplicate()}

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DAY_SKY
	# distance fog in the sky's colour hides the edge of the loaded world
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_sky_affect = 0.0
	env.fog_depth_curve = 1.6
	we.environment = env
	add_child(we)
	sun = _sky_quad(Color(1, 0.95, 0.7), 40)
	moon = _sky_quad(Color(0.85, 0.88, 1), 25)

	Boot.stage("chunks")
	chunks = ChunkManager.new()
	var distance := int(I18n.settings["view_distance"])
	chunks.setup(world, materials, 2 if Boot.safe_mode else (distance if distance > 0 else (3 if use_touch else 4)))
	add_child(chunks)
	wildlife = Wildlife.new(world)

	Boot.stage("player")
	player = Player.new()
	player.world = world
	var start = pd.get("position")
	player.position = Vector3(start[0], start[1], start[2]) if start is Array else spawn_point
	player.set_physics_process(false)          # wait until the ground under us exists
	add_child(player)
	player.look(-_initial_look)

	ghost = MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3.ONE * 0.98
	ghost.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(1, 1, 1, 0.22)
	gmat.no_depth_test = false
	ghost.material_override = gmat
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	highlight = _wire_cube(Color.BLACK)
	selection_box = _wire_cube(Color(0.3, 0.9, 1.0))
	paste_preview = _wire_cube(Color(1, 0.9, 0.2))
	for i in 6:
		crack_textures.append(load("res://data/icons/crack_%d.png" % i))
	crack = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 1.01
	crack.mesh = box
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	crack.material_override = cm
	crack.visible = false
	add_child(crack)

	Boot.stage("ui")
	hud = Hud.new()
	hud.atlas = atlas
	add_child(hud)
	hud.respawn_pressed.connect(respawn)

	hud.minimap.world = world
	weather = Weather.new()
	add_child(weather)
	weather.column_top = func(x: int, z: int) -> int:
		return world.top_y(x, z) if world.is_loaded(x, z) else 0   # never generate a chunk for rain
	weather.load_data(world.player_data.get("weather", {}))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--weather="):              # testing: start in this weather, fully
			weather.set_weather(a.substr(10))
			weather.rain_amount = 1.0 if a.ends_with("rain") else 0.0
			weather.cloud_amount = 0.0 if a.ends_with("clear") else 1.0
	drops = Drops.new()
	drops.world = world
	drops.hud = hud
	add_child(drops)
	power = Power.new(world)
	world.on_edit = power.note
	power.set_block = func(p: Vector3i, id: int) -> void: edit(p, id, true, false)
	power.spawn_drop = func(st: Array, p: Vector3) -> void: drops.spawn(st, p)
	power.break_drops = func(id: int) -> Array:
		var d := Items.drop_for(id)
		return [[d, 1]] if d != 0 else []

	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	touch = TouchControls.new()
	layer.add_child(touch)
	touch.visible = use_touch
	touch.place_pressed.connect(place_block)
	touch.world_tapped.connect(tap_world)
	touch.hotbar_tapped.connect(func(pos): _select(hud.slot_at(pos)))
	touch.menu_pressed.connect(func(): save_game(); hud.flash(I18n.t("saved")))
	touch.inventory_pressed.connect(open_screen)
	touch.fly_pressed.connect(func(): set_flying(not player.flying))
	touch.build_pressed.connect(toggle_build_panel)
	touch.settings_pressed.connect(open_settings)
	tutorial = Tutorial.new()
	tutorial.visible = false
	tutorial.finished.connect(_update_touch_rects)
	layer.add_child(tutorial)
	build_panel = BuildPanel.new()
	build_panel.builder = builder
	build_panel.visible = false
	build_panel.action.connect(build_action)
	layer.add_child(build_panel)

	var top := CanvasLayer.new()
	top.layer = 3
	add_child(top)
	screen = InventoryScreen.new()
	screen.hud = hud
	screen.saved_hotbars = saved_hotbars
	screen.visible = false
	screen.closed.connect(close_screen)
	screen.mode_toggle_pressed.connect(func(): set_mode(not creative); screen.creative = creative; screen.refresh())
	screen.time_pressed.connect(func(v): world.time_of_day = v)
	screen.freeze_pressed.connect(func(): time_speed = 0.0 if time_speed != 0.0 else 1.0; hud.flash(I18n.t("time_frozen") if time_speed == 0.0 else I18n.t("time_running")))
	screen.message.connect(hud.flash)
	screen.weather_pressed.connect(func(k): weather.set_weather(k); hud.flash(I18n.t("weather_" + k)))
	screen.drop_stack.connect(func(st):
		var f := player.forward()
		drops.spawn(st, player.eye() + f * 0.5 - Vector3(0, 0.3, 0), f * 5.0 + Vector3(0, 2.0, 0), 1.5))
	top.add_child(screen)
	settings = SettingsScreen.new()
	settings.in_game = true
	settings.visible = false
	settings.exit_pressed.connect(func(): save_game(); get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	settings.closed.connect(close_settings)
	settings.touch_buttons_changed.connect(func(on): touch.set_classic(on))
	settings.tutorial_pressed.connect(func(): close_settings(); start_tutorial())
	settings.view_distance_changed.connect(func(v): chunks.render_distance = v; chunks.update_center(player.position, true))
	settings.language_picked.connect(func(code):
		save_game()
		I18n.set_language(code)
		get_tree().reload_current_scene())          # rebuild every screen in the new language
	top.add_child(settings)
	hud.fps.visible = bool(I18n.settings["show_fps"])

	_select(0)
	_refresh_mode()
	hud.flash(I18n.t("welcome_touch") if use_touch else I18n.t("welcome_desktop"))
	if "--menutest" in args:
		print("game opened world: ", Session.world_dir, " creative: ", creative, " seed: ", world.seed)
		get_tree().quit.call_deferred()
	if Boot.crashed_last_time:
		hud.flash(I18n.f("crashed_note", Boot.last_stage))
		hud._message_time = 15.0
	Boot.stage("loading world")


func _sky_quad(color: Color, size: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A unit cube outline (1x1x1, centred). Scale it for bigger boxes.
func _wire_cube(color: Color) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var corners := []
	for x in [-0.5, 0.5]:
		for y in [-0.5, 0.5]:
			for z in [-0.5, 0.5]:
				corners.append(Vector3(x, y, z))
	for i in 8:
		for j in range(i + 1, 8):
			var d: Vector3 = corners[i] - corners[j]
			if absf(d.x) + absf(d.y) + absf(d.z) < 1.1:
				verts.append(corners[i])
				verts.append(corners[j])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return mi


# ---------------------------------------------------------------- modes and menus
func _refresh_mode() -> void:
	touch.show_button("fly", true)            # in survival it says flying is for creative
	touch.show_button("build", creative)
	touch.show_button("up", creative and player.flying)
	touch.show_button("down", creative and player.flying)
	if not creative:
		build_panel.visible = false
	var text := I18n.t("creative_label") if creative else ""
	if player.flying:
		text += " - " + I18n.t("flying_label")
	if player.noclip:
		text += " - " + I18n.t("noclip_label")
	hud.mode_label.text = text
	hud.show_hotbar(inv, selected, creative)
	hud.show_bars(health, creative)


const CREATIVE_HOTBAR := [1, 22, 4, 7, 41, 12, 50, 48, 510]
const STARTER_KIT := [[201, 1], [203, 1], [209, 1], [105, 6], [50, 8], [7, 16], [46, 1], [48, 1]]


## A new world's first items: building blocks in creative, a small kit in survival.
func _fill_starter(is_creative: bool) -> void:
	for st in (CREATIVE_HOTBAR.map(func(i): return [i, Items.max_stack(i)]) if is_creative else STARTER_KIT):
		inv.add(st[0], st[1])


func _hotbar_empty() -> bool:
	for i in 9:
		if inv.slots[i] != null:
			return false
	return true


func set_mode(to_creative: bool) -> void:
	creative = to_creative
	if creative and _hotbar_empty():
		for i in 9:                          # an empty hand in creative: give a row of blocks
			inv.slots[i] = [CREATIVE_HOTBAR[i], Items.max_stack(CREATIVE_HOTBAR[i])]
	if not creative:
		set_flying(false)
	health.fall_top = null
	hud.flash(I18n.t("mode_creative") if creative else I18n.t("mode_survival"))
	_refresh_mode()


func set_flying(on: bool) -> void:
	if on and not creative:
		hud.flash(I18n.t("fly_creative_only"))
		on = false
	player.flying = on
	if not on:
		player.noclip = false
	player.velocity = Vector3.ZERO
	_refresh_mode()


func toggle_build_panel() -> void:
	build_panel.visible = creative and not build_panel.visible
	_update_touch_rects()


func _update_touch_rects() -> void:
	touch.ui_rects = []
	if build_panel.visible:
		var grid: Control = build_panel.get_child(0)
		touch.ui_rects.append(Rect2(grid.position, grid.size + Vector2(10, 10)))
	if tutorial.visible:
		touch.ui_rects.append(tutorial.get_rect().grow(6))


## First-time hints. Test runs skip it unless --tutorial is given.
func start_tutorial() -> void:
	tutorial.start(creative, use_touch)
	hud.message.text = ""                       # the tutorial replaces the short welcome line
	_tut_last = null


func _update_tutorial() -> void:
	if not tutorial.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	tutorial.position = Vector2(roundf((vp.x - tutorial.size.x) / 2), 58)
	_update_touch_rects()
	if not spawned or screen.visible or settings.visible:
		return
	var now := [player.yaw, player.pitch, player.position]
	if _tut_last != null:
		tutorial.report("look", absf(now[0] - _tut_last[0]) + absf(now[1] - _tut_last[1]))
		var step: Vector3 = now[2] - _tut_last[2]
		if not player.flying:
			tutorial.report("walk", minf(Vector2(step.x, step.z).length(), 1.0))
		if player.velocity.y > 3.0 and not player.flying:
			tutorial.report("jump")
	if player.flying:
		tutorial.report("fly")
	_tut_last = now


func open_screen(chest = null, kind := "") -> void:
	if health.dead:
		return
	chest_pos = chest
	chest_inv = Inventory.from_data(world.containers.get(chest), 27) if chest != null else null
	tutorial.report("items")
	screen.hotbar_selected = selected
	screen.open(inv, creative, chest_inv, kind)
	player.set_physics_process(false)
	touch.blocked = true
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_settings() -> void:
	settings.visible = true
	player.set_physics_process(false)
	touch.blocked = true
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	settings.visible = false
	hud.fps.visible = bool(I18n.settings["show_fps"])
	player.set_physics_process(spawned and not health.dead)
	touch.blocked = false


func close_screen() -> void:
	screen.close()
	if chest_pos != null:
		world.containers[chest_pos] = chest_inv.to_data()
		chest_pos = null
	player.set_physics_process(spawned and not health.dead)
	touch.blocked = false
	_refresh_mode()


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if settings.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_F2]:
			I18n.save_settings()
			close_settings()
		return
	if screen.visible or health.dead:
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_E, KEY_ESCAPE] and screen.visible:
			close_screen()
		return
	if use_touch and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not use_touch:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				place_block()
			MOUSE_BUTTON_MIDDLE:
				pick_block()
			MOUSE_BUTTON_WHEEL_UP:
				_select(selected - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_select(selected + 1)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look(event.relative * MOUSE_SENSITIVITY * float(I18n.settings["sensitivity"]))
	elif event is InputEventKey and not event.echo:
		var key: int = event.physical_keycode
		if not event.pressed:
			if key == KEY_V and _previewing_paste:
				build_action("paste_now")
			return
		var n: int = key - KEY_1
		if n >= 0 and n < 9:
			if creative and event.alt_pressed:
				screen.inv = inv
				screen.save_hotbar_mode = event.shift_pressed
				screen._hotbar_button(n)
				_refresh_mode()
			else:
				_select(n)
			return
		match key:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_E:
				open_screen()
			KEY_G:
				set_mode(not creative)
			KEY_N:
				if player.flying:
					player.noclip = not player.noclip
					_refresh_mode()
			KEY_SPACE:
				var now := Time.get_ticks_msec() / 1000.0
				if creative and now - _last_space < 0.3:
					set_flying(not player.flying)
					_last_space = -1.0
				else:
					_last_space = now
					if player.is_on_floor() and not creative:
						health.exert(float(Items.survival["JUMP"]))
			KEY_F1:
				hud.visible = not hud.visible
			KEY_F2:
				open_settings()
			KEY_F5:
				save_game()
				hud.flash(I18n.t("saved"))
			KEY_Y:
				weather.set_weather({"clear": "cloudy", "cloudy": "rain", "rain": "clear"}[weather.kind])
				hud.flash(I18n.t("weather_" + {"clear": "cloudy", "cloudy": "rain", "rain": "clear"}[weather.kind]))
			KEY_T:
				time_speed = 40.0 if time_speed != 40.0 else 1.0
				hud.flash(I18n.f("time_fast", int(time_speed)))
			KEY_Z:
				build_action("corner1")
			KEY_X:
				build_action("corner2")
			KEY_F:
				build_action("replace" if event.shift_pressed else "fill")
			KEY_H:
				build_action("hollow")
			KEY_DELETE, KEY_BACKSPACE:
				build_action("clear")
			KEY_C:
				build_action("copy")
			KEY_V:
				if creative and not builder.clipboard.is_empty():
					_previewing_paste = true
			KEY_R:
				build_action("rotate")
			KEY_M:
				build_action("mirror")
			KEY_U:
				build_action("undo")
			KEY_Q:
				build_action("deselect")
			KEY_L:
				build_action("library")


func _select(i: int) -> void:
	if i == -1:
		return
	selected = posmod(i, 9)
	hud.show_hotbar(inv, selected, creative)


func _read_controls() -> void:
	var move := Vector2.ZERO
	var jump := false
	var vertical := 0.0
	var fast := false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move = Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		jump = Input.is_physical_key_pressed(KEY_SPACE)
		vertical = float(jump) - float(Input.is_physical_key_pressed(KEY_SHIFT))
		fast = Input.is_physical_key_pressed(KEY_CTRL)
	if use_touch:
		if touch.move.length() > 0.05:
			move = touch.move
		jump = jump or touch.jump_held
		if touch.up_held or touch.down_held:
			vertical = float(touch.up_held) - float(touch.down_held)
		player.look(touch.take_look() * float(I18n.settings["sensitivity"]))
	player.move_input = move.limit_length(1.0)
	player.jump_held = jump
	player.vertical = vertical
	player.fast = fast


func _breaking() -> bool:
	return (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) \
		or (use_touch and (touch.break_held or touch.aiming))


# ---------------------------------------------------------------- world interaction
func reach() -> float:
	return 10.0 if creative else 6.0


var _aim_screen = null            # touch: screen point being aimed at, null = screen centre


## Where actions go: the screen centre, or the finger on a touch screen.
func aim_dir() -> Vector3:
	if _aim_screen != null:
		return player.camera.project_ray_normal(_aim_screen)
	return player.forward()


func target(hit_water := false) -> Dictionary:
	return world.raycast(player.eye(), aim_dir(), reach(), hit_water)


## A tap anywhere on the view (touch) acts on the block under the crosshair: use doors /
## chests / beds, place the held block, eat,
## or else hit what is there (instant in creative and for soft blocks like flowers).
func tap_world(pos: Vector2) -> void:
	if health.dead or not spawned:
		return
	var animal = looked_at_animal()        # the crosshair decides, not where the finger tapped
	var item := inv.item_at(selected)
	var hit := target()
	if animal != null:
		attack(animal)
	elif not hit.is_empty() and use_block(hit["pos"]):
		pass
	elif Items.placeable.has(item) or Items.food.has(item) or Items.plant.has(item) or _is_hoe(item) \
			or item in [int(Items.S["BUCKET"]), int(Items.S["WATER_BUCKET"])]:
		place_block()
	elif not hit.is_empty():
		var id := world.get_block(hit["pos"].x, hit["pos"].y, hit["pos"].z)
		if creative or Blocks.hardness[id] == 0:
			break_at(hit["pos"])
		else:
			hud.flash(I18n.t("hold_to_break"))


## The animal in the crosshair if it is closer than the block behind it.
func looked_at_animal():
	var best = null
	var best_d := reach()
	for a in animal_views:
		var d: float = animal_views[a].ray_hit(player.eye(), aim_dir(), best_d)
		if d >= 0 and d < best_d:
			best = a
			best_d = d
	if best == null:
		return null
	var hit := target()
	return best if hit.is_empty() or best_d < hit["distance"] + 0.3 else null


func edit(pos: Vector3i, id: int, force := false, flood := true) -> bool:
	var keys := world.set_block(pos.x, pos.y, pos.z, id, force, flood)
	_rebuild(keys)
	return not keys.is_empty()


func _rebuild(keys: Array) -> void:
	var all := {}
	for k in keys:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				all[Vector2i(k.x + dx, k.y + dz)] = true
	chunks.rebuild(all.keys())


func break_at(pos: Vector3i) -> void:
	var id := world.get_block(pos.x, pos.y, pos.z)
	if id == 0 or id == WorldData.WATER or (Blocks.hardness[id] < 0 and not creative):
		return
	if Blocks.hardness[id] < 0:
		edit(pos, 0, true)
		return
	Sfx.play(Sfx.dig_sound(id))
	buzz(30)
	tutorial.report("break")
	var tool := inv.item_at(selected)
	var m := Items.mining(id, tool)
	var contents = world.containers.get(pos)
	world.containers.erase(pos)
	if not edit(pos, 0) or creative:
		return
	health.exert(float(Items.survival["MINE"]))
	var stacks := []
	var drop := Items.drop_for(id) if m[1] else 0
	if drop != 0:
		stacks.append([drop, 1])
	var bonus = Blocks.defs[id].get("bonus")
	if bonus is Array:                         # ripe crops give extra seeds / carrots
		stacks.append([int(bonus[0]), randi_range(int(bonus[1]), int(bonus[2]))])
	if contents is Array:
		for s in contents:
			if s != null:
				stacks.append(s.map(func(v): return int(v)))
	for s in stacks:
		drops.spawn(s, Vector3(pos))
	if not m[1] and int(Blocks.defs[id]["level"]) > 0:
		hud.flash(I18n.f("needs_tool", Items.name_of(id)))
	if m[2] and inv.wear(selected):
		hud.flash(I18n.f("tool_broke", Items.name_of(tool)))
	hud.show_hotbar(inv, selected, creative)


func attack(animal) -> void:
	var item := inv.item_at(selected)
	var feeding: bool = animal.wants_food(item)
	var drop: Array = animal.hit(player.position, Items.attack_damage(item) if not creative else 100)
	if feeding:
		return                                    # fed, not hit: the animal plays its own sound
	Sfx.play("hurt", -4.0, 1.7)
	if creative:
		return
	health.exert(float(Items.survival["ATTACK"]))
	if Items.tools.has(item) and inv.wear(selected):
		hud.flash(I18n.f("tool_broke", Items.name_of(item)))
	if not drop.is_empty():
		if inv.add(drop[0], drop[1]) > 0:
			hud.flash(I18n.t("inventory_full"))
		else:
			hud.flash(I18n.f("added", "%d %s" % [drop[1], Items.name_of(drop[0])]))
			Sfx.play("pop")
	hud.show_hotbar(inv, selected, creative)


func _replaceable(p: Vector3i) -> bool:
	return world.get_block(p.x, p.y, p.z) in [0, WorldData.WATER, 51, 52]


func _overlaps_player(p: Vector3i, id: int) -> bool:
	if player.noclip or not Blocks.solid[id]:
		return false
	var feet := Vector3i(floori(player.position.x + 0.5), floori(player.position.y + 0.5), floori(player.position.z + 0.5))
	return p.x == feet.x and p.z == feet.z and p.y in [feet.y, feet.y + 1]


## Doors open and close, chests open, beds set your spawn point (and skip the night).
func use_block(pos: Vector3i) -> bool:
	var id := world.get_block(pos.x, pos.y, pos.z)
	var d: Dictionary = Blocks.defs.get(id, {})
	if d.has("door"):
		var other_y: int = pos.y - 1 if d["door"]["top"] else pos.y + 1
		for p in [pos, Vector3i(pos.x, other_y, pos.z)]:
			var b := world.get_block(p.x, p.y, p.z)
			if Blocks.defs.get(b, {}).has("door"):
				edit(p, b - 2 if Blocks.defs[b]["door"]["open"] else b + 2)
		return true
	if d.get("container", false):
		open_screen(pos)
		return true
	if id == 47:
		open_screen(null, "furnace")
		return true
	match power.kind_of(id):
		"switch":
			edit(pos, 1703 if id == 1702 else 1702, true, false)
			Sfx.play("click", -2.0, 0.8 if id == 1703 else 1.1)
			buzz(20)
			return true
		"button":
			power.press_button(pos)
			Sfx.play("click", -2.0, 1.3)
			buzz(20)
			return true
	if id == 62:
		spawn_point = Vector3(pos.x, pos.y + 1.5, pos.z)
		if world.time_of_day > 0.5 and world.time_of_day < 0.97:
			world.time_of_day = 0.0
			hud.flash(I18n.t("slept"))
		else:
			hud.flash(I18n.t("spawn_set"))
		return true
	return false


# ---------------------------------------------------------------- machines
func _update_machines(delta: float) -> void:
	if power.parts.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var feet := Vector3i(floori(player.position.x + 0.5), floori(player.position.y - 0.4), floori(player.position.z + 0.5))
	var pressed := {}
	pressed[feet] = true
	for a in wildlife.animals:
		pressed[Vector3i(floori(a.pos.x + 0.5), floori(a.pos.y + 0.1), floori(a.pos.z + 0.5))] = true
	power.pressed = pressed
	power.is_day = world.time_of_day < 0.5
	power.update(delta)
	# conveyors carry the player and items standing on them
	var below := feet + Vector3i(0, -1, 0)
	for c in [feet, below]:
		if power.parts.get(c, "") == "conveyor" and (player.is_on_floor() or player.velocity.y <= 0):
			var d: Vector3i = Power.DIRS[power.facing_of(world.get_block(c.x, c.y, c.z))]
			player.position += Vector3(d) * 2.2 * delta
			break
	for dr in drops.drops.duplicate():
		var dp: Vector3 = dr["pos"]
		var under := Vector3i(floori(dp.x + 0.5), floori(dp.y - 0.2 + 0.5), floori(dp.z + 0.5))
		var k: String = power.parts.get(under, "")
		if k == "conveyor":
			var d: Vector3i = Power.DIRS[power.facing_of(world.get_block(under.x, under.y, under.z))]
			dr["pos"] = dp + Vector3(d) * 2.2 * delta
		elif k == "collector" and dr["age"] > 0.3:
			var left = power.take_drop(under, dr["stack"])
			if left == null:
				drops._remove(dr)
			else:
				dr["stack"] = left
	_perf("machines", Time.get_ticks_usec() - t0)


# ---------------------------------------------------------------- farming and growing
var growing := {}                  # Vector3i -> true: saplings and crops that will grow
var _grow_timer := 0.0


func _is_hoe(item: int) -> bool:
	return Items.tools.has(item) and Items.tools[item]["kind"] == "hoe"


## Hoe grass or dirt into farmland, or plant seeds / a carrot on farmland. True if it did.
func _farm(pos: Vector3i, item: int) -> bool:
	var id := world.get_block(pos.x, pos.y, pos.z)
	var above := pos + Vector3i(0, 1, 0)
	var free := world.get_block(above.x, above.y, above.z) == 0
	if _is_hoe(item):
		if id in [1, 2] and free:
			edit(pos, Items.farmland)
			Sfx.play("dig_dirt")
			buzz(20)
			if not creative and inv.wear(selected):
				hud.flash(I18n.f("tool_broke", Items.name_of(item)))
			_refresh_mode()
		else:
			hud.flash(I18n.t("hoe_hint"))
		return true
	if Items.plant.has(item):
		if id == Items.farmland and free:
			if edit(above, int(Items.plant[item])):
				growing[above] = true
				Sfx.play("dig_soft")
				buzz(15)
				if not creative:
					inv.use_one(selected)
				_refresh_mode()
			return true
		if not Items.food.has(item):            # seeds are only for planting
			hud.flash(I18n.t("needs_farmland"))
			return true
	return false


## Every second: crops move to the next stage now and then, saplings become trees.
func _update_growing(delta: float) -> void:
	_grow_timer += delta
	if _grow_timer < 1.0:
		return
	_grow_timer = 0.0
	for p in growing.keys():
		if not world.is_loaded(p.x, p.z):
			continue
		var id := world.get_block(p.x, p.y, p.z)
		var d: Dictionary = Blocks.defs.get(id, {})
		if d.has("crop"):
			var nxt := int(d["crop"]["next"])
			if nxt == 0:
				growing.erase(p)                # ripe
			elif randf() < 1.0 / 45.0:          # about 45 s per stage
				edit(p, nxt)
		elif Items.sapling_trees.has(id):
			if randf() < 1.0 / 90.0:            # about a minute and a half
				if _grow_tree(p, Items.sapling_trees[id]):
					growing.erase(p)
		else:
			growing.erase(p)                    # broken or replaced


func _grow_tree(p: Vector3i, parts: Array) -> bool:
	var height := randi_range(4, 6)
	if p.y + height + 2 >= WorldData.H:
		return false
	for y in range(1, height + 1):
		if world.get_block(p.x, p.y + y, p.z) != 0:
			return false                        # no room yet; try again later
	var edits := {}
	for dx in range(-2, 3):
		for dz in range(-2, 3):
			for dy in range(height - 2, height + 2):
				var r := absi(dx) + absi(dz) + maxi(0, dy - height + 1) * 2
				if r <= 3 and not (absi(dx) == 2 and absi(dz) == 2):
					var q := p + Vector3i(dx, dy, dz)
					if world.get_block(q.x, q.y, q.z) == 0:
						edits[q] = int(parts[1])
	for y in height:
		edits[p + Vector3i(0, y, 0)] = int(parts[0])
	_rebuild(world.bulk_set(edits)[0])
	if player.position.distance_to(Vector3(p)) < 24:
		hud.flash(I18n.t("tree_grew"))
	return true


## A short vibration on phones (can be turned off in the settings).
func buzz(ms: int) -> void:
	if use_touch and bool(I18n.settings.get("vibrate", true)):
		Input.vibrate_handheld(ms)


func _facing() -> int:
	var f := player.forward()
	if absf(f.x) > absf(f.z):
		return 1 if f.x > 0 else 3
	return 0 if f.z > 0 else 2


func place_block() -> void:
	if health.dead:
		return
	var hit := target()
	var item := inv.item_at(selected)
	if not hit.is_empty() and use_block(hit["pos"]):
		return
	if not hit.is_empty() and _farm(hit["pos"], item):
		return
	if Items.food.has(item) and not creative:
		if health.eat(Items.food[item]):
			Sfx.play("eat")
			inv.use_one(selected)
			hud.flash(I18n.f("ate", Items.name_of(item)))
		else:
			hud.flash(I18n.t("not_hungry"))
		_refresh_mode()
		return
	if item == int(Items.S["BUCKET"]):
		var w := target(true)
		if not w.is_empty() and world.get_block(w["pos"].x, w["pos"].y, w["pos"].z) == WorldData.WATER:
			edit(w["pos"], 0, true, false)
			if not creative:
				inv.use_one(selected)
				if inv.add(int(Items.S["WATER_BUCKET"])) > 0:
					hud.flash(I18n.t("inventory_full"))
			_refresh_mode()
		return
	if hit.is_empty():
		return
	var pos: Vector3i = hit["pos"] + hit["normal"]
	if item == int(Items.S["WATER_BUCKET"]):
		if _replaceable(pos) and edit(pos, WorldData.WATER) and not creative:
			inv.slots[selected] = [int(Items.S["BUCKET"]), 1]
			_refresh_mode()
		return
	if not Items.placeable.has(item) or not _replaceable(pos) or _overlaps_player(pos, item):
		return
	var d: Dictionary = Blocks.defs[item]
	var below := world.get_block(pos.x, pos.y - 1, pos.z)
	if d["shape"] in ["cross", "torch"] and (below == 0 or not Blocks.solid[below]):
		return                                 # plants and torches need ground
	var id := item
	if d.get("logic") is Dictionary and d["logic"].has("facing"):
		# machines face away from you; pushers and breakers can also face up or down
		var f := _facing()
		var fy := player.forward().y
		var six := power.kind_of(item) in ["pusher", "breaker"]
		if six and fy > 0.75:
			f = 4
		elif six and fy < -0.75:
			f = 5
		id = item + f
	match d["shape"]:
		"stair":
			id = item + _facing()
		"ladder":
			var n: Vector3i = hit["normal"]
			var by_normal := {Vector2i(0, -1): 0, Vector2i(-1, 0): 1, Vector2i(0, 1): 2, Vector2i(1, 0): 3}
			id = 500 + by_normal.get(Vector2i(n.x, n.z), _facing())
		"door":
			var above := pos + Vector3i(0, 1, 0)
			if not _replaceable(above) or _overlaps_player(above, 512):
				return
			var axis := 0 if _facing() in [0, 2] else 1
			if edit(pos, item + axis * 4) and edit(above, item + 1 + axis * 4) and not creative:
				inv.use_one(selected)
			_refresh_mode()
			return
	if edit(pos, id):
		Sfx.play(Sfx.dig_sound(id) if Blocks.defs[id].get("shape") == "cross" else "place")
		InventoryScreen.note_recent(item)
		buzz(15)
		if Items.sapling_trees.has(id):
			growing[pos] = true                   # saplings grow into trees
		tutorial.report("place")
		if not creative:
			inv.use_one(selected)
			_refresh_mode()


func pick_block() -> void:
	var hit := target()
	if hit.is_empty():
		return
	var id := world.get_block(hit["pos"].x, hit["pos"].y, hit["pos"].z)
	var d: Dictionary = Blocks.defs.get(id, {})
	var item := id
	if d.has("door"):
		item = int(d["door"].get("base", 510))
	elif d.get("shape") == "ladder":
		item = 500
	elif d.get("shape") == "stair":
		item = id - int(d["facing"])
	if not Items.placeable.has(item):
		return
	for i in 9:
		if inv.item_at(i) == item:
			_select(i)
			return
	if creative:
		inv.slots[selected] = Items.new_stack(item, Items.max_stack(item))
	else:
		for i in inv.slots.size():
			if inv.item_at(i) == item:
				var t = inv.slots[selected]
				inv.slots[selected] = inv.slots[i]
				inv.slots[i] = t
				break
	_refresh_mode()


func _update_mining(delta: float) -> void:
	var held := _breaking() and not screen.visible and not health.dead
	var animal = looked_at_animal() if spawned else null
	if held and not _break_was_held and animal != null:
		attack(animal)
	_break_was_held = held
	var hit := target() if spawned and animal == null else {}
	highlight.visible = not hit.is_empty()
	if hit.is_empty():
		ghost.visible = false
		hud.show_target("")
		mine_pos = null
		crack.visible = false
		return
	var pos: Vector3i = hit["pos"]
	highlight.position = Vector3(pos)
	highlight.scale = Vector3.ONE * 1.004
	var id := world.get_block(pos.x, pos.y, pos.z)
	hud.show_target(Items.name_of(id))
	# ghost of the held block (with a crosshair; on touch the finger shows where it goes)
	var held_item := inv.item_at(selected)
	var ghost_pos: Vector3i = pos + hit["normal"]
	ghost.visible = Items.placeable.has(held_item) and not held_item in [WorldData.WATER] \
		and _replaceable(ghost_pos) and not _overlaps_player(ghost_pos, held_item)
	if ghost.visible:
		ghost.position = Vector3(ghost_pos)
	if held and (Blocks.hardness[id] >= 0 or creative):
		if creative:
			if mine_pos != pos:
				break_at(pos)                  # creative: instant, one block per press
				mine_pos = pos
			return
		if mine_pos != pos:
			mine_pos = pos
			mine_progress = 0.0
		mine_progress += delta / maxf(Items.mining(id, inv.item_at(selected))[0], 0.05)
		_dig_tick -= delta
		if _dig_tick <= 0:
			_dig_tick = 0.25
			Sfx.play(Sfx.dig_sound(id), -9.0, 0.9)
		if mine_progress >= 1.0:
			break_at(pos)
			mine_pos = null
			mine_progress = 0.0
	else:
		mine_pos = null
		mine_progress = 0.0
	crack.visible = not creative and mine_pos != null and mine_progress > 0
	if crack.visible:
		crack.position = Vector3(pos)
		crack.material_override.albedo_texture = crack_textures[mini(int(mine_progress * 6), 5)]


# ---------------------------------------------------------------- building tools
func build_action(name: String) -> void:
	if not creative:
		return
	var hit := target()
	var msg := ""
	var result := []
	var item := inv.item_at(selected)
	var fill_ok: bool = Items.placeable.has(item) and Blocks.defs[item]["shape"] != "door"
	match name:
		"corner1", "corner2":
			if hit.is_empty():
				return
			builder.set(name, hit["pos"])
			msg = I18n.f("corner_at", [name.right(1), hit["pos"]])
		"fill", "hollow":
			if not fill_ok:
				msg = I18n.t("hold_block")
			else:
				result = builder.fill(world, item, name == "hollow")
		"replace":
			if hit.is_empty() or not fill_ok:
				msg = I18n.t("hold_replace")
			else:
				result = builder.fill(world, item, false, world.get_block(hit["pos"].x, hit["pos"].y, hit["pos"].z))
		"clear":
			result = builder.fill(world, 0)
		"copy":
			msg = builder.copy(world)
		"paste":
			_previewing_paste = not builder.clipboard.is_empty()
			msg = I18n.t("paste_aim") if _previewing_paste else I18n.t("nothing_copied")
			if _previewing_paste and use_touch:
				_paste_armed = not _paste_armed
				if not _paste_armed:
					build_action("paste_now")
					return
		"paste_now":
			_previewing_paste = false
			_paste_armed = false
			if not hit.is_empty():
				result = builder.paste(world, hit["pos"] + hit["normal"], Input.is_physical_key_pressed(KEY_SHIFT))
		"rotate":
			msg = builder.rotate()
		"mirror":
			msg = builder.mirror()
		"undo":
			result = builder.undo(world)
		"deselect":
			builder.corner1 = null
			builder.corner2 = null
			msg = I18n.t("selection_cleared")
		"library":
			build_panel.visible = true
			build_panel.open_library()
			_update_touch_rects()
		_:
			if name.begins_with("loaded:"):
				msg = I18n.f("loaded_building" if use_touch else "loaded_building_desktop", name.substr(7))
	if not result.is_empty():
		_rebuild(result[0])
		msg = result[1]
	if msg != "":
		hud.flash(msg)


var _paste_armed := false
var _dig_tick := 0.0
var _step_distance := 0.0
var _was_swimming := false
var _last_step_pos = null
var _ready_frames := 0
var tutorial: Tutorial
var drops: Drops
var weather: Weather
var power: Power
var ghost: MeshInstance3D           # where the held block would go
var _tut_last = null              # [yaw, pitch, position] last frame, for the tutorial


func _update_footsteps() -> void:
	if not spawned:
		return
	var here := player.position
	if player.swimming and not _was_swimming and player.velocity.y < -1.0:
		Sfx.play("splash", -3.0)
	_was_swimming = player.swimming
	if _last_step_pos != null and player.is_on_floor() and not player.flying:
		_step_distance += Vector2(here.x - _last_step_pos.x, here.z - _last_step_pos.z).length()
		if _step_distance > 1.8:
			_step_distance = 0.0
			var below := world.get_block(floori(here.x + 0.5), floori(here.y - 0.5), floori(here.z + 0.5))
			Sfx.play(Sfx.dig_sound(below) if below != 0 else "step", -16.0, 1.15, 0.12)
	_last_step_pos = here


func _update_building() -> void:
	var b = builder.bounds() if creative else null
	selection_box.visible = b != null
	var parts := []
	if b != null:
		selection_box.position = (Vector3(b[0]) + Vector3(b[1])) / 2.0
		selection_box.scale = Vector3(b[1] - b[0]) + Vector3.ONE * 1.02
		var s = builder.size()
		parts.append(I18n.f("selection", [s.x, s.y, s.z, builder.volume()]))
	if creative and not builder.clipboard.is_empty():
		var c = builder.clipboard_size()
		parts.append(I18n.f("copy_size", [c.x, c.y, c.z]))
	hud.build_label.text = "   |   ".join(parts)
	var hit := target() if _previewing_paste and creative else {}
	paste_preview.visible = not hit.is_empty()
	if paste_preview.visible:
		var size: Vector3i = builder.clipboard_size()
		var origin: Vector3i = hit["pos"] + hit["normal"]
		paste_preview.position = Vector3(origin) + (Vector3(size) - Vector3.ONE) / 2.0
		paste_preview.scale = Vector3(size) + Vector3.ONE * 0.02


# ---------------------------------------------------------------- animals, health, sky
func _update_animals(delta: float) -> void:
	var monsters: bool = I18n.settings.get("monsters", true)
	var damage := wildlife.update(delta, player.position, daylight, monsters, not creative and not health.dead)
	if damage > 0 and not creative and not health.dead:
		health.damage(damage, "gloom")
		hud.hurt_flash()
		Sfx.play("hurt")
		hud.show_bars(health, creative)
		if health.dead:
			hud.show_death(health.cause)
			player.set_physics_process(false)
	var alive := {}
	for a in wildlife.animals:
		alive[a] = true
		if not animal_views.has(a):
			var v := AnimalView.new(a)
			add_child(v)
			animal_views[a] = v
		animal_views[a].sync(delta, daylight, world)
	for a in animal_views.keys():
		if not alive.has(a):
			animal_views[a].queue_free()
			animal_views.erase(a)


func _update_health(delta: float) -> void:
	if creative or health.dead or not spawned:
		_last_position = null
		hud.show_bars(health, creative)
		return
	var moved := 0.0
	if _last_position != null:
		moved = Vector2(player.position.x - _last_position.x, player.position.z - _last_position.z).length()
		if moved > 5:
			moved = 0.0
			health.fall_top = null
	_last_position = player.position
	var taken := health.tick(delta, moved, player.head_under_water())
	taken += health.track_fall(player.position.y, player.is_on_floor() or player.on_ladder, player.swimming)
	if taken > 0:
		hud.hurt_flash()
		Sfx.play("hurt")
	if health.dead:
		hud.show_death(health.cause)
		player.set_physics_process(false)
		if not use_touch:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_bars(health, creative)


func respawn() -> void:
	health.respawn()
	hud.death.visible = false
	player.position = spawn_point
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	_refresh_mode()


func _update_sky(delta: float) -> void:
	world.time_of_day = fposmod(world.time_of_day + delta * time_speed / DAY_LENGTH, 1.0)
	var angle := world.time_of_day * TAU
	var sun_height := sin(angle)
	var day := clampf((sun_height + 0.15) / 0.45, 0, 1)
	var dusk := clampf(1 - absf(sun_height) / 0.35, 0, 1)
	var sky_color := NIGHT_SKY.lerp(DAY_SKY, day).lerp(DUSK_SKY, dusk * 0.7 * maxf(day, 0.5))
	sky_color = weather.tint_sky(sky_color)
	env.background_color = sky_color
	env.fog_light_color = sky_color
	var reach_m := chunks.render_distance * 16.0
	env.fog_depth_begin = reach_m * 0.55
	env.fog_depth_end = reach_m * 0.95
	weather.update(delta, player.position, 0.16 + 0.84 * day)
	daylight = (0.16 + 0.84 * day) * (1.0 - weather.sky_dim())
	var tint := Vector3(0.65, 0.75, 1.0).lerp(Vector3.ONE, day).lerp(Vector3(1.0, 0.78, 0.6), dusk * 0.5)
	for m in materials.values():
		m.set_shader_parameter("daylight", daylight)
		m.set_shader_parameter("sky_tint", Color(tint.x, tint.y, tint.z))
	var dir := Vector3(cos(angle), sun_height, -0.3).normalized()
	sun.global_position = player.eye() + dir * 300
	moon.global_position = player.eye() - dir * 300
	var hours := fposmod(world.time_of_day * 24 + 6, 24)
	hud.clock.text = "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60)]


# ---------------------------------------------------------------- main loop
var _perf_ms := {}                  # system -> smoothed milliseconds per frame


func _perf(name: String, usec: int) -> void:
	_perf_ms[name] = lerpf(_perf_ms.get(name, 0.0), usec / 1000.0, 0.05)


func _process(delta: float) -> void:
	var tc := Time.get_ticks_usec()
	chunks.update_center(player.position)
	_perf("world", Time.get_ticks_usec() - tc)
	_perf("chunks", chunks.last_usec)
	hud.perf = _perf_ms
	if not spawned and chunks.is_ready_at(player.position):
		_ready_frames += 1
		if _ready_frames >= 3:                     # give the physics engine the new ground first
			spawned = true
			Boot.stage("playing")
			var args := Array(OS.get_cmdline_user_args())
			var testing := args.any(func(a): return a.begins_with("--shot") or a in ["--selftest", "--gloomtest", "--menutest", "--machines"])
			if "--tutorial" in args or (not testing and not I18n.settings.get("tutorial_done", false)):
				start_tutorial()
			player.set_physics_process(not screen.visible and not health.dead)
	touch.hotbar_rect = hud.hotbar_rect()
	if not screen.visible and not settings.visible:
		_read_controls()
	touch.show_button("up", creative and player.flying)
	touch.show_button("down", creative and player.flying)
	var t0 := Time.get_ticks_usec()
	_update_mining(delta)
	_update_footsteps()
	_update_building()
	var t1 := Time.get_ticks_usec()
	_update_sky(delta)
	var t2 := Time.get_ticks_usec()
	Wildlife.held_item = inv.item_at(selected)
	_update_animals(delta)
	var t3 := Time.get_ticks_usec()
	_update_health(delta)
	_perf("play", t1 - t0)
	_perf("sky", t2 - t1)
	_perf("mobs", t3 - t2)
	_update_tutorial()
	if spawned:
		_update_growing(delta)
		_update_machines(delta)
	var t4 := Time.get_ticks_usec()
	if spawned and hud.minimap.visible:
		hud.minimap.update_map(player.position, player.forward(), spawn_point)
	var t5 := Time.get_ticks_usec()
	_perf("map", t5 - t4)
	if spawned:
		var got := drops.update(delta, player.position, inv, 1.0)
		if not got.is_empty():
			Sfx.play("pop", -10.0, randf_range(1.1, 1.5))
			hud.show_hotbar(inv, selected, creative)
			if screen.visible:
				screen.refresh()
	if "--stress" in OS.get_cmdline_user_args() and spawned:
		# testing: fly fast in a straight line to stream many chunks through the worker threads
		player.flying = true
		player.position += Vector3(2.5, 0, 1.0)
		_st_frame += 1
		if _st_frame > 900:
			print("STRESS done at ", player.position, " chunks shown ", chunks.views.size(), " fps ", Engine.get_frames_per_second())
			get_tree().quit()
	if "--selftest" in OS.get_cmdline_user_args() and spawned:
		_selftest_step()
	if "--machines" in OS.get_cmdline_user_args() and spawned and not _st.has("machines"):
		# testing: a small machine demo in front of the player, for screenshots
		_st["machines"] = true
		var f := player.forward()
		var o := Vector3i(floori(player.position.x + f.x * 8 + 0.5), floori(player.position.y) + 1, floori(player.position.z + f.z * 8 + 0.5))
		for x in range(-4, 5):
			for z in range(-1, 4):
				for y in range(0, 4):
					edit(o + Vector3i(x, y, z), 0, true, false)
				edit(o + Vector3i(x, -1, z), 41, true, false)
		edit(o + Vector3i(-4, 0, 0), 1703)                    # switch on
		for x in range(-3, 0):
			edit(o + Vector3i(x, 0, 0), 1700)
		edit(o + Vector3i(0, 0, 0), 1708)                     # lamp
		edit(o + Vector3i(2, 0, 0), 1714)                     # and gate
		edit(o + Vector3i(4, 0, 0), 1705)                     # power cell
		edit(o + Vector3i(-4, 0, 2), 1731)                    # pusher
		edit(o + Vector3i(-2, 0, 2), 1736)                    # breaker
		for x in range(0, 4):
			edit(o + Vector3i(x, -1, 2), 1743)                # conveyor
		edit(o + Vector3i(4, -1, 2), 1746)                    # collector
		edit(o + Vector3i(2, 0, 3), 1747)                     # smelter
		edit(o + Vector3i(0, 0, 3), 1707)                     # light sensor
		edit(o + Vector3i(-1, 0, 3), 1706)                    # plate
		drops.spawn([25, 3], Vector3(o + Vector3i(0, 0, 2)))
		set_flying(true)
		player.position.y += 5
		player.look(Vector2(0, 0.55))
	if "--gloomtest" in OS.get_cmdline_user_args() and spawned and not _st.has("gloom"):
		# testing: night, and a gloom a few blocks in front of the player
		world.time_of_day = 0.75
		var f := player.forward()
		var p := player.position + Vector3(f.x, 0, f.z).normalized() * 6.0
		var g := Wildlife.Animal.new("gloom", Vector3(p.x, world.top_y(floori(p.x + 0.5), floori(p.z + 0.5)) + 0.5, p.z))
		wildlife.animals.append(g)
		_st["gloom"] = g
		_st["health0"] = health.health
	if _st.has("gloom") and _shot_frames == 1:
		print("GLOOM distance to player: ", snappedf(Vector2(_st["gloom"].pos.x - player.position.x, _st["gloom"].pos.z - player.position.z).length(), 0.1), ", player health ", _st["health0"], " -> ", health.health)
	if _shot_path != "" and spawned:
		_shot_frames -= 1
		if _shot_frames <= 0:
			get_viewport().get_texture().get_image().save_png(_shot_path)
			print("screenshot saved: ", _shot_path, " chunks: ", chunks.views.size())
			get_tree().quit()
	_autosave -= delta
	if _autosave <= 0:
		_autosave = AUTOSAVE_EVERY
		save_game()


func save_game() -> void:
	I18n.save_settings()
	if chest_pos != null and chest_inv != null:
		world.containers[chest_pos] = chest_inv.to_data()
	var data: Dictionary = world.player_data.duplicate()
	data["position"] = [player.position.x, player.position.y + 0.1, player.position.z]
	data["inventory"] = inv.to_data()
	data["survival"] = health.to_data()
	data["mode"] = "creative" if creative else "survival"
	data["hotbars"] = saved_hotbars
	data["weather"] = weather.save_data()
	data["growing"] = growing.keys().map(func(v): return [v.x, v.y, v.z])
	data["spawn"] = [spawn_point.x, spawn_point.y, spawn_point.z]
	world.save(SAVE_PATH, data)
	Session.touch(data["mode"])


func _notification(what: int) -> void:
	# phones can close a paused app at any time: save when we go to the background
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if world and player:
			save_game()


# ---------------------------------------------------------------- self test (-- --selftest --touch)
var _st_frame := 0
var _st := {}


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _st_shot(name: String) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			get_viewport().get_texture().get_image().save_png(a.substr(10) + "/" + name + ".png")


func _press(name: String, index: int, down: bool) -> void:
	var b: Panel = touch._buttons[name]
	_touch(index, b.position + b.size / 2, down)


## Drives the game with real touch events and prints what happened. Starts in survival.
func _selftest_step() -> void:
	_st_frame += 1
	var s := get_viewport().get_visible_rect().size
	match _st_frame:
		5:
			_st["start"] = player.position
			_touch(0, Vector2(200, s.y - 200), true)
			_drag(0, Vector2(200, s.y - 290), Vector2(0, -90))
		60:
			_touch(0, Vector2(200, s.y - 290), false)
			print("SELFTEST walked: ", snappedf(_st["start"].distance_to(player.position), 0.1), " blocks")
			health.damage(5, "test")
			health.hunger = 13
			hud.show_bars(health, creative)
			_st_shot("t1_survival_hud")
		70:
			player.look(Vector2(0, 0.9))                       # look down at the ground
			_st["ground"] = target()["pos"]
			_st["ground_id"] = world.get_block(_st["ground"].x, _st["ground"].y, _st["ground"].z)
			_touch(1, s / 2, true)                               # survival: hold a finger on the ground to dig
		400:
			_touch(1, s / 2, false)
			var g: Vector3i = _st["ground"]
			print("SELFTEST dug a block with a held finger: ", world.get_block(g.x, g.y, g.z) != _st["ground_id"], ", drops on the ground / picked up: ", drops.drops.size(), " / ", drops.picked_total)
			_select(5)                                           # the planks of the starter kit
			player.look(Vector2(0, -0.35))                       # aim a little ahead, not at our own feet
			_st["planks"] = inv.count(7)
			_touch(1, s / 2, true)                               # a short tap places the held block
		402:
			_touch(1, s / 2, false)
		404:
			print("SELFTEST tap placed a block: ", inv.count(7) == _st["planks"] - 1)
			# farming: hoe a dirt block, plant seeds, let it ripen, harvest
			var f := player.position + player.forward() * 3.0
			var fp := Vector3i(floori(f.x + 0.5), world.top_y(floori(f.x + 0.5), floori(f.z + 0.5)), floori(f.z + 0.5))
			edit(fp, 2, true)
			edit(fp + Vector3i(0, 1, 0), 0, true)
			_farm(fp, 217)
			var tilled := world.get_block(fp.x, fp.y, fp.z) == Items.farmland
			_farm(fp, 120)
			var crop_pos := fp + Vector3i(0, 1, 0)
			var planted := growing.has(crop_pos)
			for i in 3:
				edit(crop_pos, int(Blocks.defs[world.get_block(crop_pos.x, crop_pos.y, crop_pos.z)]["crop"]["next"]))
			var wheat_before := drops.drops.filter(func(d): return d["stack"][0] == 121).size()
			break_at(crop_pos)
			var wheat_after := drops.drops.filter(func(d): return d["stack"][0] == 121).size()
			print("SELFTEST farming: tilled ", tilled, ", planted ", planted, ", harvested wheat ", wheat_after > wheat_before)
			# a sapling grows into a tree
			var sp := fp + Vector3i(2, 0, 0)
			edit(sp, 2, true)
			for y in range(1, 9):
				edit(sp + Vector3i(0, y, 0), 0, true)
			edit(sp + Vector3i(0, 1, 0), 714)
			for i in 4:                                        # a little farm row and a door, for the screenshot
				for side in [-1, 1]:
					var q := fp + Vector3i(i - 1, 0, side)
					edit(q, Items.farmland, true)
					edit(q + Vector3i(0, 1, 0), (971 if side < 0 else 975) + i, true)
			var dp := fp + Vector3i(-2, 1, 0)
			edit(dp, 1524, true)
			edit(dp + Vector3i(0, 1, 0), 1525, true)
			print("SELFTEST sapling grew: ", _grow_tree(sp + Vector3i(0, 1, 0), Items.sapling_trees[714]), ", trunk: ", world.get_block(sp.x, sp.y + 2, sp.z) == 710)
		405:
			_st_shot("t7_farm")
			inv.add(4, 2)                                        # two logs to craft with
			_press("inventory", 2, true)
			_press("inventory", 2, false)
		410:
			print("SELFTEST inventory open: ", screen.visible, ", touch blocked: ", touch.blocked)
			var planks: Dictionary = Items.recipes[0]
			var before := inv.count(7)
			screen.recipe = planks
			screen._craft(planks, 1)
			screen.refresh()
			print("SELFTEST crafted planks: ", inv.count(7) == before + 4)
		411:
			_st_shot("t2_crafting")
			inv.add(25, 3)                                       # iron ore and coal for the furnace
			inv.add(102, 2)
			screen.open(inv, false, null, "furnace")
		412:
			_st_shot("t8_furnace")
			screen.closed.emit()
			open_settings()
		413:
			_st_shot("t5_settings")
			settings._open_log()
		414:
			_st_shot("t6_log")
			settings._log_panel.visible = false
			settings._panel.visible = true
			close_settings()
		415:
			print("SELFTEST inventory closed: ", not screen.visible)
			set_mode(true)
			_press("fly", 3, true)
			_press("fly", 3, false)
		420:
			_st["fly_y"] = player.position.y
			_press("up", 4, true)
		450:
			_press("up", 4, false)
			print("SELFTEST creative flying rose: ", snappedf(player.position.y - _st["fly_y"], 0.1), " blocks")
			_press("build", 5, true)
			_press("build", 5, false)
		452:
			open_screen()
		454:
			screen._tap_palette(int(screen._families["concrete"][0]), "concrete")   # open a colour family
			print("SELFTEST family opened: ", screen.expanded, ", slots shown: ", screen._grid.get_child_count())
		456:
			_st_shot("t3_creative_menu")
			screen.closed.emit()
		460:
			print("SELFTEST build panel open: ", build_panel.visible)
			var px := floori(player.position.x + 0.5)
			var pz := floori(player.position.z + 0.5)
			player.position.y = world.top_y(px, pz) + 3.0      # come back down near the ground
			player.look(Vector2(0, 0.5))
			var hit := target()
			if hit.is_empty():
				print("SELFTEST nothing to aim at for building")
				get_tree().quit()
				return
			builder.corner1 = hit["pos"] + Vector3i(-1, 1, -1)
			builder.corner2 = hit["pos"] + Vector3i(1, 3, 1)
			inv.slots[selected] = [41, 64]
			build_action("hollow")
			print("SELFTEST hollow box: ", hud.message.text)
		500:
			_st_shot("t4_build_panel")
		501:
			build_action("undo")
			print("SELFTEST undo: ", hud.message.text)
			save_game()
			var again := WorldData.load_from(SAVE_PATH)
			print("SELFTEST sounds played: ", Sfx.played)
			print("SELFTEST saved mode / inventory: ", again.player_data["mode"], " / ", again.player_data["inventory"].filter(func(x): return x != null).size(), " stacks")
			get_tree().quit()
