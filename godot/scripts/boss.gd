class_name StormRay
extends Node3D
## The boss of the sky realm: a huge flying ray made of boxes. It circles the main island,
## now and then swoops at the player (hits hard and knocks back), and when below half health
## it also throws storm orbs. Every storm crystal still standing on the four pillars heals it
## through a visible beam: break the crystals first. 300 health.
##
## The game calls update() every frame, hit() when the player strikes it, and reads `dead`.

signal died(at: Vector3)
signal hurt_player(damage: int, push: Vector3)

const MAX_HEALTH := 300
const RADIUS := 30.0
const SWOOP_SPEED := 17.0
const CIRCLE_SPEED := 0.32               # radians per second
const CONTACT := 3.0                     # how close a swoop must come to hit
const SWOOP_DAMAGE := 6
const ORB_DAMAGE := 4
const HEAL_PER_CRYSTAL := 3.0            # health per second, per crystal

var world: WorldData
var center := Vector3.ZERO               # the middle of the island, at flying height
var crystals: Array = []                 # Vector3i of the storm crystals
var health := float(MAX_HEALTH)
var dead := false
var state := "circle"
var _angle := 0.0
var _timer := 6.0
var _target := Vector3.ZERO
var _orb_timer := 3.0
var _flap := 0.0
var _hurt := 0.0
var _hit_this_swoop := false
var _wings: Array = []
var _tail: Node3D
var _eyes: Array = []
var _orbs := []                          # [node, velocity, age]
var _beams: MeshInstance3D
var _beam_mesh: ImmediateMesh
var _body_mat: StandardMaterial3D


func _ready() -> void:
	var dark := Color(0.12, 0.14, 0.3)
	var stripe := Color(0.3, 0.85, 1.0)
	_body_mat = _mat(dark)
	_box(self, Vector3(4.0, 1.0, 6.0), Vector3.ZERO, _body_mat)                 # body
	_box(self, Vector3(3.0, 0.4, 4.8), Vector3(0, -0.55, 0), _mat(Color(0.75, 0.8, 0.95)))  # pale belly
	_box(self, Vector3(0.5, 0.12, 4.0), Vector3(0, 0.55, 0.3), _mat(stripe, true))           # back stripe
	_box(self, Vector3(2.2, 0.8, 1.4), Vector3(0, 0.1, -3.4), _body_mat)        # head
	for side in [-1, 1]:
		var eye := _box(self, Vector3(0.4, 0.3, 0.2), Vector3(0.65 * side, 0.25, -4.12), _mat(Color(0.6, 1.0, 1.0), true))
		_eyes.append(eye)
		var joint := Node3D.new()                  # wings flap from the body's side
		joint.position = Vector3(2.0 * side, 0, 0)
		add_child(joint)
		_box(joint, Vector3(7.0, 0.35, 4.6), Vector3(3.5 * side, 0, 0.3), _body_mat)
		_box(joint, Vector3(6.0, 0.1, 0.4), Vector3(3.2 * side, 0.22, -0.9), _mat(stripe, true))
		_wings.append(joint)
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0, 3.0)
	add_child(_tail)
	_box(_tail, Vector3(0.45, 0.45, 7.0), Vector3(0, 0, 3.5), _body_mat)
	_box(_tail, Vector3(1.4, 0.2, 0.9), Vector3(0, 0, 6.8), _mat(stripe, true))
	_beam_mesh = ImmediateMesh.new()
	_beams = MeshInstance3D.new()
	_beams.mesh = _beam_mesh
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.5, 0.95, 1.0)
	_beams.material_override = bm
	_beams.top_level = true
	add_child(_beams)
	position = center + Vector3(RADIUS, 0, 0)


func _mat(c: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		m.albedo_color = c.lightened(0.2)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func alive_crystals() -> Array:
	return crystals.filter(func(c: Vector3i): return world.get_block(c.x, c.y, c.z) == 1806)


func enraged() -> bool:
	return health < MAX_HEALTH * 0.5


## Moves the boss. `player`: the player's feet.
func update(delta: float, player: Vector3, can_hurt: bool) -> void:
	if dead:
		return
	var healers := alive_crystals()
	health = minf(MAX_HEALTH, health + HEAL_PER_CRYSTAL * healers.size() * delta)
	_draw_beams(healers)
	_flap += delta * (7.0 if state == "swoop" else 3.5)
	for i in _wings.size():
		_wings[i].rotation.z = sin(_flap) * 0.45 * (1 if i == 0 else -1)
	_tail.rotation.y = sin(_flap * 0.5) * 0.25
	_hurt = maxf(0.0, _hurt - delta)
	_body_mat.albedo_color = Color(0.12, 0.14, 0.3).lerp(Color(1, 0.3, 0.3), _hurt * 3.0)
	var speed_up := 1.5 if enraged() else 1.0
	_timer -= delta
	match state:
		"circle":
			_angle += CIRCLE_SPEED * speed_up * delta
			var want := center + Vector3(cos(_angle) * RADIUS, sin(_flap * 0.3) * 2.0, sin(_angle) * RADIUS)
			_fly_to(want, 12.0 * speed_up, delta)
			if _timer <= 0.0 and can_hurt and player.distance_to(center) < RADIUS + 30:
				state = "swoop"
				_target = player + Vector3(0, 1.0, 0)
				_hit_this_swoop = false
				_timer = 4.0
		"swoop":
			_target = _target.lerp(player + Vector3(0, 1.0, 0), delta * 0.8)   # it follows a little
			_fly_to(_target, SWOOP_SPEED * speed_up, delta)
			if not _hit_this_swoop and can_hurt and position.distance_to(player + Vector3(0, 1.0, 0)) < CONTACT:
				_hit_this_swoop = true
				var push := (player - position).normalized() * 9.0 + Vector3(0, 6, 0)
				hurt_player.emit(SWOOP_DAMAGE, push)
			if position.distance_to(_target) < 1.5 or _timer <= 0.0:
				state = "climb"
				_timer = 2.5
		"climb":
			_fly_to(center + Vector3(cos(_angle) * RADIUS, 4.0, sin(_angle) * RADIUS), 10.0 * speed_up, delta)
			if _timer <= 0.0:
				state = "circle"
				_timer = randf_range(4.0, 7.0) if enraged() else randf_range(6.0, 10.0)
	if enraged() and can_hurt:
		_orb_timer -= delta
		if _orb_timer <= 0.0 and state == "circle":
			_orb_timer = 3.0
			_throw_orb(player + Vector3(0, 1.0, 0))
	_update_orbs(delta, player, can_hurt)


func _fly_to(p: Vector3, speed: float, delta: float) -> void:
	var to := p - position
	if to.length() > 0.01:
		var step := to.normalized() * minf(speed * delta, to.length())
		position += step
		var look := Vector3(to.x, to.y * 0.4, to.z)
		if look.length() > 0.1:
			look_at(position + look, Vector3.UP)


func _throw_orb(at: Vector3) -> void:
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	orb.mesh = sm
	orb.material_override = _mat(Color(0.6, 0.95, 1.0), true)
	orb.top_level = true
	add_child(orb)
	orb.global_position = global_position + Vector3(0, -0.8, 0)
	_orbs.append([orb, (at - orb.global_position).normalized() * 13.0, 0.0])
	Sfx.play("pop", -2.0, 0.5)


func _update_orbs(delta: float, player: Vector3, can_hurt: bool) -> void:
	for o in _orbs.duplicate():
		var node: MeshInstance3D = o[0]
		o[2] += delta
		node.global_position += o[1] * delta
		var p := node.global_position
		var hit_player: bool = can_hurt and p.distance_to(player + Vector3(0, 1.0, 0)) < 1.3
		var cell := world.get_block(floori(p.x + 0.5), floori(p.y + 0.5), floori(p.z + 0.5))
		if hit_player:
			hurt_player.emit(ORB_DAMAGE, Vector3(o[1].x, 2.0, o[1].z).normalized() * 4.0)
		if hit_player or (cell != 0 and Blocks.solid[cell] == 1) or o[2] > 6.0:
			node.queue_free()
			_orbs.erase(o)


func _draw_beams(healers: Array) -> void:
	_beam_mesh.clear_surfaces()
	if healers.is_empty():
		return
	_beam_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for c in healers:
		for k in 3:                                # three lines make a thicker beam
			var off := Vector3(0.15 * k, 0.1 * k, -0.15 * k)
			_beam_mesh.surface_add_vertex(Vector3(c) + Vector3(0, 0.5, 0) + off)
			_beam_mesh.surface_add_vertex(global_position + off)
	_beam_mesh.surface_end()


## Distance along the ray to the boss, or -1 (a sphere around its body is enough).
func ray_hit(origin: Vector3, dir: Vector3, max_d: float) -> float:
	if dead:
		return -1.0
	var to := global_position - origin
	var t := to.dot(dir)
	if t < 0 or t > max_d + 4.0:
		return -1.0
	var closest := origin + dir * t
	return t if closest.distance_to(global_position) < 3.2 else -1.0


func hit(damage: int) -> void:
	if dead:
		return
	health -= damage
	_hurt = 0.3
	Sfx.play("hurt", 0.0, 0.5)
	if health <= 0:
		health = 0
		dead = true
		for o in _orbs:
			o[0].queue_free()
		_orbs.clear()
		_beam_mesh.clear_surfaces()
		died.emit(global_position)
		visible = false
