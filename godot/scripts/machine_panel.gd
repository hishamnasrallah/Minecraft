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


func open(kind: String, id: int, delay: int, mode := "compare", choices := [], current := 0) -> void:
	# built after the tap that asked for it is fully handled: removing a button while its press
	# is still being delivered makes Godot complain ("can_process ... !is_inside_tree")
	visible = true
	_open_now.call_deferred(kind, id, delay, mode, choices, current)


func _open_now(kind: String, id: int, delay: int, mode: String, choices: Array, current: int) -> void:
	if not visible:
		return                                      # closed again before it was built
	_mode = mode
	for c in _list.get_children():
		_list.remove_child(c)                       # gone now, not at the end of the frame
		c.queue_free()
	var title := Label.new()
	title.text = I18n.t(["job_farmer", "job_smith", "job_baker"][clampi(id, 0, 2)]) if kind == "trade" else Items.name_of(id)
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
	if kind in ["timer", "counter", "note"]:
		var label: String = {"timer": "panel_every", "counter": "panel_count", "note": "panel_note"}[kind]
		var row := _row(I18n.t(label))
		var opts: Array = {"timer": [0.5, 1.0, 2.0, 5.0, 10.0, 30.0], "counter": [2, 3, 4, 5, 8, 10],
			"note": [0, 2, 4, 5, 7, 9, 11, 12]}[kind]
		var names := ["Do", "Re", "Mi", "Fa", "Sol", "La", "Si", "Do+"]
		var scale := 10.0 if kind == "timer" else 1.0
		for i in opts.size():
			if i == 4:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				_list.add_child(row)
			var v: float = float(opts[i])
			var text := ""
			match kind:
				"timer":
					text = I18n.f("seconds", ("%.1f" % v) if v < 1.0 else str(int(v)))
				"counter":
					text = I18n.f("pulses", str(int(v)))
				"note":
					text = names[i]
			var b := _button(text, int(v * scale) == current)
			var val := int(v * scale)
			b.pressed.connect(func(): chosen.emit(kind, val))
			row.add_child(b)
		var done_s := _button(I18n.t("done"), false)
		done_s.pressed.connect(close)
		_list.add_child(done_s)
		visible = true
		_place.call_deferred()
		return
	if kind == "trade":
		# a worker's offers: one button each, greyed out when you cannot pay
		for i in choices.size():
			var o: Array = choices[i]
			var b := _button("%d %s  →  %d %s" % [o[1], Items.name_of(int(o[0])), o[3], Items.name_of(int(o[2]))], false)
			b.disabled = not bool(o[4])
			b.custom_minimum_size = Vector2(380, 52)
			b.pressed.connect(func(): chosen.emit("trade", i))
			_list.add_child(b)
		var done_t := _button(I18n.t("done"), false)
		done_t.pressed.connect(close)
		_list.add_child(done_t)
		visible = true
		_place.call_deferred()
		return
	if kind == "collector":
		# a filter: take everything, or only one thing
		var row := _row(I18n.t("panel_takes"))
		var any := _button(I18n.t("filter_any"), current == 0)
		any.pressed.connect(func(): chosen.emit("filter", 0))
		row.add_child(any)
		var shown := choices.duplicate()
		if current != 0 and not current in shown:
			shown.push_front(current)
		var n := 0
		for item in shown:
			if n == 4:
				row = HBoxContainer.new()
				row.add_theme_constant_override("separation", 8)
				_list.add_child(row)
			var b := _button(Items.name_of(int(item)), int(item) == current)
			b.pressed.connect(func(): chosen.emit("filter", int(item)))
			row.add_child(b)
			n += 1
		if shown.is_empty():
			var none := Label.new()
			none.text = I18n.t("filter_put_in")
			none.add_theme_font_size_override("font_size", 16)
			none.modulate = Color(1, 1, 1, 0.7)
			_list.add_child(none)
		var box := _button("📦  " + I18n.t("panel_open"), false)
		box.pressed.connect(func(): chosen.emit("open", 0))
		_list.add_child(box)
	elif kind == "crafter":
		# what it makes: by itself (food first), or one thing you pick from what is inside
		var row := _row(I18n.t("panel_makes"))
		var auto := _button(I18n.t("craft_auto"), current == 0)
		auto.pressed.connect(func(): chosen.emit("craft", 0))
		row.add_child(auto)
		var shown := choices.duplicate()
		if current != 0 and not current in shown:
			shown.push_front(current)
		var n := 0
		for item in shown:
			if n == 4:
				row = HBoxContainer.new()             # a second row for the rest
				row.add_theme_constant_override("separation", 8)
				_list.add_child(row)
			var b := _button(Items.name_of(int(item)), int(item) == current)
			b.pressed.connect(func(): chosen.emit("craft", int(item)))
			row.add_child(b)
			n += 1
		if shown.is_empty():
			var none := Label.new()
			none.text = I18n.t("craft_put_in")
			none.add_theme_font_size_override("font_size", 16)
			none.modulate = Color(1, 1, 1, 0.7)
			_list.add_child(none)
		var box := _button("📦  " + I18n.t("panel_open"), false)
		box.pressed.connect(func(): chosen.emit("open", 0))
		_list.add_child(box)
	else:
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
