class_name InventoryScreen
extends Control
## The items screen, made for fingers first.
##
##  [tabs]  [ creative blocks / recipe book / chest / furnace ]  [ your items + info ]
##
## Your items: tap a slot to pick it, tap another slot to move it there (stacks merge,
## different items swap), or drag it straight there. Double tap = quick move between the
## hotbar and the bag. The info strip under the bag acts on the picked slot: quick move,
## split in half, throw away / drop.
## Creative: tap a block to put a full stack in your hotbar; blocks with variants (colours,
## woods...) show a "+": tap to open the whole family. Hold a block to star it (favourites).
## Survival: the recipe book shows what you can make; tap a recipe, then craft x1 or as many
## as you can.

signal closed
signal mode_toggle_pressed
signal time_pressed(value: float)
signal freeze_pressed
signal message(text: String)
signal drop_stack(stack: Array)
signal weather_pressed(kind: String)

const SLOT := 60.0
const GAP := 4.0
const HOLD := 0.45
const BG := Color(0.11, 0.12, 0.14, 0.97)
const PICKED := Color(1, 0.86, 0.3)
const FAMILY_BG := Color(0.2, 0.3, 0.42, 0.95)
const TAB_ICONS := {"natural": 1, "building": 8, "colored": 75, "plants": 53, "functional": 48,
	"tools": 201, "food": 105, "materials": 106}

var hud: Hud
var inv: Inventory
var chest: Inventory = null
var station := ""                    # "", "chest" or "furnace"
var creative := false
var hotbar_selected := 0
var saved_hotbars: Array = []
var save_hotbar_mode := false
var tab := "all"
var expanded := ""                   # the open family in the creative grid
var craftable_only := false
var picked = null                    # [Inventory, slot index] chosen with a tap
var recipe = null                    # the recipe open in the recipe book

var _families := {}                  # family -> [ids]
var _family_of := {}                 # id -> family
var _inv_slots := []                 # Control per slot (0..35)
var _chest_slots := []
var _main: HBoxContainer
var _dim: ColorRect
var _title: Label
var _search: LineEdit
var _mode_button: Button
var _sort_button: Button
var _tab_box: VBoxContainer
var _tab_buttons := {}
var _content_scroll: ScrollContainer
var _grid: GridContainer
var _chest_grid: GridContainer
var _recipe_panel: VBoxContainer
var _info_icon: TextureRect
var _info_name: Label
var _info_text: Label
var _info_actions: HBoxContainer
var _creative_tools: HFlowContainer
var _hotbar_buttons := []
var _save_toggle: Button
var _craftable_button: Button
var _last_tap := [null, -1, 0.0]     # inventory, index, time: for double taps
var _grid_key := ""
var _drag_ended_at := 0


func _ready() -> void:
	_load_families()
	_dim = ColorRect.new()
	_dim.color = Color(0.02, 0.03, 0.05, 0.88)
	add_child(_dim)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	add_child(outer)
	_main = HBoxContainer.new()            # filled below; outer holds the top bar too

	# ---- top bar
	var top_panel := PanelContainer.new()
	var ts := _box_style(Color(0.16, 0.18, 0.22, 0.98))
	ts.content_margin_top = 4
	ts.content_margin_bottom = 4
	top_panel.add_theme_stylebox_override("panel", ts)
	outer.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top_panel.add_child(top)
	if I18n.is_arabic():
		top.layout_direction = Control.LAYOUT_DIRECTION_RTL
	top.add_child(_button(I18n.t("close"), func(): closed.emit(), 0, "close"))
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.custom_minimum_size.x = 150
	top.add_child(_title)
	_search = LineEdit.new()
	_search.placeholder_text = I18n.t("search")
	_search.custom_minimum_size = Vector2(240, 48)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): expanded = ""; refresh())
	top.add_child(_search)
	_craftable_button = _button(I18n.t("craftable_only"), func(): craftable_only = not craftable_only; refresh(), 0, "check")
	_craftable_button.toggle_mode = true
	top.add_child(_craftable_button)
	_sort_button = _button(I18n.t("sort"), _sort, 0, "sort")
	top.add_child(_sort_button)
	_mode_button = _button("", func(): mode_toggle_pressed.emit(), 0)
	top.add_child(_mode_button)

	_main.add_theme_constant_override("separation", 10)
	_main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_main)
	if I18n.is_arabic():
		_main.layout_direction = Control.LAYOUT_DIRECTION_RTL   # mirror the content, not the screen position

	# ---- tab rail
	var rail_scroll := ScrollContainer.new()
	rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail_scroll.custom_minimum_size.x = 64
	_main.add_child(rail_scroll)
	_tab_box = VBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 4)
	rail_scroll.add_child(_tab_box)
	for t in ["favorites", "recent", "all"] + Array(Items.tabs).filter(func(x): return x != "all"):
		var b := Button.new()
		b.custom_minimum_size = Vector2(58, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = I18n.tab(t) if t not in ["favorites", "recent"] else I18n.t("tab_" + t)
		if TAB_ICONS.has(t):
			b.icon = hud.icon_for(TAB_ICONS[t])
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		else:
			b.icon = load("res://data/ui/%s.png" % {"favorites": "star", "recent": "recent", "all": "all"}[t])
		b.add_theme_constant_override("icon_max_width", 34)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(func(): tab = t; expanded = ""; recipe = null; _search.text = ""; refresh())
		_tab_box.add_child(b)
		_tab_buttons[t] = b

	# ---- content: creative grid / recipe book / chest
	var content := PanelContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_stylebox_override("panel", _box_style(BG))
	_main.add_child(content)
	var cv := VBoxContainer.new()
	content.add_child(cv)
	_content_scroll = ScrollContainer.new()
	_content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(_content_scroll)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(GAP))
	_grid.add_theme_constant_override("v_separation", int(GAP))
	_content_scroll.add_child(_grid)
	_recipe_panel = VBoxContainer.new()
	_recipe_panel.add_theme_constant_override("separation", 6)
	cv.add_child(_recipe_panel)
	_chest_grid = GridContainer.new()
	_chest_grid.columns = 9
	_chest_grid.add_theme_constant_override("h_separation", int(GAP))
	_chest_grid.add_theme_constant_override("v_separation", int(GAP))
	cv.add_child(_chest_grid)
	for i in 27:
		_chest_slots.append(_inv_slot(_chest_grid, func(): return chest, i))

	# ---- your items
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	_main.add_child(right)
	var bag := PanelContainer.new()
	bag.add_theme_stylebox_override("panel", _box_style(BG))
	right.add_child(bag)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 10)
	bag.add_child(bv)
	var storage := GridContainer.new()
	storage.columns = 9
	storage.add_theme_constant_override("h_separation", int(GAP))
	storage.add_theme_constant_override("v_separation", int(GAP))
	bv.add_child(storage)
	var hotbar := GridContainer.new()
	hotbar.columns = 9
	hotbar.add_theme_constant_override("h_separation", int(GAP))
	bv.add_child(hotbar)
	_inv_slots.resize(36)
	for i in range(9, 36):
		_inv_slots[i] = _inv_slot(storage, func(): return inv, i)
	for i in 9:
		_inv_slots[i] = _inv_slot(hotbar, func(): return inv, i)   # the hotbar row at the bottom, like the HUD

	# info strip: what is picked, and what you can do with it
	var info := PanelContainer.new()
	info.add_theme_stylebox_override("panel", _box_style(BG))
	right.add_child(info)
	var iv := VBoxContainer.new()
	info.add_child(iv)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 10)
	iv.add_child(ih)
	_info_icon = TextureRect.new()
	_info_icon.custom_minimum_size = Vector2(44, 44)
	_info_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_info_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ih.add_child(_info_icon)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(names)
	_info_name = Label.new()
	_info_name.add_theme_font_size_override("font_size", 20)
	names.add_child(_info_name)
	_info_text = Label.new()
	_info_text.add_theme_font_size_override("font_size", 14)
	_info_text.add_theme_color_override("font_color", Color(0.75, 0.78, 0.82))
	_info_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_text.custom_minimum_size.x = 380
	names.add_child(_info_text)
	_info_actions = HBoxContainer.new()
	_info_actions.add_theme_constant_override("separation", 6)
	iv.add_child(_info_actions)
	_info_actions.add_child(_button(I18n.t("quick_move"), func(): _act("quick"), 0, "quick"))
	_info_actions.add_child(_button(I18n.t("split"), func(): _act("split"), 0, "half"))
	var trash := _button(I18n.t("trash"), func(): _act("trash"), 0, "trash")
	trash.add_theme_color_override("font_color", Color(1, 0.55, 0.55))
	trash.set_drag_forwarding(Callable(), _can_drop_slot, _drop_trash)
	_info_actions.add_child(trash)

	# creative extras: time of day, saved hotbars
	_creative_tools = HFlowContainer.new()
	_creative_tools.add_theme_constant_override("h_separation", 4)
	_creative_tools.add_theme_constant_override("v_separation", 4)
	right.add_child(_creative_tools)
	for t in [["sunrise", 0.0], ["noon", 0.25], ["sunset", 0.5], ["midnight", 0.75]]:
		var tb := _button("", func(): time_pressed.emit(t[1]), 48, t[0])
		tb.tooltip_text = I18n.t(t[0])
		_creative_tools.add_child(tb)
	for w in ["clear", "rain"]:
		_creative_tools.add_child(_button(I18n.t("weather_" + w), func(): weather_pressed.emit(w), 0))
	var fz := _button("", func(): freeze_pressed.emit(), 48, "freeze")
	fz.tooltip_text = I18n.t("freeze")
	_creative_tools.add_child(fz)
	_creative_tools.add_child(_button(I18n.t("clear_inventory"), func(): inv.slots.fill(null); picked = null; refresh(), 0, "clear_inventory"))
	var hb_label := Label.new()
	hb_label.text = I18n.t("hotbars")
	_creative_tools.add_child(hb_label)
	for n in 9:
		var b := _button(str(n + 1), func(): _hotbar_button(n), 44)
		_creative_tools.add_child(b)
		_hotbar_buttons.append(b)
	_save_toggle = _button("", func(): save_hotbar_mode = not save_hotbar_mode; refresh(), 48, "save_hotbar")
	_save_toggle.toggle_mode = true
	_save_toggle.tooltip_text = I18n.t("save_hotbar")
	_creative_tools.add_child(_save_toggle)

	get_viewport().size_changed.connect(_layout)
	_layout()


func _load_families() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))
	if d is Dictionary and d.get("families") is Dictionary:
		for f in d["families"]:
			var ids: Array = d["families"][f].map(func(v): return int(v))
			if ids.size() > 1:
				_families[f] = ids
				for i in ids:
					_family_of[i] = f


## Sizes come from the screen size (anchors don't follow a CanvasLayer parent reliably).
func _layout() -> void:
	var s := get_viewport_rect().size
	position = Vector2.ZERO
	size = s
	_dim.size = s
	var outer: Control = get_child(1)
	outer.position = Vector2(12, 10)
	outer.size = s - Vector2(24, 20)
	# columns that fit the content panel: screen - rail - bag column - gaps
	var free := s.x - 24 - 64 - (9 * SLOT + 8 * GAP + 16) - 20 - 16
	_grid.columns = clampi(int((free + GAP) / (SLOT + GAP)), 4, 12)


func _box_style(color: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = color
	st.set_corner_radius_all(8)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	return st


func _button(text: String, action: Callable, width := 0, icon := "") -> Button:
	var b := Button.new()
	b.text = text
	if icon != "":
		b.icon = load("res://data/ui/%s.png" % icon)
		b.add_theme_constant_override("icon_max_width", 26)
	b.custom_minimum_size = Vector2(width, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


func _slot_style(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.set_border_width_all(width)
	st.border_color = border
	st.set_corner_radius_all(6)
	return st


# ---------------------------------------------------------------- inventory / chest slots
## A slot of an inventory: tap, double tap, and drag & drop. `owner_of` returns the Inventory.
func _inv_slot(parent: Control, owner_of: Callable, i: int) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.set_meta("parts", hud.make_slot_parts(p, SLOT))
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			if Time.get_ticks_msec() - _drag_ended_at > 150:
				_tap_slot(owner_of.call(), i)
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_pick_slot(owner_of.call(), i)
			_act("split"))
	p.set_drag_forwarding(_slot_drag.bind(owner_of, i, p), _can_drop_slot, _drop_slot.bind(owner_of, i))
	parent.add_child(p)
	return p


func _slot_drag(_pos: Vector2, owner_of: Callable, i: int, p: Control) -> Variant:
	var o: Inventory = owner_of.call()
	if o == null or o.slots[i] == null:
		return null
	var prev := TextureRect.new()
	prev.texture = hud.icon_for(o.slots[i][0])
	prev.size = Vector2(SLOT, SLOT) * 0.9
	prev.position = -prev.size / 2
	prev.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	prev.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var holder := Control.new()
	holder.add_child(prev)
	p.set_drag_preview(holder)
	return ["slot", o, i]


func _can_drop_slot(_pos: Vector2, d: Variant) -> bool:
	return d is Array and d.size() == 3 and d[0] == "slot"


func _drop_slot(_pos: Vector2, d: Variant, owner_of: Callable, i: int) -> void:
	_drag_ended_at = Time.get_ticks_msec()
	_move(d[1], d[2], owner_of.call(), i)
	picked = null
	refresh()


func _drop_trash(_pos: Vector2, d: Variant) -> void:
	_pick_slot(d[1], d[2])
	_act("trash")


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_ended_at = Time.get_ticks_msec()


func _tap_slot(o: Inventory, i: int) -> void:
	if o == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _last_tap[0] == o and _last_tap[1] == i and now - _last_tap[2] < 0.35:
		_last_tap = [null, -1, 0.0]
		picked = [o, i]
		_act("quick")                              # double tap
		return
	_last_tap = [o, i, now]
	if picked != null and (picked[0] != o or picked[1] != i):
		_move(picked[0], picked[1], o, i)
		picked = null
		Sfx.play("click", -8.0)
	elif picked != null:
		picked = null
	elif o.slots[i] != null:
		picked = [o, i]
		Sfx.play("click", -12.0, 1.3)
	refresh()


func _pick_slot(o: Inventory, i: int) -> void:
	picked = [o, i] if o != null and o.slots[i] != null else null


## Move a stack (or `amount` of it) to another slot: merge with the same item, else swap.
func _move(src: Inventory, si: int, dst: Inventory, di: int, amount := -1) -> void:
	if src == null or dst == null or (src == dst and si == di):
		return
	var a = src.slots[si]
	if a == null:
		return
	var b = dst.slots[di]
	var n: int = a[1] if amount < 0 else mini(amount, a[1])
	if b == null:
		var moved: Array = a.duplicate()
		moved[1] = n
		dst.slots[di] = moved
		a[1] -= n
		if a[1] <= 0:
			src.slots[si] = null
	elif b[0] == a[0] and a.size() < 3 and b.size() < 3:
		var t := mini(Items.max_stack(a[0]) - b[1], n)
		b[1] += t
		a[1] -= t
		if a[1] <= 0:
			src.slots[si] = null
	elif amount < 0:
		src.slots[si] = b
		dst.slots[di] = a


func _act(what: String) -> void:
	if picked == null:
		message.emit(I18n.t("pick_first"))
		return
	var o: Inventory = picked[0]
	var i: int = picked[1]
	var st = o.slots[i]
	if st == null:
		picked = null
		refresh()
		return
	match what:
		"quick":
			if o == chest:
				chest.slots[i] = inv.give(st)
			elif chest != null:
				inv.slots[i] = chest.give(st)
			else:
				inv.quick_move(i)
			picked = null
		"split":
			if st[1] < 2:
				message.emit(I18n.t("cant_split"))
			else:
				var empty := o.slots.find(null)
				if empty == -1:
					message.emit(I18n.t("inventory_full"))
				else:
					_move(o, i, o, empty, st[1] / 2)
		"trash":
			o.slots[i] = null
			picked = null
			if not creative:
				drop_stack.emit(st)
			Sfx.play("pop", -6.0, 0.8)
	refresh()


func _sort() -> void:
	# merge equal stacks, then order the bag (not the hotbar) by tab and id
	var stacks := []
	for i in range(9, 36):
		if inv.slots[i] != null:
			stacks.append(inv.slots[i])
			inv.slots[i] = null
	var tab_of := {}
	for c in Items.creative:
		tab_of[int(c[0])] = Items.tabs.find(c[1])
	stacks.sort_custom(func(a, b):
		var ta: int = tab_of.get(int(a[0]), 99)
		var tb: int = tab_of.get(int(b[0]), 99)
		return ta < tb if ta != tb else a[0] < b[0])
	for st in stacks:
		var placed := false
		if st.size() < 3:
			for i in range(9, 36):
				var s2 = inv.slots[i]
				if s2 != null and s2[0] == st[0] and s2.size() < 3 and s2[1] < Items.max_stack(st[0]):
					var t := mini(Items.max_stack(st[0]) - s2[1], st[1])
					s2[1] += t
					st[1] -= t
					if st[1] <= 0:
						placed = true
						break
		if not placed:
			for i in range(9, 36):
				if inv.slots[i] == null:
					inv.slots[i] = st
					break
	picked = null
	Sfx.play("pop", -8.0)
	refresh()


# ---------------------------------------------------------------- opening
func open(inventory: Inventory, is_creative: bool, chest_inventory: Inventory = null, kind := "") -> void:
	inv = inventory
	creative = is_creative
	chest = chest_inventory
	station = "chest" if chest != null else kind
	picked = null
	recipe = null
	expanded = ""
	_grid_key = ""
	visible = true
	refresh()


func close() -> void:
	picked = null
	visible = false


# ---------------------------------------------------------------- refresh
func refresh() -> void:
	if inv == null:
		return
	for i in 36:
		_show_slot(_inv_slots[i], inv.slots[i], picked != null and picked[0] == inv and picked[1] == i, i == hotbar_selected)
	var in_chest := station == "chest"
	_chest_grid.visible = in_chest
	if in_chest:
		for i in 27:
			_show_slot(_chest_slots[i], chest.slots[i], picked != null and picked[0] == chest and picked[1] == i, false)
	var book := not creative and not in_chest
	_content_scroll.visible = not in_chest
	_recipe_panel.visible = book and recipe != null
	_tab_box.get_parent().visible = not in_chest
	_search.visible = not in_chest
	_craftable_button.visible = book
	_craftable_button.button_pressed = craftable_only
	_mode_button.visible = not in_chest and station == ""
	_mode_button.text = I18n.t("to_survival") if creative else I18n.t("to_creative")
	_creative_tools.visible = creative and not in_chest
	for t in _tab_buttons:
		var on: bool = t == tab and _search.text == ""
		_tab_buttons[t].add_theme_stylebox_override("normal", _slot_style(Color(0.25, 0.4, 0.6) if on else Color(0.16, 0.17, 0.2), Color(1, 1, 1, 0.5 if on else 0.1)))
	if in_chest:
		_title.text = I18n.t("chest")
	elif station == "furnace":
		_title.text = I18n.t("furnace_title")
	elif creative:
		_title.text = I18n.t("creative")
		for n in 9:
			_hotbar_buttons[n].modulate = Color(0.6, 0.85, 1.4) if saved_hotbars[n] != null else Color.WHITE
		_save_toggle.button_pressed = save_hotbar_mode
	else:
		_title.text = I18n.t("crafting")
	if not in_chest:
		if creative:
			_fill_creative()
		else:
			_fill_book()
	_show_info()


func _show_slot(p: Panel, stack, is_picked: bool, is_selected: bool) -> void:
	hud.show_stack(p.get_meta("parts"), stack, SLOT, not creative)
	var border := PICKED if is_picked else (Color(1, 1, 1, 0.55) if is_selected else Color(1, 1, 1, 0.16))
	p.add_theme_stylebox_override("panel", _slot_style(Color(0.2, 0.18, 0.08, 0.95) if is_picked else Color(0.07, 0.08, 0.1, 0.95), border, 3 if is_picked else (2 if is_selected else 1)))


func _show_info() -> void:
	var item := -1
	var stack = null
	if picked != null:
		stack = picked[0].slots[picked[1]]
		if stack != null:
			item = stack[0]
	elif recipe != null:
		item = recipe["out"][0]
	_info_actions.visible = picked != null and stack != null
	if item == -1:
		_info_icon.texture = null
		_info_name.text = I18n.t("items_hint_title")
		_info_text.text = I18n.t("items_hint_creative" if creative else "items_hint")
		return
	_info_icon.texture = hud.icon_for(item)
	_info_name.text = Items.name_of(item) + (("  ×%d" % stack[1]) if stack != null and stack[1] > 1 and not creative else "")
	_info_text.text = describe(item)


## One line about an item: what it is good for.
func describe(item: int) -> String:
	var parts := []
	if Items.tools.has(item):
		var t: Dictionary = Items.tools[item]
		parts.append(I18n.f("info_tool", [int(t["durability"])]))
	elif Items.food.has(item):
		parts.append(I18n.f("info_food", [int(Items.food[item])]))
	elif Blocks.defs.has(item):
		var d: Dictionary = Blocks.defs[item]
		if int(d.get("emit", 0)) > 0:
			parts.append(I18n.t("info_light"))
		if d.get("container", false):
			parts.append(I18n.t("info_container"))
		if d.get("tool") != null and str(d.get("tool")) != "":
			parts.append(I18n.f("info_mine_with", I18n.t("tool_" + str(d["tool"]))))
		if _family_of.has(item):
			parts.append(I18n.f("info_variants", _families[_family_of[item]].size()))
	var r := _recipe_for(item)
	if not r.is_empty():
		parts.append(I18n.t("info_recipe") + " " + _ingredients_text(r))
	return "  •  ".join(parts)


func _recipe_for(item: int) -> Dictionary:
	for r in Items.recipes:
		if int(r["out"][0]) == item:
			return r
	return {}


func _ingredients_text(r: Dictionary) -> String:
	var parts := []
	for k in r["in"]:
		parts.append("%d %s" % [r["in"][k], Items.ingredient_name(k)])
	return " + ".join(parts)


# ---------------------------------------------------------------- creative grid
func _tab_items() -> Array:
	if _search.text != "":
		return Items.creative_items("all", _search.text)
	match tab:
		"favorites":
			return Array(I18n.settings.get("favorites", [])).map(func(v): return int(v))
		"recent":
			return Array(I18n.settings.get("recent", [])).map(func(v): return int(v))
	return Items.creative_items(tab, "")


func _fill_creative() -> void:
	var key := "c|%s|%s|%s|%d" % [tab, _search.text, expanded, I18n.settings.get("favorites", []).size()]
	if key == _grid_key:
		return
	_grid_key = key
	_clear_grid()
	var items := _tab_items()
	var grouped := _search.text == "" and tab not in ["favorites", "recent"]
	var shown_families := {}
	if items.is_empty():
		_empty_note(I18n.t("no_favorites") if tab == "favorites" else I18n.t("nothing_found"))
	for item in items:
		var fam: String = _family_of.get(item, "") if grouped else ""
		if fam != "":
			if shown_families.has(fam):
				continue
			shown_families[fam] = true
			_palette_slot(item, fam, false)
			if fam == expanded:
				for v in _families[fam]:
					if v != item:
						_palette_slot(v, "", true)
		else:
			_palette_slot(item, "", false)


func _clear_grid() -> void:
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()


func _empty_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_grid.add_child(l)


## A creative item. Tap: give it (or open its family). Hold: favourite. Drag: scroll the list.
func _palette_slot(item: int, family: String, in_family: bool) -> void:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(SLOT, SLOT)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var fav: bool = Array(I18n.settings.get("favorites", [])).has(item)
	var bg := FAMILY_BG if in_family or (family != "" and family == expanded) else Color(0.07, 0.08, 0.1, 0.95)
	p.add_theme_stylebox_override("panel", _slot_style(bg, Color(1, 0.86, 0.3, 0.8) if fav else Color(1, 1, 1, 0.16), 2 if fav else 1))
	var parts := hud.make_slot_parts(p, SLOT)
	hud.show_stack(parts, [item, 1], SLOT, false)
	if family != "":
		var badge := Label.new()
		badge.text = "−" if family == expanded else "+%d" % (_families[family].size() - 1)
		badge.add_theme_font_size_override("font_size", 13)
		badge.add_theme_color_override("font_color", Color.WHITE)
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(0.15, 0.45, 0.85) if family != expanded else Color(0.85, 0.45, 0.15)
		bs.set_corner_radius_all(8)
		bs.content_margin_left = 4
		bs.content_margin_right = 4
		badge.add_theme_stylebox_override("normal", bs)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(SLOT - 30, 1)
		p.add_child(badge)
		badge.position.x = SLOT - badge.get_combined_minimum_size().x - 1
	var state := {"down": false, "t": 0.0, "moved": 0.0, "held": false}
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				state["down"] = true
				state["t"] = Time.get_ticks_msec() / 1000.0
				state["moved"] = 0.0
				state["held"] = false
				_hold_check(p, state, item)
			elif state["down"]:
				state["down"] = false
				if not state["held"] and state["moved"] < 14.0:
					_tap_palette(item, family)
		elif e is InputEventMouseMotion and state["down"]:
			state["moved"] += e.relative.length()
			_content_scroll.scroll_vertical -= int(e.relative.y)    # drag scrolls, also on top of slots
		elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_toggle_favorite(item))
	_grid.add_child(p)


func _hold_check(p: Panel, state: Dictionary, item: int) -> void:
	await get_tree().create_timer(HOLD).timeout
	if is_instance_valid(p) and state["down"] and state["moved"] < 14.0:
		state["held"] = true
		_toggle_favorite(item)


func _toggle_favorite(item: int) -> void:
	var favs: Array = Array(I18n.settings.get("favorites", [])).map(func(v): return int(v))
	if favs.has(item):
		favs.erase(item)
		message.emit(I18n.f("unfavorited", Items.name_of(item)))
	else:
		favs.append(item)
		message.emit(I18n.f("favorited", Items.name_of(item)))
	I18n.settings["favorites"] = favs
	I18n.save_settings()
	_grid_key = ""
	Sfx.play("pop", -8.0, 1.2)
	refresh()


func _tap_palette(item: int, family: String) -> void:
	if family != "" and family != expanded:
		expanded = family                        # first tap on a family opens it
		refresh()
		return
	if family != "" and family == expanded and save_hotbar_mode:
		return
	# into the picked slot, else the first empty hotbar slot, else the selected hotbar slot
	var slot := -1
	if picked != null and picked[0] == inv:
		slot = picked[1]
	else:
		for i in 9:
			if inv.slots[i] == null:
				slot = i
				break
	if slot == -1:
		slot = hotbar_selected
	inv.slots[slot] = Items.new_stack(item, Items.max_stack(item))
	note_recent(item)
	picked = null
	message.emit(I18n.f("added", Items.name_of(item)))
	Sfx.play("click", -6.0)
	refresh()


static func note_recent(item: int) -> void:
	var rec: Array = Array(I18n.settings.get("recent", [])).map(func(v): return int(v))
	rec.erase(item)
	rec.push_front(item)
	I18n.settings["recent"] = rec.slice(0, 27)


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
			var st = saved_hotbars[n][i]
			inv.slots[i] = st.map(func(v): return int(v)) if st != null else null
		message.emit(I18n.f("hotbar_loaded", n + 1))
	refresh()


# ---------------------------------------------------------------- recipe book (survival)
func _recipes_shown() -> Array:
	var all: Array = Items.recipes.filter(func(r): return str(r.get("station", "")) == station)
	var text := _search.text.to_lower()
	var tab_of := {}
	for c in Items.creative:
		tab_of[int(c[0])] = c[1]
	var out := []
	for r in all:
		var o: int = int(r["out"][0])
		if text != "":
			if not text in (Items.name_of(o) + " " + str(Items.names.get(o, ""))).to_lower():
				continue
		elif tab not in ["all", "favorites", "recent"] and tab_of.get(o, "") != tab:
			continue
		elif tab == "favorites" and not Array(I18n.settings.get("favorites", [])).has(o):
			continue
		if craftable_only and not inv.can_craft(r):
			continue
		out.append(r)
	out.sort_custom(func(a, b): return inv.can_craft(a) and not inv.can_craft(b))
	return out


func _fill_book() -> void:
	_grid_key = ""
	_clear_grid()
	var shown := _recipes_shown()
	if shown.is_empty():
		_empty_note(I18n.t("nothing_found"))
	for r in shown:
		var can := inv.can_craft(r)
		var p := Panel.new()
		p.custom_minimum_size = Vector2(SLOT, SLOT)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		var border := PICKED if r == recipe else (Color(0.4, 1, 0.5, 0.9) if can else Color(1, 1, 1, 0.12))
		p.add_theme_stylebox_override("panel", _slot_style(Color(0.08, 0.16, 0.1, 0.95) if can else Color(0.07, 0.08, 0.1, 0.95), border, 3 if r == recipe else (2 if can else 1)))
		var parts := hud.make_slot_parts(p, SLOT)
		hud.show_stack(parts, [int(r["out"][0]), int(r["out"][1])], SLOT, true)
		if not can:
			p.modulate = Color(0.6, 0.6, 0.6)
		var state := {"down": false, "moved": 0.0}
		p.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					state["down"] = true
					state["moved"] = 0.0
				elif state["down"]:
					state["down"] = false
					if state["moved"] < 14.0:
						recipe = r
						picked = null
						refresh()
			elif e is InputEventMouseMotion and state["down"]:
				state["moved"] += e.relative.length()
				_content_scroll.scroll_vertical -= int(e.relative.y))
		_grid.add_child(p)
	_fill_recipe_panel()


func _fill_recipe_panel() -> void:
	for c in _recipe_panel.get_children():
		_recipe_panel.remove_child(c)
		c.queue_free()
	if recipe == null:
		return
	var r: Dictionary = recipe
	var sep := HSeparator.new()
	_recipe_panel.add_child(sep)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 12)
	_recipe_panel.add_child(row)
	for k in r["in"]:
		var need := int(r["in"][k])
		var have := _have(k)
		var l := Label.new()
		l.text = "%s  %d/%d" % [Items.ingredient_name(k), mini(have, need), need]
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.5, 1, 0.55) if have >= need else Color(1, 0.5, 0.45))
		row.add_child(l)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_recipe_panel.add_child(buttons)
	var one := _button(I18n.f("craft_n", [1, int(r["out"][1])]), func(): _craft(r, 1), 0, "build")
	var most := _max_crafts(r)
	var all := _button(I18n.f("craft_all", [most * int(r["out"][1])]), func(): _craft(r, most), 0, "quick")
	one.disabled = most == 0
	all.disabled = most < 2
	buttons.add_child(one)
	buttons.add_child(all)


func _have(key) -> int:
	if key is String:
		var n := 0
		for i in Items.groups.get(key, []):
			n += inv.count(int(i))
		return n
	return inv.count(int(key))


func _max_crafts(r: Dictionary) -> int:
	var most := 999
	for k in r["in"]:
		most = mini(most, _have(k) / maxi(1, int(r["in"][k])))
	return mini(most, 64)


func _craft(r: Dictionary, times: int) -> void:
	var made := 0
	for i in times:
		if inv.craft(r):
			made += 1
		else:
			break
	if made > 0:
		Sfx.play("pop")
		message.emit(I18n.f("crafted", [made * int(r["out"][1]), Items.name_of(int(r["out"][0]))]))
	else:
		message.emit(I18n.t("missing_ingredients") if not inv.can_craft(r) else I18n.t("inventory_full"))
	refresh()
