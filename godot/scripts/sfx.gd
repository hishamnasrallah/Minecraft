extends Node
## Sound effects (autoload "Sfx"): a small pool of players so sounds can overlap, slight
## random pitch so repeats don't sound robotic, and the volume from Settings.

const POOL := 8
const NAMES := ["dig_stone", "dig_dirt", "dig_wood", "dig_glass", "dig_soft", "place", "step",
	"splash", "hurt", "eat", "pop", "click", "rain", "cluck", "bleat", "croak", "chirp", "note"]

var _streams := {}
var _players := []
var _next := 0
var played := {}                 # name -> how many times (for tests)


func _ready() -> void:
	for n in NAMES:
		_streams[n] = load("res://data/sounds/%s.wav" % n)
	for i in POOL:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	apply_volume()


func apply_volume() -> void:
	var v := float(I18n.settings.get("sound", 0.8))
	AudioServer.set_bus_mute(0, v <= 0.01)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(v, 0.01)))


func play(name: String, volume_db := 0.0, pitch := 1.0, jitter := 0.08) -> void:
	var s = _streams.get(name)
	if s == null:
		return
	played[name] = played.get(name, 0) + 1
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(1.0 - jitter, 1.0 + jitter)
	p.play()


## Which digging sound a block makes, from what it is made of.
func dig_sound(block: int) -> String:
	var d: Dictionary = Blocks.defs.get(block, {})
	var name: String = d.get("name", "")
	if "glass" in name or name in ["ice", "lamp"]:
		return "dig_glass"
	if d.get("leaves", false) or d.get("shape") == "cross" or "wool" in name or name == "bed":
		return "dig_soft"
	match d.get("tool"):
		"pickaxe":
			return "dig_stone"
		"axe":
			return "dig_wood"
	return "dig_dirt"
