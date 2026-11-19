class_name InventoryScreen
extends Control
## The inventory screen, made for fingers as well as a mouse.
## Left: your 36 slots. Right: crafting (survival), the creative menu, or a chest.
## Tap a slot to pick up / put down / swap. Two toggles stand in for right click and shift:
##   "Half"  - take half a stack, or put down one item
##   "Quick" - move a stack straight between hotbar / storage / chest, craft x16,
##             or add a creative item straight to the inventory

signal closed
signal mode_toggle_pressed
signal time_pressed(value: float)
signal freeze_pressed
signal message(text: String)

const SLOT := 62.0

var hud: Hud
var inv: Inventory
var chest: Inventory = null
var creative := false
var saved_hotbars: Array = []
var cursor = null
var half := false
var quick := false
var tab := "all"
var save_hotbar_mode := false

var _inv_parts := []
var _chest_parts := []
var _right: VBoxContainer
var _palette: GridContainer
var _recipes: VBoxContainer
var _search: LineEdit
var _holding_parts: Array
var _half_button: Button
var _quick_button: Button
var _mode_button: Button
var _title: Label
var _tab_buttons := {}
var _hotbar_buttons := []
var _save_toggle: Button
var _creative_box: VBoxContainer
var _crafting_box: VBoxContainer
var _chest_box: Control
var _tooltip: Label
var _dim: ColorRect
var _main: HBoxContainer


func _ready() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	add_child(_dim)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 16)
	add_child(main)
	_main = main
	if I18n.is_arabic():
		main.layout_direction = Control.LAYOUT_DIRECTION_RTL   # mirror the content, not the screen position

	# ---- left: toolbar + inventory
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	main.add_child(left)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	left.add_child(bar)
	bar.add_child(_button(I18n.t("close"), func(): closed.emit(), 110, false, "close"))
	_half_button = _button(I18n.t("half"), func(): half = not half; _refresh_toggles(), 100, true, "half")
	bar.add_child(_half_button)
	_quick_button = _button(I18n.t("quick"), func(): quick = not quick; _refresh_toggles(), 100, true, "quick")
	bar.add_child(_quick_button)
	var holding := Panel.new()
	holding.custom_minimum_size = Vector2(SLOT, SLOT)
	bar.add_child(holding)
	_holding_parts = hud.make_slot_parts(holding, SLOT)
	_tooltip = Label.new()
	_tooltip.add_theme_font_size_override("font_size", 18)
	bar.add_child(_tooltip)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	left.add_child(grid)
	var order := []
	for i in range(9, 36):
		order.append(i)
	for i in 9:
		order.append(i)                     # the hotbar row goes at the bottom, like the HUD
	var parts_by_index := {}
	for i in order:
		parts_by_index[i] = _slot(grid, func(alt): _tap_inventory(i, alt), func(): _hover(inv.slots[i]))
	for i in 36:
		_inv_parts.append(parts_by_index[i])
	var hint := Label.new()
	hint.text = I18n.t("storage_hint")
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	left.add_child(hint)

	# ---- right panel
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(panel)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 6)
	panel.add_child(_right)
	var head := HBoxContainer.new()
	_right.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_mode_button = _button("", func(): mode_toggle_pressed.emit(), 190)
	head.add_child(_mode_button)
	_search = LineEdit.new()
	_search.placeholder_text = I18n.t("search")
	_search.custom_minimum_size.y = 44
	_search.text_changed.connect(func(_t): refresh())
	_right.add_child(_search)

	_creative_box = VBoxContainer.new()
	_creative_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(_creative_box)
	var tabs := HFlowContainer.new()
	_creative_box.add_child(tabs)
	for t in Items.tabs:
		var b := _button(I18n.tab(t), func(): tab = t; _search.text = ""; refresh(), 0)
		b.add_theme_font_size_override("font_size", 15)
		tabs.add_child(b)
		_tab_buttons[t] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_creative_box.add_child(scroll)
	_palette = GridContainer.new()
	_palette.columns = 9
	_palette.add_theme_constant_override("h_separation", 4)
	_palette.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_palette)
	var tools := HFlowContainer.new()
	_creative_box.add_child(tools)
	var trash := _button(I18n.t("trash"), func(): cursor = null; refresh(), 0, false, "trash")
	trash.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	tools.add_child(trash)
	tools.add_child(_button(I18n.t("clear_inventory"), func(): inv.slots.fill(null); refresh(), 0, false, "clear_inventory"))
	for t in [["sunrise", 0.0], ["noon", 0.25], ["sunset", 0.5], ["midnight", 0.75]]:
		tools.add_child(_button(I18n.t(t[0]), func(): time_pressed.emit(t[1]), 0, false, t[0]))
	tools.add_child(_button(I18n.t("freeze"), func(): freeze_pressed.emit(), 0, false, "freeze"))
	var hb := HFlowContainer.new()
	_creative_box.add_child(hb)
	var l := Label.new()
	l.text = I18n.t("hotbars")
	hb.add_child(l)
	for n in 9:
		var b := _button(str(n + 1), func(): _hotbar_button(n), 46)
		hb.add_child(b)
		_hotbar_buttons.append(b)
	_save_toggle = _button(I18n.t("save_hotbar"), func(): save_hotbar_mode = not save_hotbar_mode; refresh(), 90, true, "save_hotbar")
	hb.add_child(_save_toggle)

	_crafting_box = VBoxContainer.new()
	_crafting_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_right.add_child(_crafting_box)
	var rscroll := ScrollContainer.new()
	rscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crafting_box.add_child(rscroll)
	_recipes = VBoxContainer.new()
	_recipes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rscroll.add_child(_recipes)

	_chest_box = GridContainer.new()
	_chest_box.columns = 9
	_chest_box.add_theme_constant_override("h_separation", 4)
	_chest_box.add_theme_constant_override("v_separation", 4)
	_right.add_child(_chest_box)
	for i in 27:
		_chest_parts.append(_slot(_chest_box, func(alt): _tap_chest(i, alt), func(): _hover(chest.slots[i] if chest else null)))
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	get_viewport().size_changed.connect(_layout)
	_layout()


## Sizes come from the screen size (anchors don't follow a CanvasLayer parent reliably).
func _layout() -> void:
	var s := get_viewport_rect().size
	position = Vector2.ZERO
	size = s
	_dim.size = s
	_main.position = Vector2(16, 12)
	_main.size = s - Vector2(32, 24)


func _button(text: String, action: Callable, width := 0, toggle := false, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		b.icon = load("res://data/ui/%s.png" % icon)
		b.add_theme_constant_override("icon_max_width", 26)      # fixed size, even on narrow buttons
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(width, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


## A tappable slot. `on_tap(alt)` gets alt = true for a right click.
func _slot(parent: Control, on_tap: Callable, on_hover: Callable) -> Array:
	var b := Button.new()
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.12, 0.9)
	style.set_border_width_all(1)
	style.border_color = Color(1, 1, 1, 0.2)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, style)
	b.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	b.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			on_tap.call(e.button_index == MOUSE_BUTTON_RIGHT)
			accept_event())
	b.mouse_entered.connect(on_hover)
	parent.add_child(b)
	return hud.make_slot_parts(b, SLOT)


func _hover(stack) -> void:
	_tooltip.text = Items.name_of(stack[0]) if stack != null else ""


func open(inventory: Inventory, is_creative: bool, chest_inventory: Inventory = null) -> void:
	inv = inventory
	creative = is_creative
	chest = chest_inventory
	cursor = null
	half = false
	quick = false
	visible = true
	refresh()


## Put back whatever is held and close.
func close() -> void:
	if cursor != null and not creative:
		var left = inv.give(cursor)
		if left != null:
			message.emit(I18n.f("dropped", Items.name_of(cursor[0])))
	cursor = null
	visible = false


func _refresh_toggles() -> void:
	_half_button.button_pressed = half
	_quick_button.button_pressed = quick


func _tap_inventory(i: int, alt: bool) -> void:
	if quick and not alt:
		if chest != null:
			inv.slots[i] = chest.give(inv.slots[i]) if inv.slots[i] != null else null
		else:
			inv.quick_move(i)
	else:
		cursor = inv.click(i, cursor, half or alt)
	_hover(inv.slots[i])
	refresh()


func _tap_chest(i: int, alt: bool) -> void:
	if quick and not alt:
		if chest.slots[i] != null:
			chest.slots[i] = inv.give(chest.slots[i])
	else:
		cursor = chest.click(i, cursor, half or alt)
	refresh()


func _tap_palette(item: int, alt: bool) -> void:
	if cursor != null:
		cursor = null                       # tapping the menu with something held throws it away
	elif quick and not alt:
		inv.add(item, Items.max_stack(item))
		message.emit(I18n.f("added", Items.name_of(item)))
	else:
		cursor = Items.new_stack(item, 1 if (half or alt) else Items.max_stack(item))
	_tooltip.text = Items.name_of(item)
	refresh()


func _craft(r: Dictionary) -> void:
	var made := 0
	for i in (16 if quick else 1):
		if inv.craft(r):
			made += 1
	if made == 0:
		message.emit(I18n.t("missing_ingredients") if not inv.can_craft(r) else I18n.t("inventory_full"))
	refresh()


func _hotbar_button(n: int) -> void:
	if save_hotbar_mode:
		var saved := []
		for i in 9:
			saved.append(inv.slots[i].duplicate() if inv.slots[i] != null else null)
		saved_hotbars[n] = saved
		save_hotbar_mode = false
		message.emit(I18n.f("hotbar_saved", n + 1))
	elif saved_hotbars[n] == null:
		message.emit(I18n.f("hotbar_empty", [n + 1, n + 1]))
	else:
		for i in 9:
			var s = saved_hotbars[n][i]
			inv.slots[i] = s.map(func(v): return int(v)) if s != null else null
		message.emit(I18n.f("hotbar_loaded", n + 1))
	refresh()


func refresh() -> void:
	if inv == null:
		return
	for i in 36:
		hud.show_stack(_inv_parts[i], inv.slots[i], SLOT, not creative)
	hud.show_stack(_holding_parts, cursor, SLOT, not creative)
	_refresh_toggles()
	_chest_box.visible = chest != null
	_creative_box.visible = creative and chest == null
	_crafting_box.visible = not creative and chest == null
	_search.visible = chest == null
	_mode_button.text = I18n.t("to_survival") if creative else I18n.t("to_creative")
	_mode_button.visible = chest == null
	if chest != null:
		_title.text = I18n.t("chest")
		for i in 27:
			hud.show_stack(_chest_parts[i], chest.slots[i], SLOT)
	elif creative:
		_title.text = I18n.t("creative")
		_fill_palette()
		for t in _tab_buttons:
			_tab_buttons[t].modulate = Color(0.6, 0.85, 1.4) if t == tab and _search.text == "" else Color.WHITE
		for n in 9:
			_hotbar_buttons[n].modulate = Color(0.6, 0.85, 1.4) if saved_hotbars[n] != null else Color.WHITE
		_save_toggle.button_pressed = save_hotbar_mode
	else:
		_title.text = I18n.t("crafting")
		_fill_recipes()


var _palette_key := ""


func _fill_palette() -> void:
	var key := tab + "|" + _search.text
	if key == _palette_key:
		return
	_palette_key = key
	for c in _palette.get_children():
		c.queue_free()
	for item in Items.creative_items(tab, _search.text):
		var parts := _slot(_palette, func(alt): _tap_palette(item, alt), func(): _tooltip.text = Items.name_of(item))
		hud.show_stack(parts, [item, 1], SLOT, false)


func _fill_recipes() -> void:
	for c in _recipes.get_children():
		c.queue_free()
	var text := _search.text.to_lower()
	var shown := []
	for r in Items.recipes:
		if text == "" or text in Items.recipe_text(r).to_lower():
			shown.append(r)
	shown.sort_custom(func(a, b): return inv.can_craft(a) and not inv.can_craft(b))
	for r in shown:
		var b := Button.new()
		b.text = "  " + Items.recipe_text(r)
		b.icon = hud.icon_for(r["out"][0])
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 40)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 52
		b.focus_mode = Control.FOCUS_NONE
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if inv.can_craft(r):
			b.modulate = Color(0.75, 1.3, 0.8)
		else:
			b.modulate = Color(0.75, 0.75, 0.75)
		b.pressed.connect(func(): _craft(r))
		_recipes.add_child(b)
