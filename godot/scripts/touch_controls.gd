class_name TouchControls
extends Control
## Phone controls, all multi-touch:
##  - left side: a joystick appears where the finger lands (move)
##  - right side: drag to look around
##  - buttons: jump, break (hold), place / use
##  - taps on the hotbar are passed to the HUD
## Every finger is tracked by its index, so you can walk, look and press buttons at once.

signal place_pressed
signal hotbar_tapped(position: Vector2)
signal menu_pressed

const JOY_RADIUS := 90.0
const LOOK_SENSITIVITY := 0.006

var move := Vector2.ZERO
var look_delta := Vector2.ZERO        # accumulated, read and cleared by the game every frame
var jump_held := false
var break_held := false
var hotbar_rect := Rect2()            # set by the HUD so taps there select a slot

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
	_add_button("jump", "JUMP", Vector2(-150, -170), 120)
	_add_button("break", "BREAK", Vector2(-290, -120), 110)
	_add_button("place", "PLACE", Vector2(-150, -300), 110)
	_add_button("menu", "II", Vector2(-80, 20), 60, true)
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


func _add_button(name: String, text: String, offset: Vector2, size: float, top := false) -> void:
	var p := _circle(size, Color(1, 1, 1, 0.18))
	p.set_meta("offset", offset)
	p.set_meta("top", top)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(size, size)
	label.add_theme_font_size_override("font_size", int(size / 5))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label)
	_buttons[name] = p


func _layout() -> void:
	var s := get_viewport_rect().size
	for name in _buttons:
		var p: Panel = _buttons[name]
		var o: Vector2 = p.get_meta("offset")
		p.position = Vector2(s.x + o.x - p.size.x / 2, (o.y if p.get_meta("top") else s.y + o.y) - p.size.y / 2)


func _button_at(pos: Vector2) -> String:
	for name in _buttons:
		var p: Panel = _buttons[name]
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


func _input(event: InputEvent) -> void:
	if not visible:
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
			elif pos.x < get_viewport_rect().size.x * 0.4 and _joy_finger == -1:
				_joy_finger = event.index
				_joy_center = pos
				_joy_base.position = pos - _joy_base.size / 2
				_joy_knob.position = pos - _joy_knob.size / 2
				_joy_base.visible = true
				_joy_knob.visible = true
			elif _look_finger == -1:
				_look_finger = event.index
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
				_look_finger = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == _joy_finger:
			var offset: Vector2 = (event.position - _joy_center).limit_length(JOY_RADIUS)
			_joy_knob.position = _joy_center + offset - _joy_knob.size / 2
			move = Vector2(offset.x, -offset.y) / JOY_RADIUS
		elif event.index == _look_finger:
			look_delta += event.relative * LOOK_SENSITIVITY
		get_viewport().set_input_as_handled()


func take_look() -> Vector2:
	var d := look_delta
	look_delta = Vector2.ZERO
	return d
