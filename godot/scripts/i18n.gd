extends Node
## Translations (autoload "I18n"): UI text and item names in Arabic or English.
## Data comes from data/i18n.json (exported from i18n.py). The language follows the phone's
## language the first time, then whatever you pick in Settings (saved in user://settings.json).

signal changed

const SETTINGS := "user://settings.json"

var lang := "en"
var ui := {}
var names_ar := {}
var groups_ar := {}
var tabs_ar := {}
var settings := {"lang": "", "sensitivity": 1.0, "view_distance": 0, "show_fps": true, "sound": 0.8}


func _init() -> void:
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n.json"))
	ui = d["ui"]
	for k in d["names_ar"]:
		names_ar[int(k)] = d["names_ar"][k]
	groups_ar = d["groups_ar"]
	tabs_ar = d["tabs_ar"]
	if FileAccess.file_exists(SETTINGS):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS))
		if saved is Dictionary:
			settings.merge(saved, true)
	lang = settings["lang"] if settings["lang"] in ["ar", "en"] else ("ar" if OS.get_locale_language() == "ar" else "en")


func save_settings() -> void:
	settings["lang"] = lang
	var f := FileAccess.open(SETTINGS, FileAccess.WRITE)
	f.store_string(JSON.stringify(settings))


func set_language(code: String) -> void:
	lang = code
	save_settings()
	changed.emit()


func is_arabic() -> bool:
	return lang == "ar"


## A UI text by key (the key itself if it's missing, so nothing ever shows blank).
func t(key: String) -> String:
	var entry = ui.get(key)
	if entry == null:
		return key
	return entry[lang]


## A UI text with %s / %d filled in.
func f(key: String, args) -> String:
	return t(key) % args


func item(id: int, english: String) -> String:
	return names_ar.get(id, english) if lang == "ar" else english


func tab(name: String) -> String:
	return tabs_ar.get(name, name) if lang == "ar" else name


func group(name: String) -> String:
	return groups_ar.get(name, name) if lang == "ar" else name
