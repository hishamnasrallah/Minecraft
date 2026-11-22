class_name Boats
extends Node3D
## Boats: put one on water, tap it to sit in it, walk forward to row the way you look. A boat
## floats on the surface, stops at the shore and drifts to a halt when nobody rows.

const SPEED := 6.0
const DRAG := 2.5

class Boat:
	var pos := Vector3.ZERO
	var yaw := 0.0
	var speed := 0.0
	var node: Node3D
	var rider := false

var world: WorldData
var boats: Array = []
var _mats := []


func add(at: Vector3, yaw := 0.0) -> Boat:
	var b := Boat.new()
	b.pos = at
	b.yaw = yaw
	b.node = _make_node()
	add_child(b.node)
	boats.append(b)
	_place(b)
	return b


func remove(b: Boat) -> void:
	b.node.queue_free()
	boats.erase(b)


func ray_boat(origin: Vector3, dir: Vector3, max_d: float) -> Array:
	var best = null
	var best_d := max_d
	for b: Boat in boats:
		var t := (b.pos - origin).dot(dir)
		if t < 0 or t > best_d:
			continue
		if (origin + dir * t).distance_to(b.pos) < 0.9:
			best = b
			best_d = t
	return [best, best_d] if best != null else []


## The water surface under or at a point (the y of the top water cell), or -999.
func surface(p: Vector3) -> float:
	var x := floori(p.x + 0.5)
	var z := floori(p.z + 0.5)
	for dy in [1, 0, -1, -2]:
		var y: int = floori(p.y + 0.5) + dy
		if Blocks.is_water(world.get_block(x, y, z)) and not Blocks.is_water(world.get_block(x, y + 1, z)):
			return y + 0.35
	return -999.0


func update(delta: float, look_yaw: float, drive: float) -> void:
	for b: Boat in boats:
		if b.rider and absf(drive) > 0.05:
			b.yaw = lerp_angle(b.yaw, look_yaw, minf(1.0, delta * 3.0))
			b.speed = move_toward(b.speed, SPEED * drive, delta * 6.0)
		else:
			b.speed = move_toward(b.speed, 0.0, delta * DRAG)
		var s := surface(b.pos)
		if s > -900.0:
			b.pos.y = lerpf(b.pos.y, s, minf(1.0, delta * 6.0))
		else:
			b.pos.y -= delta * 4.0                  # on land: it settles and does not row
			if world.solid_at(floori(b.pos.x + 0.5), floori(b.pos.y - 0.3), floori(b.pos.z + 0.5)):
				b.pos.y += delta * 4.0
			b.speed = 0.0
		if absf(b.speed) > 0.01:
			var step := Vector3(-sin(b.yaw), 0, -cos(b.yaw)) * b.speed * delta
			var ahead := b.pos + step.normalized() * 0.8 + step
			if world.solid_at(floori(ahead.x + 0.5), floori(b.pos.y + 0.2), floori(ahead.z + 0.5)):
				b.speed = 0.0                        # the shore
			else:
				b.pos += step
		_place(b)


func _place(b: Boat) -> void:
	b.node.position = b.pos
	b.node.rotation.y = b.yaw


func _make_node() -> Node3D:
	var n := Node3D.new()
	var wood := _mat(Color(0.62, 0.45, 0.27))
	var dark := _mat(Color(0.4, 0.28, 0.16))
	_box(n, Vector3(1.0, 0.1, 1.6), Vector3(0, -0.05, 0), dark)
	for s in [-1, 1]:
		_box(n, Vector3(0.1, 0.35, 1.6), Vector3(0.5 * s, 0.12, 0), wood)
		_box(n, Vector3(1.0, 0.35, 0.1), Vector3(0, 0.12, 0.8 * s), wood)
	_box(n, Vector3(0.9, 0.06, 0.25), Vector3(0, 0.1, 0.1), wood)   # the seat
	return n


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats.append([m, c])
	return m


func set_light(light: float) -> void:
	for e in _mats:
		e[0].albedo_color = (e[1] as Color) * clampf(light, 0.25, 1.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func save_data() -> Array:
	return boats.map(func(b): return [b.pos.x, b.pos.y, b.pos.z, b.yaw])


func load_data(list) -> void:
	if list is Array:
		for e in list:
			if e is Array and e.size() >= 4:
				add(Vector3(float(e[0]), float(e[1]), float(e[2])), float(e[3]))
