class_name SettingsScreen
extends Control
## Language, look sensitivity, view distance and the FPS counter. Saved in user://settings.json.

signal closed
signal language_picked(code: String)
signal view_distance_changed(value: int)
signal exit_pressed
signal tutorial_pressed

var in_game := false             # shows "save and go to the menu"

var _dim: ColorRect
var _panel: PanelContainer
var _sens_label: Label
var _dist_label: Label


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(560, 0)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	if I18n.is_arabic():
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL    # only the content: our own positions stay put
	_panel.add_child(box)
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
	dist.max_value = 6
	dist.step = 1
	dist.value = float(I18n.settings["view_distance"]) if int(I18n.settings["view_distance"]) > 0 else 3.0
	dist.custom_minimum_size.y = 40
	dist.value_changed.connect(func(v): I18n.settings["view_distance"] = int(v); _update_labels(); view_distance_changed.emit(int(v)))
	box.add_child(dist)

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

	var monsters := CheckBox.new()
	monsters.text = I18n.t("monsters")
	monsters.button_pressed = bool(I18n.settings.get("monsters", true))
	monsters.toggled.connect(func(on): I18n.settings["monsters"] = on)
	box.add_child(monsters)

	var fps := CheckBox.new()
	fps.text = I18n.t("show_fps")
	fps.button_pressed = bool(I18n.settings["show_fps"])
	fps.toggled.connect(func(on): I18n.settings["show_fps"] = on)
	box.add_child(fps)

	var safe := CheckBox.new()
	safe.text = I18n.t("safe_mode")
	safe.button_pressed = Boot.safe_mode
	safe.toggled.connect(func(on): Boot.set_safe_mode(on))
	box.add_child(safe)

	if in_game:
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

	var done := Button.new()
	done.text = I18n.t("done")
	done.custom_minimum_size = Vector2(0, 50)
	done.pressed.connect(func(): I18n.save_settings(); closed.emit())
	box.add_child(done)
	_update_labels()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _caption(text: String, icon: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	return l


func _update_labels() -> void:
	_sens_label.text = "%s: %.1f" % [I18n.t("sensitivity"), float(I18n.settings["sensitivity"])]
	var d := int(I18n.settings["view_distance"])
	_dist_label.text = "%s: %d" % [I18n.t("view_distance"), d if d > 0 else 3]


func _layout() -> void:
	var s := get_viewport_rect().size
	size = s
	_dim.size = s
	_panel.position = s / 2 - _panel.get_combined_minimum_size() / 2
