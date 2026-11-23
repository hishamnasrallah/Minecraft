class_name SettingsScreen
extends Control
## Language, look sensitivity, view distance and the FPS counter. Saved in user://settings.json.

signal closed
signal language_picked(code: String)
signal view_distance_changed(value: int)
signal far_distance_changed(value: int)
signal max_fps_changed(value: int)
signal exit_pressed
signal tutorial_pressed
signal touch_buttons_changed(on: bool)
signal host_pressed

var in_game := false             # shows "save and go to the menu"

var _dim: ColorRect
var _panel: PanelContainer
var _sens_label: Label
var _dist_label: Label
var _far_label: Label
var _fps_label: Label
const FPS_STEPS := [0, 60, 40, 30]         # 0 = no limit; 60, 40 and 30 divide a 120 Hz screen evenly
var _scroll: ScrollContainer
var _box: VBoxContainer
var _log_panel: PanelContainer
var _log_text: TextEdit


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	_panel.add_theme_stylebox_override("panel", _style())
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_scroll)
	var box := VBoxContainer.new()
	_box = box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	if I18n.is_arabic():
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL    # only the content: our own positions stay put
	_scroll.add_child(box)
	var title := Label.new()
	title.text = I18n.t("settings")
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)

	box.add_child(_caption(I18n.t("language"), "language"))
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 10)
	box.add_child(langs)
	for l in [["ar", "عربي"], ["en", "English"]]:
		var b := Button.new()
		b.text = l[1]
		b.toggle_mode = true
		b.button_pressed = I18n.lang == l[0]
		b.custom_minimum_size = Vector2(200, 56)
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(func(): if I18n.lang != l[0]: language_picked.emit(l[0]))
		langs.add_child(b)

	_sens_label = _caption("", "")
	box.add_child(_sens_label)
	var sens := HSlider.new()
	sens.min_value = 0.3
	sens.max_value = 3.0
	sens.step = 0.1
	sens.value = float(I18n.settings["sensitivity"])
	sens.custom_minimum_size.y = 40
	sens.value_changed.connect(func(v): I18n.settings["sensitivity"] = v; _update_labels())
	box.add_child(sens)

	_dist_label = _caption("", "")
	box.add_child(_dist_label)
	var dist := HSlider.new()
	dist.min_value = 2
	dist.max_value = 12
	dist.step = 1
	dist.value = float(I18n.settings["view_distance"]) if int(I18n.settings["view_distance"]) > 0 else float(Main.default_view_distance())
	dist.custom_minimum_size.y = 40
	dist.value_changed.connect(func(v): I18n.settings["view_distance"] = int(v); _update_labels(); view_distance_changed.emit(int(v)))
	box.add_child(dist)

	# the far land: mountains and seas drawn lightly beyond the loaded chunks (0 = off)
	_far_label = _caption("", "")
	box.add_child(_far_label)
	var far := HSlider.new()
	far.min_value = 0
	far.max_value = 1024
	far.step = 128
	far.value = float(I18n.settings.get("far_distance", 512))
	far.custom_minimum_size.y = 40
	far.value_changed.connect(func(v): I18n.settings["far_distance"] = int(v); _update_labels(); far_distance_changed.emit(int(v)))
	box.add_child(far)

	# frame limit: fewer frames keep the device cooler and leave more time for loading the land
	_fps_label = _caption("", "")
	box.add_child(_fps_label)
	var cap := HSlider.new()
	cap.min_value = 0
	cap.max_value = FPS_STEPS.size() - 1
	cap.step = 1
	cap.value = float(maxi(0, FPS_STEPS.find(int(I18n.settings.get("max_fps", 60)))))
	cap.custom_minimum_size.y = 40
	cap.value_changed.connect(func(v): I18n.settings["max_fps"] = int(FPS_STEPS[int(v)]); _update_labels(); max_fps_changed.emit(int(FPS_STEPS[int(v)])))
	box.add_child(cap)

	var sound_label := _caption(I18n.t("sound"), "")
	box.add_child(sound_label)
	var sound := HSlider.new()
	sound.min_value = 0.0
	sound.max_value = 1.0
	sound.step = 0.05
	sound.value = float(I18n.settings.get("sound", 0.8))
	sound.custom_minimum_size.y = 40
	sound.value_changed.connect(func(v): I18n.settings["sound"] = v; Sfx.apply_volume())
	sound.drag_ended.connect(func(_c): Sfx.play("pop"))
	box.add_child(sound)

	var name_row := HBoxContainer.new()
	box.add_child(name_row)
	var name_label := _caption(I18n.t("your_name"), "")
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.text = Net._my_name()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.max_length = 20
	name_edit.custom_minimum_size.y = 46
	name_edit.text_changed.connect(func(t): I18n.settings["player_name"] = t.strip_edges())
	name_row.add_child(name_edit)

	var monsters := CheckButton.new()
	monsters.text = I18n.t("monsters")
	monsters.button_pressed = bool(I18n.settings.get("monsters", true))
	monsters.toggled.connect(func(on): I18n.settings["monsters"] = on)
	box.add_child(monsters)

	var buttons := CheckButton.new()
	buttons.text = I18n.t("touch_buttons")
	buttons.button_pressed = bool(I18n.settings.get("touch_buttons", false))
	buttons.toggled.connect(func(on): I18n.settings["touch_buttons"] = on; touch_buttons_changed.emit(on))
	box.add_child(buttons)

	var vib := CheckButton.new()
	vib.text = I18n.t("vibrate")
	vib.button_pressed = bool(I18n.settings.get("vibrate", true))
	vib.toggled.connect(func(on): I18n.settings["vibrate"] = on)
	box.add_child(vib)

	var map := CheckButton.new()
	map.text = I18n.t("show_map")
	map.button_pressed = bool(I18n.settings.get("show_map", true))
	map.toggled.connect(func(on): I18n.settings["show_map"] = on)
	box.add_child(map)

	var fps := CheckButton.new()
	fps.text = I18n.t("show_fps")
	fps.button_pressed = bool(I18n.settings["show_fps"])
	fps.toggled.connect(func(on): I18n.settings["show_fps"] = on)
	box.add_child(fps)

	var safe := CheckButton.new()
	safe.text = I18n.t("safe_mode")
	safe.button_pressed = Boot.safe_mode
	safe.toggled.connect(func(on): Boot.set_safe_mode(on))
	box.add_child(safe)

	if in_game:
		var host := Button.new()
		host.text = I18n.t("open_to_friends") if not Net.active() else I18n.f("hosting", ", ".join(Net.local_ips()))
		host.icon = load("res://data/ui/language.png")
		host.add_theme_constant_override("icon_max_width", 26)
		host.custom_minimum_size = Vector2(0, 50)
		host.disabled = Net.active()
		host.pressed.connect(func(): host_pressed.emit())
		box.add_child(host)
		var tut := Button.new()
		tut.text = I18n.t("tut_again")
		tut.icon = load("res://data/ui/items.png")
		tut.add_theme_constant_override("icon_max_width", 26)
		tut.custom_minimum_size = Vector2(0, 50)
		tut.pressed.connect(func(): I18n.save_settings(); tutorial_pressed.emit())
		box.add_child(tut)
		var exit := Button.new()
		exit.text = I18n.t("exit_to_menu")
		exit.icon = load("res://data/ui/save.png")
		exit.add_theme_constant_override("icon_max_width", 26)
		exit.custom_minimum_size = Vector2(0, 50)
		exit.pressed.connect(func(): I18n.save_settings(); exit_pressed.emit())
		box.add_child(exit)

	var log_button := Button.new()
	log_button.text = I18n.t("show_log")
	log_button.icon = load("res://data/ui/library.png")
	log_button.add_theme_constant_override("icon_max_width", 26)
	log_button.custom_minimum_size = Vector2(0, 50)
	log_button.pressed.connect(_open_log)
	box.add_child(log_button)

	var done := Button.new()
	done.text = I18n.t("done")
	done.custom_minimum_size = Vector2(0, 50)
	done.pressed.connect(func(): I18n.save_settings(); closed.emit())
	box.add_child(done)
	_update_labels()
	for c in box.get_children():
		if c is CheckButton:
			SettingsScreen.style_switch(c)
	_build_log_panel()
	get_viewport().size_changed.connect(_layout)
	_layout()


static var _switch_on: Texture2D
static var _switch_off: Texture2D


## A clear switch: green with the knob on the right = on, grey with the knob on the left = off.
static func _switch_texture(on: bool) -> Texture2D:
	var w := 60
	var h := 32
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := Color(0.25, 0.75, 0.4) if on else Color(0.42, 0.44, 0.5)
	var r := h / 2.0
	var knob_x := w - r if on else r
	for x in w:
		for y in h:
			var cx := clampf(x + 0.5, r, w - r)
			var d := Vector2(x + 0.5 - cx, y + 0.5 - r).length()
			if d <= r:
				img.set_pixel(x, y, track)
			var dk := Vector2(x + 0.5 - knob_x, y + 0.5 - r).length()
			if dk <= r - 3:
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


static func style_switch(b: CheckButton) -> void:
	if _switch_on == null:
		_switch_on = _switch_texture(true)
		_switch_off = _switch_texture(false)
	for name in ["checked", "checked_mirrored"]:
		b.add_theme_icon_override(name, _switch_on)
	for name in ["unchecked", "unchecked_mirrored"]:
		b.add_theme_icon_override(name, _switch_off)
	b.custom_minimum_size.y = 46


func _style() -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.1, 0.11, 0.13, 0.97)
	st.set_corner_radius_all(10)
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		st.set_content_margin(side, 14)
	return st


func _caption(text: String, icon: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l


func _update_labels() -> void:
	_sens_label.text = "%s: %.1f" % [I18n.t("sensitivity"), float(I18n.settings["sensitivity"])]
	var d := int(I18n.settings["view_distance"])
	_dist_label.text = "%s: %d" % [I18n.t("view_distance"), d if d > 0 else Main.default_view_distance()]
	var fd := int(I18n.settings.get("far_distance", 512))
	_far_label.text = "%s: %s" % [I18n.t("far_distance"), I18n.t("off") if fd <= 0 else I18n.f("blocks_n", fd)]
	var mf := int(I18n.settings.get("max_fps", 60))
	_fps_label.text = "%s: %s" % [I18n.t("max_fps"), I18n.t("no_limit") if mf <= 0 else str(mf)]


func _layout() -> void:
	var s := get_viewport_rect().size
	size = s
	_dim.size = s
	var want := _box.get_combined_minimum_size()
	_scroll.custom_minimum_size = Vector2(want.x + 12, minf(want.y, s.y - 60))
	_panel.size = Vector2.ZERO
	_panel.position = (s - _panel.get_combined_minimum_size()) / 2
	if _log_panel:
		_log_panel.position = Vector2(20, 20)
		_log_panel.size = s - Vector2(40, 40)


# ---------------------------------------------------------------- the log, to send to the developer
## The game's log (user://logs/godot.log) plus the startup black box, in a box you can copy.
func _build_log_panel() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.visible = false
	_log_panel.add_theme_stylebox_override("panel", _style())
	add_child(_log_panel)
	var v := VBoxContainer.new()
	_log_panel.add_child(v)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var title := Label.new()
	title.text = I18n.t("show_log")
	title.add_theme_font_size_override("font_size", 22)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var copy := Button.new()
	copy.text = I18n.t("copy_log")
	copy.icon = load("res://data/ui/copy.png")
	copy.add_theme_constant_override("icon_max_width", 24)
	copy.custom_minimum_size = Vector2(150, 48)
	copy.pressed.connect(func(): DisplayServer.clipboard_set(_log_text.text); copy.text = I18n.t("log_copied"))
	row.add_child(copy)
	var back := Button.new()
	back.text = I18n.t("done")
	back.custom_minimum_size = Vector2(110, 48)
	back.pressed.connect(func(): _log_panel.visible = false; _panel.visible = true)
	row.add_child(back)
	_log_text = TextEdit.new()
	_log_text.editable = false
	_log_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_text.add_theme_font_size_override("font_size", 14)
	_log_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_log_text.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v.add_child(_log_text)


func _open_log() -> void:
	_log_text.text = SettingsScreen.log_report()
	_panel.visible = false
	_log_panel.visible = true
	_layout()
	_log_text.set_caret_line(_log_text.get_line_count())
	_log_text.scroll_vertical = _log_text.get_line_count()


static func log_report() -> String:
	var out := "BlockWorld | %s %s | %s | %s | cores %d | %s\n" % [OS.get_name(), OS.get_version(), OS.get_model_name(),
		RenderingServer.get_video_adapter_name(), OS.get_processor_count(), Time.get_datetime_string_from_system()]
	out += "boot: last stage '%s', crashed last time: %s, safe mode: %s\n" % [Boot.last_stage, Boot.crashed_last_time, Boot.safe_mode]
	var lines := []
	var dir := DirAccess.open("user://logs")
	if dir:
		var files := Array(dir.get_files()).filter(func(f): return f.ends_with(".log"))
		files.sort()
		# the newest log is godot.log; the previous runs are kept with a date in their name
		var order := files.filter(func(f): return f != "godot.log")
		if files.has("godot.log"):
			order.append("godot.log")
		for f in order.slice(maxi(0, order.size() - 2)):
			lines.append("===== " + f)
			lines.append_array(FileAccess.get_file_as_string("user://logs/" + f).split("\n"))
	else:
		lines.append("(no log files)")
	return out + "\n".join(lines.slice(maxi(0, lines.size() - 400)))
