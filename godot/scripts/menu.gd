extends Control
## Main menu: your worlds (play / delete) and creating a new one (name, seed, mode).
## With --new / --selftest / --shot on the command line it goes straight into a test world.

const GAME := "res://scenes/main.tscn"

var _list: VBoxContainer
var _name: LineEdit
var _seed: LineEdit
var _creative := false
var _mode_buttons := []
var _settings: SettingsScreen
var _confirm: ConfirmationDialog
var _pending_delete := ""
var _bg: ColorRect
var _content: HBoxContainer
var _title: Label
var _gear: Button


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--lang="):                 # testing: a language without saving it
			I18n.lang = a.substr(7)
	if "--new" in args or "--selftest" in args or Array(args).any(func(a): return a.begins_with("--shot=")):
		var seed := -1
		for a in args:
			if a.begins_with("--seed="):
				seed = int(a.substr(7))
		Session.use_test_world("--new" in args, seed, "--creative" in args)
		get_tree().change_scene_to_file.call_deferred(GAME)
		return
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	for a in args:
		if a.begins_with("--menushot="):           # testing: screenshot the menu, optionally create a world
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png(a.substr(11))
			print("menu worlds: ", Session.list_worlds().map(func(w): return [w["id"], w.get("name"), w.get("mode")]))
			if "--create" in args:
				_name.text = "Test valley"
				_creative = true
				_create()
				return
			get_tree().quit()


func _build() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.36, 0.55, 0.78)
	add_child(_bg)
	_title = Label.new()
	_title.text = I18n.t("title")
	_title.add_theme_font_size_override("font_size", 52)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_title.add_theme_constant_override("outline_size", 10)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	_gear = Button.new()
	_gear.icon = load("res://data/ui/settings.png")
	_gear.add_theme_constant_override("icon_max_width", 36)
	_gear.custom_minimum_size = Vector2(64, 64)
	_gear.pressed.connect(func(): _settings.visible = true)
	add_child(_gear)

	_content = HBoxContainer.new()
	_content.add_theme_constant_override("separation", 20)
	add_child(_content)

	var worlds := _panel(I18n.t("worlds"))
	_content.add_child(worlds)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	worlds.get_child(0).add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	var create := _panel(I18n.t("new_world"))
	_content.add_child(create)
	var box: VBoxContainer = create.get_child(0)
	_name = LineEdit.new()
	_name.placeholder_text = I18n.t("world_name")
	_name.custom_minimum_size.y = 54
	box.add_child(_name)
	_seed = LineEdit.new()
	_seed.placeholder_text = I18n.t("seed_hint")
	_seed.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_seed.custom_minimum_size.y = 54
	box.add_child(_seed)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	box.add_child(modes)
	for m in [[false, "survival", "break"], [true, "creative_mode", "fly"]]:
		var b := Button.new()
		b.text = I18n.t(m[1])
		b.icon = load("res://data/ui/%s.png" % m[2])
		b.add_theme_constant_override("icon_max_width", 30)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 60
		b.pressed.connect(func(): _creative = m[0]; _refresh_modes())
		modes.add_child(b)
		_mode_buttons.append(b)
	_refresh_modes()
	if I18n.is_arabic():
		_content.move_child(create, 0)            # right to left: your worlds on the right
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var go := Button.new()
	go.text = I18n.t("create")
	go.icon = load("res://data/ui/place.png")
	go.add_theme_constant_override("icon_max_width", 34)
	go.add_theme_font_size_override("font_size", 26)
	go.custom_minimum_size.y = 72
	go.pressed.connect(_create)
	box.add_child(go)

	_confirm = ConfirmationDialog.new()
	_confirm.ok_button_text = I18n.t("delete")
	_confirm.cancel_button_text = I18n.t("cancel")
	_confirm.confirmed.connect(func(): Session.delete_world(_pending_delete); _refresh())
	add_child(_confirm)

	var layer := CanvasLayer.new()
	layer.layer = 3
	add_child(layer)
	_settings = SettingsScreen.new()
	_settings.visible = false
	_settings.closed.connect(func(): _settings.visible = false)
	_settings.language_picked.connect(func(code): I18n.set_language(code); get_tree().reload_current_scene())
	layer.add_child(_settings)


func _panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	if I18n.is_arabic():
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL   # inside the panel only
	p.add_child(box)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)
	return p


func _layout() -> void:
	var s := get_viewport_rect().size
	position = Vector2.ZERO
	size = s
	_bg.size = s
	_title.position = Vector2(0, 14)
	_title.size = Vector2(s.x, 80)
	_gear.position = Vector2(s.x - 84, 20)
	_content.position = Vector2(30, 110)
	_content.size = Vector2(s.x - 60, s.y - 140)


func _refresh_modes() -> void:
	_mode_buttons[0].button_pressed = not _creative
	_mode_buttons[1].button_pressed = _creative


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var worlds := Session.list_worlds()
	_name.placeholder_text = I18n.f("my_world_n", worlds.size() + 1)
	if worlds.is_empty():
		var l := Label.new()
		l.text = I18n.t("no_worlds")
		_list.add_child(l)
	for w in worlds:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		var play := Button.new()
		play.text = "%s\n%s  -  %s" % [w.get("name", w["id"]), I18n.t("creative_mode") if w.get("mode") == "creative" else I18n.t("survival"), _when(w.get("last_played"))]
		play.icon = load("res://data/ui/%s.png" % ("fly" if w.get("mode") == "creative" else "break"))
		play.add_theme_constant_override("icon_max_width", 34)
		play.alignment = HORIZONTAL_ALIGNMENT_LEFT if not I18n.is_arabic() else HORIZONTAL_ALIGNMENT_RIGHT
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		play.custom_minimum_size.y = 76
		play.pressed.connect(func(): Session.open_world(w["id"]); get_tree().change_scene_to_file(GAME))
		row.add_child(play)
		var del := Button.new()
		del.icon = load("res://data/ui/trash.png")
		del.add_theme_constant_override("icon_max_width", 30)
		del.custom_minimum_size = Vector2(64, 76)
		del.pressed.connect(func():
			_pending_delete = w["id"]
			_confirm.dialog_text = I18n.f("delete_confirm", w.get("name", w["id"]))
			_confirm.popup_centered())
		row.add_child(del)


func _when(t) -> String:
	if t == null:
		return I18n.t("never_played")
	var days := int((Time.get_unix_time_from_system() - float(t)) / 86400.0)
	if days <= 0:
		return I18n.t("today")
	if days == 1:
		return I18n.t("yesterday")
	return I18n.f("days_ago", days)


func _create() -> void:
	var name := _name.text.strip_edges()
	if name == "":
		name = _name.placeholder_text
	var seed := int(_seed.text) if _seed.text.strip_edges().is_valid_int() else -1
	Session.create_world(name, seed, _creative)
	get_tree().change_scene_to_file(GAME)
