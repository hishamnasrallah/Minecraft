class_name Wildlife
extends RefCounted
## Wandering animals: behaviour, simple voxel physics and spawning. Port of animals.py.

const GRAVITY := 20.0
const MAX_ANIMALS := 12
const MAX_HOSTILE := 6
const CHASE_RANGE := 18.0
const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 3
const SPAWN_EVERY := 2.0
const SPAWN_MIN := 18.0
const SPAWN_MAX := 44.0
const DESPAWN_DISTANCE := 70.0
const SPECIES := {
	"rabbit": {"speed": 3.4, "height": 0.5, "width": 0.4, "flee_range": 5.0, "swims": false, "group": [1, 3], "health": 3},
	"deer": {"speed": 2.6, "height": 1.4, "width": 0.6, "flee_range": 3.0, "swims": false, "group": [1, 3], "health": 8},
	"duck": {"speed": 1.4, "height": 0.5, "width": 0.4, "flee_range": 2.0, "swims": true, "group": [2, 4], "health": 3},
	# the gloom: comes out in the dark, chases and hits the player, fades in sunlight
	"gloom": {"speed": 2.4, "height": 1.8, "width": 0.6, "flee_range": 0.0, "swims": false, "group": [1, 2], "health": 10,
		"hostile": true},
}
const DROPS := {"rabbit": [103, 1, 1], "deer": [103, 2, 3], "duck": [103, 1, 2], "gloom": [102, 0, 2]}   # item, min, max


static func cell(v: float) -> int:
	return floori(v + 0.5)


class Animal:
	var kind: String
	var spec: Dictionary
	var pos: Vector3
	var vy := 0.0
	var yaw := 0.0                 # degrees, 0 = +z, 90 = +x
	var state := "idle"
	var timer := 1.0
	var target := Vector2.ZERO
	var on_ground := false
	var in_water := false
	var knock := Vector2.ZERO
	var walk_phase := 0.0
	var moving := false
	var health: int
	var dead := false
	var hurt_time := 0.0
	var hostile := false
	var attack_cooldown := 0.0
	var wants_attack := false     # set when close enough to hit the player this frame
	var fade := 0.0               # >0 while dissolving in sunlight (seconds left)

	func _init(k: String, p: Vector3) -> void:
		kind = k
		spec = SPECIES[k]
		pos = p
		yaw = randf() * 360.0
		timer = randf_range(0.5, 3.0)
		health = spec["health"]
		hostile = spec.get("hostile", false)

	func blocked(world: WorldData, x: float, z: float) -> bool:
		for y in [pos.y + 0.1, pos.y + spec["height"] - 0.1]:
			if world.solid_at(Wildlife.cell(x), Wildlife.cell(y), Wildlife.cell(z)):
				return true
		return false

	func unsafe(world: WorldData, x: float, z: float) -> bool:
		if spec["swims"]:
			return false
		var feet := Wildlife.cell(pos.y - 0.4)
		for drop in 3:
			var b := world.get_block(Wildlife.cell(x), feet - drop, Wildlife.cell(z))
			if b == WorldData.WATER:
				return true
			if b != 0:
				return false
		return true

	## The player hit us. Returns [item, count] dropped if it died, else [].
	func hit(from: Vector3, damage: int) -> Array:
		health -= damage
		hurt_time = 0.25
		if health <= 0:
			dead = true
			var n := randi_range(DROPS[kind][1], DROPS[kind][2])
			return [DROPS[kind][0], n] if n > 0 else []
		var away := Vector2(pos.x - from.x, pos.z - from.z)
		away = away.normalized() if away.length() > 0.01 else Vector2(1, 0)
		knock = away * 6
		if on_ground or in_water:
			vy = 5.0
		if not hostile:
			state = "flee"
			timer = 4.0
		return []

	func think(dt: float, player: Vector3, can_target := true) -> void:
		var dist := Vector2(pos.x - player.x, pos.z - player.z).length()
		attack_cooldown -= dt
		wants_attack = false
		if hostile and can_target and dist < CHASE_RANGE and absf(player.y - pos.y) < 6:
			state = "chase"
			yaw = rad_to_deg(atan2(player.x - pos.x, player.z - pos.z))
			if dist < ATTACK_RANGE and attack_cooldown <= 0:
				wants_attack = true
				attack_cooldown = 1.0
			return
		if state == "chase":
			state = "idle"
			timer = 1.0
		if dist < spec["flee_range"]:
			state = "flee"
			timer = maxf(timer, 2.0)
		timer -= dt
		if state == "flee":
			yaw = rad_to_deg(atan2(pos.x - player.x, pos.z - player.z))
			if timer <= 0:
				state = "idle"
				timer = randf_range(1, 3)
		elif state == "walk":
			if Vector2(target.x - pos.x, target.y - pos.z).length() < 0.5 or timer <= 0:
				state = "idle"
				timer = randf_range(2, 6)
			else:
				var want := rad_to_deg(atan2(target.x - pos.x, target.y - pos.z))
				var turn := fposmod(want - yaw + 180.0, 360.0) - 180.0
				yaw += clampf(turn, -240 * dt, 240 * dt)
		elif timer <= 0:
			var a := randf() * TAU
			var d := randf_range(3, 8)
			target = Vector2(pos.x + sin(a) * d, pos.z + cos(a) * d)
			state = "walk"
			timer = 8.0

	func update(dt: float, world: WorldData, player: Vector3, can_target := true) -> void:
		dt = minf(dt, 0.1)
		hurt_time = maxf(0.0, hurt_time - dt)
		if not world.is_loaded(Wildlife.cell(pos.x), Wildlife.cell(pos.z)):
			return
		think(dt, player, can_target)
		var speed := 0.0
		if state == "flee" or state == "chase":
			speed = spec["speed"]
		elif state == "walk":
			speed = spec["speed"] * 0.45
		if in_water and not spec["swims"]:
			speed *= 0.6
		var rad := deg_to_rad(yaw)
		var dx := sin(rad) * speed * dt + knock.x * dt
		var dz := cos(rad) * speed * dt + knock.y * dt
		knock *= 0.85
		moving = false
		if dx != 0 or dz != 0:
			var length := Vector2(dx, dz).length()
			var reach: float = spec["width"] / 2.0
			var ax := pos.x + dx + dx / length * reach
			var az := pos.z + dz + dz / length * reach
			if blocked(world, ax, az):
				var step_free := not world.solid_at(Wildlife.cell(ax), Wildlife.cell(pos.y + 1.1), Wildlife.cell(az)) \
					and not world.solid_at(Wildlife.cell(ax), Wildlife.cell(pos.y + spec["height"] + 0.9), Wildlife.cell(az))
				if (on_ground or in_water) and step_free:
					vy = 7.0
				elif state == "walk":
					state = "idle"
					timer = randf_range(1, 3)
			elif state == "chase" and Vector2(player.x - pos.x, player.z - pos.z).length() < ATTACK_RANGE * 0.7:
				pass                               # close enough: stop and hit instead of pushing in
			elif state != "flee" and state != "chase" and unsafe(world, ax, az):
				state = "idle"
				timer = randf_range(1, 3)
				yaw += 180
			else:
				pos.x += dx
				pos.z += dz
				moving = speed > 0
				walk_phase += length * 6
		in_water = world.get_block(Wildlife.cell(pos.x), Wildlife.cell(pos.y + spec["height"] * 0.4), Wildlife.cell(pos.z)) == WorldData.WATER
		if in_water:
			vy = minf(vy + 25 * dt, 1.5) if vy < 5 else vy - GRAVITY * dt
			vy *= 0.9
		else:
			vy -= GRAVITY * dt
		var new_y := pos.y + vy * dt
		on_ground = false
		if vy <= 0:
			var below := Wildlife.cell(new_y - 0.01)
			if world.solid_at(Wildlife.cell(pos.x), below, Wildlife.cell(pos.z)):
				new_y = below + 0.5
				vy = 0.0
				on_ground = true
		elif world.solid_at(Wildlife.cell(pos.x), Wildlife.cell(new_y + spec["height"]), Wildlife.cell(pos.z)):
			new_y = pos.y
			vy = 0.0
		pos.y = new_y


var world: WorldData
var animals := []
var _spawn_timer := 0.0


func _init(w: WorldData) -> void:
	world = w


## Moves every animal. Returns how much damage the player takes this frame from attacks.
## daylight: 0 at night .. 1 at noon. hostile: night monsters on/off. can_target: false in creative.
func update(dt: float, player: Vector3, daylight := 1.0, hostile := true, can_target := true) -> int:
	var damage := 0
	for a in animals.duplicate():
		a.update(dt, world, player, can_target)
		if a.wants_attack:
			damage += ATTACK_DAMAGE
		if a.hostile:
			if not hostile:
				a.dead = true
			elif a.fade > 0:
				a.fade -= dt
				if a.fade <= 0:
					a.dead = true
			elif daylight > 0.6 and _open_sky(a.pos):
				a.fade = 2.0                   # dissolves in sunlight
		var gone := not world.is_loaded(cell(a.pos.x), cell(a.pos.z))
		if a.dead or gone or Vector2(a.pos.x - player.x, a.pos.z - player.z).length() > DESPAWN_DISTANCE or a.pos.y < -10:
			animals.erase(a)
	_spawn_timer -= dt
	if _spawn_timer <= 0:
		_spawn_timer = SPAWN_EVERY
		try_spawn(player)
		if hostile:
			try_spawn_hostile(player, daylight)
	return damage


func _open_sky(p: Vector3) -> bool:
	var col = world.column(cell(p.x), cell(p.z))
	return col != null and cell(p.y + 0.3) > col[0]


func hostile_count() -> int:
	return animals.filter(func(a): return a.hostile).size()


## Glooms appear in the dark: on the surface at night, or in caves at any time,
## never within 8 blocks of a lamp or torch.
func try_spawn_hostile(player: Vector3, daylight: float) -> Array:
	if hostile_count() >= MAX_HOSTILE:
		return []
	var a := randf() * TAU
	var d := randf_range(16.0, 40.0)
	var x := cell(player.x + sin(a) * d)
	var z := cell(player.z + cos(a) * d)
	var col = world.column(x, z)
	if col == null:
		return []
	var top: int = col[0]
	var y := -1
	if daylight < 0.35 and col[1] < top and world.solid_at(x, top, z) and world.get_block(x, top + 1, z) == 0 \
			and world.get_block(x, top + 2, z) == 0:
		y = top + 1                            # dark surface
	else:
		for cy in range(top - 2, 2, -1):       # a cave: 2 cells of air with solid ground below
			if world.get_block(x, cy, z) == 0 and world.get_block(x, cy + 1, z) == 0 and world.solid_at(x, cy - 1, z):
				y = cy
				break
	if y < 0 or _near_light(Vector3i(x, y, z)):
		return []
	var g := Animal.new("gloom", Vector3(x, y - 0.5, z))
	if g.blocked(world, g.pos.x, g.pos.z):
		return []
	animals.append(g)
	return [g]


func _near_light(p: Vector3i) -> bool:
	var key := WorldData.chunk_key(p.x, p.z)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for e in world.emitters.get(Vector2i(key.x + dx, key.y + dz), {}):
				if (e as Vector3i - p).length_squared() < 64:
					return true
	return false


func try_spawn(player: Vector3) -> Array:
	if animals.size() >= MAX_ANIMALS:
		return []
	var a := randf() * TAU
	var d := randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := cell(player.x + sin(a) * d)
	var z := cell(player.z + cos(a) * d)
	var col = world.column(x, z)
	if col == null:
		return []
	var top: int = col[0]
	var water_top: int = col[1]
	var ground := world.get_block(x, top, z)
	var kind: String
	var y: float
	if water_top > top:
		kind = "duck"
		y = water_top + 0.3
	elif ground == 1 and top > world.WATER_LEVEL:
		kind = ["rabbit", "rabbit", "deer"].pick_random()
		y = top + 0.5
	elif ground == 6:
		kind = "duck"
		y = top + 0.5
	else:
		return []
	var spawned := []
	for i in randi_range(SPECIES[kind]["group"][0], SPECIES[kind]["group"][1]):
		if animals.size() >= MAX_ANIMALS:
			break
		var animal := Animal.new(kind, Vector3(x + randf_range(-1.5, 1.5), y, z + randf_range(-1.5, 1.5)))
		if animal.blocked(world, animal.pos.x, animal.pos.z):
			continue
		animals.append(animal)
		spawned.append(animal)
	return spawned
