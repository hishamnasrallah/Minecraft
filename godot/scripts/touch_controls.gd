class_name TouchControls
extends Control
## Phone controls, all multi-touch:
##  - left side: a joystick appears where the finger lands (move)
##  - right side: drag to look around; a tap places / uses / hits what the crosshair points
##    at, pressing and holding breaks it (keep dragging to sweep along)
##  - buttons: jump, items, ...; the old break / place buttons are an option in the settings
##  - taps on the hotbar are passed to the HUD
## Every finger is tracked by its index, so you can walk, look and press buttons at once.

signal place_pressed
signal world_tapped(position: Vector2)
signal hotbar_tapped(position: Vector2)
signal map_tapped
signal menu_pressed
signal inventory_pressed
signal fly_pressed
signal build_pressed
signal settings_pressed
signal chat_pressed

const JOY_RADIUS := 90.0
const LOOK_SENSITIVITY := 0.006
const HOLD_TIME := 0.32               # seconds a still finger needs to start breaking / placing
const TAP_SLOP := 30.0                # how far a finger may wander and still count as a tap
                                      # (fingers on big tablets wobble more than you think)

var move := Vector2.ZERO
var look_delta := Vector2.ZERO        # accumulated, read and cleared by the game every frame
var jump_held := false
var break_held := false
var up_held := false
var down_held := false
var map_rect := Rect2()               # the small map: a tap opens the big one
var hotbar_rect := Rect2()            # set by the HUD so taps there select a slot
var aim_point := Vector2.ZERO         # where a held finger points (valid while aiming)
var aiming := false                   # a finger is held on the world: break there
var classic := false                  # show the break / place buttons instead of tap-to-act
var _look_start := Vector2.ZERO
var _look_time := 0.0
var _look_moved := false

var _joy_finger := -1
var _joy_center := Vector2.ZERO
var _look_finger := -1
var _buttons := {}                    # name -> Panel
var _button_fingers := {}             # finger index -> button name
var _joy_base: Panel
var _joy_knob: Panel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_joy_base = _circle(JOY_RADIUS * 2, Color(1, 1, 1, 0.12))
	_joy_knob = _circle(JOY_RADIUS * 0.9, Color(1, 1, 1, 0.3))
	_joy_base.visible = false
	_joy_knob.visible = false
	# name, icon, label key, position (from the bottom-right / top-right corner), size
	_add_button("jump", "jump", "btn_jump", Vector2(-150, -170), 120)
	_add_button("break", "break", "btn_break", Vector2(-290, -120), 110)
	_add_button("place", "place", "btn_place", Vector2(-150, -300), 110)
	_add_button("inventory", "items", "btn_items", Vector2(-300, -330), 90)
	_add_button("up", "up", "btn_up", Vector2(-290, -250), 80)
	_add_button("down", "down", "btn_down", Vector2(-290, -40), 80)
	_add_button("menu", "save", "btn_save", Vector2(-80, 50), 72, true)
	_add_button("settings", "settings", "btn_settings", Vector2(-170, 50), 72, true)
	_add_button("fly", "fly", "btn_fly", Vector2(-80, 140), 72, true)
	_add_button("build", "build", "btn_build", Vector2(-80, 230), 72, true)
	_add_button("chat", "chat", "btn_chat", Vector2(-260, 50), 72, true)
	show_button("up", false)
	show_button("down", false)
	show_button("chat", false)
	set_classic(bool(I18n.settings.get("touch_buttons", false)))
	get_viewport().size_changed.connect(_layout)
	_layout()


func _circle(size: float, color: Color) -> Panel:
	var p := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(size / 2))
	p.add_theme_stylebox_override("panel", style)
	p.size = Vector2(size, size)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	return p


func _add_button(name: String, icon: String, label_key: String, offset: Vector2, size: float, top := false) -> void:
	var p := _circle(size, Color(1, 1, 1, 0.18))
	p.set_meta("offset", offset)
	p.set_meta("top", top)
	var tex := TextureRect.new()
	tex.texture = load("res://data/ui/%s.png" % icon)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.size = Vector2(size, size) * 0.42
	tex.position = Vector2(size * 0.29, size * 0.14)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tex)
	var label := Label.new()
	label.text = I18n.t(label_key)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, size * 0.56)
	label.size = Vector2(size, size * 0.3)
	label.add_theme_font_size_override("font_size", maxi(12, int(size / 6.5)))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label)
	_buttons[name] = p


func _layout() -> void:
	var s := get_viewport_rect().size
	for name in _buttons:
		var p: Panel = _buttons[name]
		var o: Vector2 = p.get_meta("offset")
		p.position = Vector2(s.x + o.x - p.size.x / 2, (o.y if p.get_meta("top") else s.y + o.y) - p.size.y / 2)


func show_button(name: String, on: bool) -> void:
	_buttons[name].visible = on


func set_classic(on: bool) -> void:
	classic = on
	show_button("break", on)
	show_button("place", on)


func _process(delta: float) -> void:
	if _look_finger == -1:
		return
	_look_time += delta
	if not classic and not _look_moved and not aiming and _look_time >= HOLD_TIME:
		aiming = true
		aim_point = _look_start


func _end_look() -> void:
	_look_finger = -1
	aiming = false


func _button_at(pos: Vector2) -> String:
	for name in _buttons:
		var p: Panel = _buttons[name]
		if not p.visible:
			continue
		if pos.distance_to(p.position + p.size / 2) <= p.size.x / 2 + 10:
			return name
	return ""


func _set_button(name: String, down: bool) -> void:
	_buttons[name].modulate = Color(1.6, 1.6, 1.6) if down else Color.WHITE
	match name:
		"jump":
			jump_held = down
		"break":
			break_held = down
		"place":
			if down:
				place_pressed.emit()
		"menu":
			if down:
				menu_pressed.emit()
		"inventory":
			if down:
				inventory_pressed.emit()
		"fly":
			if down:
				fly_pressed.emit()
		"build":
			if down:
				build_pressed.emit()
		"settings":
			if down:
				settings_pressed.emit()
		"chat":
			if down:
				chat_pressed.emit()
		"up":
			up_held = down
		"down":
			down_held = down


var blocked := false:       # true while a full-screen menu is open: let the menu have the touches
	set(v):
		blocked = v
		if v:
			release_all()


## Forget every finger (a menu opened or the controls were hidden while touched): their
## "lift" would never reach us, and the player would keep walking or breaking by itself.
func release_all() -> void:
	move = Vector2.ZERO
	_joy_finger = -1
	if _joy_base != null:
		_joy_base.visible = false
	_end_look()
	for f in _button_fingers:
		_set_button(_button_fingers[f], false)
	_button_fingers.clear()
	jump_held = false
	break_held = false
	up_held = false
	down_held = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()
var ui_rects: Array = []    # other on-screen controls (e.g. the build buttons) that keep their touches


func _input(event: InputEvent) -> void:
	if not visible or blocked:
		return
	if event is InputEventScreenTouch and event.pressed:
		for r in ui_rects:
			if r.has_point(event.position):
				return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			var b := _button_at(pos)
			if b != "":
				_button_fingers[event.index] = b
				_set_button(b, true)
			elif hotbar_rect.has_point(pos):
				hotbar_tapped.emit(pos)
			elif map_rect.has_point(pos):
				map_tapped.emit()
			elif pos.x < get_viewport_rect().size.x * 0.4 and _joy_finger == -1:
				_joy_finger = event.index
				_joy_center = pos
				_joy_base.position = pos - _joy_base.size / 2
				_joy_knob.position = pos - _joy_knob.size / 2
				_joy_base.visible = true
				_joy_knob.visible = true
			elif _look_finger == -1:
				_look_finger = event.index
				_look_start = pos
				_look_time = 0.0
				_look_moved = false
				aiming = false
		else:
			if _button_fingers.has(event.index):
				_set_button(_button_fingers[event.index], false)
				_button_fingers.erase(event.index)
			if event.index == _joy_finger:
				_joy_finger = -1
				move = Vector2.ZERO
				_joy_base.visible = false
				_joy_knob.visible = false
			if event.index == _look_finger:
				if "--walkplace" in OS.get_cmdline_user_args():
					print("RELEASE look finger moved=%s aiming=%s time=%.2f" % [_look_moved, aiming, _look_time])
				if not classic and not aiming and not _look_moved and _look_time < HOLD_TIME:
					world_tapped.emit(pos)
				_end_look()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			var offset: Vector2 = (event.position - _joy_center).limit_length(JOY_RADIUS)
			_joy_knob.position = _joy_center + offset - _joy_knob.size / 2
			move = Vector2(offset.x, -offset.y) / JOY_RADIUS
		elif event.index == _look_finger:
			# breaking or not, dragging turns the view (the crosshair is what you aim with)
			if event.position.distance_to(_look_start) > TAP_SLOP:
				_look_moved = true
			if _look_moved or aiming:
				look_delta += event.relative * LOOK_SENSITIVITY
		get_viewport().set_input_as_handled()


func take_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
