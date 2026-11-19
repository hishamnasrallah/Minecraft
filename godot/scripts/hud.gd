class_name Hud
extends CanvasLayer
## Hotbar (icons, counts, tool wear), hearts / hunger / air, crosshair, clock, messages,
## the hurt flash and the death screen.

signal respawn_pressed

const SLOT := 64.0
const ICON := 22.0

var atlas: Texture2D
var slots := []
var icons := []
var counts := []
var bars := []
var item_label: Label
var clock: Label
var fps: Label
var message: Label
var mode_label: Label
var build_label: Label
var target_label: Label
var minimap: Minimap
var chat_log: Label
var boss_box: Control
var _boss_fill: ColorRect
var _boss_label: Label
var _portal: ColorRect
var _chat_lines := []                # [text, time shown]
var perf := {}                       # system -> ms per frame, shown under the FPS counter
var _message_time := 0.0
var hotbar_box: HBoxContainer
var hearts := []
var food := []
var bubbles := []
var hud_tex := {}
var hurt: ColorRect
var death: Control
var death_cause: Label
var root: Control


func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	for name in ["heart_full", "heart_half", "heart_empty", "food_full", "food_half", "food_empty", "bubble"]:
		hud_tex[name] = load("res://data/icons/%s.png" % name)
	hurt = ColorRect.new()
	hurt.color = Color(0.8, 0, 0, 0)
	hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hurt)
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
	hotbar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hotbar_box)
	for i in 9:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hotbar_box.add_child(p)
		var parts := make_slot_parts(p, SLOT)
		slots.append(p)
		icons.append(parts[0])
		counts.append(parts[1])
		bars.append(parts[2])
	for i in 10:
		hearts.append(_icon())
		food.append(_icon())
		bubbles.append(_icon())
	item_label = _label(22)
	clock = _label(20)
	fps = _label(16)
	message = _label(20)
	mode_label = _label(16)
	mode_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	target_label = _label(17)
	target_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	target_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	build_label = _label(16)
	build_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	_portal = ColorRect.new()
	_portal.color = Color(0.55, 0.25, 0.9, 0)
	_portal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_portal)
	boss_box = Control.new()
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.visible = false
	root.add_child(boss_box)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.size = Vector2(520, 18)
	bg.position = Vector2(0, 30)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(bg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.35, 0.8, 1.0)
	_boss_fill.size = Vector2(516, 14)
	_boss_fill.position = Vector2(2, 32)
	_boss_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(_boss_fill)
	_boss_label = Label.new()
	_boss_label.add_theme_font_size_override("font_size", 20)
	_boss_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_label.add_theme_constant_override("outline_size", 5)
	_boss_label.size = Vector2(520, 28)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_box.add_child(_boss_label)
	chat_log = _label(18)
	chat_log.add_theme_color_override("font_color", Color(1, 1, 1))
	chat_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	minimap = Minimap.new()
	root.add_child(minimap)
	_make_death_screen()
	_layout.call_deferred()
	get_viewport().size_changed.connect(_layout)


## Icon + count + durability bar inside a slot panel. Shared with the inventory screen.
func make_slot_parts(p: Control, size: float) -> Array:
	var icon := TextureRect.new()
	icon.position = Vector2(size * 0.12, size * 0.12)
	icon.size = Vector2(size * 0.76, size * 0.76)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	var count := Label.new()
	count.add_theme_font_size_override("font_size", int(size * 0.28))
	count.add_theme_color_override("font_outline_color", Color.BLACK)
	count.add_theme_constant_override("outline_size", 4)
	count.position = Vector2(size * 0.35, size * 0.55)
	count.size = Vector2(size * 0.6, size * 0.4)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(count)
	var bar := ColorRect.new()
	bar.position = Vector2(size * 0.12, size * 0.84)
	bar.size = Vector2(size * 0.76, 4)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	p.add_child(bar)
	return [icon, count, bar]


func show_stack(parts: Array, stack, size: float, show_count := true) -> void:
	var icon: TextureRect = parts[0]
	var count: Label = parts[1]
	var bar: ColorRect = parts[2]
	icon.texture = icon_for(stack[0]) if stack != null else null
	count.text = str(stack[1]) if stack != null and stack[1] > 1 and show_count else ""
	bar.visible = false
	if stack != null and stack.size() == 3:
		var full := float(Items.tools[stack[0]]["durability"])
		if stack[2] < full:
			var left: float = stack[2] / full
			bar.visible = true
			bar.size.x = size * 0.76 * left
			bar.color = Color.RED.lerp(Color.LIME_GREEN, left)


func _icon() -> TextureRect:
	var t := TextureRect.new()
	t.size = Vector2(ICON, ICON)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(t)
	return t


func _label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _make_death_screen() -> void:
	death = ColorRect.new()
	death.color = Color(0.45, 0, 0, 0.6)
	death.set_anchors_preset(Control.PRESET_FULL_RECT)
	death.visible = false
	root.add_child(death)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	death.add_child(box)
	var title := Label.new()
	title.text = I18n.t("you_died")
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	death_cause = Label.new()
	death_cause.add_theme_font_size_override("font_size", 26)
	death_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(death_cause)
	var b := Button.new()
	b.text = I18n.t("respawn")
	b.custom_minimum_size = Vector2(260, 80)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(func(): respawn_pressed.emit())
	box.add_child(b)
	box.position = -box.get_combined_minimum_size() / 2


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var w := 9 * SLOT + 8 * 4
	var x0 := (s.x - w) / 2
	hotbar_box.position = Vector2(x0, s.y - SLOT - 14)
	hotbar_box.size = Vector2(w, SLOT)
	for i in 10:
		var y := s.y - SLOT - 14 - ICON - 6
		hearts[i].position = Vector2(x0 + i * (ICON + 2), y)
		food[i].position = Vector2(x0 + w - (i + 1) * (ICON + 2), y)
		bubbles[i].position = Vector2(x0 + w - (i + 1) * (ICON + 2), y - ICON - 4)
	item_label.position = Vector2(s.x / 2 - 200, s.y - SLOT - 14 - ICON - 42)
	item_label.size = Vector2(400, 30)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock.position = Vector2(s.x / 2 - 40, 8)
	target_label.position = Vector2(s.x / 2 - 200, s.y / 2 + 22)
	target_label.size = Vector2(400, 26)
	var y0 := 0.0
	if minimap.visible:
		minimap.position = Vector2(14, 14)
		y0 = minimap.size.y + 16
	fps.position = Vector2(12, 12 + y0)
	message.position = Vector2(12, 40 + y0)
	mode_label.position = Vector2(12, 70 + y0)
	build_label.position = Vector2(12, 94 + y0)
	boss_box.position = Vector2(s.x / 2 - 260, 44)
	chat_log.position = Vector2(12, s.y - SLOT - 230)
	chat_log.size = Vector2(minf(560, s.x * 0.45), 150)
	var box: Control = death.get_child(0)
	box.position = s / 2 - box.get_combined_minimum_size() / 2


func hotbar_rect() -> Rect2:
	return Rect2(hotbar_box.position, hotbar_box.size)


func slot_at(pos: Vector2) -> int:
	if not hotbar_rect().has_point(pos):
		return -1
	return clampi(int((pos.x - hotbar_box.position.x) / (SLOT + 4)), 0, 8)


func show_hotbar(inv: Inventory, selected: int, creative: bool) -> void:
	for i in 9:
		show_stack([icons[i], counts[i], bars[i]], inv.slots[i], SLOT, not creative)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.45)
		style.set_border_width_all(4 if i == selected else 1)
		style.border_color = Color(1, 0.86, 0.3) if i == selected else Color(1, 1, 1, 0.25)
		style.set_corner_radius_all(6)
		if i == selected:
			style.bg_color = Color(0.25, 0.2, 0.05, 0.6)
		slots[i].add_theme_stylebox_override("panel", style)
		slots[i].pivot_offset = Vector2(SLOT, SLOT) / 2
		slots[i].scale = Vector2.ONE * (1.14 if i == selected else 1.0)
		slots[i].z_index = 1 if i == selected else 0
	var s = inv.slots[selected]
	item_label.text = Items.name_of(s[0]) if s != null else ""
	if s != null and s.size() == 3:
		item_label.text += "  (%d/%d)" % [s[2], int(Items.tools[s[0]]["durability"])]


func show_bars(sv: Survival, creative: bool) -> void:
	var heart_icons := Survival.icons(sv.health, int(sv.K["MAX_HEALTH"]))
	var food_icons := Survival.icons(sv.hunger, int(sv.K["MAX_HUNGER"]))
	var max_air := float(sv.K["MAX_AIR"])
	for i in 10:
		hearts[i].visible = not creative
		food[i].visible = not creative
		hearts[i].texture = hud_tex["heart_" + heart_icons[i]]
		food[i].texture = hud_tex["food_" + food_icons[i]]
		bubbles[i].texture = hud_tex["bubble"]
		bubbles[i].visible = not creative and sv.air < max_air and i < ceili(sv.air / max_air * 10)


static var _icons3d: Texture2D
static var _icon_cache := {}


func icon_for(item: int) -> AtlasTexture:
	if _icon_cache.has(item):
		return _icon_cache[item]
	var t := AtlasTexture.new()
	if Items.icons3d.has(item):
		if _icons3d == null:
			_icons3d = load("res://data/icons3d.png")
		var n: int = Items.icons3d[item]
		var sz := float(Items.icon3d_size)
		t.atlas = _icons3d
		t.region = Rect2((n % Items.icon3d_cols) * sz, (n / Items.icon3d_cols) * sz, sz, sz)
		_icon_cache[item] = t
		return t
	t.atlas = atlas
	t.region = Blocks.tile_region(Items.icons.get(item, 0))
	_icon_cache[item] = t
	return t


func show_target(text: String) -> void:
	if target_label.text != text:
		target_label.text = text


func show_boss(name: String, fraction: float, crystals: int) -> void:
	boss_box.visible = true
	_boss_fill.size.x = 516.0 * clampf(fraction, 0.0, 1.0)
	_boss_fill.color = Color(1.0, 0.4, 0.4) if fraction < 0.5 else Color(0.35, 0.8, 1.0)
	_boss_label.text = name if crystals == 0 else "%s   •   %s" % [name, I18n.f("boss_crystals", crystals)]


func hide_boss() -> void:
	boss_box.visible = false


## Standing in a portal: the screen turns purple as you are about to travel.
func portal_glow(amount: float) -> void:
	_portal.color.a = clampf(amount, 0.0, 1.0) * 0.6


## A chat message from a friend (or us): shown for 12 seconds, the last 6 at most.
func chat(name: String, text: String) -> void:
	_chat_lines.append(["%s: %s" % [name, text], Time.get_ticks_msec()])
	if _chat_lines.size() > 6:
		_chat_lines.pop_front()
	_show_chat()


func _show_chat() -> void:
	var now := Time.get_ticks_msec()
	_chat_lines = _chat_lines.filter(func(l): return now - int(l[1]) < 12000)
	chat_log.text = "\n".join(_chat_lines.map(func(l): return l[0]))


func flash(text: String) -> void:
	message.text = text
	message.modulate.a = 1.0
	_message_time = 2.0


func hurt_flash() -> void:
	hurt.color.a = 0.35


func show_death(cause: String) -> void:
	death_cause.text = I18n.t("cause_" + cause)
	death.visible = true


func _process(delta: float) -> void:
	if not _chat_lines.is_empty() and Engine.get_process_frames() % 30 == 0:
		_show_chat()
	var t := "%d fps" % Engine.get_frames_per_second()
	if not perf.is_empty():
		var parts := []
		for k in perf:
			parts.append("%s %.1f" % [k, perf[k]])
		t += "  |  " + "  ".join(parts) + " ms"
	fps.text = t
	if minimap.visible != bool(I18n.settings.get("show_map", true)):
		minimap.visible = not minimap.visible
		_layout()
	if _message_time > 0:
		_message_time -= delta
		message.modulate.a = clampf(_message_time / 0.5, 0, 1)
	if hurt.color.a > 0:
		hurt.color.a = maxf(0, hurt.color.a - delta)
