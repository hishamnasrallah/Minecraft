class_name MachinePanel
extends Control
## A small panel that opens when you tap a machine: change a gate's kind (NOT / AND / OR /
## XOR / wait), how long a wait gate waits, or turn the machine to face another way.
## A tap outside it, or Back, closes it. The game applies the choices (signal `chosen`).

signal chosen(action: String, value: int)
signal closed

const GATES := ["not", "and", "or", "xor", "delay"]
const DELAYS := [1, 3, 5, 10]            # ticks of 0.1 s

var _box: PanelContainer
var _list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP           # a tap outside the panel closes it
	visible = false
	gui_input.connect(func(e):
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed:
			close())
	_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2)
	_box.add_theme_stylebox_override("panel", sb)
	add_child(_box)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	_box.add_child(_list)


var _mode := "compare"


func open(kind: String, id: int, delay: int, mode := "compare") -> void:
	_mode = mode
	for c in _list.get_children():
		_list.remove_child(c)                       # gone now, not at the end of the frame
		c.queue_free()
	var title := Label.new()
	title.text = Items.name_of(id)
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(title)
	var hint := Label.new()
	hint.text = I18n.t("hint_" + kind)
	hint.add_theme_font_size_override("font_size", 17)
	hint.modulate = Color(1, 1, 1, 0.75)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.add_child(hint)
	if kind in GATES:
		var row := _row(I18n.t("panel_kind"))
		for g in GATES.size():
			var b := _button(I18n.t("gate_short_" + GATES[g]), GATES[g] == kind)
			b.pressed.connect(func(): chosen.emit("kind", g))
			row.add_child(b)
	if kind == "comparator":
		var row := _row(I18n.t("panel_mode"))
		var modes := ["compare", "subtract"]
		for m in modes.size():
			var b := _button(I18n.t("mode_" + modes[m]), modes[m] == _mode)
			b.pressed.connect(func(): chosen.emit("mode", m))
			row.add_child(b)
	if kind == "delay":
		var row := _row(I18n.t("panel_wait"))
		for t in DELAYS:
			var b := _button(I18n.f("seconds", "%.1f" % (t / 10.0)), t == delay)
			b.pressed.connect(func(): chosen.emit("delay", t))
			row.add_child(b)
	var turn := _button("↻  " + I18n.t("panel_turn"), false)
	turn.pressed.connect(func(): chosen.emit("turn", 0))
	_list.add_child(turn)
	var done := _button(I18n.t("done"), false)
	done.pressed.connect(close)
	_list.add_child(done)
	visible = true
	_place.call_deferred()


func _place() -> void:
	var s := get_viewport_rect().size
	_box.size = _box.get_combined_minimum_size()
	_box.position = Vector2(floorf((s.x - _box.size.x) / 2), maxf(10.0, s.y - _box.size.y - 110))


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _row(label: String) -> HBoxContainer:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if I18n.is_arabic() else HORIZONTAL_ALIGNMENT_LEFT
	_list.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list.add_child(row)
	return row


func _button(text: String, on: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(96, 56)
	b.add_theme_font_size_override("font_size", 19)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.25, 0.55, 0.3) if on else Color(0.2, 0.22, 0.27)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var pressed_sb := sb.duplicate()
	pressed_sb.bg_color = sb.bg_color.lightened(0.2)
	b.add_theme_stylebox_override("pressed", pressed_sb)
	return b
