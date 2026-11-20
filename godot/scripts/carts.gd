class_name Carts
extends Node3D
## Carts that run on tracks. A cart follows the track's links: straight on, round turns, and it
## stops at a dead end. A powered boost track speeds it up, an unpowered one brakes it. You can
## ride one (the game moves you with it) or push it by walking into it.
##
## Track pieces (from blocks.json, "links": the two sides they lead to):
## 1750 / 1751 straight along x / z, 1752-1755 turns, 1756-1759 boost tracks (off x/z, on x/z).

const MAX_SPEED := 9.0
const FRICTION := 0.2                   # blocks per second lost every second
const KICK := 6.0                       # a powered boost track gets a cart going at least this fast
const BOOST := 9.0                      # speed gained per second on a powered boost track
const BRAKE := 7.0                      # speed lost per second on an unpowered one

class Cart:
	var pos := Vector3.ZERO             # x / z: the centre line; y: the track's cell
	var dir := Vector2i(1, 0)           # where it is heading
	var speed := 0.0
	var decided := Vector3i(0, -999, 0) # the cell whose way out is already chosen
	var node: Node3D
	var rider := false

var world: WorldData
var carts: Array = []
var _links := {}                        # track id -> [Vector2i, Vector2i]
var _mats := []                         # [material, base colour]


func _ready() -> void:
	for id in Blocks.defs:
		var l = Blocks.defs[id].get("links")
		if l is Array and l.size() == 2:
			_links[int(id)] = [Vector2i(int(l[0][0]), int(l[0][1])), Vector2i(int(l[1][0]), int(l[1][1]))]


func is_track(id: int) -> bool:
	return _links.has(id)


func links_of(id: int) -> Array:
	return _links.get(id, [])


func add(cell: Vector3i, heading := Vector2i(1, 0)) -> Cart:
	var c := Cart.new()
	c.pos = Vector3(cell)
	var l := links_of(world.get_block(cell.x, cell.y, cell.z))
	c.dir = heading if (heading in l or -heading in l or l.is_empty()) else l[0]
	c.node = _make_node()
	add_child(c.node)
	carts.append(c)
	_place_node(c)
	return c


func remove(c: Cart) -> void:
	c.node.queue_free()
	carts.erase(c)


## The cart under a ray (a sphere round its body is enough), or null; `out_d` gets the distance.
func ray_cart(origin: Vector3, dir: Vector3, max_d: float):
	var best = null
	var best_d := max_d
	for c in carts:
		var centre: Vector3 = c.pos + Vector3(0, -0.15, 0)
		var t := (centre - origin).dot(dir)
		if t < 0 or t > best_d:
			continue
		if (origin + dir * t).distance_to(centre) < 0.6:
			best = c
			best_d = t
	return [best, best_d] if best != null else []


## Moves every cart. `push`: the player walking into a cart ([cart, Vector2 direction]) or [].
## `drive`: for the ridden cart, -1 .. 1 (forward along where you look).
func update(delta: float, look: Vector3, drive: float) -> void:
	for c in carts:
		var cell := _cell(c)
		var id := world.get_block(cell.x, cell.y, cell.z)
		var l := links_of(id)
		if l.is_empty():
			c.speed = 0.0                       # off the track: it just sits there
			continue
		if c.rider and absf(drive) > 0.05:
			var look2 := Vector2(look.x, look.z).normalized()
			if c.speed < 0.3:                   # standing: set off the way you look
				var best: Vector2i = l[0]
				for d in l:
					if Vector2(d).dot(look2) > Vector2(best).dot(look2):
						best = d
				if drive < 0:
					best = l[0] if best == l[1] else l[1]
				if best != c.dir:
					c.dir = best
					c.decided = cell
			var along := signf(Vector2(c.dir).dot(look2)) if absf(Vector2(c.dir).dot(look2)) > 0.2 else 1.0
			c.speed = clampf(c.speed + drive * along * 5.0 * delta, 0.0, MAX_SPEED * 0.7)
		if id == 1758 or id == 1759:
			if c.speed < 0.3 and not (c.dir in l or -c.dir in l):
				c.dir = l[0]
			c.speed = minf(MAX_SPEED, maxf(c.speed, KICK) + BOOST * delta)   # a kick, then faster
		elif id == 1756 or id == 1757:
			c.speed = maxf(0.0, c.speed - BRAKE * delta)
		c.speed = maxf(0.0, c.speed - FRICTION * delta)
		if c.speed > 0.0:
			_move(c, c.speed * delta)
		_place_node(c)


## Pushes a cart the way you walk into it (only along its track).
func push(c: Cart, toward: Vector2) -> void:
	var cell := _cell(c)
	var l := links_of(world.get_block(cell.x, cell.y, cell.z))
	if l.is_empty():
		return
	var best: Vector2i = l[0]
	for d in l:
		if Vector2(d).dot(toward) > Vector2(best).dot(toward):
			best = d
	if Vector2(best).dot(toward) < 0.3:
		return
	if best != c.dir:
		c.dir = best
		c.decided = cell
	c.speed = maxf(c.speed, 3.5)


func _cell(c: Cart) -> Vector3i:
	return Vector3i(roundi(c.pos.x), roundi(c.pos.y), roundi(c.pos.z))


func _move(c: Cart, dist: float) -> void:
	var left := dist
	var guard := 0
	while left > 0.0001 and guard < 16:
		guard += 1
		var cell := _cell(c)
		var l := links_of(world.get_block(cell.x, cell.y, cell.z))
		if l.is_empty():
			c.speed = 0.0
			return
		var centre := Vector2(cell.x, cell.z)
		var p := Vector2(c.pos.x, c.pos.z)
		var d := Vector2(c.dir)
		if c.decided != cell:
			var ahead := (centre - p).dot(d)
			if ahead > 0.0001:
				var step := minf(left, ahead)
				_go(c, p + d * step, centre)
				left -= step
				continue
			# at the centre: which way out (not back where it came from)
			var out: Vector2i = c.dir if c.dir in l else (l[1] if l[0] == -c.dir else l[0])
			var nxt := cell + Vector3i(out.x, 0, out.y)
			var nl := links_of(world.get_block(nxt.x, nxt.y, nxt.z))
			c.pos = Vector3(cell.x, c.pos.y, cell.z)
			if not (-out in nl):
				c.speed = 0.0                   # the track ends here
				c.dir = -out if -out in l else c.dir
				c.decided = Vector3i(0, -999, 0)
				return
			c.dir = out
			c.decided = cell
		else:
			var to_edge := 0.5 - (p - centre).dot(d) + 0.002
			var step2 := minf(left, to_edge)
			_go(c, p + d * step2, centre)
			left -= step2


func _go(c: Cart, p: Vector2, centre: Vector2) -> void:
	# stay on the centre line of the piece you are on
	if c.dir.x != 0:
		p.y = centre.y
	else:
		p.x = centre.x
	c.pos = Vector3(p.x, c.pos.y, p.y)


func _place_node(c: Cart) -> void:
	c.node.position = c.pos + Vector3(0, -0.12, 0)
	var target := atan2(float(c.dir.x), float(c.dir.y))
	c.node.rotation.y = lerp_angle(c.node.rotation.y, target, 0.35)


func _make_node() -> Node3D:
	var n := Node3D.new()
	var wood := _mat(Color(0.55, 0.38, 0.22))
	var dark := _mat(Color(0.32, 0.22, 0.13))
	var metal := _mat(Color(0.7, 0.71, 0.75))
	var wheel := _mat(Color(0.18, 0.18, 0.2))
	_box(n, Vector3(0.84, 0.08, 0.96), Vector3(0, -0.12, 0), dark)          # floor
	for s in [-1, 1]:
		_box(n, Vector3(0.08, 0.42, 0.96), Vector3(0.38 * s, 0.09, 0), wood)  # sides
		_box(n, Vector3(0.84, 0.42, 0.08), Vector3(0, 0.09, 0.44 * s), wood)  # front / back
		_box(n, Vector3(0.9, 0.06, 0.06), Vector3(0, 0.2, 0.46 * s), metal)   # bands
		for f in [-1, 1]:
			_box(n, Vector3(0.1, 0.2, 0.2), Vector3(0.43 * s, -0.24, 0.3 * f), wheel)
	return n


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats.append([m, c])
	return m


## Carts are drawn like the animals: unshaded, dimmed with the daylight.
func set_light(light: float) -> void:
	for e in _mats:
		e[0].albedo_color = (e[1] as Color) * clampf(light, 0.25, 1.0)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)


func save_data() -> Array:
	return carts.map(func(c): return [c.pos.x, c.pos.y, c.pos.z, c.dir.x, c.dir.y])


func load_data(list) -> void:
	if not list is Array:
		return
	for e in list:
		if e is Array and e.size() >= 5:
			var c := add(Vector3i(roundi(float(e[0])), roundi(float(e[1])), roundi(float(e[2]))), Vector2i(int(e[3]), int(e[4])))
			c.pos = Vector3(float(e[0]), float(e[1]), float(e[2]))
