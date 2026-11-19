class_name BuildPanel
extends Control
## Creative building tools as big buttons (they act on the block in the crosshair), and the
## schematics library: save the current copy as a file, load one to paste, or delete it.

signal action(name: String)

const TOOLS := [
	["Corner 1", "corner1"], ["Corner 2", "corner2"], ["Fill", "fill"], ["Hollow", "hollow"],
	["Replace", "replace"], ["Clear", "clear"], ["Copy", "copy"], ["Paste", "paste"],
	["Rotate", "rotate"], ["Mirror", "mirror"], ["Undo", "undo"], ["Deselect", "deselect"],
	["Library", "library"],
]

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
		b.text = t[0]
		b.custom_minimum_size = Vector2(112, 50)
		b.focus_mode = Control.FOCUS_NONE
		b.modulate = Color(1, 1, 1, 0.85)
		b.pressed.connect(func(): action.emit(t[1]))
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
	library.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Buildings"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(110, 48)
	close.pressed.connect(func(): library.visible = false)
	head.add_child(close)
	var row := HBoxContainer.new()
	box.add_child(row)
	_name = LineEdit.new()
	_name.placeholder_text = "name for the current copy"
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size.y = 48
	row.add_child(_name)
	var save := Button.new()
	save.text = "Save copy"
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


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for entry in Schematics.list_saved():
		var row := HBoxContainer.new()
		_list.add_child(row)
		var b := Button.new()
		b.text = "%s   (%d x %d x %d)%s" % [entry[1], entry[2][0], entry[2][1], entry[2][2], "   - example" if entry[3] else ""]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 50
		b.pressed.connect(func(): _load(entry))
		row.add_child(b)
		if not entry[3]:
			var d := Button.new()
			d.text = "Delete"
			d.custom_minimum_size = Vector2(100, 50)
			d.pressed.connect(func(): Schematics.delete(entry[0]); _refresh())
			row.add_child(d)


func _save() -> void:
	var problem := Schematics.save(builder.clipboard, _name.text)
	_status.text = problem if problem != "" else "Saved " + Schematics.clean_name(_name.text)
	if problem == "":
		_name.text = ""
	_refresh()


func _load(entry: Array) -> void:
	var clip := Schematics.load_file(entry[0])
	if clip.is_empty():
		_status.text = "Could not read that file"
		return
	builder.clipboard = clip
	library.visible = false
	action.emit("loaded:" + str(entry[1]))
