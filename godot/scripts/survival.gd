class_name Survival
extends RefCounted
## Health, hunger, breath, fall damage and death. Port of survival.py (numbers from items.json).

var health: int
var hunger: int
var exhaustion := 0.0
var air: float
var dead := false
var cause := ""
var fall_top = null
var _regen := 0.0
var _starve := 0.0
var _drown := 0.0
var K: Dictionary


func _init() -> void:
	K = Items.survival
	respawn()


func respawn() -> void:
	health = int(K["MAX_HEALTH"])
	hunger = int(K["MAX_HUNGER"])
	exhaustion = 0.0
	air = float(K["MAX_AIR"])
	dead = false
	cause = ""
	fall_top = null
	_regen = 0.0
	_starve = 0.0
	_drown = 0.0


func exert(amount: float) -> void:
	exhaustion += amount
	while exhaustion >= float(K["EXHAUSTION_PER_POINT"]):
		exhaustion -= float(K["EXHAUSTION_PER_POINT"])
		hunger = maxi(0, hunger - 1)


var armor := {}                  # slot ("head", "chest", "legs", "feet") -> the piece worn


## Armour points: every point takes away 4% of a hit (at most 80%).
func armor_points() -> int:
	var n := 0
	for slot in armor:
		n += int(Items.armor.get(int(armor[slot]), {}).get("points", 0))
	return n


func damage(amount: int, why: String) -> bool:
	if dead or amount <= 0:
		return false
	if not why in ["starved", "drowned", "void", "fall"] and not armor.is_empty():
		amount = maxi(1, roundi(amount * (1.0 - minf(0.8, armor_points() * 0.04))))
	health = maxi(0, health - amount)
	if health == 0:
		dead = true
		cause = why
	return true


func eat(points: int) -> bool:
	if dead or hunger >= int(K["MAX_HUNGER"]):
		return false
	hunger = mini(int(K["MAX_HUNGER"]), hunger + points)
	return true


## Advance hunger, healing, starving and drowning. Returns the damage taken.
func tick(dt: float, moved := 0.0, head_under_water := false) -> int:
	if dead:
		return 0
	var before := health
	exert(dt * float(K["IDLE_PER_SECOND"]) + moved * float(K["WALK_PER_BLOCK"]))
	if hunger >= 18 and health < int(K["MAX_HEALTH"]):
		_regen += dt
		if _regen >= float(K["REGEN_EVERY"]):
			_regen = 0.0
			health += 1
			exert(float(K["REGEN"]))
	else:
		_regen = 0.0
	if hunger == 0:
		_starve += dt
		if _starve >= float(K["STARVE_EVERY"]):
			_starve = 0.0
			damage(1, "starved")
	else:
		_starve = 0.0
	if head_under_water:
		air = maxf(0.0, air - dt)
		if air == 0.0:
			_drown += dt
			if _drown >= float(K["DROWN_EVERY"]):
				_drown = 0.0
				damage(2, "drowned")
	else:
		air = minf(float(K["MAX_AIR"]), air + dt * 4)
		_drown = 0.0
	return maxi(0, before - health)


## Call every physics frame with the feet height. Returns fall damage taken on landing.
func track_fall(y: float, on_ground: bool, in_water: bool) -> int:
	if in_water:
		fall_top = null
		return 0
	if not on_ground:
		fall_top = y if fall_top == null else maxf(fall_top, y)
		return 0
	var hurt := 0
	if fall_top != null:
		hurt = floori(fall_top - y - float(K["SAFE_FALL"]))
		if hurt > 0:
			damage(hurt, "fell from a high place")
	fall_top = null
	return maxi(hurt, 0)


func to_data() -> Dictionary:
	return {"health": health, "hunger": hunger, "exhaustion": exhaustion, "armor": armor}


static func from_data(data) -> Survival:
	var s := Survival.new()
	if data is Dictionary:
		s.health = maxi(1, int(data.get("health", s.health)))
		s.hunger = int(data.get("hunger", s.hunger))
		s.exhaustion = float(data.get("exhaustion", 0.0))
		var ar = data.get("armor", {})
		if ar is Dictionary:
			for slot in ar:
				s.armor[str(slot)] = int(ar[slot])
	return s


## 10 icons for a 0..20 value: "full", "half" or "empty".
static func icons(value: int, maximum: int) -> Array:
	var out := []
	for i in maximum / 2:
		var left := value - i * 2
		out.append("full" if left >= 2 else ("half" if left == 1 else "empty"))
	return out
