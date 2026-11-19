class_name Drops
extends Node3D
## Items lying in the world: what a broken block drops, or what you throw away.
## Each is a small spinning picture of the item that falls, rests on blocks, bobs, gets
## pulled towards a nearby player and is picked up. Unpicked items vanish after 5 minutes.

const PICK_RADIUS := 1.4
const PULL_RADIUS := 3.2
const PICK_DELAY := 0.5
const LIFETIME := 300.0
const MAX_DROPS := 160

var world: WorldData
var hud: Hud
var drops := []        # {stack, pos, vel, age, node}
var picked_total := 0


func spawn(stack: Array, pos: Vector3, vel := Vector3.ZERO, delay := PICK_DELAY) -> void:
	# merge with a resting drop of the same item nearby, so mining a wall doesn't litter
	for d in drops:
		if d["stack"][0] == stack[0] and stack.size() < 3 and d["stack"].size() < 3 \
				and d["pos"].distance_to(pos) < 1.0 and d["stack"][1] + stack[1] <= Items.max_stack(stack[0]):
			d["stack"][1] += stack[1]
			return
	if drops.size() >= MAX_DROPS:
		var old: Dictionary = drops.pop_front()
		old["node"].queue_free()
	var s := Sprite3D.new()
	s.texture = hud.icon_for(stack[0])
	s.pixel_size = 0.022
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.double_sided = true
	add_child(s)
	if vel == Vector3.ZERO:
		vel = Vector3(randf_range(-1.2, 1.2), 3.0, randf_range(-1.2, 1.2))
	drops.append({"stack": stack.duplicate(), "pos": pos, "vel": vel, "age": PICK_DELAY - delay, "node": s})


## Moves the drops; returns the stacks the player picked up this frame.
func update(delta: float, player_pos: Vector3, inv: Inventory, light: float) -> Array:
	var got := []
	var centre := player_pos + Vector3(0, 0.6, 0)
	for d in drops.duplicate():
		d["age"] += delta
		var pos: Vector3 = d["pos"]
		var vel: Vector3 = d["vel"]
		var to_player := centre - pos
		var dist := to_player.length()
		if d["age"] > PICK_DELAY and dist < PULL_RADIUS and inv.can_take(d["stack"]):
			vel = vel.lerp(to_player.normalized() * 9.0, minf(1.0, delta * 8.0))
			if dist < PICK_RADIUS * 0.6:
				var left = inv.give(d["stack"])
				if left == null:
					got.append(d["stack"])
					_remove(d)
					continue
				d["stack"] = left
		else:
			vel.y -= 22.0 * delta
			vel.x *= 1.0 - minf(1.0, delta * 2.0)
			vel.z *= 1.0 - minf(1.0, delta * 2.0)
		var next := pos + vel * delta
		if vel.y < 0 and world.solid_at(floori(next.x + 0.5), floori(next.y - 0.15 + 0.5), floori(next.z + 0.5)):
			next.y = floorf(next.y - 0.15 + 0.5) + 0.5 + 0.15
			vel = Vector3(vel.x * 0.5, 0, vel.z * 0.5)
		if world.solid_at(floori(next.x + 0.5), floori(next.y + 0.5), floori(next.z + 0.5)):
			next = Vector3(pos.x, next.y + 0.02, pos.z)      # pushed out of walls, not through
			vel.x = 0
			vel.z = 0
		d["pos"] = next
		d["vel"] = vel
		var node: Sprite3D = d["node"]
		node.position = next + Vector3(0, sin(d["age"] * 2.5) * 0.06, 0)
		node.rotation.y = d["age"] * 1.6
		node.modulate = Color(light, light, light)
		if d["age"] > LIFETIME or next.y < -10:
			_remove(d)
	picked_total += got.size()
	return got


func _remove(d: Dictionary) -> void:
	d["node"].queue_free()
	drops.erase(d)
