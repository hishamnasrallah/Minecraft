class_name BuildPanel
extends Control
## Creative building tools as big buttons (they act on the block in the crosshair), and the
## schematics library: save the current copy as a file, load one to paste, or delete it.

signal action(name: String)

const TOOLS := ["corner1", "corner2", "fill", "hollow", "replace", "clear", "copy", "paste",
	"rotate", "mirror", "undo", "deselect", "library"]

var builder: Builder
var library: Control
var _name: LineEdit
var _list: VBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := GridContainer.new()
	column.columns = 2
	column.position = Vector2(12, 130)
	column.add_theme_constant_override("h_separation", 6)
	column.add_theme_constant_override("v_separation", 6)
	add_child(column)
	for t in TOOLS:
		var b := Button.new()
		b.text = I18n.t(t)
		b.icon = load("res://data/ui/%s.png" % t)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 26)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(132, 50)
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color(1, 1, 1, 0.88)
		b.pressed.connect(func(): action.emit(t))
		column.add_child(b)
	_make_library()


func _make_library() -> void:
	library = PanelContainer.new()
	library.set_anchors_preset(Control.PRESET_CENTER)
	library.custom_minimum_size = Vector2(760, 560)
	library.visible = false
	add_child(library)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	if I18n.is_arabic():
		box.layout_direction = Control.LAYOUT_DIRECTION_RTL
	library.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = I18n.t("buildings")
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = I18n.t("close")
	close.icon = load("res://data/ui/close.png")
	close.expand_icon = true
	close.add_theme_constant_override("icon_max_width", 24)
	close.custom_minimum_size = Vector2(110, 48)
	close.pressed.connect(func(): library.visible = false)
	head.add_child(close)
	var row := HBoxContainer.new()
	box.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = I18n.t("building_name")
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size.y = 48
	row.add_child(_name)
	var save := Button.new()
	save.text = I18n.t("save_copy")
	save.icon = load("res://data/ui/save.png")
	save.expand_icon = true
	save.add_theme_constant_override("icon_max_width", 24)
	save.custom_minimum_size = Vector2(150, 48)
	save.pressed.connect(_save)
	row.add_child(save)
	_status = Label.new()
	box.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func open_library() -> void:
	library.visible = true
	library.position = get_viewport_rect().size / 2 - library.custom_minimum_size / 2
	_refresh()


const CATEGORY_KEYS := ["houses", "signs", "small_factories", "big_factories", "mine"]


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var by_cat := {}
	for entry in Schematics.list_saved():
		var cat: String = entry[4]
		if not by_cat.has(cat):
			by_cat[cat] = []
		by_cat[cat].append(entry)
	for cat in CATEGORY_KEYS:
		if not by_cat.has(cat):
			continue
		var head := Label.new()
		head.text = I18n.t("lib_" + cat)
		head.add_theme_font_size_override("font_size", 20)
		head.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		_list.add_child(head)
		for entry in by_cat[cat]:
			var row := HBoxContainer.new()
			_list.add_child(row)
			var b := Button.new()
			var size_text := "%d × %d × %d" % [entry[2][0], entry[2][1], entry[2][2]]
			if entry[5] > 0:
				size_text += "  •  " + I18n.f("lib_blocks", entry[5])
			b.text = "%s   (%s)" % [entry[1], size_text]
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not I18n.is_arabic() else HORIZONTAL_ALIGNMENT_RIGHT
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = 50
			b.pressed.connect(func(): _load(entry))
			row.add_child(b)
			if not entry[3]:
				var d := Button.new()
				d.text = I18n.t("delete")
				d.custom_minimum_size = Vector2(100, 50)
				d.pressed.connect(func(): Schematics.delete(entry[0]); _refresh())
				row.add_child(d)


func _save() -> void:
	var problem := Schematics.save(builder.clipboard, _name.text)
	_status.text = problem if problem != "" else I18n.f("saved_file", Schematics.clean_name(_name.text))
	if problem == "":
		_name.text = ""
	_refresh()


func _load(entry: Array) -> void:
	var clip := Schematics.load_file(entry[0])
	if clip.is_empty():
		_status.text = I18n.t("cant_read")
		return
	builder.clipboard = clip
	library.visible = false
	action.emit("loaded:" + str(entry[1]))
