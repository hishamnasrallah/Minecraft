extends Node3D
## BlockWorld (Godot version) - phase 1: the world, building, day and night, phone and desktop controls.
##
## Desktop: WASD + mouse, Space jump, hold left mouse break, right click place,
##          1-9 / wheel hotbar, F5 save, Esc releases the mouse.
## Phone:   joystick (left), drag to look (right), JUMP / BREAK (hold) / PLACE buttons, tap the hotbar.
## Command line (after --): --new for a new world, --touch to show the phone controls on a desktop.

const SAVE_PATH := "user://save.json"
const REACH := 6.0
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
var env: Environment
var materials := {}
var sun: MeshInstance3D
var moon: MeshInstance3D
var highlight: MeshInstance3D
var crack: MeshInstance3D
var crack_textures := []
var hotbar := [1, 22, 4, 7, 41, 12, 50, 61, 11]   # phase 1: a fixed block palette
var selected := 0
var mine_pos = null
var mine_progress := 0.0
var spawned := false
var time_speed := 1.0
var _autosave := AUTOSAVE_EVERY
var use_touch := false
var _shot_path := ""            # --shot=file.png: take a screenshot once the world is ready, then quit
var _shot_frames := 30
var _initial_look := Vector2.ZERO


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if FileAccess.file_exists(SAVE_PATH) and not "--new" in args:
		world = WorldData.load_from(SAVE_PATH)
	if world == null:
		var seed_arg := -1
		for a in args:
			if a.begins_with("--seed="):
				seed_arg = int(a.substr(7))
		world = WorldData.new(seed_arg)
	use_touch = DisplayServer.is_touchscreen_available() or "--touch" in args or OS.has_feature("mobile")
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--frames="):
			_shot_frames = int(a.substr(9))
		elif a.begins_with("--look="):          # --look=yaw,pitch in radians (for screenshots)
			var parts := a.substr(7).split(",")
			_initial_look = Vector2(float(parts[0]), float(parts[1]))

	var atlas: Texture2D = load("res://data/atlas.png")
	var solid := ShaderMaterial.new()
	solid.shader = load("res://shaders/block.gdshader")
	solid.set_shader_parameter("atlas", atlas)
	var glass := ShaderMaterial.new()
	glass.shader = load("res://shaders/block_alpha.gdshader")
	glass.set_shader_parameter("atlas", atlas)
	var water := glass.duplicate()
	water.set_shader_parameter("opacity", 0.72)
	var plants := solid.duplicate()
	materials = {"solid": solid, "translucent": glass, "water": water, "plants": plants}

	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = DAY_SKY
	we.environment = env
	add_child(we)
	sun = _sky_quad(Color(1, 0.95, 0.7), 40)
	moon = _sky_quad(Color(0.85, 0.88, 1), 25)

	chunks = ChunkManager.new()
	chunks.setup(world, materials, 3 if use_touch else 4)
	add_child(chunks)

	player = Player.new()
	player.world = world
	var start = world.player_data.get("position")
	player.position = Vector3(start[0], start[1], start[2]) if start is Array else world.spawn_point()
	player.set_physics_process(false)          # wait until the ground under us exists
	add_child(player)
	player.look(-_initial_look)

	highlight = _wire_cube()
	add_child(highlight)
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

	hud = Hud.new()
	hud.atlas = atlas
	add_child(hud)
	touch = TouchControls.new()
	var layer := CanvasLayer.new()
	layer.layer = 2
	layer.add_child(touch)
	add_child(layer)
	touch.visible = use_touch
	touch.place_pressed.connect(place_block)
	touch.hotbar_tapped.connect(func(pos): _select(hud.slot_at(pos)))
	touch.menu_pressed.connect(func(): save_game(); hud.flash("Saved"))
	_select(0)
	hud.flash("Welcome! %s" % ("Joystick left, drag right to look" if use_touch else "Click to play, WASD + mouse"))


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


func _wire_cube() -> MeshInstance3D:
	var verts := PackedVector3Array()
	var c := 0.502
	var corners := []
	for x in [-c, c]:
		for y in [-c, c]:
			for z in [-c, c]:
				corners.append(Vector3(x, y, z))
	for i in 8:
		for j in range(i + 1, 8):
			var d: Vector3 = corners[i] - corners[j]
			if absf(d.x) + absf(d.y) + absf(d.z) < 1.1:      # neighbours along one edge
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
	m.albedo_color = Color(0, 0, 0)
	mi.material_override = m
	mi.visible = false
	return mi


# ---------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if use_touch and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not use_touch:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				place_block()
			MOUSE_BUTTON_WHEEL_UP:
				_select(selected - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_select(selected + 1)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		player.look(event.relative * MOUSE_SENSITIVITY)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_F5:
				save_game()
				hud.flash("Saved")
			KEY_T:
				time_speed = 40.0 if time_speed == 1.0 else 1.0
				hud.flash("Time x%d" % int(time_speed))
			_:
				var n: int = event.physical_keycode - KEY_1
				if n >= 0 and n < 9:
					_select(n)


func _select(i: int) -> void:
	if i < 0 and i != -1:
		i = posmod(i, 9)
	if i == -1:
		return
	selected = posmod(i, 9)
	hud.show_hotbar(hotbar, selected)


func _read_controls() -> void:
	var move := Vector2.ZERO
	var jump := false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move = Vector2(
			float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_W)) - float(Input.is_physical_key_pressed(KEY_S)))
		jump = Input.is_physical_key_pressed(KEY_SPACE)
	if use_touch:
		if touch.move.length() > 0.05:
			move = touch.move
		jump = jump or touch.jump_held
		player.look(touch.take_look())
	player.move_input = move.limit_length(1.0)
	player.jump_held = jump


func _breaking() -> bool:
	return (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) \
		or (use_touch and touch.break_held)


# ---------------------------------------------------------------- building
func target(hit_water := false) -> Dictionary:
	return world.raycast(player.eye(), player.forward(), REACH, hit_water)


func edit(pos: Vector3i, id: int) -> bool:
	var keys := world.set_block(pos.x, pos.y, pos.z, id)
	chunks.rebuild(keys)
	# light reaches into the chunks around too
	var c := WorldData.chunk_key(pos.x, pos.z)
	var around := []
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			around.append(Vector2i(c.x + dx, c.y + dz))
	chunks.rebuild(around)
	return not keys.is_empty()


func place_block() -> void:
	var hit := target()
	if hit.is_empty():
		return
	var pos: Vector3i = hit["pos"] + hit["normal"]
	var item: int = hotbar[selected]
	if world.get_block(pos.x, pos.y, pos.z) not in [0, WorldData.WATER, 51, 52]:
		return
	var feet := Vector3i(floori(player.position.x + 0.5), floori(player.position.y + 0.5), floori(player.position.z + 0.5))
	if Blocks.solid[item] and pos.x == feet.x and pos.z == feet.z and pos.y in [feet.y, feet.y + 1]:
		return                                   # don't build inside yourself
	edit(pos, item)


func _update_mining(delta: float) -> void:
	var hit := target() if spawned else {}
	highlight.visible = not hit.is_empty()
	if hit.is_empty():
		mine_pos = null
		crack.visible = false
		return
	var pos: Vector3i = hit["pos"]
	highlight.position = Vector3(pos)
	var id := world.get_block(pos.x, pos.y, pos.z)
	if _breaking() and Blocks.hardness[id] >= 0:
		if mine_pos != pos:
			mine_pos = pos
			mine_progress = 0.0
		mine_progress += delta / maxf(Blocks.hardness[id] * 1.5, 0.05)
		if mine_progress >= 1.0:
			edit(pos, 0)
			mine_pos = null
			mine_progress = 0.0
	else:
		mine_pos = null
		mine_progress = 0.0
	crack.visible = mine_pos != null and mine_progress > 0
	if crack.visible:
		crack.position = Vector3(pos)
		crack.material_override.albedo_texture = crack_textures[mini(int(mine_progress * 6), 5)]


# ---------------------------------------------------------------- day and night
func _update_sky(delta: float) -> void:
	world.time_of_day = fposmod(world.time_of_day + delta * time_speed / DAY_LENGTH, 1.0)
	var angle := world.time_of_day * TAU
	var sun_height := sin(angle)
	var day := clampf((sun_height + 0.15) / 0.45, 0, 1)
	var dusk := clampf(1 - absf(sun_height) / 0.35, 0, 1)
	var sky := NIGHT_SKY.lerp(DAY_SKY, day).lerp(DUSK_SKY, dusk * 0.7 * maxf(day, 0.5))
	env.background_color = sky
	var daylight := 0.16 + 0.84 * day
	var tint := Vector3(0.65, 0.75, 1.0).lerp(Vector3.ONE, day).lerp(Vector3(1.0, 0.78, 0.6), dusk * 0.5)
	for m in materials.values():
		m.set_shader_parameter("daylight", daylight)
		m.set_shader_parameter("sky_tint", Color(tint.x, tint.y, tint.z))
	# the world is mirrored compared to the Python version's left-handed axes, so z flips here
	var dir := Vector3(cos(angle), sun_height, -0.3).normalized()
	sun.global_position = player.eye() + dir * 300
	moon.global_position = player.eye() - dir * 300
	var hours := fposmod(world.time_of_day * 24 + 6, 24)
	hud.clock.text = "%02d:%02d" % [int(hours), int(fmod(hours, 1.0) * 60)]


# ---------------------------------------------------------------- main loop
func _process(delta: float) -> void:
	chunks.update_center(player.position)
	if not spawned and chunks.is_ready_at(player.position):
		spawned = true
		player.set_physics_process(true)
	touch.hotbar_rect = hud.hotbar_rect()
	_read_controls()
	_update_mining(delta)
	_update_sky(delta)
	if "--selftest" in OS.get_cmdline_user_args() and spawned:
		_selftest_step()
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
	var data: Dictionary = world.player_data.duplicate()
	data["position"] = [player.position.x, player.position.y + 0.1, player.position.z]
	world.save(SAVE_PATH, data)


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


## Drives the game with real touch events and prints what happened.
func _selftest_step() -> void:
	_st_frame += 1
	var s := get_viewport().get_visible_rect().size
	match _st_frame:
		5:
			_st["start"] = player.position
			_touch(0, Vector2(200, s.y - 200), true)              # joystick finger down
			_drag(0, Vector2(200, s.y - 290), Vector2(0, -90))    # push forward
		60:
			_touch(0, Vector2(200, s.y - 290), false)
			print("SELFTEST walked: ", snappedf(_st["start"].distance_to(player.position), 0.1), " blocks")
		90:
			var b: Panel = touch._buttons["jump"]
			_st["y"] = player.position.y
			_st["floor"] = player.is_on_floor()
			_touch(1, b.position + b.size / 2, true)
		96:
			print("SELFTEST jump rose: ", player.position.y > _st["y"] + 0.3, " (was on floor: ", _st["floor"], ")")
			var b: Panel = touch._buttons["jump"]
			_touch(1, b.position + b.size / 2, false)
		130:
			var r := hud.hotbar_rect()
			_touch(2, r.position + Vector2(3.5 * (Hud.SLOT + 4), Hud.SLOT / 2), true)
			_touch(2, r.position + Vector2(3.5 * (Hud.SLOT + 4), Hud.SLOT / 2), false)
		132:
			print("SELFTEST hotbar slot selected: ", selected, " (", Blocks.name_of[hotbar[selected]], ")")
			player.look(Vector2(0, 0.9))                              # look down at the ground
		135:
			var hit := target()
			_st["placed_at"] = hit["pos"] + hit["normal"] if not hit.is_empty() else null
			var b: Panel = touch._buttons["place"]
			_touch(3, b.position + b.size / 2, true)
			_touch(3, b.position + b.size / 2, false)
		137:
			var p = _st["placed_at"]
			print("SELFTEST placed: ", p != null and world.get_block(p.x, p.y, p.z) == hotbar[selected])
			var b: Panel = touch._buttons["break"]
			_touch(4, b.position + b.size / 2, true)
		400:
			var b: Panel = touch._buttons["break"]
			_touch(4, b.position + b.size / 2, false)
			var p = _st["placed_at"]
			print("SELFTEST broken by holding BREAK: ", world.get_block(p.x, p.y, p.z) == 0)
			get_tree().quit()
