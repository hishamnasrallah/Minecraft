class_name Wildlife
extends RefCounted
## Wandering creatures: behaviour, simple voxel physics, biome-aware spawning, feeding and
## breeding. Port of animals.py (which keeps the same species table).
##
## Movement kinds: "walk" (land, steps up one block; goats jump two), "hop" (moves only in
## the air: frogs, globs), "swim" (fish: stays under water), "fly" (birds, butterflies,
## fireflies: no gravity, wander around a home point; purely ambient).
## Performance: animals beyond CLOSE blocks update every 2nd frame, beyond NEAR every 3rd,
## beyond FAR every 6th and are hidden (AnimalView checks `hidden`); idle animals skip their
## physics; each group (land, fish, ambient, hostile) has a small cap.

const GRAVITY := 20.0
const MAX_ANIMALS := 12         # passive land / water-surface animals
const MAX_FISH := 6
const MAX_AMBIENT := 6          # birds, butterflies, fireflies
const MAX_HOSTILE := 6
const CHASE_RANGE := 18.0
const ATTACK_RANGE := 1.4
const ATTACK_DAMAGE := 3
const SPAWN_EVERY := 2.0
const SPAWN_MIN := 18.0
const SPAWN_MAX := 44.0
const DESPAWN_DISTANCE := 70.0
const AMBIENT_DESPAWN := 40.0
const CLOSE := 12.0             # full-rate updates within this distance, every 2nd frame to NEAR,
const NEAR := 24.0              # every 3rd frame to FAR, every 6th (and hidden) beyond
const FAR := 48.0
const TEMPT_RANGE := 10.0
const LOVE_TIME := 30.0
const BREED_COOLDOWN := 60.0
const GROW_TIME := 240.0
const BABY_SCALE := 0.55

const STICK := 101
const COAL := 102
const RAW_MEAT := 103
const APPLE := 105
const SEEDS := 120
const WHEAT := 121
const CARROT := 123
const EGG := 124
const FEATHER := 125
const RAW_FISH := 126
const WOOL := 70                # + colour index (0..15)

# cap: which limit the species counts against ("land", "fish", "ambient", "hostile")
const SPECIES := {
	"rabbit": {"speed": 3.4, "height": 0.5, "width": 0.4, "flee_range": 5.0, "swims": false, "group": [1, 3], "health": 3,
		"food": [CARROT], "call": ""},
	"deer": {"speed": 2.6, "height": 1.4, "width": 0.6, "flee_range": 3.0, "swims": false, "group": [1, 3], "health": 8,
		"food": [APPLE], "call": ""},
	"duck": {"speed": 1.4, "height": 0.5, "width": 0.4, "flee_range": 2.0, "swims": true, "group": [2, 4], "health": 3,
		"food": [SEEDS], "call": "chirp"},
	# a round, fluffy grazer whose fleece comes in many colours
	"woolly": {"speed": 1.6, "height": 1.0, "width": 0.8, "flee_range": 0.0, "swims": false, "group": [2, 4], "health": 6,
		"food": [WHEAT], "call": "bleat"},
	# a plump little ground bird that lays eggs now and then and flutters down from ledges
	"hen": {"speed": 1.5, "height": 0.6, "width": 0.4, "flee_range": 1.5, "swims": false, "group": [2, 4], "health": 3,
		"food": [SEEDS], "call": "cluck", "flutter": true},
	"goat": {"speed": 2.2, "height": 1.1, "width": 0.6, "flee_range": 2.5, "swims": false, "group": [1, 3], "health": 7,
		"food": [WHEAT], "call": "bleat", "climb": 2},
	"frog": {"speed": 2.2, "height": 0.35, "width": 0.4, "flee_range": 2.5, "swims": true, "group": [1, 3], "health": 2,
		"move": "hop", "hop": 6.5, "call": "croak"},
	"turtle": {"speed": 0.7, "height": 0.4, "width": 0.7, "flee_range": 0.0, "swims": true, "group": [1, 2], "health": 10},
	"lizard": {"speed": 3.8, "height": 0.3, "width": 0.4, "flee_range": 4.0, "swims": false, "group": [1, 2], "health": 2},
	# water: small schools that stay under the surface
	"fish": {"speed": 1.8, "height": 0.3, "width": 0.3, "flee_range": 4.0, "swims": true, "group": [3, 5], "health": 1,
		"move": "swim", "cap": "fish"},
	# sky: ambient, not hittable
	"bird": {"speed": 4.5, "height": 0.3, "width": 0.3, "flee_range": 0.0, "swims": false, "group": [1, 3], "health": 1,
		"move": "fly", "cap": "ambient", "alt": [5.0, 11.0], "roam": 14.0, "call": "chirp"},
	"butterfly": {"speed": 1.3, "height": 0.2, "width": 0.2, "flee_range": 0.0, "swims": false, "group": [1, 2], "health": 1,
		"move": "fly", "cap": "ambient", "alt": [0.6, 2.2], "roam": 4.0},
	"firefly": {"speed": 0.6, "height": 0.1, "width": 0.1, "flee_range": 0.0, "swims": false, "group": [3, 5], "health": 1,
		"move": "fly", "cap": "ambient", "alt": [0.5, 2.5], "roam": 3.0},
	# the gloom: comes out in the dark, chases and hits the player, fades in sunlight
	"gloom": {"speed": 2.4, "height": 1.8, "width": 0.6, "flee_range": 0.0, "swims": false, "group": [1, 2], "health": 10,
		"hostile": true, "cap": "hostile", "damage": 2, "cooldown": 1.4, "sense": 32.0},
	# the bramble: a low, slow thorn crawler that hits hard; dozes off in daylight
	"bramble": {"speed": 1.25, "height": 0.7, "width": 0.9, "flee_range": 0.0, "swims": false, "group": [1, 1],
		"health": 16, "hostile": true, "cap": "hostile", "damage": 5, "cooldown": 1.8, "reach": 1.7, "sun_proof": true},
	# the bog glob: a hopping one-eyed lump that bursts into two globlets
	"glob": {"speed": 2.6, "height": 0.9, "width": 0.9, "flee_range": 0.0, "swims": true, "group": [1, 1], "health": 8,
		"hostile": true, "cap": "hostile", "move": "hop", "hop": 7.0, "damage": 2, "reach": 1.5, "splits": "globlet"},
	# workers: people who live at a farm or factory from the library. A farmer (green) walks to
	# ripe crops near home, harvests them, plants the seed again and takes the harvest to the
	# nearest chest; a smith (grey) and a baker (white) go from machine to machine tending them.
	"worker": {"speed": 2.6, "height": 1.9, "width": 0.5, "flee_range": 0.0, "swims": false, "group": [1, 1],
		"health": 20, "food": [122], "call": ""},
	"globlet": {"speed": 3.0, "height": 0.45, "width": 0.45, "flee_range": 0.0, "swims": true, "group": [1, 1], "health": 3,
		"hostile": true, "cap": "hostile", "move": "hop", "hop": 6.0, "damage": 1, "reach": 1.1},
}
const DROPS := {"rabbit": [RAW_MEAT, 1, 1], "deer": [RAW_MEAT, 2, 3], "duck": [RAW_MEAT, 1, 2], "gloom": [COAL, 0, 2],
	"woolly": [WOOL, 1, 2], "hen": [FEATHER, 1, 2], "goat": [RAW_MEAT, 1, 2], "frog": [0, 0, 0], "turtle": [0, 0, 0],
	"lizard": [0, 0, 0], "fish": [RAW_FISH, 1, 1], "bird": [FEATHER, 0, 1], "butterfly": [0, 0, 0], "firefly": [0, 0, 0],
	"bramble": [STICK, 1, 3], "glob": [0, 0, 0], "globlet": [SEEDS, 0, 1], "worker": [0, 0, 0]}   # item, min, max
# colour variants: woolly fleece = wool colour index (mostly naturals); see AnimalView.PALETTES
const WOOL_COLOURS := [0, 0, 0, 0, 1, 1, 2, 3, 4, 4, 6, 7, 10, 12, 13, 14]
const VARIANTS := {"rabbit": 2, "fish": 3, "butterfly": 4, "bird": 3, "worker": 3}
const NIGHT_RESTERS := ["woolly", "hen", "goat", "deer"]
const AROUND := [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3), Vector2i(-3, -3)]

static var held_item := 0       # what the player is holding (food makes animals follow)
## Playing with friends (host): the other players, [peer id, position, can be attacked].
## Night creatures chase whoever is nearest; their hits on friends are collected here.
static var others: Array = []
static var remote_damage := {}  # peer id -> damage this frame


static func cell(v: float) -> int:
	return floori(v + 0.5)


static func cap_of(kind: String) -> String:
	return SPECIES[kind].get("cap", "land")


class Animal:
	var kind: String
	var spec: Dictionary
	var move: String
	var pos: Vector3
	var vy := 0.0
	var vel := Vector3.ZERO        # flyers and swimmers
	var yaw := 0.0                 # degrees, 0 = +z, 90 = +x
	var state := "idle"
	var timer := 1.0
	var target := Vector2.ZERO
	var target3 := Vector3.ZERO
	var home := Vector3.ZERO
	var on_ground := false
	var in_water := false
	var knock := Vector2.ZERO
	var walk_phase := 0.0
	var moving := false
	var health: int
	var dead := false
	var killed := false            # died from the player's hits (not despawned)
	var burn := 0.0                # time spent in lava since the last burn
	var farm := false              # lives on a farm (came with a library building): kept, but stays home
	var carry := {}                # a worker's harvest: item -> count
	var job_t := 0.0
	var work_cell = null           # the crop or machine a worker is going to
	var hurt_time := 0.0
	var hostile := false
	var ambient := false
	var attack_cooldown := 0.0
	var wants_attack := false     # set when close enough to hit the player this frame
	var fade := 0.0               # >0 while dissolving in sunlight (seconds left)
	var dormant := false          # brambles in daylight
	var variant := 0              # colour variant (wool colour for woollies)
	var age := 0.0                # >0: a baby, grows up when it reaches 0
	var love := 0.0               # >0: fed, looking for a mate
	var breed_cd := 0.0
	var tame := false
	var fed := false              # was just fed (Wildlife takes the food from the player)
	var egg_timer := 0.0
	var hop_cd := 0.0
	var dry_time := 0.0           # fish out of water
	var call_timer := 0.0
	var hidden := false           # far away: not drawn
	var slot := 0                 # spreads far updates over frames
	var acc := 0.0                # time saved up between far updates
	var player_dist := 0.0
	var rest_check := 0.0         # standing still: the ground is only re-checked now and then
	var frozen := false           # testing lineup: stands still
	var uid := 0                  # number shared with friends (given by the host)
	var net_pos := Vector3.ZERO   # friends: where the host says it is (we glide there)

	func _init(k: String, p: Vector3) -> void:
		kind = k
		spec = SPECIES[k]
		move = spec.get("move", "walk")
		pos = p
		home = p
		target3 = p
		yaw = randf() * 360.0
		timer = randf_range(0.5, 3.0)
		health = spec["health"]
		hostile = spec.get("hostile", false)
		ambient = Wildlife.cap_of(k) == "ambient"
		slot = randi() % 6
		call_timer = randf_range(4.0, 20.0)
		if k == "woolly":
			variant = Wildlife.WOOL_COLOURS.pick_random()
		elif VARIANTS.has(k):
			variant = randi() % int(VARIANTS[k])
		if k == "hen":
			egg_timer = randf_range(60.0, 150.0)

	func size() -> float:
		return Wildlife.BABY_SCALE if age > 0 else 1.0

	func blocked(world: WorldData, x: float, z: float) -> bool:
		if world.solid_at(Wildlife.cell(x), Wildlife.cell(pos.y + 0.1), Wildlife.cell(z)):
			return true
		return world.solid_at(Wildlife.cell(x), Wildlife.cell(pos.y + spec["height"] - 0.1), Wildlife.cell(z))

	func unsafe(world: WorldData, x: float, z: float) -> bool:
		if spec["swims"]:
			return false
		var feet := Wildlife.cell(pos.y - 0.4)
		for drop in 3:
			var b := world.get_block(Wildlife.cell(x), feet - drop, Wildlife.cell(z))
			if Blocks.is_water(b):
				return true
			if b != 0:
				return false
		return true

	func wants_food(item: int) -> bool:
		return item != 0 and not hostile and spec.has("food") and item in spec["food"]

	## The player hit us. Returns [item, count] dropped if it died, else [].
	## Holding the food this animal likes feeds it instead (no damage).
	func hit(from: Vector3, damage: int) -> Array:
		if wants_food(Wildlife.held_item):
			if age > 0:
				age = maxf(0.0, age - 60.0)       # babies grow up faster
				fed = true
			elif love <= 0 and breed_cd <= 0:
				love = Wildlife.LOVE_TIME
				fed = true
			tame = true
			return []
		if tame and damage <= 1:
			return []                          # a bare hand is a pat: pets are not hurt by it
		health -= damage
		hurt_time = 0.25
		if health <= 0:
			dead = true
			killed = true
			var d: Array = DROPS[kind]
			var n := randi_range(d[1], d[2])
			if age > 0 or d[0] == 0 or n <= 0:
				return []
			return [d[0] + variant if kind == "woolly" else d[0], n]
		var away := Vector2(pos.x - from.x, pos.z - from.z)
		away = away.normalized() if away.length() > 0.01 else Vector2(1, 0)
		knock = away * 6
		if on_ground or in_water:
			vy = 5.0
		if not hostile:
			state = "flee"
			timer = 4.0
			love = 0.0
		return []

	func think(dt: float, player: Vector3, can_target := true) -> void:
		var px := player.x - pos.x
		var pz := player.z - pos.z
		var dist := sqrt(px * px + pz * pz)
		player_dist = dist
		attack_cooldown -= dt
		wants_attack = false
		if hostile:
			if can_target and not dormant and dist < float(spec.get("sense", CHASE_RANGE)) and absf(player.y - pos.y) < 6:
				state = "chase"
				yaw = rad_to_deg(atan2(px, pz))
				if dist < float(spec.get("reach", ATTACK_RANGE)) and attack_cooldown <= 0:
					wants_attack = true
					attack_cooldown = float(spec.get("cooldown", 1.0))
				return
			if state == "chase":
				state = "idle"
				timer = 1.0
		elif state != "flee" and wants_food(Wildlife.held_item) and dist < TEMPT_RANGE:
			state = "follow"
			yaw = rad_to_deg(atan2(px, pz))
			return
		elif tame and not farm and not spec["swims"] and dist < 48.0 and (dist > 7.0 or (state == "follow" and dist > 3.0)):
			state = "follow"                       # a pet tags along when you walk off
			yaw = rad_to_deg(atan2(px, pz))
			return
		elif state == "follow":
			state = "idle"
			timer = 1.0
		if dist < spec["flee_range"] and not tame:
			state = "flee"
			timer = maxf(timer, 2.0)
		timer -= dt
		if state == "flee":
			yaw = rad_to_deg(atan2(-px, -pz))
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
			if farm and Vector2(home.x - pos.x, home.z - pos.z).length() > 4.0:
				target = Vector2(home.x, home.z) + Vector2(randf_range(-2, 2), randf_range(-2, 2))
			state = "walk"
			timer = 8.0

	func update(dt: float, world: WorldData, player: Vector3, can_target := true) -> void:
		dt = minf(dt, 0.1)
		hurt_time = maxf(0.0, hurt_time - dt)
		if not world.is_loaded(Wildlife.cell(pos.x), Wildlife.cell(pos.z)):
			return
		if move == "fly":
			_fly(dt, world)
			return
		if move == "swim":
			in_water = Blocks.is_water(world.get_block(Wildlife.cell(pos.x), Wildlife.cell(pos.y + 0.15), Wildlife.cell(pos.z)))
			if in_water:
				_swim(dt, world, player)
				return
			dry_time += dt                     # a fish on land flops about and soon dies
			if dry_time > 12.0:
				dead = true
			if on_ground:
				vy = 4.0
				yaw += randf_range(-90, 90)
			_fall(dt, world)
			return
		think(dt, player, can_target)
		var speed := 0.0
		if state == "flee" or state == "chase":
			speed = spec["speed"]
		elif state == "walk":
			speed = spec["speed"] * 0.45
		elif state == "follow":
			speed = spec["speed"] * (1.0 if player_dist > 12.0 else 0.6) if player_dist > 1.8 else 0.0
		if age > 0:
			speed *= 1.1
		if in_water and not spec["swims"]:
			speed *= 0.6
		if move == "hop":                       # only moves while in the air
			hop_cd -= dt
			if on_ground:
				if speed > 0 and hop_cd <= 0:
					vy = float(spec["hop"])
					hop_cd = randf_range(0.3, 0.9) if state == "chase" or state == "flee" else randf_range(0.8, 2.0)
					on_ground = false
				speed = 0.0 if on_ground else speed
			else:
				speed *= 1.3
		if speed == 0.0 and on_ground and not in_water and knock.length_squared() < 0.01:
			moving = false                     # idle on the ground: skip the physics most frames
			rest_check -= dt
			if rest_check > 0:
				return
			rest_check = 0.4
		else:
			rest_check = 0.0
		var rad := deg_to_rad(yaw)
		var dx := sin(rad) * speed * dt + knock.x * dt
		var dz := cos(rad) * speed * dt + knock.y * dt
		knock *= 0.85
		moving = false
		if dx != 0 or dz != 0:
			var length := sqrt(dx * dx + dz * dz)
			var reach: float = spec["width"] / 2.0
			var ax := pos.x + dx + dx / length * reach
			var az := pos.z + dz + dz / length * reach
			if blocked(world, ax, az):
				var cx := Wildlife.cell(ax)
				var cz := Wildlife.cell(az)
				var head := Wildlife.cell(pos.y + spec["height"] + 0.9)
				# fences and walls are too tall to step over (they are 1.5 blocks in the original)
				var low := world.get_block(cx, Wildlife.cell(pos.y + 0.1), cz)
				var fenced: bool = Blocks.shape[low] == "fence"
				var step_free := not fenced and not world.solid_at(cx, Wildlife.cell(pos.y + 1.1), cz) and not world.solid_at(cx, head, cz)
				var leap_free: bool = int(spec.get("climb", 1)) >= 2 and not step_free and not fenced \
					and not world.solid_at(cx, Wildlife.cell(pos.y + 2.1), cz) and not world.solid_at(cx, head + 1, cz)
				if (on_ground or in_water) and step_free:
					vy = 7.0
				elif on_ground and leap_free:
					vy = 9.4                       # goats spring up two blocks
				elif state == "walk":
					state = "idle"
					timer = randf_range(1, 3)
			elif state == "chase" and player_dist < float(spec.get("reach", ATTACK_RANGE)) * 0.7:
				pass                               # close enough: stop and hit instead of pushing in
			elif state != "flee" and state != "chase" and state != "follow" and unsafe(world, ax, az):
				state = "idle"
				timer = randf_range(1, 3)
				yaw += 180
			else:
				pos.x += dx
				pos.z += dz
				moving = speed > 0
				walk_phase += length * 6
		if move == "hop" and not on_ground:
			moving = true
		_fall(dt, world)

	## Gravity, floating in water and landing.
	func _fall(dt: float, world: WorldData) -> void:
		var h: float = spec["height"]
		in_water = Blocks.is_water(world.get_block(Wildlife.cell(pos.x), Wildlife.cell(pos.y + h * 0.4), Wildlife.cell(pos.z)))
		if in_water and move != "swim":
			vy = minf(vy + 25 * dt, 1.5) if vy < 5 else vy - GRAVITY * dt
			vy *= 0.9
		else:
			vy -= GRAVITY * dt
			if spec.get("flutter", false) and vy < -2.5:
				vy = -2.5                          # hens glide down
		var new_y := pos.y + vy * dt
		on_ground = false
		if vy <= 0:
			var below := Wildlife.cell(new_y - 0.01)
			if world.solid_at(Wildlife.cell(pos.x), below, Wildlife.cell(pos.z)):
				new_y = below + 0.5
				vy = 0.0
				on_ground = true
		elif world.solid_at(Wildlife.cell(pos.x), Wildlife.cell(new_y + h), Wildlife.cell(pos.z)):
			new_y = pos.y
			vy = 0.0
		pos.y = new_y

	## Fish: glide towards random points inside the water, dart away from the player.
	func _swim(dt: float, world: WorldData, player: Vector3) -> void:
		timer -= dt
		var away := Vector3(pos.x - player.x, 0, pos.z - player.z)
		player_dist = away.length()
		var scared: bool = player_dist < spec["flee_range"]
		if timer <= 0 or pos.distance_squared_to(target3) < 0.25 or (scared and state != "flee"):
			var t := pos
			if scared:
				t = pos + away.normalized() * 4.0
				state = "flee"
			else:
				var a := randf() * TAU
				t = pos + Vector3(sin(a) * 4.0, randf_range(-1.0, 1.0), cos(a) * 4.0)
				state = "walk"
			if Blocks.is_water(world.get_block(Wildlife.cell(t.x), Wildlife.cell(t.y), Wildlife.cell(t.z))) \
					and Blocks.is_water(world.get_block(Wildlife.cell(t.x), Wildlife.cell(t.y + 0.5), Wildlife.cell(t.z))):
				target3 = t
			timer = randf_range(2.0, 5.0)
		var to := target3 - pos
		var speed: float = spec["speed"] * (2.0 if state == "flee" else 1.0)
		if to.length_squared() > 0.01:
			vel = vel.lerp(to.normalized() * speed, minf(1.0, dt * 3.0))
		var n := pos + vel * dt
		if Blocks.is_water(world.get_block(Wildlife.cell(n.x), Wildlife.cell(n.y + 0.15), Wildlife.cell(n.z))):
			pos = n
		else:
			vel = -vel * 0.5
			timer = 0.0
		if vel.x != 0 or vel.z != 0:
			yaw = rad_to_deg(atan2(vel.x, vel.z))
		moving = true
		walk_phase += dt * (14.0 if state == "flee" else 7.0)
		vy = 0.0

	## Flyers: no gravity, wander between points around their home at their own height.
	func _fly(dt: float, world: WorldData) -> void:
		timer -= dt
		if timer <= 0 or pos.distance_squared_to(target3) < 0.36:
			var roam: float = spec["roam"]
			var x := home.x + randf_range(-roam, roam)
			var z := home.z + randf_range(-roam, roam)
			var col = world.column(Wildlife.cell(x), Wildlife.cell(z))
			var ground: float = pos.y - 2.0
			if col != null:
				ground = float(maxi(int(col[0]), int(col[1])))
			var alt: Array = spec["alt"]
			target3 = Vector3(x, ground + randf_range(alt[0], alt[1]), z)
			timer = randf_range(3.0, 8.0)
		var to := target3 - pos
		var speed: float = spec["speed"]
		if to.length_squared() > 0.0001:
			vel = vel.lerp(to.normalized() * speed, minf(1.0, dt * (1.5 if kind == "bird" else 3.0)))
		var n := pos + vel * dt
		if kind == "butterfly":
			n.y += sin(walk_phase * 0.37) * dt * 1.2
		if world.solid_at(Wildlife.cell(n.x), Wildlife.cell(n.y), Wildlife.cell(n.z)):
			vel.y = absf(speed)
			timer = 0.0
			n = pos + Vector3(0, speed * dt, 0)
			if world.solid_at(Wildlife.cell(n.x), Wildlife.cell(n.y), Wildlife.cell(n.z)):
				n = pos
		pos = n
		if absf(vel.x) + absf(vel.z) > 0.01:
			yaw = rad_to_deg(atan2(vel.x, vel.z))
		moving = true
		walk_phase += dt * (22.0 if kind == "butterfly" else 12.0)


var world: WorldData
var animals := []
var parked := []                # tame / farm animals in chunks that are not loaded
var laid := []                  # [[item, count], position] dropped while no game is attached (tests)
var _spawn_timer := 0.0
var _spawn_turn := 0
var _frame := 0
var _game_ref: WeakRef = null
var _game_check := 0.0
var _lovers := []               # reused every frame
var _born := []
var _counts := {"land": 0, "fish": 0, "ambient": 0, "hostile": 0}
var _player := Vector3.ZERO
var _zoo := 0                   # testing: 1 = show every creature in a row (`-- --zoo`), 2 = done
var _next_uid := 1
var puppet := false             # a friend's game: the host moves the animals, we only show them
var _by_uid := {}


func _init(w: WorldData) -> void:
	world = w
	_zoo = 1 if "--zoo" in OS.get_cmdline_user_args() else 0


## Moves every animal. Returns how much damage the player takes this frame from attacks.
## daylight: 0 at night .. 1 at noon. hostile: night monsters on/off. can_target: false in creative.
func update(dt: float, player: Vector3, daylight := 1.0, hostile := true, can_target := true) -> int:
	_frame += 1
	_player = player
	var game = _game(dt)
	if game != null:
		held_item = int(game.inv.item_at(game.selected))
		if _zoo == 1 and game.spawned:
			_zoo = 2
			for z: Animal in spawn_lineup(player, game.player.forward()):
				z.frozen = true
	var damage := 0
	var near2 := NEAR * NEAR
	var far2 := FAR * FAR
	_lovers.clear()
	var i := animals.size() - 1
	while i >= 0:
		var a: Animal = animals[i]
		if a.frozen:
			a.hidden = false
			i -= 1
			continue
		if a.uid == 0:
			a.uid = _next_uid
			_next_uid += 1
		var dx := a.pos.x - player.x
		var dz := a.pos.z - player.z
		var d2 := dx * dx + dz * dz
		var target := player
		var target_peer := 0
		var target_ok := can_target
		for o in others:                       # friends count as players too
			var op: Vector3 = o[1]
			var od := (a.pos.x - op.x) * (a.pos.x - op.x) + (a.pos.z - op.z) * (a.pos.z - op.z)
			if od < d2:
				d2 = od
				target = op
				target_peer = int(o[0])
				target_ok = bool(o[2])
		var hide := d2 > far2
		a.hidden = hide
		var every := 1
		if a.state != "chase" and d2 > CLOSE * CLOSE:
			every = 6 if hide else (3 if d2 > near2 else 2)
		a.acc += dt
		if every == 1 or (_frame + a.slot) % every == 0:
			a.update(a.acc, world, target, target_ok)
			a.acc = 0.0
		if a.wants_attack:
			if target_peer == 0:
				damage += int(a.spec.get("damage", ATTACK_DAMAGE))
			else:
				remote_damage[target_peer] = int(remote_damage.get(target_peer, 0)) + int(a.spec.get("damage", ATTACK_DAMAGE))
		if a.kind == "worker" and not a.dead:
			_tick_worker(a, dt, game)
		if not a.ambient and not a.dead and Blocks.fluid[world.get_block(cell(a.pos.x), cell(a.pos.y + 0.2), cell(a.pos.z))] == 2:
			_burn(a, dt, game)
		if a.hostile:
			if not hostile:
				a.dead = true
			elif a.spec.get("sun_proof", false):
				a.dormant = daylight > 0.6 and _open_sky(a.pos)
				if a.dormant and d2 > 24.0 * 24.0:
					a.dead = true                  # crawls off once out of sight
			elif a.fade > 0:
				a.fade -= dt
				if a.fade <= 0:
					a.dead = true
			elif daylight > 0.6 and _open_sky(a.pos):
				a.fade = 2.0                       # dissolves in sunlight
		elif a.ambient:
			var night_kind := a.kind == "firefly"
			if (night_kind and daylight > 0.45) or (not night_kind and daylight < 0.3):
				if d2 > 16.0 * 16.0 or a.kind == "firefly":
					a.dead = true
			if d2 > AMBIENT_DESPAWN * AMBIENT_DESPAWN:
				a.dead = true
		else:
			_tick_passive(a, dt, d2, daylight, game)
		if a.dead and a.killed and a.spec.has("splits"):
			for k in 2:
				var s := Animal.new(a.spec["splits"], a.pos + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4)))
				s.vy = 4.0
				_born.append(s)
		var gone := not world.is_loaded(cell(a.pos.x), cell(a.pos.z))
		var too_far := d2 > DESPAWN_DISTANCE * DESPAWN_DISTANCE and not a.tame
		if gone and a.tame and not a.dead:
			parked.append(a)                       # a farm or a pet far away: back when you return
			animals.remove_at(i)
		elif a.dead or gone or too_far or a.pos.y < -10:
			animals.remove_at(i)
		i -= 1
	if not _lovers.is_empty():
		_breed()
	if not _born.is_empty():
		animals.append_array(_born)
		_born.clear()
	if not parked.is_empty() and _frame % 30 == 0:
		_unpark()
	_spawn_timer -= dt
	if _spawn_timer <= 0:
		_spawn_timer = SPAWN_EVERY
		_spawn_turn += 1
		# take turns spawning around each player
		var around := player
		if not others.is_empty() and _spawn_turn % (others.size() + 1) != 0:
			around = others[_spawn_turn % (others.size() + 1) - 1][1]
		try_spawn(around)
		if _spawn_turn % 2 == 0:
			try_spawn_ambient(around, daylight)
		if hostile and _spawn_turn % 3 == 0:          # night creatures come one by one, not in a wave
			try_spawn_hostile(around, daylight)
	return damage


## Growing up, love, eggs, calls and taking the food after feeding.
func _tick_passive(a: Animal, dt: float, d2: float, daylight: float, game) -> void:
	if a.age > 0:
		a.age = maxf(0.0, a.age - dt)
	if a.breed_cd > 0:
		a.breed_cd -= dt
	if a.love > 0:
		a.love -= dt
		_lovers.append(a)
	if a.fed:
		a.fed = false
		_sound("eat", d2, -4.0)
		if game != null and not game.creative:
			game.inv.use_one(game.selected)
			game.hud.show_hotbar(game.inv, game.selected, game.creative)
	if a.kind == "hen" and a.age <= 0:
		a.egg_timer -= dt
		if a.egg_timer <= 0:
			a.egg_timer = randf_range(90.0, 180.0)
			if d2 < 40.0 * 40.0:
				_drop([EGG, 1], a.pos + Vector3(0, 0.3, 0), game)
				_sound("cluck", d2)
	if daylight < 0.25 and a.state == "walk" and a.kind in NIGHT_RESTERS:
		a.state = "idle"                       # settle down for the night
		a.timer = 5.0
	a.call_timer -= dt
	if a.call_timer <= 0:
		a.call_timer = randf_range(8.0, 24.0)
		var call: String = a.spec.get("call", "")
		if call != "" and d2 < 16.0 * 16.0:
			_sound(call, d2, 0.0, 1.35 if a.age > 0 else 1.0)


## A machine (a thrower) holds out food at `at`: the nearest animal there that likes it eats
## it (a baby grows faster, a grown one wants to breed). 1 if one ate, -1 if one that likes it
## is there but cannot eat now (in love or resting after a lamb), 0 if nobody is there.
func feed_near(at: Vector3, item: int, reach := 3.0) -> int:
	var best: Animal = null
	var best_d := reach * reach
	var full := false
	var crowd := 0
	for a: Animal in animals:
		if a.dead or not a.wants_food(item):
			continue
		var d := Vector2(a.pos.x - at.x, a.pos.z - at.z).length_squared()
		if d >= reach * reach or absf(a.pos.y - at.y) > 1.5:
			continue
		crowd += 1
		if a.age <= 0 and (a.love > 0 or a.breed_cd > 0):
			full = true                            # not now
			continue
		if d < best_d:
			best = a
			best_d = d
	if best != null and best.age <= 0 and crowd >= 8:
		return -1                                  # the pen is full: no more lambs
	if best == null:
		return -1 if full else 0
	if best.age > 0:
		best.age = maxf(0.0, best.age - 60.0)
	else:
		best.love = LOVE_TIME
	best.tame = true
	_sound("eat", best.pos.distance_squared_to(_player), -4.0)
	return 1


## A worker's job, twice a second. Farmers: walk to a ripe crop near home, harvest it, plant
## it again; with a full basket (or nothing left to pick) walk to the nearest chest and put
## the harvest in. Smiths and bakers: walk from machine to machine near home and tend them.
func _tick_worker(a: Animal, dt: float, game) -> void:
	a.job_t -= dt
	if a.job_t > 0:
		return
	a.job_t = 0.5
	if a.state == "flee" or a.state == "follow" and not a.farm:
		return
	var here := Vector3i(cell(a.pos.x), cell(a.pos.y + 0.2), cell(a.pos.z))
	var home := Vector3i(cell(a.home.x), cell(a.home.y + 0.2), cell(a.home.z))
	var basket := 0
	for k in a.carry:
		basket += int(a.carry[k])
	if a.variant == 0:
		var crop = _near(home, 7, 2, func(b: int) -> bool:
			var c = Blocks.defs.get(b, {}).get("crop")
			return c is Dictionary and int(c["next"]) == 0)
		if basket >= 12 or (basket > 0 and crop == null):
			var chest = _near(home, 8, 3, func(b: int) -> bool: return b == 48)
			if chest != null:
				if _reach(a, chest):
					var inv := Inventory.from_data(world.containers.get(chest), 27)
					for k in a.carry.keys():
						var left := inv.add(int(k), int(a.carry[k]))
						if left > 0:
							a.carry[k] = left
						else:
							a.carry.erase(k)
					world.containers[chest] = inv.to_data()
					if game != null and game.power != null:
						game.power.changed_containers[chest] = true
					a.walk_phase += 3.0
				return
		if crop != null:
			if _reach(a, crop):
				var b := world.get_block(crop.x, crop.y, crop.z)
				var c: Dictionary = Blocks.defs[b]["crop"]
				var drop := Items.drop_for(b)
				if drop != 0:
					a.carry[drop] = int(a.carry.get(drop, 0)) + 1
				var bonus = Blocks.defs[b].get("bonus")
				if bonus is Array:
					var n := randi_range(int(bonus[1]), int(bonus[2])) - 1      # one is planted again
					if n > 0:
						a.carry[int(bonus[0])] = int(a.carry.get(int(bonus[0]), 0)) + n
				if game != null:
					game.edit(crop, b - int(c["stage"]), true, false)
				else:
					world.set_block(crop.x, crop.y, crop.z, b - int(c["stage"]), true, false)
				a.walk_phase += 3.0                # the arms swing: work done
				harvested += 1
			return
	else:
		# smith (1): smelters, crafters, chests; baker (2): crafters and chests
		var wanted := [1747, 1748, 1868, 1869, 48] if a.variant == 1 else [1868, 1869, 48, 47]
		if a.work_cell == null or randf() < 0.08:
			var spots := _all_near(home, 7, 3, func(b: int) -> bool: return b in wanted)
			if not spots.is_empty():
				a.work_cell = spots.pick_random()
		if a.work_cell != null and _reach(a, a.work_cell):
			a.walk_phase += 2.0
			if randf() < 0.15:
				a.work_cell = null                 # on to the next machine


## Walk to a cell; true once standing next to it (the worker faces it).
func _reach(a: Animal, c: Vector3i) -> bool:
	var to := Vector2(c.x - a.pos.x, c.z - a.pos.z)
	if to.length() < 1.45 and absf(c.y - a.pos.y) < 2.5:
		a.state = "idle"
		a.timer = 1.5
		a.yaw = rad_to_deg(atan2(to.x, to.y))
		return true
	a.state = "walk"
	a.target = Vector2(c.x, c.z) - to.normalized() * 0.9
	a.timer = 4.0
	return false


var harvested := 0                   # crops picked by workers (tests)


func _near(centre: Vector3i, r: int, h: int, ok: Callable):
	var best = null
	var best_d := 1 << 30
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dy in range(-h, h + 1):
				var q := centre + Vector3i(dx, dy, dz)
				if ok.call(world.get_block(q.x, q.y, q.z)):
					var d := dx * dx + dz * dz + dy * dy
					if d < best_d:
						best = q
						best_d = d
	return best


func _all_near(centre: Vector3i, r: int, h: int, ok: Callable) -> Array:
	var out := []
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dy in range(-h, h + 1):
				var q := centre + Vector3i(dx, dy, dz)
				if ok.call(world.get_block(q.x, q.y, q.z)):
					out.append(q)
	return out


## Lava burns an animal; one that dies in it drops its meat cooked, at the edge of the lava.
func _burn(a: Animal, dt: float, game) -> void:
	a.burn += dt
	if a.burn < 0.5:
		return
	a.burn = 0.0
	var held := held_item
	held_item = 0                              # lava does not feed anyone
	var tame := a.tame
	a.tame = false
	var drop: Array = a.hit(a.pos, 2)
	a.tame = tame
	held_item = held
	if drop.is_empty():
		return
	var cooked := {RAW_MEAT: 104, RAW_FISH: 127}
	drop[0] = int(cooked.get(int(drop[0]), int(drop[0])))
	var at := a.pos + Vector3(0, 0.6, 0)
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var q: Vector3 = a.pos + d
		var b := world.get_block(cell(q.x), cell(q.y + 0.2), cell(q.z))
		if Blocks.fluid[b] != 2 and (b == 0 or Blocks.solid[b] == 0):
			at = q + Vector3(0, 0.3, 0)
			break
	_drop(drop, at, game)


## Pairs of fed adults walk to each other; when they meet a baby appears.
func _breed() -> void:
	for a: Animal in _lovers:
		if a.love <= 0 or a.state == "flee":
			continue
		var best: Animal = null
		var best_d := 64.0
		for b: Animal in _lovers:
			if b != a and b.kind == a.kind and b.love > 0:
				var d := a.pos.distance_squared_to(b.pos)
				if d < best_d:
					best = b
					best_d = d
		if best == null:
			continue
		if best_d < 1.7 * 1.7:
			var baby := Animal.new(a.kind, (a.pos + best.pos) * 0.5 + Vector3(0, 0.3, 0))
			baby.age = GROW_TIME
			baby.tame = true
			baby.farm = a.farm
			baby.variant = a.variant if randf() < 0.5 else best.variant
			_born.append(baby)
			for p: Animal in [a, best]:
				p.love = 0.0
				p.breed_cd = BREED_COOLDOWN
				p.state = "idle"
				p.timer = 2.0
			_sound("pop", a.pos.distance_squared_to(_player))
		else:
			a.state = "walk"
			a.target = Vector2(best.pos.x, best.pos.z)
			a.timer = 2.0


## The running game scene (for the held item, the inventory, dropping eggs), or null in tests.
func _game(dt: float):
	_game_check -= dt
	if _game_ref != null:
		if _game_ref.get_ref() != null:
			return _game_ref.get_ref()
		_game_ref = null                       # the game scene was closed
		held_item = 0
	if _game_check > 0:
		return null
	_game_check = 1.0
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = tree.current_scene if tree != null else null
	if scene != null and "inv" in scene and "drops" in scene and "selected" in scene and "hud" in scene:
		_game_ref = weakref(scene)
		return scene
	return null


func _drop(stack: Array, at: Vector3, game) -> void:
	if game != null and game.drops != null:
		game.drops.spawn(stack, at)
	else:
		laid.append([stack, at])
		if laid.size() > 16:
			laid.pop_front()


## A creature sound, quieter further away (only the 3 extra sounds load lazily).
func _sound(name: String, d2: float, volume := 0.0, pitch := 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var sfx = tree.root.get_node_or_null("Sfx") if tree != null else null
	if sfx == null or sfx._players.is_empty():
		return
	if not sfx._streams.has(name):
		var path := "res://data/sounds/%s.wav" % name
		sfx._streams[name] = load(path) if ResourceLoader.exists(path) else null
	sfx.play(name, volume - sqrt(d2) * 0.9, pitch)


func _open_sky(p: Vector3) -> bool:
	var col = world.column(cell(p.x), cell(p.z))
	return col != null and cell(p.y + 0.3) > col[0]


## Tamed animals are kept with the world (wild ones come and go): kind, place, colour, age.
func save_pets() -> Array:
	var out := []
	for a in animals + parked:
		if a.tame and not a.dead and not a.hostile:
			out.append([a.kind, a.pos.x, a.pos.y, a.pos.z, a.variant, a.age, a.health, a.farm])
	return out


## Tamed and farm animals whose ground is not loaded wait here, and come back with it.
func _unpark() -> void:
	for i in range(parked.size() - 1, -1, -1):
		var a: Animal = parked[i]
		if world.is_loaded(cell(a.pos.x), cell(a.pos.z)):
			animals.append(a)
			parked.remove_at(i)


func load_pets(list) -> void:
	if not list is Array:
		return
	for p in list:
		if not (p is Array and p.size() >= 7 and SPECIES.has(str(p[0]))):
			continue
		var a := Animal.new(str(p[0]), Vector3(float(p[1]), float(p[2]), float(p[3])))
		a.variant = int(p[4])
		a.age = float(p[5])
		a.health = int(p[6])
		a.tame = true
		a.farm = p.size() >= 8 and bool(p[7])
		a.home = a.pos
		if world.is_loaded(cell(a.pos.x), cell(a.pos.z)):
			animals.append(a)
		else:
			parked.append(a)


func hostile_count() -> int:
	return _count()["hostile"]


func _count() -> Dictionary:
	for k in _counts:
		_counts[k] = 0
	for a: Animal in animals:
		var c := cap_of(a.kind)
		_counts[c] += 1
	return _counts


## Night creatures appear in the dark: on the surface at night, or in caves at any time,
## never within 8 blocks of a lamp or torch. Glooms anywhere, brambles on grass, globs in
## caves and by water.
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
	var kind := "gloom"
	if daylight < 0.35 and col[1] < top and world.solid_at(x, top, z) and world.get_block(x, top + 1, z) == 0 \
			and world.get_block(x, top + 2, z) == 0:
		y = top + 1                            # dark surface
		var r := randf()
		if world.get_block(x, top, z) == 1 and r < 0.35:
			kind = "bramble"
		elif r > 0.8:
			kind = "glob"
	else:
		for cy in range(top - 2, 2, -1):       # a cave: 2 cells of air with solid ground below
			if world.get_block(x, cy, z) == 0 and world.get_block(x, cy + 1, z) == 0 and world.solid_at(x, cy - 1, z):
				y = cy
				break
		if randf() < 0.35:
			kind = "glob"
	if y < 0 or _near_light(Vector3i(x, y, z)):
		return []
	var g := Animal.new(kind, Vector3(x, y - 0.5, z))
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


## What lives at (x, z): [kind, y, variant] or [] (biomes from the ground block and height).
func pick_kind(x: int, z: int) -> Array:
	var col = world.column(x, z)
	if col == null:
		return []
	var top: int = col[0]
	var water_top: int = col[1]
	var ground := world.get_block(x, top, z)
	if water_top > top:
		if water_top - top >= 2 and randf() < 0.65:
			return ["fish", top + 1.0 + randf() * (water_top - top - 1.5), -1]
		return ["duck", water_top + 0.3, -1]
	var y := top + 0.5
	if ground == 6:
		if top <= world.WATER_LEVEL + 1:
			return ["turtle" if randf() < 0.4 else "duck", y, -1]       # beach
		return ["lizard", y, -1]                                       # desert
	if ground == 16 or top >= world.SNOW_LINE - 2:
		return ["goat", y, -1] if randf() < 0.6 else ["rabbit", y, 1]   # snowy heights: white rabbits
	if ground == 3 and top > world.WATER_LEVEL + 8:
		return ["goat", y, -1]
	if ground != 1 or top <= world.WATER_LEVEL:
		return []
	var wet := false
	var trees := 0
	for o: Vector2i in AROUND:
		var c = world.column(x + o.x, z + o.y)
		if c != null and c[1] > c[0]:
			wet = true
		if world.has_tree(x + o.x, z + o.y) or world.has_tree(x + o.x + 1, z + o.y):
			trees += 1
	if wet and randf() < 0.5:
		return ["frog", y, -1]
	if trees >= 2:
		return [["deer", "deer", "rabbit", "hen"].pick_random(), y, -1]   # forest
	return [["woolly", "woolly", "woolly", "hen", "hen", "rabbit", "deer"].pick_random(), y, -1]   # meadow


func try_spawn(player: Vector3) -> Array:
	var counts := _count()
	if counts["land"] >= MAX_ANIMALS and counts["fish"] >= MAX_FISH:
		return []
	var a := randf() * TAU
	var d := randf_range(SPAWN_MIN, SPAWN_MAX)
	var x := cell(player.x + sin(a) * d)
	var z := cell(player.z + cos(a) * d)
	var pick := pick_kind(x, z)
	if pick.is_empty():
		return []
	var kind: String = pick[0]
	var cap := cap_of(kind)
	var limit := MAX_FISH if cap == "fish" else MAX_ANIMALS
	var spawned := []
	var group: Array = SPECIES[kind]["group"]
	var colour := -1
	for i in randi_range(group[0], group[1]):
		if counts[cap] >= limit:
			break
		var p := Vector3(x + randf_range(-1.5, 1.5), pick[1], z + randf_range(-1.5, 1.5))
		var animal := Animal.new(kind, p)
		if pick[2] >= 0:
			animal.variant = pick[2]
		if kind == "fish":                      # a school shares a colour
			colour = animal.variant if colour < 0 else colour
			animal.variant = colour
			if not Blocks.is_water(world.get_block(cell(p.x), cell(p.y + 0.15), cell(p.z))):
				continue
		elif animal.blocked(world, animal.pos.x, animal.pos.z):
			continue
		animals.append(animal)
		spawned.append(animal)
		counts[cap] += 1
	return spawned


## Birds and butterflies by day, fireflies at night, near the player.
func try_spawn_ambient(player: Vector3, daylight: float) -> Array:
	var counts := _count()
	if counts["ambient"] >= MAX_AMBIENT or (daylight > 0.45 and daylight < 0.55):
		return []
	var a := randf() * TAU
	var d := randf_range(8.0, 26.0)
	var x := cell(player.x + sin(a) * d)
	var z := cell(player.z + cos(a) * d)
	var col = world.column(x, z)
	if col == null or col[1] > col[0]:
		return []
	var ground := world.get_block(x, col[0], z)
	var kind := ""
	if daylight < 0.3:
		if ground == 1:
			kind = "firefly"
	elif ground == 1 and randf() < 0.55:
		kind = "butterfly"
	elif ground != 16:
		kind = "bird"
	if kind == "":
		return []
	var spawned := []
	var group: Array = SPECIES[kind]["group"]
	var alt: Array = SPECIES[kind]["alt"]
	var colour := randi() % int(VARIANTS.get(kind, 1))
	for i in randi_range(group[0], group[1]):
		if counts["ambient"] >= MAX_AMBIENT:
			break
		var p := Vector3(x + randf_range(-2, 2), col[0] + randf_range(alt[0], alt[1]), z + randf_range(-2, 2))
		if world.solid_at(cell(p.x), cell(p.y), cell(p.z)):
			continue
		var f := Animal.new(kind, p)
		f.home = Vector3(x, p.y, z)
		f.variant = colour if kind == "bird" else f.variant
		animals.append(f)
		spawned.append(f)
		counts["ambient"] += 1
	return spawned


## Testing (`-- --zoo`): one of every creature in two rows in front of the player.
func spawn_lineup(origin: Vector3, forward: Vector3) -> Array:
	forward = Vector3(forward.x, 0, forward.z).normalized()
	var side := Vector3(forward.z, 0, -forward.x)
	var rows := [["rabbit", "duck", "hen", "frog", "turtle", "lizard", "fish", "globlet", "butterfly", "firefly", "bird"],
		["deer", "woolly", "goat", "gloom", "bramble", "glob"]]
	var out := []
	for r in rows.size():
		var kinds: Array = rows[r]
		var gap := 1.0 if r == 0 else 1.6
		for i in kinds.size():
			var k: String = kinds[i]
			var p := origin + forward * (4.5 + r * 3.0) + side * (i - (kinds.size() - 1) / 2.0) * gap
			var col = world.column(cell(p.x), cell(p.z))
			if col != null:
				p.y = maxf(float(col[0]), float(col[1])) + 0.5
			if k in ["bird", "butterfly", "firefly"]:
				p.y += 0.8
			var an := Animal.new(k, p)
			an.yaw = rad_to_deg(atan2(-forward.x, -forward.z)) + randf_range(-25, 25)
			an.home = p
			an.target3 = p
			an.tame = true
			out.append(an)
	animals.append_array(out)
	return out


# ---------------------------------------------------------------- playing with friends
const NET_FIELDS := 11


## Host: every animal in 11 numbers (uid, kind, position, yaw, moving, colour, age, hurt, fade).
func snapshot() -> PackedFloat32Array:
	var kinds: Array = SPECIES.keys()
	var out := PackedFloat32Array()
	for a: Animal in animals:
		if a.uid == 0:
			continue
		out.append_array([a.uid, kinds.find(a.kind), a.pos.x, a.pos.y, a.pos.z, a.yaw, 1.0 if a.moving else 0.0,
			a.variant, a.age, a.hurt_time, a.fade])
	return out


## Friend: show what the host sent. New animals appear, missing ones go.
func apply_snapshot(data: PackedFloat32Array) -> void:
	puppet = true
	var kinds: Array = SPECIES.keys()
	var seen := {}
	for i in range(0, data.size() - NET_FIELDS + 1, NET_FIELDS):
		var uid := int(data[i])
		var kind_i := int(data[i + 1])
		if kind_i < 0 or kind_i >= kinds.size():
			continue
		var p := Vector3(data[i + 2], data[i + 3], data[i + 4])
		var a: Animal = _by_uid.get(uid)
		if a == null:
			a = Animal.new(kinds[kind_i], p)
			a.uid = uid
			_by_uid[uid] = a
			animals.append(a)
		a.net_pos = p
		a.yaw = data[i + 5]
		a.moving = data[i + 6] > 0.5
		a.variant = int(data[i + 7])
		a.age = data[i + 8]
		a.hurt_time = data[i + 9]
		a.fade = data[i + 10]
		seen[uid] = true
	for uid in _by_uid.keys():
		if not seen.has(uid):
			animals.erase(_by_uid[uid])
			_by_uid.erase(uid)


## Friend: glide towards the host's positions between snapshots.
func puppet_step(dt: float, player: Vector3) -> void:
	for a: Animal in animals:
		a.pos = a.pos.lerp(a.net_pos, minf(1.0, dt * 10.0))
		if a.moving:
			a.walk_phase += dt * 8.0
		var dx := a.pos.x - player.x
		var dz := a.pos.z - player.z
		a.hidden = dx * dx + dz * dz > FAR * FAR


func by_uid(uid: int) -> Animal:
	for a: Animal in animals:
		if a.uid == uid:
			return a
	return null
