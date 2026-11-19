class_name Wildlife
extends RefCounted
## Wandering animals: behaviour, simple voxel physics and spawning. Port of animals.py.

const GRAVITY := 20.0
const MAX_ANIMALS := 12
const SPAWN_EVERY := 2.0
const SPAWN_MIN := 18.0
const SPAWN_MAX := 44.0
const DESPAWN_DISTANCE := 70.0
const SPECIES := {
	"rabbit": {"speed": 3.4, "height": 0.5, "width": 0.4, "flee_range": 5.0, "swims": false, "group": [1, 3], "health": 3},
	"deer": {"speed": 2.6, "height": 1.4, "width": 0.6, "flee_range": 3.0, "swims": false, "group": [1, 3], "health": 8},
	"duck": {"speed": 1.4, "height": 0.5, "width": 0.4, "flee_range": 2.0, "swims": true, "group": [2, 4], "health": 3},
}
const DROPS := {"rabbit": [1, 1], "deer": [2, 3], "duck": [1, 2]}   # raw meat, min..max


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

	func _init(k: String, p: Vector3) -> void:
		kind = k
		spec = SPECIES[k]
		pos = p
		yaw = randf() * 360.0
		timer = randf_range(0.5, 3.0)
		health = spec["health"]

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

	## The player hit us. Returns the meat dropped if it died.
	func hit(from: Vector3, damage: int) -> int:
		health -= damage
		hurt_time = 0.25
		if health <= 0:
			dead = true
			return randi_range(DROPS[kind][0], DROPS[kind][1])
		var away := Vector2(pos.x - from.x, pos.z - from.z)
		away = away.normalized() if away.length() > 0.01 else Vector2(1, 0)
		knock = away * 6
		if on_ground or in_water:
			vy = 5.0
		state = "flee"
		timer = 4.0
		return 0

	func think(dt: float, player: Vector3) -> void:
		var dist := Vector2(pos.x - player.x, pos.z - player.z).length()
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

	func update(dt: float, world: WorldData, player: Vector3) -> void:
		dt = minf(dt, 0.1)
		hurt_time = maxf(0.0, hurt_time - dt)
		if not world.is_loaded(Wildlife.cell(pos.x), Wildlife.cell(pos.z)):
			return
		think(dt, player)
		var speed := 0.0
		if state == "flee":
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
			elif state != "flee" and unsafe(world, ax, az):
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


func update(dt: float, player: Vector3) -> void:
	for a in animals.duplicate():
		a.update(dt, world, player)
		var gone := not world.is_loaded(cell(a.pos.x), cell(a.pos.z))
		if a.dead or gone or Vector2(a.pos.x - player.x, a.pos.z - player.z).length() > DESPAWN_DISTANCE or a.pos.y < -10:
			animals.erase(a)
	_spawn_timer -= dt
	if _spawn_timer <= 0:
		_spawn_timer = SPAWN_EVERY
		try_spawn(player)


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
