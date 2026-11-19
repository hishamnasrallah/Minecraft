class_name ChatBox
extends PanelContainer
## Typing to friends: a line to write in, a send button, and who is in the world.
## The messages themselves are shown by the HUD (they fade after a while).

signal closed

var _input: LineEdit
var _players: Label


func _ready() -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.08, 0.09, 0.12, 0.92)
	st.set_corner_radius_all(10)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		st.set_content_margin(side, 10)
	add_theme_stylebox_override("panel", st)
	var box := VBoxContainer.new()
	if I18n.is_arabic():
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL
	add_child(box)
	_players = Label.new()
	_players.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_players)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_input = LineEdit.new()
	_input.placeholder_text = I18n.t("chat_hint")
	_input.custom_minimum_size = Vector2(420, 50)
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.max_length = 160
	_input.text_submitted.connect(func(_t): _send())
	row.add_child(_input)
	var send := Button.new()
	send.text = I18n.t("send")
	send.custom_minimum_size = Vector2(100, 50)
	send.pressed.connect(_send)
	row.add_child(send)
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(50, 50)
	close.pressed.connect(func(): visible = false; closed.emit())
	row.add_child(close)
	visible = false


func open() -> void:
	_players.text = I18n.f("in_world", "، ".join(Net.player_names()) if I18n.is_arabic() else ", ".join(Net.player_names()))
	visible = true
	var s := get_viewport_rect().size
	size = Vector2(minf(700, s.x - 40), 0)
	position = Vector2((s.x - size.x) / 2, 70)
	_input.grab_focus()


func _send() -> void:
	Net.say(_input.text)
	_input.text = ""
	visible = false
	closed.emit()
