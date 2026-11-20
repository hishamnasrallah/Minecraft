class_name Player
extends CharacterBody3D
## First-person player. Inputs come from the keyboard/mouse or the touch controls
## through move_input / look() / jump_held, so both work the same way.

const WALK_SPEED := 6.0
const SWIM_SPEED := 3.5
const GRAVITY := 24.0
const JUMP_VELOCITY := 7.8          # about 1.25 blocks high
const EYE_HEIGHT := 1.62
const FLY_SPEED := 10.0

var world: WorldData
var move_input := Vector2.ZERO      # x = right, y = forward, length <= 1
var jump_held := false
var yaw := 0.0
var pitch := 0.0
var swimming := false
var flying := false
var fast := false                   # sprint / fast flying
var vertical := 0.0                 # flying: +1 up, -1 down
var noclip := false
var on_ladder := false
var camera: Camera3D


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.8, 0.6)
	shape.shape = box
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = EYE_HEIGHT
	camera.fov = 75
	camera.near = 0.05
	camera.far = 400
	add_child(camera)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)


func look(delta: Vector2) -> void:
	yaw -= delta.x
	pitch = clampf(pitch - delta.y, -1.55, 1.55)
	rotation.y = yaw
	camera.rotation.x = pitch


func forward() -> Vector3:
	return -camera.global_transform.basis.z


func eye() -> Vector3:
	return camera.global_position


func _cell(v: float) -> int:
	return floori(v + 0.5)


func _water_at(p: Vector3) -> bool:
	return world.get_block(_cell(p.x), _cell(p.y), _cell(p.z)) == WorldData.WATER


func head_under_water() -> bool:
	return _water_at(eye())


var riding := false                  # in a cart: the cart moves us, no walking or falling


func _physics_process(delta: float) -> void:
	if world == null:
		return
	if riding:
		velocity = Vector3.ZERO
		return
	# safety net: if a lag spike (or a collision shape that wasn't ready yet) let us sink
	# into a solid block, climb back out on top of it
	if not noclip:
		var inside := world.get_block(_cell(position.x), _cell(position.y + 0.3), _cell(position.z))
		if inside != 0 and Blocks.solid[inside] and Blocks.shape[inside] == "cube":
			position.y = _cell(position.y + 0.3) + 0.5
			velocity.y = 0.0
	swimming = _water_at(position + Vector3(0, 0.6, 0)) or _water_at(position + Vector3(0, -0.4, 0))
	var feet_block := world.get_block(_cell(position.x), _cell(position.y + 0.5), _cell(position.z))
	on_ladder = Blocks.defs.get(feet_block, {}).get("climbable", false)
	var speed := SWIM_SPEED if swimming else WALK_SPEED * (1.4 if fast else 1.0)
	if flying:
		speed = FLY_SPEED * (2.5 if fast else 1.0)
	var basis_flat := Basis(Vector3.UP, yaw)
	var wish := basis_flat * Vector3(move_input.x, 0, -move_input.y)
	velocity.x = wish.x * speed
	velocity.z = wish.z * speed
	var mask := 0 if noclip else 1
	if collision_mask != mask:
		collision_mask = mask
	if flying:
		velocity.y = vertical * speed
	elif on_ladder:
		velocity.y = 3.0 if (move_input.y > 0.3 or jump_held) else maxf(velocity.y - GRAVITY * delta, -1.5)
	elif swimming:
		velocity.y = maxf(velocity.y - GRAVITY * 0.15 * delta, -2.0)
		if jump_held:
			velocity.y = 4.0
		if wish.length() > 0.1 and _step_ahead(wish):
			velocity.y = maxf(velocity.y, JUMP_VELOCITY * 0.85)   # climb out onto a shore a block up
		elif wish.length() > 0.1 and is_on_wall():
			velocity.y = maxf(velocity.y, 3.0)                    # swimming into a bank: rise along it
	else:
		velocity.y -= GRAVITY * delta
		if jump_held and is_on_floor():
			velocity.y = JUMP_VELOCITY
		elif is_on_floor() and wish.length() > 0.1 and _step_ahead(wish):
			velocity.y = JUMP_VELOCITY      # auto-jump onto a single block step
	if noclip:
		position += velocity * delta
	else:
		move_and_slide()
	if position.y < -20:
		position = world.spawn_point()
		velocity = Vector3.ZERO


## Is there a one-block step right in front of us (with room above it)?
func _step_ahead(wish: Vector3) -> bool:
	var ahead := position + wish.normalized() * 0.6
	var x := _cell(ahead.x)
	var z := _cell(ahead.z)
	var feet := _cell(position.y + 0.5)
	return world.solid_at(x, feet, z) and not world.solid_at(x, feet + 1, z) and not world.solid_at(x, feet + 2, z)
