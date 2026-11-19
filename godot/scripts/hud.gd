class_name Hud
extends CanvasLayer
## Hotbar, crosshair, clock, messages and FPS.

const SLOT := 64.0

var atlas: Texture2D
var slots := []                 # Panels
var icons := []                 # TextureRects
var item_label: Label
var clock: Label
var fps: Label
var message: Label
var _message_time := 0.0
var hotbar_box: HBoxContainer


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# crosshair
	for size in [Vector2(18, 2), Vector2(2, 18)]:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.size = size
		r.set_anchors_preset(Control.PRESET_CENTER)
		r.position = -size / 2
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(r)
	hotbar_box = HBoxContainer.new()
	hotbar_box.add_theme_constant_override("separation", 4)
	hotbar_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hotbar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hotbar_box)
	for i in 9:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.position = Vector2(8, 8)
		icon.size = Vector2(SLOT - 16, SLOT - 16)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		hotbar_box.add_child(p)
		slots.append(p)
		icons.append(icon)
	item_label = _label(root, Control.PRESET_CENTER_BOTTOM, 22)
	clock = _label(root, Control.PRESET_TOP_RIGHT, 20)
	fps = _label(root, Control.PRESET_TOP_LEFT, 16)
	message = _label(root, Control.PRESET_TOP_LEFT, 20)
	_layout.call_deferred()
	get_viewport().size_changed.connect(_layout)


func _label(root: Control, preset: int, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.set_anchors_preset(preset)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var w := 9 * SLOT + 8 * 4
	hotbar_box.position = Vector2((s.x - w) / 2, s.y - SLOT - 14)
	hotbar_box.size = Vector2(w, SLOT)
	item_label.position = Vector2(s.x / 2 - 200, s.y - SLOT - 50)
	item_label.size = Vector2(400, 30)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.position = Vector2(s.x - 190, 12)
	fps.position = Vector2(12, 12)
	message.position = Vector2(12, 40)


func hotbar_rect() -> Rect2:
	return Rect2(hotbar_box.position, hotbar_box.size)


func slot_at(pos: Vector2) -> int:
	if not hotbar_rect().has_point(pos):
		return -1
	return clampi(int((pos.x - hotbar_box.position.x) / (SLOT + 4)), 0, 8)


func show_hotbar(items: Array, selected: int) -> void:
	for i in 9:
		var item: int = items[i] if i < items.size() else 0
		icons[i].texture = icon_for(item) if item else null
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_border_width_all(3 if i == selected else 1)
		style.border_color = Color.WHITE if i == selected else Color(1, 1, 1, 0.25)
		slots[i].add_theme_stylebox_override("panel", style)
	var current: int = items[selected] if selected < items.size() else 0
	item_label.text = Blocks.name_of[current] if current and Blocks.exists(current) else ""


func icon_for(item: int) -> AtlasTexture:
	var t := AtlasTexture.new()
	t.atlas = atlas
	t.region = Blocks.tile_region(Blocks.tile_side[item])
	return t


func flash(text: String) -> void:
	message.text = text
	message.modulate.a = 1.0
	_message_time = 2.0


func _process(delta: float) -> void:
	fps.text = "%d fps" % Engine.get_frames_per_second()
	if _message_time > 0:
		_message_time -= delta
		message.modulate.a = clampf(_message_time / 0.5, 0, 1)
