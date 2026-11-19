class_name Tutorial
extends PanelContainer
## First-time hints: one short step at a time (look, walk, jump or fly, break, place, items).
## Each step finishes by itself when the player does it. Shown once; "Skip" ends it.

signal finished

const STEPS_SURVIVAL := ["look", "walk", "jump", "break", "place", "items", "done"]
const STEPS_CREATIVE := ["look", "walk", "fly", "break", "place", "items", "done"]
const ICONS := {"look": "rotate", "walk": "up", "jump": "jump", "fly": "fly", "break": "break",
	"place": "place", "items": "items", "done": "noon"}

var steps: Array = STEPS_SURVIVAL
var index := 0
var touch := true
var _progress := 0.0
var _done_timer := 0.0
var _icon: TextureRect
var _text: Label
var _count: Label


func _ready() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if I18n.is_arabic():
		row.layout_direction = Control.LAYOUT_DIRECTION_RTL
	add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(40, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.add_child(_icon)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 22)
	_text.custom_minimum_size.x = 420
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_text)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 16)
	_count.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	row.add_child(_count)
	var skip := Button.new()
	skip.text = I18n.t("tut_skip")
	skip.custom_minimum_size = Vector2(90, 48)
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_finish)
	row.add_child(skip)
	modulate = Color(1, 1, 1, 0.93)


func start(is_creative: bool, is_touch: bool) -> void:
	steps = STEPS_CREATIVE if is_creative else STEPS_SURVIVAL
	touch = is_touch
	index = 0
	visible = true
	_show()


func current() -> String:
	return steps[index] if visible and index < steps.size() else ""


## The game reports what the player did; matching steps move on.
## Amounts add up for "look" (radians turned) and "walk" (blocks walked).
func report(event: String, amount := 1.0) -> void:
	if current() != event:
		return
	_progress += amount
	var needed: float = {"look": 1.5, "walk": 4.0}.get(event, 1.0)
	if _progress >= needed:
		_progress = 0.0
		index += 1
		Sfx.play("pop", -6.0)
		_show()


func _show() -> void:
	if index >= steps.size():
		_finish()
		return
	var step: String = steps[index]
	_icon.texture = load("res://data/ui/%s.png" % ICONS[step])
	var key := "tut_" + step
	if step == "done":
		key += "_creative" if steps == STEPS_CREATIVE else "_survival"
		_done_timer = 9.0
	elif I18n.ui.has(key + ("_t" if touch else "_d")):
		key += "_t" if touch else "_d"
	_text.text = I18n.t(key)
	_count.text = "%d/%d" % [mini(index + 1, steps.size() - 1), steps.size() - 1] if step != "done" else ""
	reset_size()


func _process(delta: float) -> void:
	if visible and current() == "done":
		_done_timer -= delta
		if _done_timer <= 0:
			_finish()


func _finish() -> void:
	visible = false
	I18n.settings["tutorial_done"] = true
	I18n.save_settings()
	finished.emit()
