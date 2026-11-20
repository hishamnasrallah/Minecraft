class_name Main
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
const NIGHT_SKY := Color(0.07, 0.1, 0.22)          # moonlit navy, not black
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
var shown_light := 1.0              # brightness drawn on screen (brighter than `daylight` at night)
const NIGHT_LIGHT := 0.42

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
	var remote: Dictionary = Session.remote
	if not remote.is_empty():
		# a friend's world: the seed plus everything they built; the rest is generated here
		world = WorldData.new(int(remote["seed"]))
		world.changes = remote["changes"]
		world.containers = remote["containers"]
		world.time_of_day = float(remote["time"])
		world.player_data = {"mode": "creative" if remote.get("creative", false) else "survival",
			"position": remote["spawn"], "spawn": remote["spawn"]}
		Session.remote = {}
		_remote_world = true
	elif FileAccess.file_exists(SAVE_PATH) and fresh.is_empty():
		world = WorldData.load_from(SAVE_PATH)
	Minimap.memory = {}
	if remote.is_empty() and fresh.is_empty():
		Minimap.load_memory(SAVE_PATH.get_basename() + "_map.bin")   # the places you have seen
	if world == null and Session.dimension == "sky":
		# first visit to the sky realm: its own seed, derived from the world's
		var base := int(Session.carry.get("seed", fresh.get("seed", -1)))
		world = WorldData.new(base + 7777 if base >= 0 else -1, "sky")
		world.player_data["base_seed"] = base
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
	var carry: Dictionary = Session.carry
	if not carry.is_empty():
		# through a portal: you bring your things, health and mode with you
		inv = Inventory.from_data(carry["inventory"])
		creative = carry["mode"] == "creative"
	elif not pd.has("inventory"):
		_fill_starter(creative)
	health = Survival.from_data(carry.get("survival", pd.get("survival")))
	saved_hotbars = carry.get("hotbars", pd.get("hotbars", []))
	Session.carry = {}
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
	chunks.setup(world, materials, 2 if Boot.safe_mode else (distance if distance > 0 else default_view_distance()))
	add_child(chunks)
	wildlife = Wildlife.new(world)
	wildlife.load_pets(world.player_data.get("pets", []))

	Boot.stage("player")
	player = Player.new()
	player.world = world
	var start = pd.get("position")
	player.position = Vector3(start[0], start[1], start[2]) if start is Array else spawn_point
	player.set_physics_process(false)          # wait until the ground under us exists
	add_child(player)
	player.look(-_initial_look)

	debris = Debris.new()
	add_child(debris)
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
	remote_players = RemotePlayers.new()
	remote_players.icon_for = hud.icon_for
	add_child(remote_players)
	if world.dimension == "sky":
		weather.set_weather("clear")
		if not world.player_data.get("boss_dead", false):
			_spawn_boss()
	Net.remote_edits.connect(_apply_remote_edits)
	Net.remote_container.connect(func(p, data): world.containers[p] = data)
	Net.player_state.connect(func(id, st): remote_players.update_state(id, st))
	Net.player_left.connect(func(id): remote_players.remove(id); hud.flash(I18n.f("player_left", Net.names.get(id, "?"))))
	Net.player_joined.connect(func(_id, name): hud.flash(I18n.f("player_joined", name)))
	Net.clock.connect(func(t, w):
		world.time_of_day = t
		if weather.kind != w:
			weather.set_weather(w))
	Net.failed.connect(func(reason):
		if _remote_world:
			hud.flash(I18n.t("net_" + reason)))
	Net.animals.connect(func(data): wildlife.apply_snapshot(data))
	Net.animal_drop.connect(func(st): drops.spawn(st, player.position + Vector3(0, 1.0, 0), Vector3.ZERO, 0.0))
	Net.hurt.connect(func(dmg): _take_damage(dmg))
	Net.animal_hit.connect(_on_friend_hit_animal)
	Net.chat_message.connect(func(name, text): hud.chat(name, text); Sfx.play("pop", -10.0, 1.4))
	Net.failed.connect(func(reason):
		if reason == "host_left" and _remote_world:
			await get_tree().create_timer(3.0).timeout
			get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	Net.get_world_data = func() -> Dictionary:
		return {"seed": world.seed, "changes": world.changes, "containers": world.containers,
			"time": world.time_of_day, "weather": weather.kind, "creative": creative,
			"spawn": [player.position.x + 3.0, player.position.y + 0.5, player.position.z]}   # next to the host
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
	world.on_edit = func(p: Vector3i, id: int) -> void:
		power.note(p, id)
		if Net.active() and not _applying_remote:
			Net.send_edit(p, id)
		if Blocks.defs.get(id, {}).has("crop") or Items.sapling_trees.has(id):
			growing[p] = true                      # also crops and saplings from pasted buildings
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
	touch.map_tapped.connect(open_map)
	touch.mine_toggled.connect(func(on): hud.flash(I18n.t("mode_break" if on else "mode_build")))
	hud.big_map.gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close_map())
	touch.menu_pressed.connect(func(): save_game(); hud.flash(I18n.t("saved")))
	touch.inventory_pressed.connect(open_screen)
	touch.fly_pressed.connect(func(): set_flying(not player.flying))
	touch.build_pressed.connect(toggle_build_panel)
	touch.settings_pressed.connect(open_settings)
	touch.chat_pressed.connect(open_chat)
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
	chat_box = ChatBox.new()
	chat_box.closed.connect(func():
		touch.blocked = false
		if not use_touch:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	top.add_child(chat_box)
	settings = SettingsScreen.new()
	settings.in_game = true
	settings.visible = false
	settings.exit_pressed.connect(func(): save_game(); Net.stop(); get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	settings.host_pressed.connect(_host_game)
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
	touch.show_button("chat", Net.active())
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
const STARTER_KIT := [[201, 1], [203, 1], [209, 1], [105, 6], [50, 8], [7, 16], [46, 1], [48, 1], [213, 1]]   # ends with a wooden sword for the first night


## A new world's first items: building blocks in creative, a small kit in survival.
func _fill_starter(is_creative: bool) -> void:
	for st in (CREATIVE_HOTBAR.map(func(i): return [i, Items.max_stack(i)]) if is_creative else STARTER_KIT):
		inv.add(st[0], st[1])


func _hotbar_empty() -> bool:
	for i in 9:
		if inv.slots[i] != null:
			return false
	return true


## How far to see when the player never chose: more on devices with plenty of memory
## (every chunk column is 320 blocks high).
static func default_view_distance() -> int:
	var mem: Dictionary = OS.get_memory_info()
	var gb := float(mem.get("physical", 0)) / 1073741824.0
	if not OS.has_feature("mobile"):
		return 6
	if gb < 0.5:
		return 5                                  # the phone did not say: assume a decent one
	# phones report a little less than the box says (an "8 GB" tablet shows ~7.3)
	return 6 if gb >= 7.0 else (5 if gb >= 5.2 else (4 if gb >= 3.4 else 3))


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


var _tut_was_visible := false


func open_map() -> void:
	if health.dead or screen.visible or settings.visible:
		return
	hud.open_big_map(world)
	touch.visible = false                         # the map covers the screen; no buttons on top
	_tut_was_visible = tutorial.visible
	tutorial.visible = false
	touch.blocked = true
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_map() -> void:
	hud.close_big_map()
	tutorial.visible = _tut_was_visible
	touch.visible = use_touch
	touch.blocked = false
	if not use_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_chat() -> void:
	if not Net.active():
		return
	chat_box.open()
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
		Net.send_container(chest_pos, world.containers[chest_pos])
		chest_pos = null
	player.set_physics_process(spawned and not health.dead)
	touch.blocked = false
	_refresh_mode()


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if hud.big_map.visible:
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_M, KEY_ESCAPE]:
			close_map()
		return
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
				_place_timer = PLACE_EVERY * 1.5       # a click places once; holding repeats after a moment
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
			KEY_ENTER:
				open_chat()
			KEY_E:
				open_screen()
			KEY_M:
				open_map()
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
	if touch != null and touch.mine_mode:
		touch.set_mine_mode(false)                # picked something to hold: back to building
		hud.flash(I18n.t("mode_build"))
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


var _load_t0 := Time.get_ticks_msec()     # when this world started loading (for the log)
var _forced_hit := {}                # testing: pretend the crosshair is on this face


func target(hit_water := false) -> Dictionary:
	if not _forced_hit.is_empty():
		return _forced_hit
	return world.raycast(player.eye(), aim_dir(), reach(), hit_water)


## A tap anywhere on the view (touch) acts on the block under the crosshair: use doors /
## chests / beds, place the held block, eat,
## or else hit what is there (instant in creative and for soft blocks like flowers).
func tap_world(pos: Vector2) -> void:
	if "--walkplace" in OS.get_cmdline_user_args():
		var th := target()
		print("TAP at ", pos, " item ", inv.item_at(selected), " target ", th.get("pos"), " normal ", th.get("normal"),
			" block ", world.get_block(th["pos"].x, th["pos"].y, th["pos"].z) if not th.is_empty() else -1, " player ", player.position)
	if health.dead or not spawned:
		return
	if _boss_in_sight():
		_hit_boss()
		return
	var animal = looked_at_animal()        # the crosshair decides, not where the finger tapped
	var item := inv.item_at(selected)
	var hit := target()
	if animal != null:
		attack(animal)
	elif touch.mine_mode:
		if not hit.is_empty():
			var mid := world.get_block(hit["pos"].x, hit["pos"].y, hit["pos"].z)
			if creative or Blocks.hardness[mid] == 0:
				break_at(hit["pos"])
			else:
				hud.flash(I18n.t("hold_to_break"))
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
	# light can change up to 15 blocks away: re-mesh the sections within 16 rows
	_rebuild(keys, maxi(pos.y - 16, 0), mini(pos.y + 16, WorldData.H - 1))
	return not keys.is_empty()


## Rows: the height range that changed (default: anything, e.g. building tools).
func _rebuild(keys: Array, y_lo := -1, y_hi := -1) -> void:
	# the chunks the edit touched show it at once; the ring around them only needs its light
	# touched up, so it waits for a free moment (fast building merges into one redraw)
	var ring := {}
	for k in keys:
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var r := Vector2i(k.x + dx, k.y + dz)
				if not r in keys:
					ring[r] = true
	chunks.rebuild(keys, y_lo, y_hi)
	chunks.rebuild(ring.keys(), y_lo, y_hi, false)


func break_at(pos: Vector3i) -> void:
	var id := world.get_block(pos.x, pos.y, pos.z)
	if id == 0 or id == WorldData.WATER or (Blocks.hardness[id] < 0 and not creative):
		return
	if Blocks.hardness[id] < 0:
		edit(pos, 0, true)
		return
	Sfx.play(Sfx.dig_sound(id))
	debris.burst(Vector3(pos), id, clampf(shown_light + 0.2, 0.3, 1.0))
	buzz(30)
	tutorial.report("break")
	var tool := inv.item_at(selected)
	var m := Items.mining(id, tool)
	var contents = world.containers.get(pos)
	world.containers.erase(pos)
	var on_top := []                          # what stands on it: the world removes it with the block
	var ay := pos.y + 1
	while true:
		var a := world.get_block(pos.x, ay, pos.z)
		if not (Blocks.plants_need_soil.has(a) or a in [50, 60]):
			break
		on_top.append([Vector3i(pos.x, ay, pos.z), a])
		ay += 1
	if not edit(pos, 0):
		return
	_drop_attached(pos)
	if not creative:
		for t in on_top:
			if world.get_block(t[0].x, t[0].y, t[0].z) == 0:
				var dr := Items.drop_for(t[1])
				if dr != 0:
					drops.spawn([dr, 1], Vector3(t[0]))
	if creative:
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


const WALL_TORCH := 1810


func _solid_at(p: Vector3i) -> bool:
	var b := world.get_block(p.x, p.y, p.z)
	return b != 0 and Blocks.solid[b] == 1 and Blocks.defs[b].get("shape", "cube") == "cube"


## A block was broken: what stood on it (plants, torches) or hung on it (wall torches, ladders)
## falls off and drops as an item, instead of floating in the air.
func _drop_attached(pos: Vector3i) -> void:
	var cells := [[pos + Vector3i(0, 1, 0), -1]]
	for f in 4:
		var v: Vector2i = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][f]
		cells.append([pos - Vector3i(v.x, 0, v.y), f])          # hangs on `pos` when it faces it
	for c in cells:
		var p: Vector3i = c[0]
		var id := world.get_block(p.x, p.y, p.z)
		if id == 0 or id == WorldData.WATER:
			continue
		var d: Dictionary = Blocks.defs[id]
		var shape: String = d.get("shape", "cube")
		var falls := false
		if c[1] == -1:
			falls = (shape == "cross" and not d.has("door")) or (shape == "torch" and id < WALL_TORCH)
		else:
			var hangs := shape == "ladder" or (shape == "torch" and id >= WALL_TORCH)
			falls = hangs and int(d.get("facing", -1)) == c[1]
		if not falls or not edit(p, 0):
			continue
		if not creative:
			var drop := Items.drop_for(id)
			if drop != 0:
				drops.spawn([drop, 1], Vector3(p))
		if c[1] == -1:
			_drop_attached(p)                         # a tall stack of reeds comes down whole


func attack(animal) -> void:
	var item := inv.item_at(selected)
	var feeding: bool = animal.wants_food(item)
	if animal.tame and not feeding and Items.attack_damage(item) <= 1:
		var call := str(animal.spec.get("call", ""))
		Sfx.play(call if call != "" else "pop", -3.0, 1.15)          # a pat: it answers, unhurt
		return
	if _remote_world:
		# the host owns the animals: it applies the hit and sends back what dropped
		Net.hit_animal(animal.uid, Items.attack_damage(item) if not creative else 100, item, player.position)
		animal.hurt_time = 0.25
		if feeding:
			if not creative:
				inv.use_one(selected)
				_refresh_mode()
			Sfx.play("eat", -6.0)
			return
		Sfx.play("hurt", -4.0, 1.7)
		if not creative:
			health.exert(float(Items.survival["ATTACK"]))
			if Items.tools.has(item) and inv.wear(selected):
				hud.flash(I18n.f("tool_broke", Items.name_of(item)))
		return
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
	# the player's real box (0.6 wide, 1.8 tall, from the feet) against the block's cell
	var pp := player.position
	var e := 0.02                                  # touching is fine, overlapping is not
	return absf(pp.x - p.x) < 0.8 - e and absf(pp.z - p.z) < 0.8 - e \
		and pp.y < p.y + 0.5 - e and pp.y + 1.8 > p.y - 0.5 + e


func _usable(id: int) -> bool:
	var d: Dictionary = Blocks.defs.get(id, {})
	return d.has("door") or d.get("container", false) or id == 62 or id == 47 or power.kind_of(id) in ["switch", "button"]


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
		Sfx.play("dig_wood", -3.0, 0.8 if d["door"]["open"] else 1.15)   # creak shut / swing open
		buzz(12)
		return true
	if d.get("container", false):
		Sfx.play("click", -4.0, 0.7)
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


# ---------------------------------------------------------------- the sky realm: portals and the boss
## The sky key on a frame of amethyst blocks: the empty space it encloses (up to 8 x 8, in an
## upright plane) fills with portal.
func _open_portal(hit_pos: Vector3i) -> void:
	if world.get_block(hit_pos.x, hit_pos.y, hit_pos.z) != WorldData.SKY["FRAME"]:
		hud.flash(I18n.t("portal_needs_frame"))
		return
	for plane in [Vector3i(1, 0, 0), Vector3i(0, 0, 1)]:
		var starts := []                         # any empty cell near the tapped frame block
		for a in range(-2, 3):
			for b in range(-2, 3):
				starts.append(hit_pos + plane * a + Vector3i(0, b, 0))
		for start in starts:
			if world.get_block(start.x, start.y, start.z) != 0:
				continue
			var inside := {start: true}
			var queue := [start]
			var ok := true
			while not queue.is_empty() and ok:
				var c: Vector3i = queue.pop_back()
				for d in [plane, -plane, Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
					var n: Vector3i = c + d
					if inside.has(n):
						continue
					var b := world.get_block(n.x, n.y, n.z)
					if b == WorldData.SKY["FRAME"]:
						continue
					if b != 0 or inside.size() >= 36:
						ok = false                   # not closed by amethyst, or too big
						break
					inside[n] = true
					queue.append(n)
			if ok and inside.size() >= 2:
				var edits := {}
				for c in inside:
					edits[c] = WorldData.SKY["PORTAL"]
				_rebuild(world.bulk_set(edits)[0])
				Sfx.play("pop", 0.0, 0.6)
				hud.flash(I18n.t("portal_opened"))
				if not creative:
					inv.use_one(selected)
					_refresh_mode()
				return
	hud.flash(I18n.t("portal_needs_frame"))


## Standing in a portal for a moment takes you to the other world.
func _update_portal(delta: float) -> void:
	var p := player.position
	var inside := false
	for dy in [0.6, 1.4]:
		var b := world.get_block(floori(p.x + 0.5), floori(p.y + dy), floori(p.z + 0.5))
		if b == WorldData.SKY["PORTAL"]:
			inside = true
	if not inside:
		_portal_lock = false
		_portal_time = 0.0
		hud.portal_glow(0.0)
		return
	if _portal_lock:
		return
	_portal_time += delta
	hud.portal_glow(_portal_time / 1.4)
	if _portal_time >= 1.4:
		_travel()


func _travel() -> void:
	if Net.active():
		hud.flash(I18n.t("portal_with_friends"))
		_portal_lock = true
		return
	save_game()
	var base := world.seed if world.dimension != "sky" else int(world.player_data.get("base_seed", -1))
	Session.carry = {"inventory": inv.to_data(), "survival": health.to_data(), "hotbars": saved_hotbars,
		"mode": "creative" if creative else "survival", "seed": base}
	Session.set_dimension("" if world.dimension == "sky" else "sky")
	get_tree().reload_current_scene()


func _spawn_boss() -> void:
	boss = StormRay.new()
	boss.world = world
	boss.center = Vector3(0, WorldData.SKY_BASE + 20, 0)
	for pc in WorldData.PILLARS:
		boss.crystals.append(Vector3i(pc.x, WorldData.SKY_BASE + 6 + WorldData.PILLAR_HEIGHT + 1, pc.y))
	boss.hurt_player.connect(func(dmg, push):
		_take_damage(dmg, "storm")
		player.velocity += push)
	boss.died.connect(_boss_died)
	add_child(boss)


func _boss_in_sight() -> bool:
	if boss == null or boss.dead or not spawned:
		return false
	var d := boss.ray_hit(player.eye(), aim_dir(), reach() + 4.0)
	if d < 0:
		return false
	var hit := target()
	return hit.is_empty() or d < hit["distance"] + 0.5


func _hit_boss() -> void:
	var item := inv.item_at(selected)
	boss.hit(Items.attack_damage(item) * (10 if creative else 1))
	buzz(25)
	if not creative and Items.tools.has(item) and inv.wear(selected):
		hud.flash(I18n.f("tool_broke", Items.name_of(item)))


func _boss_died(_at: Vector3) -> void:
	world.player_data["boss_dead"] = true
	hud.hide_boss()
	hud.flash(I18n.t("boss_defeated"))
	Sfx.play("pop", 4.0, 0.4)
	# the prize: the storm core and star shards rain down next to you, a trophy in the middle
	drops.spawn([132, 1], player.position + Vector3(0, 2, 0), Vector3(0, 2, 0), 0.3)
	for i in 4:
		drops.spawn([130, 4], player.position + Vector3(randf_range(-1, 1), 2, randf_range(-1, 1)))
	edit(Vector3i(0, WorldData.SKY_BASE + 7, 0), 1808, true, false)
	save_game()


# ---------------------------------------------------------------- playing with friends
func _host_game() -> void:
	var problem := Net.host(str(Session.world_dir.get_file()) if Session.world_dir != "" else "BlockWorld")
	if problem != "":
		hud.flash(I18n.t("net_" + problem))
		return
	Net.world_name = _world_title()
	hud.flash(I18n.f("hosting", ", ".join(Net.local_ips())))
	close_settings()
	_refresh_mode()                                 # shows the chat button


func _world_title() -> String:
	for w in Session.list_worlds():
		if Session.world_dir.ends_with("/" + str(w["id"])):
			return str(w.get("name", w["id"]))
	return "BlockWorld"


var _animals_timer := 0.0
var _chests_timer := 0.0


func _update_net(delta: float) -> void:
	hud.minimap.others = remote_players.positions()
	if not Net.active():
		return
	_net_timer -= delta
	if _net_timer <= 0.0:
		_net_timer = 0.1
		Net.send_state(player.position, player.yaw, player.pitch, inv.item_at(selected), not creative and not health.dead)
	if Net.is_host():
		_clock_timer -= delta
		if _clock_timer <= 0.0:
			_clock_timer = 2.0
			Net.send_clock(world.time_of_day, weather.kind)
		_animals_timer -= delta
		if _animals_timer <= 0.0:
			_animals_timer = 0.15                       # about 7 times a second, smoothed on arrival
			Net.send_animals(wildlife.snapshot())
		_chests_timer -= delta
		if _chests_timer <= 0.0 and not power.changed_containers.is_empty():
			_chests_timer = 0.5
			for p in power.changed_containers:
				Net.send_container(p, world.containers.get(p))
			power.changed_containers.clear()


## Host: a friend hit or fed one of our animals.
func _on_friend_hit_animal(from_id: int, uid: int, damage: int, held: int, from: Vector3) -> void:
	var a = wildlife.by_uid(uid)
	if a == null:
		return
	var mine := Wildlife.held_item
	Wildlife.held_item = held
	var drop: Array = a.hit(from, damage)
	Wildlife.held_item = mine
	a.fed = false                                       # the friend paid for the food, not us
	if not drop.is_empty():
		Net.send_drop(from_id, drop)


var _net_edits_in := 0


func _apply_remote_edits(edits: Dictionary) -> void:
	_net_edits_in += edits.size()
	_applying_remote = true
	var keys := {}
	var lo := WorldData.H
	var hi := 0
	for p in edits:
		var id: int = edits[p]
		if world.is_loaded(p.x, p.z):
			for k in world.set_block(p.x, p.y, p.z, id, true, false):
				keys[k] = true
			lo = mini(lo, p.y)
			hi = maxi(hi, p.y)
		else:
			# not loaded here yet: it is applied when this chunk is generated
			var k := WorldData.chunk_key(p.x, p.z)
			var d: Dictionary = world.changes.get(k, {})
			d[p] = id
			world.changes[k] = d
			power.note(p, id)
	_applying_remote = false
	if not keys.is_empty():
		_rebuild(keys.keys(), maxi(lo - 16, 0), mini(hi + 16, WorldData.H - 1))
	# hear your friends dig and build (a few sounds at most, quieter further away)
	var sounds := 0
	for p in edits:
		var d := player.position.distance_to(Vector3(p))
		if d < 24.0 and sounds < 2 and not power.parts.has(p):
			var id: int = edits[p]
			Sfx.play("place" if id != 0 else "dig_stone", -6.0 - d * 0.8)
			sounds += 1


# ---------------------------------------------------------------- pasting big buildings
var _paste_batches := []            # [chunk key, {pos: id}] still to build, nearest first
var _paste_total := 0
var _paste_done := 0
var _paste_prev := {}               # what was there before (one undo step for the whole paste)
var _clip_from_library := false     # library buildings replace the ground they stand in
var _paste_box := AABB()            # where the building goes: the player is moved out of it
const PASTE_PER_FRAME := 3000


## Big buildings go in a few thousand blocks per frame (no freeze), chunk by chunk; parts
## that fall in chunks not loaded yet are generated first, one chunk per frame.
func _start_paste(origin: Vector3i, include_air: bool) -> void:
	var by_chunk := {}
	for p in builder.clipboard:
		var id: int = builder.clipboard[p]
		if id == 0 and not include_air:
			continue
		var q: Vector3i = origin + p
		if q.y < 1 or q.y >= WorldData.H:
			continue
		var k := WorldData.chunk_key(q.x, q.z)
		if not by_chunk.has(k):
			by_chunk[k] = {}
		by_chunk[k][q] = id
	var me := WorldData.chunk_key(floori(player.position.x + 0.5), floori(player.position.z + 0.5))
	var keys: Array = by_chunk.keys()
	keys.sort_custom(func(a, b): return (a - me).length_squared() < (b - me).length_squared())
	_paste_batches = keys.map(func(k): return [k, by_chunk[k]])
	var size: Vector3i = builder.clipboard_size()
	_paste_box = AABB(Vector3(origin) - Vector3(0.5, 0.5, 0.5), Vector3(size))
	_paste_total = 0
	for k in keys:
		_paste_total += by_chunk[k].size()
	_paste_done = 0
	_paste_prev = {}


## After pasting a building on top of the player: move them just outside its nearest side,
## onto the ground there, instead of leaving them stuck in the walls.
func _step_out_of(box: AABB) -> void:
	var p := player.position
	# blocks are centred on whole numbers: the cell the feet are in is y + 0.5 (+ a little)
	var feet := Vector3i(floori(p.x + 0.5), floori(p.y + 0.6), floori(p.z + 0.5))
	var stuck := false
	for dy in [0, 1]:
		var b := world.get_block(feet.x, feet.y + dy, feet.z)
		if b != 0 and Blocks.solid[b] == 1:
			stuck = true
	if not stuck:
		return                                       # in free space (even inside a room): fine
	# the nearest side of the building, a step beyond it
	var lo := box.position
	var hi := box.end
	var options := [Vector3(lo.x - 1.0, 0, p.z), Vector3(hi.x + 1.0, 0, p.z), Vector3(p.x, 0, lo.z - 1.0), Vector3(p.x, 0, hi.z + 1.0)]
	options.sort_custom(func(a, b): return Vector2(a.x - p.x, a.z - p.z).length() < Vector2(b.x - p.x, b.z - p.z).length())
	var to: Vector3 = options[0]
	var cx := floori(to.x + 0.5)
	var cz := floori(to.z + 0.5)
	if world.is_loaded(cx, cz):
		player.position = Vector3(to.x, world.top_y(cx, cz) + 0.6, to.z)
		player.velocity = Vector3.ZERO
		hud.flash(I18n.t("moved_out"))


func _update_paste() -> void:
	if _paste_batches.is_empty():
		return
	var budget := PASTE_PER_FRAME
	while budget > 0 and not _paste_batches.is_empty():
		var key: Vector2i = _paste_batches[0][0]
		if not world.chunks.has(key):
			world.ensure_chunk(key)                 # one new chunk is this frame's work
			return
		var batch: Dictionary = _paste_batches.pop_front()[1]
		var r := world.bulk_set(batch)
		for p in r[1]:
			if not _paste_prev.has(p):
				_paste_prev[p] = r[1][p]
		var lo := WorldData.H
		var hi := 0
		for p in batch:
			lo = mini(lo, p.y)
			hi = maxi(hi, p.y)
		_rebuild(r[0], maxi(lo - 16, 0), mini(hi + 16, WorldData.H - 1))
		_paste_done += batch.size()
		budget -= batch.size()
	if _paste_batches.is_empty():
		_step_out_of(_paste_box)
		builder.undo_stack.append(_paste_prev)
		if builder.undo_stack.size() > Builder.UNDO_STEPS:
			builder.undo_stack.pop_front()
		hud.flash(I18n.f("pasted", _paste_prev.size()))
		_paste_prev = {}
	else:
		hud.flash(I18n.f("pasting", int(100.0 * _paste_done / maxf(_paste_total, 1))))


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
	power.set_inputs(pressed, world.time_of_day < 0.5)
	if not _remote_world:
		power.update(delta)                         # with friends, the host runs the machines
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


func place_block(allow_use := true) -> void:
	if health.dead:
		return
	var hit := target()
	var item := inv.item_at(selected)
	if allow_use and not hit.is_empty() and use_block(hit["pos"]):
		return
	if not hit.is_empty() and _farm(hit["pos"], item):
		return
	if item == 131 and not hit.is_empty():
		_open_portal(hit["pos"])
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
	var id := item
	var n0: Vector3i = hit["normal"]
	if d["shape"] == "torch" and n0.y == 0 and _solid_at(pos - n0):
		# tapped the side of a block: the torch hangs on that wall
		var by_n := {Vector2i(0, -1): 0, Vector2i(-1, 0): 1, Vector2i(0, 1): 2, Vector2i(1, 0): 3}
		id = WALL_TORCH + int(by_n[Vector2i(n0.x, n0.z)])
	elif d["shape"] in ["cross", "torch"] and (below == 0 or not Blocks.solid[below]):
		return                                 # plants and torches need ground
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
			var f := _ladder_facing(hit["pos"], hit["normal"], pos)
			if f < 0:
				return                                # a ladder needs a wall behind it
			id = 500 + f
		"door":
			var above := pos + Vector3i(0, 1, 0)
			if not _replaceable(above) or _overlaps_player(above, 512) or not _solid_at(pos - Vector3i(0, 1, 0)):
				return                                # a door stands on a solid block
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


const FACE_VECS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]


## Which way a ladder placed at `at` hangs (the wall it leans on), or -1 if there is no wall.
## Tapping the side of a block hangs it there; tapping the top or bottom of a ladder extends
## it; otherwise it goes on the wall in front of you.
func _ladder_facing(on: Vector3i, n: Vector3i, at: Vector3i) -> int:
	if n.y == 0:
		var f: int = FACE_VECS.find(Vector2i(-n.x, -n.z))
		return f if _solid_at(at - n) else -1
	var below: Dictionary = Blocks.defs.get(world.get_block(on.x, on.y, on.z), {})
	if below.get("shape", "") == "ladder":
		var f2 := int(below.get("facing", 0))
		var v: Vector2i = FACE_VECS[f2]
		return f2 if _solid_at(at + Vector3i(v.x, 0, v.y)) else -1
	var f3 := _facing()
	var w: Vector2i = FACE_VECS[f3]
	return f3 if _solid_at(at + Vector3i(w.x, 0, w.y)) else -1


## The outline around the block you aim at: hugs thin things (torches, plants, slabs).
func _outline_box(id: int) -> Array:
	var d: Dictionary = Blocks.defs.get(id, {})
	match d.get("shape", "cube"):
		"torch":
			if id >= WALL_TORCH:
				var v: Vector2i = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][int(d.get("facing", 0))]
				return [Vector3(0.2, 0.78, 0.2), Vector3(v.x, 0, v.y) * 0.34 + Vector3(0, 0.09, 0)]
			return [Vector3(0.2, 0.84, 0.2), Vector3(0, -0.08, 0)]
		"cross":
			return [Vector3(0.8, 0.85, 0.8), Vector3(0, -0.075, 0)]
		"slab":
			return [Vector3(1, 0.5, 1), Vector3(0, -0.25, 0)]
		"carpet":
			return [Vector3(1, 0.08, 1), Vector3(0, -0.46, 0)]
	return [Vector3.ONE, Vector3.ZERO]


## The preview of what the held item would become: [size, offset], or [] when it cannot go there.
func _ghost_box(item: int, at: Vector3i, n: Vector3i) -> Array:
	var shape: String = Blocks.defs[item].get("shape", "cube")
	var below := world.get_block(at.x, at.y - 1, at.z)
	var ground := below != 0 and Blocks.solid[below] == 1
	match shape:
		"torch":
			if n.y == 0 and _solid_at(at - n):
				return [Vector3(0.16, 0.75, 0.16), Vector3(-n) * 0.34 + Vector3(0, 0.09, 0)]
			return [Vector3(0.16, 0.8, 0.16), Vector3(0, -0.1, 0)] if ground else []
		"cross":
			return [Vector3(0.7, 0.8, 0.7), Vector3(0, -0.1, 0)] if ground else []
		"slab":
			return [Vector3(1, 0.5, 1), Vector3(0, -0.25, 0)]
		"carpet":
			return [Vector3(1, 0.07, 1), Vector3(0, -0.46, 0)]
		"door":
			return [Vector3(1, 2, 1), Vector3(0, 0.5, 0)] if _solid_at(at - Vector3i(0, 1, 0)) else []
		"ladder":
			var hit := target()
			var f := _ladder_facing(hit["pos"], hit["normal"], at) if not hit.is_empty() else -1
			if f < 0:
				return []
			var v: Vector2i = FACE_VECS[f]
			return [Vector3(1 - absf(v.x) * 0.88, 1, 1 - absf(v.y) * 0.88), Vector3(v.x, 0, v.y) * 0.44]
	return [Vector3.ONE, Vector3.ZERO]


## Testing: place what is in hand as if tapping face `n` of block `on`.
func _place_on(on: Vector3i, n: Vector3i) -> void:
	_forced_hit = {"pos": on, "normal": n, "distance": 2.0}
	place_block(false)
	_forced_hit = {}


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
	elif id >= WALL_TORCH and id < WALL_TORCH + 4:
		item = 50
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


var _place_timer := 0.0
var _hold_used := false
const PLACE_EVERY := 0.2             # holding with a block in hand: one block every 0.2 s


## Holding the finger (or the right mouse button) with a block in hand keeps placing where
## the crosshair points, so you can walk and build a line, a bridge or a wall in one go.
func _update_placing(delta: float) -> bool:
	var item := inv.item_at(selected)
	var hold_touch: bool = use_touch and not touch.classic and touch.aiming
	var hold_mouse: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var placing: bool = (hold_touch or hold_mouse) and Items.placeable.has(item) and not screen.visible and not health.dead \
		and not (use_touch and touch.mine_mode)
	if not placing:
		_place_timer = 0.0
		_hold_used = false
		return false
	_place_timer -= delta
	if _place_timer <= 0.0 and not _hold_used:
		_place_timer = PLACE_EVERY
		# holding on a door, chest, switch...: use it once, not on and off every 0.2 s
		var hit := target()
		if not hit.is_empty() and _usable(world.get_block(hit["pos"].x, hit["pos"].y, hit["pos"].z)):
			_hold_used = true
			use_block(hit["pos"])
		else:
			place_block(false)
	return hold_touch                       # a held finger with a block does not break


func _update_mining(delta: float) -> void:
	var placing := _update_placing(delta)
	var held := _breaking() and not screen.visible and not health.dead and not placing
	var animal = looked_at_animal() if spawned else null
	if held and not _break_was_held and _boss_in_sight():
		_hit_boss()
		_break_was_held = held
		return
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
	var id := world.get_block(pos.x, pos.y, pos.z)
	var hb := _outline_box(id)
	highlight.position = Vector3(pos) + hb[1]
	highlight.scale = hb[0] * 1.004
	hud.show_target(Items.name_of(id))
	# ghost of the held block (with a crosshair; on touch the finger shows where it goes)
	var held_item := inv.item_at(selected)
	var ghost_pos: Vector3i = pos + hit["normal"]
	ghost.visible = Items.placeable.has(held_item) and not held_item in [WorldData.WATER] \
		and _replaceable(ghost_pos) and not _overlaps_player(ghost_pos, held_item)
	if ghost.visible:
		var box := _ghost_box(held_item, ghost_pos, hit["normal"])
		ghost.visible = not box.is_empty()
		if ghost.visible:
			ghost.position = Vector3(ghost_pos) + box[1]
			ghost.scale = box[0]
	if held and (Blocks.hardness[id] >= 0 or creative):
		if creative:
			# creative: the first block breaks at once, then one every 0.22 s while held
			_creative_cd -= delta
			if _creative_cd <= 0.0:
				break_at(pos)
				_creative_cd = 0.22
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
		_creative_cd = 0.0
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
			_clip_from_library = false
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
				_start_paste(hit["pos"] + hit["normal"], _clip_from_library or Input.is_physical_key_pressed(KEY_SHIFT))
				return
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
				_clip_from_library = true
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
var boss: StormRay
var _portal_time := 0.0
var _portal_lock := true            # standing in a portal when the world starts: step out first
var remote_players: RemotePlayers
var chat_box: ChatBox
var _remote_world := false          # we joined a friend: their phone saves the world, not ours
var _applying_remote := false       # edits from the network must not be sent back
var _net_timer := 0.0
var _clock_timer := 0.0
var power: Power
var ghost: MeshInstance3D
var debris: Debris
var _cave_dark := 0.0               # 0 above ground .. 1 deep underground (darkens the sky)
var _creative_cd := 0.0             # creative: time until holding breaks the next block           # where the held block would go
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
func _take_damage(damage: int, cause := "gloom") -> void:
	if damage <= 0 or creative or health.dead:
		return
	if _spawn_shield > 0.0 and cause != "fall" and cause != "void":
		return                                        # a few calm seconds after coming back
	health.damage(damage, cause)
	hud.hurt_flash()
	Sfx.play("hurt")
	hud.show_bars(health, creative)
	if health.dead:
		hud.show_death(health.cause)
		player.set_physics_process(false)
		touch.visible = false                         # only the "back" button while dead


func _update_animals(delta: float) -> void:
	if _remote_world:
		wildlife.puppet_step(delta, player.position)      # the host moves them; we glide along
	else:
		var monsters: bool = I18n.settings.get("monsters", true)
		Wildlife.others = remote_players.targets() if Net.is_host() else []
		_take_damage(wildlife.update(delta, player.position, daylight, monsters, not creative and not health.dead))
		for peer in Wildlife.remote_damage:               # night creatures that hit a friend
			Net.send_hurt(peer, Wildlife.remote_damage[peer])
		Wildlife.remote_damage.clear()
	var alive := {}
	for a in wildlife.animals:
		alive[a] = true
		if not animal_views.has(a):
			var v := AnimalView.new(a)
			add_child(v)
			animal_views[a] = v
		animal_views[a].sync(delta, shown_light, world)
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
		touch.visible = false                         # only the "back" button while dead
		if not use_touch:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_bars(health, creative)


var _spawn_shield := 0.0


func respawn() -> void:
	health.respawn()
	_spawn_shield = 3.0
	# no night creature waiting at the spawn point to hit you again straight away
	for a in wildlife.animals:
		if a.hostile and a.pos.distance_to(spawn_point) < 24.0:
			a.dead = true
	hud.death.visible = false
	touch.visible = use_touch
	player.position = spawn_point
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	_refresh_mode()


func _update_sky(delta: float) -> void:
	if world.dimension == "sky":
		world.time_of_day = 0.3                       # the sky realm: an endless golden afternoon
	world.time_of_day = fposmod(world.time_of_day + delta * time_speed / DAY_LENGTH, 1.0)
	var angle := world.time_of_day * TAU
	var sun_height := sin(angle)
	var day := clampf((sun_height + 0.15) / 0.45, 0, 1)
	var dusk := clampf(1 - absf(sun_height) / 0.35, 0, 1)
	var sky_color := NIGHT_SKY.lerp(DAY_SKY, day).lerp(DUSK_SKY, dusk * 0.7 * maxf(day, 0.5))
	sky_color = weather.tint_sky(sky_color)
	if world.dimension == "sky":
		sky_color = Color(0.45, 0.36, 0.66).lerp(Color(0.95, 0.6, 0.55), 0.18)
	# underground the sky fades to dark: you no longer see blue through far cave openings
	var col = world.column(floori(player.position.x + 0.5), floori(player.position.z + 0.5))
	if col != null:
		var depth: float = float(col[0]) - player.position.y
		_cave_dark = move_toward(_cave_dark, clampf((depth - 6.0) / 18.0, 0.0, 1.0), delta * 0.8)
	sky_color = sky_color.lerp(Color(0.02, 0.02, 0.03), _cave_dark)
	env.background_color = sky_color
	env.fog_light_color = sky_color
	var reach_m := chunks.render_distance * 16.0
	env.fog_depth_begin = reach_m * 0.68
	env.fog_depth_end = reach_m * 0.98
	weather.update(delta, player.position, 0.16 + 0.84 * day)
	daylight = (0.16 + 0.84 * day) * (1.0 - weather.sky_dim())
	var tint := Vector3(0.72, 0.8, 1.0).lerp(Vector3.ONE, day).lerp(Vector3(1.0, 0.78, 0.6), dusk * 0.5)
	# what you see: moonlight keeps the night readable (monsters still use `daylight`)
	shown_light = (NIGHT_LIGHT + (1.0 - NIGHT_LIGHT) * day) * (1.0 - weather.sky_dim())
	for m in materials.values():
		m.set_shader_parameter("daylight", shown_light)
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


var _frame_t0 := 0


var _perf_last_main := 0.0          # this frame's script time (ms), for tests


func _process(delta: float) -> void:
	_frame_t0 = Time.get_ticks_usec()
	_process_inner(delta)
	_perf_last_main = (Time.get_ticks_usec() - _frame_t0) / 1000.0
	_perf("main", Time.get_ticks_usec() - _frame_t0)


func _process_inner(delta: float) -> void:
	_spawn_shield = maxf(0.0, _spawn_shield - delta)
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
			var mem: Dictionary = OS.get_memory_info()
			print("World ready in %.1f s (%d chunks, view distance %d, chosen in settings: %s, memory %.1f GB)" % [
				(Time.get_ticks_msec() - _load_t0) / 1000.0, world.chunks.size(), chunks.render_distance,
				int(I18n.settings["view_distance"]) > 0, float(mem.get("physical", 0)) / 1073741824.0])
			var args := Array(OS.get_cmdline_user_args())
			var testing := args.any(func(a): return a.begins_with("--shot") or a in ["--selftest", "--gloomtest", "--menutest", "--machines", "--bosstest", "--portaltest", "--walkplace", "--playtest", "--survivaltest"])
			if "--tutorial" in args or (not testing and not I18n.settings.get("tutorial_done", false)):
				start_tutorial()
			player.set_physics_process(not screen.visible and not health.dead)
	touch.hotbar_rect = hud.hotbar_rect()
	touch.map_rect = hud.map_rect()
	if hud.big_map.visible:
		hud.big_map_view.others = hud.minimap.others
		hud.big_map_view.update_map(player.position, player.forward(), spawn_point)
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
		_update_portal(delta)
		if world.dimension == "sky" and player.position.y < WorldData.SKY_BASE - 40:
			# fell off the islands: the wind carries you back to the main island (it stings a little)
			player.position = spawn_point
			player.velocity = Vector3.ZERO
			hud.flash(I18n.t("wind_saved"))
			_take_damage(4, "void")
		if not is_inside_tree():
			return                                    # travelled: this scene is already gone
		if boss != null and not boss.dead:
			boss.update(delta, player.position, not creative and not health.dead)
			hud.show_boss(I18n.t("boss_name"), boss.health / StormRay.MAX_HEALTH, boss.alive_crystals().size())
		_update_net(delta)
		_update_paste()
		if not _remote_world:
			_update_growing(delta)                  # with friends, the host grows plants
		_update_machines(delta)
	var t4 := Time.get_ticks_usec()
	if spawned:
		hud.minimap.record_some(delta, player.position, chunks.render_distance)
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
		player.position += Vector3(0.35, 0, 0.14)          # about 20 blocks a second
		_st_frame += 1
		if _st_frame > 900:
			print("STRESS done at ", player.position, " chunks shown ", chunks.views.size(), " sections ", chunks.sections.size(), " fps ", Engine.get_frames_per_second())
			get_tree().quit()
	if "--selftest" in OS.get_cmdline_user_args() and spawned:
		_selftest_step()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--goto-y=") and spawned and not _st.has("goto"):
			_st["goto"] = true                          # testing: jump deep underground
			creative = true
			set_flying(true)
			player.noclip = true
			var want := int(a.substr(9))
			var px := floori(player.position.x + 0.5)
			var pz := floori(player.position.z + 0.5)
			var found := want
			for dy in range(0, 60):                     # the nearest open air (a cave) at or below
				for yy in [want - dy, want + dy]:
					if yy > 2 and yy < WorldData.H - 2 and world.get_block(px, yy, pz) == 0 and world.get_block(px, yy + 1, pz) == 0:
						found = yy
						break
				if found != want or world.get_block(px, want, pz) == 0:
					break
			player.position.y = float(found)
			print("GOTO y ", found)
			_shot_frames = 150
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--paste=") and spawned and not _st.has("paste"):
			_st["paste"] = true                         # testing: build a library building in front of us
			builder.clipboard = Schematics.load_file("res://data/schematics/%s.json" % a.substr(8))
			_clip_from_library = true
			var f := player.forward()
			var at := Vector3i(floori(player.position.x + f.x * 6), floori(player.position.y) - 1, floori(player.position.z + f.z * 6))
			_start_paste(at, true)
			creative = true
			set_flying(true)
			player.position += Vector3(-f.x * 30, 45, -f.z * 30)
			player.look(Vector2(0, 0.6))
			_shot_frames = 400
	if "--host" in OS.get_cmdline_user_args() and spawned and not _st.has("host"):
		_st["host"] = true                              # testing: open this world to friends
		_host_game()
	if "--netlog" in OS.get_cmdline_user_args() and Engine.get_process_frames() % 120 == 0:
		print("NETSTATE active=%s joined=%s host=%s peer=%s remote_world=%s" % [Net.active(), Net.joined, Net.hosting, multiplayer.multiplayer_peer, _remote_world])
	if Net.active() and "--netlog" in OS.get_cmdline_user_args() and Engine.get_process_frames() % 120 == 0:
		print("NET host=%s players=%d remote_edits=%d animals=%d chat=%d" % [Net.is_host(), remote_players.count(), _net_edits_in, wildlife.animals.size(), hud._chat_lines.size()])
	if "--netbot" in OS.get_cmdline_user_args() and spawned and not _st.has("netbot") and Net.active():
		_st["netbot"] = true                            # testing: a friend builds a small tower
		var bx := floori(player.position.x + 0.5) + 2
		var bz := floori(player.position.z + 0.5)
		var by := floori(player.position.y)
		for i in 5:
			edit(Vector3i(bx, by + i, bz), 1600 + "HELLO".unicode_at(i) - 65)
		print("NETBOT built HELLO at ", Vector3i(bx, by, bz))
		Net.say("مرحبا من البوت")
		Net.animal_drop.connect(func(st): print("NETBOT got a drop from the host: ", st))
	if "--netbot" in OS.get_cmdline_user_args() and _st.has("netbot") and Engine.get_process_frames() % 20 == 0 and _remote_world:
		var best = null                                 # keep hitting the nearest animal
		var bd := 40.0
		for a in wildlife.animals:
			if not a.ambient and player.position.distance_to(a.pos) < bd:
				best = a
				bd = player.position.distance_to(a.pos)
		if best != null:
			attack(best)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pastehere=") and spawned and not _st.has("pastehere"):
			_st["pastehere"] = true                      # testing: a building right on top of us
			builder.clipboard = Schematics.load_file("res://data/schematics/%s.json" % a.substr(12))
			_clip_from_library = true
			var at := Vector3i(floori(player.position.x + 0.5), floori(player.position.y), floori(player.position.z + 0.5) - 2)   # a wall on us
			_st["before"] = player.position
			_start_paste(at, true)
		if a.begins_with("--pastehere=") and _st.has("pastehere") and _paste_batches.is_empty() and not _st.has("pastecheck") and Engine.get_process_frames() % 30 == 0:
			_st["pastecheck"] = true
			var w0 := Vector3i(floori(player.position.x + 0.5), floori(player.position.y + 0.6), floori(player.position.z + 0.5))
			edit(w0, 41, true, false)                   # a wall block right where we stand
			edit(w0 + Vector3i(0, 1, 0), 41, true, false)
			_step_out_of(_paste_box)
			var f := Vector3i(floori(player.position.x + 0.5), floori(player.position.y + 0.6), floori(player.position.z + 0.5))
			var b := world.get_block(f.x, f.y, f.z)
			print("PASTEHERE player moved from ", _st["before"], " to ", player.position, ", stuck in a block: ", b != 0 and Blocks.solid[b] == 1, " block ", b, " ", Items.name_of(b), " top_y ", world.top_y(f.x, f.z))
	if "--playtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: a heavy play session, measured
		if _st_frame == 5:
			creative = true
			set_flying(true)
			chunks.render_distance = 5
			builder.clipboard = Schematics.load_file("res://data/schematics/mega_complex.json")
			_clip_from_library = true
			if not "--nopaste" in OS.get_cmdline_user_args():
				_start_paste(Vector3i(floori(player.position.x) - 48, floori(player.position.y) - 1, floori(player.position.z) - 35), true)
			_st["times"] = []
			_st["center"] = player.position
		if _st_frame == 200 and not "--nopaste" in OS.get_cmdline_user_args():
			for k in 2:                                 # two blinking clocks on top
				builder.clipboard = Schematics.load_file("res://data/schematics/lamp_clock.json")
				_start_paste(Vector3i(floori(player.position.x) + k * 12, floori(player.position.y) + 3, floori(player.position.z)), true)
				while not _paste_batches.is_empty():
					_update_paste()
		if _st_frame > 200 and _st_frame < 1400:
			var a := (_st_frame - 200) / 1200.0 * TAU   # fly a circle over the town
			var c: Vector3 = _st["center"]
			player.position = Vector3(c.x + cos(a) * 30, c.y + 14, c.z + sin(a) * 30)
			_st["times"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if _st_frame == 1400:
			var t: Array = _st["times"]
			t.sort()
			var avg := 0.0
			for v in t:
				avg += v
			avg /= t.size()
			print("PLAYTEST frames %d: script time avg %.2f ms, p95 %.2f ms, worst %.2f ms" % [t.size(), avg, t[int(t.size() * 0.95)], t[t.size() - 1]])
			print("PLAYTEST machines %d in %d circuits, chunks %d, sections %d, memory %.0f MB" % [power.parts.size(), power._comps.size(),
				world.chunks.size(), chunks.sections.size(), Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])
			print("PLAYTEST per system (ms): ", _perf_ms)
			get_tree().quit()
	if "--survivaltest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: a survival session, step by step
		var f0 := floori(player.position.x + 0.5)
		match _st_frame:
			10:   # a night creature right next to us
				world.time_of_day = 0.75
				var g := Wildlife.Animal.new("gloom", player.position + Vector3(2, 0.5, 0))
				wildlife.animals.append(g)
				_st["h0"] = health.health
			130:
				print("SURVIVAL gloom hurt us: ", health.health < _st["h0"], " (", _st["h0"], " -> ", health.health, ")")
				world.time_of_day = 0.25
				_take_damage(100)
			140:
				print("SURVIVAL dead and death screen shown: ", health.dead and hud.death.visible)
				respawn()
			150:
				print("SURVIVAL respawned with full health: ", not health.dead and health.health == int(health.K["MAX_HEALTH"]), " (health ", health.health, ", glooms near ", wildlife.animals.filter(func(a): return a.kind == "gloom").size(), ")")
				health.hunger = 5
				inv.slots[selected] = [105, 3]          # apples
				place_block()
				print("SURVIVAL ate an apple: hunger 5 -> ", health.hunger, ", apples left ", inv.item_at(selected) == 105 and inv.slots[selected][1] == 2)
			160:  # fall from 20 blocks
				_st["h1"] = health.health
				player.position.y += 20
			260:
				print("SURVIVAL fall damage: ", _st["h1"], " -> ", health.health)
				# water: a pool around us
				var b := Vector3i(f0, floori(player.position.y + 0.6), floori(player.position.z + 0.5))
				for dx in range(-2, 3):
					for dz in range(-2, 3):
						for dy in range(-3, 1):
							edit(b + Vector3i(dx, dy, dz), WorldData.WATER, true, false)
				player.position = Vector3(b) + Vector3(0, -2.4, 0)
			320:
				print("SURVIVAL swimming in water: ", player.swimming)
				# a pickaxe on stone
				inv.slots[selected] = [201, 1, 60]
				var st := Vector3i(f0 + 4, floori(player.position.y) + 6, floori(player.position.z + 0.5))
				for k in 3:
					edit(st + Vector3i(0, k, 0), 3, true, false)
					break_at(st + Vector3i(0, k, 0))
				print("SURVIVAL pickaxe wear after 3 stones: ", inv.slots[selected][2] if inv.slots[selected] != null else "broken")
				# a chest keeps what you put in
				var cp := st + Vector3i(2, 0, 0)
				edit(cp, 48, true, false)
				open_screen(cp)
				chest_inv.slots[0] = [22, 17]
				close_screen()
				open_screen(cp)
				print("SURVIVAL chest kept its items: ", chest_inv.slots[0] == [22, 17])
				close_screen()
				_st["cp"] = cp
			330:
				save_game()
				var again := WorldData.load_from(SAVE_PATH)
				var c: Vector3i = _st["cp"]
				print("SURVIVAL saved and loaded: chest ", again.containers.get(c, [null])[0] == [22, 17] or str(again.containers.get(c, [null])[0]) == str([22, 17]),
					", position ", again.player_data["position"][1] > 0, ", edits ", again.changes.size() == world.changes.size())
				get_tree().quit()
	if "--walkplace" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: walk with the stick, tap to place
		var vs := get_viewport().get_visible_rect().size
		if _st_frame == 10:
			_select(5)
			player.look(Vector2(0, 0.55))
			_st["planks"] = inv.count(7)
			_touch(0, Vector2(200, vs.y - 200), true)
			_drag(0, Vector2(200, vs.y - 260), Vector2(0, -60))
		for k in 6:                                     # six quick taps while walking
			var f0 := 20 + k * 15
			if _st_frame == f0:
				_touch(1, vs / 2 + Vector2(40, 0), true)
			if _st_frame == f0 + 3:
				_drag(1, vs / 2 + Vector2(52, 6), Vector2(12, 6))   # fingers wobble a little
			if _st_frame == f0 + 6:
				_touch(1, vs / 2 + Vector2(52, 6), false)
		if _st_frame == 120:
			_touch(0, Vector2(200, vs.y - 260), false)
			print("WALKPLACE placed ", _st["planks"] - inv.count(7), " of 6 taps while walking")
			# a door on cleared flat ground two blocks ahead, then tap it
			var base := Vector3i(floori(player.position.x + 0.5), floori(player.position.y + 0.6), floori(player.position.z + 0.5))
			for dx in range(-2, 3):
				for dz in range(-4, 1):
					for dy in range(0, 4):
						edit(base + Vector3i(dx, dy, dz), 0, true, false)
					edit(base + Vector3i(dx, -1, dz), 41, true, false)
			var dpos := base + Vector3i(0, 0, -2)
			edit(dpos, 510, true, false)
			edit(dpos + Vector3i(0, 1, 0), 511, true, false)
			_st["door"] = dpos
		if _st_frame == 125:
			var d: Vector3i = _st["door"]
			var dir := Vector3(d) + Vector3(0, 0.3, 0) - player.eye()
			player.yaw = atan2(-dir.x, -dir.z)
			player.rotation.y = player.yaw
			player.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
			player.camera.rotation.x = player.pitch
		if _st_frame == 130:
			_touch(1, vs / 2, true)
		if _st_frame == 134:
			_touch(1, vs / 2, false)
		if _st_frame == 140:
			var d: Vector3i = _st["door"]
			print("WALKPLACE door opened by a tap: ", Blocks.defs[world.get_block(d.x, d.y, d.z)]["door"]["open"])
			get_tree().quit()
	if "--holdplace" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: hold a finger with planks in hand
		if _st_frame == 10:
			_select(5)
			player.look(Vector2(0, 0.6))
			_st["planks"] = inv.count(7)
			_st["jobs"] = chunks.jobs_started
			_st["worst"] = 0.0
		if _st_frame > 10 and _st_frame <= 160:
			_st["worst"] = maxf(_st["worst"], _perf_last_main)
			if not "--noplace" in OS.get_cmdline_user_args():
				_touch(1, get_viewport().get_visible_rect().size / 2, true)
		if _st_frame > 10 and _st_frame < 130:
			player.position.x += 0.04                   # walk while holding
		if _st_frame == 130:
			_touch(1, get_viewport().get_visible_rect().size / 2, false)
			print("HOLDPLACE placed ", _st["planks"] - inv.count(7), " planks while holding for 2 s")
		if _st_frame == 160:
			print("HOLDPLACE mesh jobs started: %d, worst frame on the main thread %.1f ms" % [chunks.jobs_started - _st["jobs"], _st["worst"]])
			if not _shot_path:
				get_tree().quit()
			if not _shot_path:
				get_tree().quit()
	if "--portaltest" in OS.get_cmdline_user_args() and spawned and not _st.has("portal"):
		_st["portal"] = true                            # testing: build a frame, open it, step in
		if world.dimension == "sky":
			print("PORTAL arrived in: ", world.dimension, ", items carried: ", inv.slots.filter(func(x): return x != null).size(),
				", boss here: ", boss != null)
			get_tree().quit()
			return
		var o := Vector3i(floori(player.position.x + 0.5) + 3, floori(player.position.y), floori(player.position.z + 0.5))
		for i in 4:
			for j in 5:
				edit(o + Vector3i(0, j, i), WorldData.SKY["FRAME"] if (i == 0 or i == 3 or j == 0 or j == 4) else 0, true, false)
		inv.slots[selected] = [131, 1]
		_open_portal(o)
		print("PORTAL opened: ", world.get_block(o.x, o.y + 1, o.z + 1) == WorldData.SKY["PORTAL"], ", key used: ", inv.item_at(selected) != 131)
		player.position = Vector3(o.x, o.y + 0.5, o.z + 1)
		_portal_lock = false
	if "--bossview" in OS.get_cmdline_user_args() and spawned and boss != null:
		var d := boss.global_position - player.eye()           # testing: keep the boss in view
		player.yaw = atan2(-d.x, -d.z)
		player.rotation.y = player.yaw
		player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
		player.camera.rotation.x = player.pitch
		if Engine.get_process_frames() % 60 == 0 and boss.state == "circle":
			boss._timer = 0.0                               # swoop at us now and then
	if "--bosstest" in OS.get_cmdline_user_args() and spawned and boss != null:
		_st_frame += 1                                  # testing: a whole fight, sped up
		if _st_frame == 30:
			print("BOSS crystals healing it: ", boss.alive_crystals().size(), ", health ", boss.health)
			boss.health = 200
		if _st_frame == 90:
			print("BOSS healed by the crystals to ", snappedf(boss.health, 1))
			for c in boss.crystals:
				edit(c, 0, true, false)                 # break the crystals
		if _st_frame == 100:
			print("BOSS crystals left: ", boss.alive_crystals().size())
		if _st_frame > 100 and _st_frame < 400 and not boss.dead and _st_frame % 5 == 0:
			boss.hit(20)
		if _st_frame == 420:
			print("BOSS dead: ", boss.dead, ", saved as beaten: ", world.player_data.get("boss_dead", false),
				", trophy placed: ", world.get_block(0, WorldData.SKY_BASE + 7, 0) == 1808,
				", prize on the ground: ", drops.drops.map(func(d): return d["stack"]), ", in bag: storm core ", inv.count(132), ", shards ", inv.count(130))
			if not _shot_path:
				get_tree().quit()
	if "--journey" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: fly far in a straight line, watch memory
		if _st_frame == 2:
			set_mode(true)
			set_flying(true)
		player.position += Vector3(0.35, 0, 0.2)       # ~20 blocks per second at 60 fps
		var top := world.top_y(floori(player.position.x + 0.5), floori(player.position.z + 0.5))
		if top > 0:
			player.position.y = maxf(player.position.y, top + 12.0)
		if _st_frame % 500 == 0:
			print("JOURNEY frame %d at %d,%d: chunks %d, views %d, sections %d, animals %d, drops %d, memory %.0f MB, script %.2f ms" % [
				_st_frame, int(player.position.x), int(player.position.z), world.chunks.size(), chunks.views.size(),
				chunks.sections.size(), wildlife.animals.size(), drops.drops.size(),
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, _perf_ms.get("main", 0.0)])
		if _st_frame == 4000:
			get_tree().quit()
	if "--voidtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: step off the edge of the sky islands
		if _st_frame == 5:
			player.position = Vector3(300, WorldData.SKY_BASE + 10, 300)
		if _st_frame in [60, 200, 400, 600]:
			print("VOID frame %d: y %.0f, health %d, dead %s" % [_st_frame, player.position.y, health.health, health.dead])
		if _st_frame == 600:
			get_tree().quit()
	if "--backtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: the phone's Back button
		if _st_frame == 5:
			open_screen()
		if _st_frame in [10, 20, 30]:
			get_tree().root.propagate_notification(NOTIFICATION_WM_GO_BACK_REQUEST)
			print("BACK %d: inventory %s, settings %s, still running %s" % [_st_frame, screen.visible, settings.visible, is_inside_tree()])
		if _st_frame == 40:
			get_tree().quit()
	if "--nighttest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: a whole night out in the open
		if _st_frame == 1:
			world.time_of_day = 0.55
			_st["hits"] = 0
			_st["h"] = health.health
		if health.health < _st["h"]:
			_st["hits"] += 1
		_st["h"] = health.health
		if health.dead:
			print("NIGHT died at frame ", _st_frame)
			respawn()
		if _st_frame % 600 == 0:
			var host := wildlife.animals.filter(func(a): return a.hostile)
			var near := host.filter(func(a): return a.pos.distance_to(player.position) < 16)
			print("NIGHT where: ", host.map(func(a): return "%s d%.0f dy%.0f %s" % [a.kind, Vector2(a.pos.x - player.position.x, a.pos.z - player.position.z).length(), a.pos.y - player.position.y, a.state]))
			print("NIGHT frame %d time %.2f: monsters %d (near %d), health %d, hits so far %d" % [_st_frame, world.time_of_day, host.size(), near.size(), health.health, _st["hits"]])
		if _st_frame == 4800:
			get_tree().quit()
	if "--laddertest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: climb a storm pillar's ladder
		if _st_frame == 5:
			player.position = Vector3(26, WorldData.SKY_BASE + 7, 0)
			player.yaw = deg_to_rad(90.0)                # facing -x, at the pillar
			player.rotation.y = player.yaw
		if _st_frame > 5 and _st_frame < 1000 and player.position.y < WorldData.SKY_BASE + 6 + WorldData.PILLAR_HEIGHT:
			player.move_input = Vector2(0, 1)         # climb until level with the top, then stop
		if _st_frame == 5 and _shot_path:
			player.position = Vector3(34, WorldData.SKY_BASE + 9, 6)
			player.look(Vector2(0, 0))
			player.yaw = atan2(34 - 24, 6 - 0)
			player.rotation.y = player.yaw
			player.pitch = 0.35
			player.camera.rotation.x = player.pitch
			_st_frame = 1000
		if _st_frame == 400:
			var c := Vector3i(24, WorldData.SKY_BASE + 6 + WorldData.PILLAR_HEIGHT + 1, 0)
			print("LADDER climbed to y %.1f (pillar top %d), crystal within reach: %s" % [player.position.y,
				WorldData.SKY_BASE + 6 + WorldData.PILLAR_HEIGHT, player.eye().distance_to(Vector3(c)) < reach()])
			get_tree().quit()
	if "--keeptest" in OS.get_cmdline_user_args() and spawned and not _st.has("keep"):
		_st["keep"] = true                              # testing: heavy things stay when the block under them breaks
		var o := Vector3i(floori(player.position.x + 0.5) + 3, floori(player.position.y) + 6, floori(player.position.z + 0.5))
		var tops := {"stone": 3, "planks": 7, "glass": 20, "slab": 300, "stairs": 320, "fence": 61, "chest": 48, "bed": 62, "furnace": 47}
		var i := 0
		for name in tops:
			var base := o + Vector3i(i * 2, 0, 0)
			edit(base, 3, true, false)
			edit(base + Vector3i(0, 1, 0), tops[name], true, false)
			i += 1
		var door := o + Vector3i(i * 2, 0, 0)               # a door on a block, and a block hanging nowhere
		edit(door, 3, true, false)
		edit(door + Vector3i(0, 1, 0), 510, true, false)
		edit(door + Vector3i(0, 2, 0), 511, true, false)
		inv.slots[selected] = null
		var before := drops.drops.size()
		i = 0
		var kept := []
		for name in tops:
			var base := o + Vector3i(i * 2, 0, 0)
			break_at(base)
			var now := world.get_block(base.x, base.y + 1, base.z)
			kept.append("%s %s" % [name, "stayed" if now == tops[name] else "FELL (now %d)" % now])
			i += 1
		break_at(door)
		var dk := world.get_block(door.x, door.y + 1, door.z)
		kept.append("door %s" % ("stayed" if dk == 510 else "FELL (now %d)" % dk))
		print("KEEP ", kept, ", extra drops ", drops.drops.size() - before)
		get_tree().quit()
	if "--placetest" in OS.get_cmdline_user_args() and spawned and not _st.has("place"):
		_st["place"] = true                             # testing: ladders and doors need support
		var o := Vector3i(floori(player.position.x + 0.5) + 4, floori(player.position.y) + 8, floori(player.position.z + 0.5))
		for y in 4:
			edit(o + Vector3i(0, y, 0), 3, true, false)          # a stone wall column
		edit(o + Vector3i(4, 0, 0), 3, true, false)              # a lone block in the air
		var res := []
		inv.slots[selected] = [500, 10]
		_place_on(o, Vector3i(1, 0, 0))                          # side of the wall
		var l1 := world.get_block(o.x + 1, o.y, o.z)
		res.append("ladder on a wall side: %s" % (Blocks.defs.get(l1, {}).get("shape", "") == "ladder"))
		_place_on(o + Vector3i(1, 0, 0), Vector3i(0, 1, 0))      # top of that ladder: extend it
		var l2 := world.get_block(o.x + 1, o.y + 1, o.z)
		res.append("extends upward, same way: %s" % (l2 == l1))
		_place_on(o + Vector3i(4, 0, 0), Vector3i(0, 1, 0))      # top of the lone block, no wall
		res.append("no ladder without a wall: %s" % (world.get_block(o.x + 4, o.y + 1, o.z) == 0))
		inv.slots[selected] = [510, 4]
		_place_on(o + Vector3i(4, 0, 0), Vector3i(0, 0, 1))      # side of the lone block: air below
		res.append("no door in the air: %s" % (world.get_block(o.x + 4, o.y, o.z + 1) == 0))
		_place_on(o + Vector3i(4, 0, 0), Vector3i(0, 1, 0))      # on top of the block
		res.append("door on a block: %s" % Blocks.defs.get(world.get_block(o.x + 4, o.y + 1, o.z), {}).has("door"))
		print("PLACE ", res)
		get_tree().quit()
	if "--swimtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: swim to a shore one block above the water and climb out
		if _st_frame == 3:
			var o := Vector3i(floori(player.position.x + 0.5), floori(player.position.y) + 20, floori(player.position.z + 0.5))
			_st["o"] = o
			for x in range(-3, 6):
				for z in range(-2, 3):
					edit(o + Vector3i(x, -3, z), 3, true, false)            # pool floor
					for y in range(-2, 2):
						var shore := x >= 3
						var id := 0
						if shore and y <= 0:
							id = 3                                         # the shore: top 1 above the water
						elif not shore and y <= -1:
							id = WorldData.WATER                           # water 2 deep, surface at y-1
						edit(o + Vector3i(x, y, z), id, true, false)
			player.position = Vector3(o.x - 1, o.y - 2, o.z)
			player.velocity = Vector3.ZERO
			player.yaw = deg_to_rad(-90.0)                # facing +x
			player.rotation.y = player.yaw
		if _st_frame > 30 and not _st.has("out"):
			player.move_input = Vector2(0, 1)
			player.jump_held = "--swimjump" in OS.get_cmdline_user_args()
			var o: Vector3i = _st["o"]
			if player.position.x > o.x + 2.6 and player.position.y > o.y + 0.4:
				_st["out"] = _st_frame - 30
		if _st_frame == 330:
			print("SWIM got out onto the shore: %s (after %s frames, jump held %s)" % [_st.has("out"), _st.get("out", "-"), "--swimjump" in OS.get_cmdline_user_args()])
			get_tree().quit()
	if "--mapmemtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: fly away, the big map still shows home
		if _st_frame == 2:
			set_mode(true)
			set_flying(true)
		if _st_frame < 900:
			player.position += Vector3(0.4, 0, 0)
			var top := world.top_y(floori(player.position.x + 0.5), floori(player.position.z + 0.5))
			if top > 0:
				player.position.y = maxf(player.position.y, top + 10.0)
		if _st_frame == 900:
			var t := Time.get_ticks_usec()
			save_game()
			print("MAPMEM remembered %d chunks, saved in %.1f ms, file %d KB" % [Minimap.memory.size(), (Time.get_ticks_usec() - t) / 1000.0,
				FileAccess.get_file_as_bytes(SAVE_PATH.get_basename() + "_map.bin").size() / 1024])
			Minimap.load_memory(SAVE_PATH.get_basename() + "_map.bin")
			print("MAPMEM loaded back: %d chunks, home chunk known: %s, home chunk loaded now: %s" % [Minimap.memory.size(),
				Minimap.memory.has(Vector2i(floori(spawn_point.x) >> 4, floori(spawn_point.z) >> 4)),
				world.chunks.has(Vector2i(floori(spawn_point.x) >> 4, floori(spawn_point.z) >> 4))])
			open_map()
		if _st_frame == 960:
			if _shot_path:
				get_viewport().get_texture().get_image().save_png(_shot_path)
			get_tree().quit()
	if "--petfollow" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: walk away from a pet, it follows
		if _st_frame == 2:
			var a := Wildlife.Animal.new("woolly", player.position + Vector3(2, 0, 0))
			a.tame = true
			wildlife.animals.append(a)
			_st["pet"] = a
			set_mode(true)
			set_flying(true)
		if _st_frame > 2 and _st_frame < 600:
			player.position += Vector3(0, 0, 0.05)       # ~3 blocks a second
		if _st_frame == 900:
			var a = _st["pet"]
			print("PETFOLLOW pet is %.1f blocks from you after you walked %.0f blocks" % [Vector2(a.pos.x - player.position.x, a.pos.z - player.position.z).length(), 0.05 * 597])
			get_tree().quit()
	if "--minetest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: a hotbar full of blocks can still break
		var mid := get_viewport().get_visible_rect().size / 2
		if _st_frame == 5:
			set_mode(true)
			for i in 9:
				inv.slots[i] = [3, 64]                   # every slot a block, like a creative hotbar
			_select(0)
			player.look(Vector2(0, 0.7))
			var h := target()
			_st["aim"] = h.get("pos")
			var btn: Panel = touch._buttons["mine"]
			_touch(5, btn.position + btn.size / 2, true)
			_touch(5, btn.position + btn.size / 2, false)
		if _st_frame == 8:
			_st["on"] = touch.mine_mode
			_touch(6, mid, true)
			_touch(6, mid, false)
		if _st_frame == 12:
			var p: Vector3i = _st["aim"]
			print("MINE button turns break mode on: %s, a tap broke the block with %s in hand: %s" % [_st["on"],
				Items.name_of(inv.item_at(selected)), world.get_block(p.x, p.y, p.z) == 0])
			_touch(7, mid, true)                        # now hold: several blocks go
			_st["n"] = world.changes.values().reduce(func(acc, d): return acc + d.size(), 0)
		if _st_frame == 80:
			_touch(7, mid, false)
			var n: int = world.changes.values().reduce(func(acc, d): return acc + d.size(), 0)
			print("MINE holding broke %d more blocks" % (n - _st["n"]))
			_select(2)
		if _st_frame == 83:
			print("MINE picking a hotbar slot goes back to building: %s" % (not touch.mine_mode))
			get_tree().quit()
	if "--pettest" in OS.get_cmdline_user_args() and spawned and not _st.has("pet"):
		_st["pet"] = true                               # testing: a tamed animal survives save and load
		var a := Wildlife.Animal.new("woolly", player.position + Vector3(3, 0, 0))
		a.tame = true
		a.variant = 5
		wildlife.animals.append(a)
		var wild := Wildlife.Animal.new("deer", player.position + Vector3(-3, 0, 0))
		wildlife.animals.append(wild)
		save_game()
		var again := WorldData.load_from(SAVE_PATH)
		var w2 := Wildlife.new(again)
		w2.load_pets(again.player_data.get("pets", []))
		print("PET after loading: ", w2.animals.map(func(x): return "%s colour %d tame %s" % [x.kind, x.variant, x.tame]))
		get_tree().quit()
	if "--torchtest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: torches on every side of a pillar, at night
		if _st_frame == 5:
			world.time_of_day = 0.8
			var f := player.forward()
			var o := Vector3i(floori(player.position.x + f.x * 4 + 0.5), floori(player.position.y) + 1, floori(player.position.z + f.z * 4 + 0.5))
			_st["o"] = o
			for y in 3:
				edit(o + Vector3i(0, y, 0), 3, true, false)
			inv.slots[selected] = [50, 20]
			for n in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				_place_on(o + Vector3i(0, 1, 0), n)
			_place_on(o + Vector3i(0, 2, 0), Vector3i(0, 1, 0))
			var ids := []
			for n in [Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1), Vector3i(0, 3, 0)]:
				var q: Vector3i = o + n
				ids.append(world.get_block(q.x, q.y, q.z))
			print("TORCH placed: ", ids)
		if _st_frame == 60 and not _shot_path:
			var o: Vector3i = _st["o"]
			var before := drops.drops.size()
			inv.slots[selected] = null
			break_at(o + Vector3i(0, 1, 0))
			var left := 0
			for n in [Vector3i(1, 1, 0), Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(0, 1, -1)]:
				var q: Vector3i = o + n
				left += int(world.get_block(q.x, q.y, q.z) != 0)
			print("TORCH after breaking the wall: hanging left ", left, ", dropped ", drops.drops.size() - before)
			var n0 := drops.drops.size()
			break_at(o + Vector3i(0, 2, 0))
			print("TORCH standing one fell: ", world.get_block(o.x, o.y + 3, o.z) == 0, ", dropped ", drops.drops.size() - n0)
			get_tree().quit()
	if "--debristest" in OS.get_cmdline_user_args() and spawned and Engine.get_process_frames() % 12 == 0:
		debris.burst(player.eye() + player.forward() * 3.0, 1)        # testing: pieces in front of the camera
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
	if "--maptest" in OS.get_cmdline_user_args() and spawned:
		_st_frame += 1                                  # testing: tap the small map, then tap to close
		if _st_frame == 200:
			_touch(3, hud.minimap.position + hud.minimap.size / 2, true)
			_touch(3, hud.minimap.position + hud.minimap.size / 2, false)
		if _st_frame == 205:
			print("MAP opened by a tap: ", hud.big_map.visible, ", buttons hidden: ", not touch.visible)
		if _st_frame == 260:
			get_viewport().get_texture().get_image().save_png("user://map_test.png")
			_touch(4, get_viewport().get_visible_rect().size / 2, true)
			_touch(4, get_viewport().get_visible_rect().size / 2, false)
		if _st_frame == 270:
			print("MAP closed by a tap: ", not hud.big_map.visible, ", buttons back: ", touch.visible)
			get_tree().quit()
	if _shot_path != "" and spawned and _shot_frames == 20:
		for a in OS.get_cmdline_user_args():        # testing: a screen open in the screenshot
			if a.begins_with("--open="):
				var what := a.substr(7)
				match what:
					"settings":
						open_settings()
					"death":
						_take_damage(100)
					"map":
						open_map()
					"chest":
						var cp := Vector3i(player.position) + Vector3i(2, 0, 0)
						world.containers[cp] = [[3, 12], [106, 5], null, [50, 30]]
						open_screen(cp)
					"inventory":
						open_screen()
					_:
						open_screen(null, what)
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
	if _remote_world:
		return                                  # a friend's world: their phone keeps it
	if chest_pos != null and chest_inv != null:
		world.containers[chest_pos] = chest_inv.to_data()
	var data: Dictionary = world.player_data.duplicate()
	data["pets"] = wildlife.save_pets()
	data["position"] = [player.position.x, player.position.y + 0.1, player.position.z]
	data["inventory"] = inv.to_data()
	data["survival"] = health.to_data()
	data["mode"] = "creative" if creative else "survival"
	data["hotbars"] = saved_hotbars
	data["weather"] = weather.save_data()
	data["growing"] = growing.keys().map(func(v): return [v.x, v.y, v.z])
	data["spawn"] = [spawn_point.x, spawn_point.y, spawn_point.z]
	world.save(SAVE_PATH, data)
	Minimap.save_memory(SAVE_PATH.get_basename() + "_map.bin")
	Session.touch(data["mode"])


func _notification(what: int) -> void:
	# phones can close a paused app at any time: save when we go to the background
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if world and player:
			save_game()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_back_pressed()


## The phone's Back button closes what is open, one thing at a time; in the game itself it
## opens the settings (where "exit to menu" is). It never quits the app by surprise.
func _back_pressed() -> void:
	if hud.big_map.visible:
		close_map()
	elif settings.visible:
		I18n.save_settings()
		close_settings()
	elif screen.visible:
		close_screen()
	elif chat_box.visible:
		chat_box.visible = false
		chat_box.closed.emit()
	elif health.dead:
		respawn()
	elif spawned:
		open_settings()


# ---------------------------------------------------------------- self test (-- --selftest --touch)
var _st_frame := 0
var _st := {}


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = get_viewport().get_final_transform() * pos    # like a real screen: window pixels
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	var xf := get_viewport().get_final_transform()
	e.position = xf * pos
	e.relative = xf.basis_xform(rel)
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
