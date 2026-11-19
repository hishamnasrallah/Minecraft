class_name AnimalView
extends Node3D
## Blocky models for the animals (port of animal_models.py): body parts are boxes with
## terrain-like face shading, legs swing while walking, rabbits hop, and they turn red when hit.

const FUR := Color8(143, 117, 92)
const CREAM := Color8(224, 212, 189)
const DARK := Color8(31, 26, 23)
const TAN := Color8(161, 115, 71)
const BELLY := Color8(219, 194, 153)
const HOOF := Color8(64, 46, 31)
const FEATHER := Color8(153, 135, 107)
const GREEN := Color8(33, 115, 56)
const ORANGE := Color8(242, 153, 38)
const WING := Color8(115, 102, 82)

# [name, position, size, colour]; positions are relative to the feet, facing +z.
# "leg" parts hang down from the given hip position.
const MODELS := {
	"rabbit": [
		["body", Vector3(0, .22, 0), Vector3(.32, .28, .46), FUR], ["head", Vector3(0, .4, .24), Vector3(.24, .22, .22), FUR],
		["ear", Vector3(.06, .6, .21), Vector3(.06, .22, .04), FUR], ["ear", Vector3(-.06, .6, .21), Vector3(.06, .22, .04), FUR],
		["eye", Vector3(.121, .43, .29), Vector3(.02, .05, .05), DARK], ["eye", Vector3(-.121, .43, .29), Vector3(.02, .05, .05), DARK],
		["tail", Vector3(0, .27, -.26), Vector3(.12, .12, .08), CREAM],
		["leg", Vector3(.09, .1, .15), Vector3(.08, .1, .1), FUR], ["leg", Vector3(-.09, .1, .15), Vector3(.08, .1, .1), FUR],
		["leg", Vector3(.12, .12, -.15), Vector3(.1, .12, .16), FUR], ["leg", Vector3(-.12, .12, -.15), Vector3(.1, .12, .16), FUR],
	],
	"deer": [
		["body", Vector3(0, .88, 0), Vector3(.45, .42, .95), TAN], ["belly", Vector3(0, .68, 0), Vector3(.4, .04, .8), BELLY],
		["neck", Vector3(0, 1.14, .42), Vector3(.2, .42, .2), TAN], ["head", Vector3(0, 1.36, .55), Vector3(.24, .24, .34), TAN],
		["nose", Vector3(0, 1.32, .735), Vector3(.12, .1, .04), HOOF],
		["ear", Vector3(.15, 1.48, .5), Vector3(.12, .07, .04), TAN], ["ear", Vector3(-.15, 1.48, .5), Vector3(.12, .07, .04), TAN],
		["eye", Vector3(.121, 1.4, .62), Vector3(.02, .05, .05), DARK], ["eye", Vector3(-.121, 1.4, .62), Vector3(.02, .05, .05), DARK],
		["tail", Vector3(0, .98, -.5), Vector3(.1, .14, .06), BELLY],
		["leg", Vector3(.15, .67, .36), Vector3(.11, .67, .11), TAN], ["leg", Vector3(-.15, .67, .36), Vector3(.11, .67, .11), TAN],
		["leg", Vector3(.15, .67, -.36), Vector3(.11, .67, .11), TAN], ["leg", Vector3(-.15, .67, -.36), Vector3(.11, .67, .11), TAN],
	],
	"duck": [
		["body", Vector3(0, .22, 0), Vector3(.3, .25, .42), FEATHER], ["tail", Vector3(0, .3, -.24), Vector3(.18, .08, .1), WING],
		["wing", Vector3(.16, .24, -.02), Vector3(.04, .16, .3), WING], ["wing", Vector3(-.16, .24, -.02), Vector3(.04, .16, .3), WING],
		["head", Vector3(0, .46, .17), Vector3(.18, .2, .18), GREEN], ["beak", Vector3(0, .42, .3), Vector3(.1, .05, .1), ORANGE],
		["eye", Vector3(.091, .5, .21), Vector3(.02, .04, .04), DARK], ["eye", Vector3(-.091, .5, .21), Vector3(.02, .04, .04), DARK],
		["leg", Vector3(.07, .1, .02), Vector3(.05, .1, .05), ORANGE], ["leg", Vector3(-.07, .1, .02), Vector3(.05, .1, .05), ORANGE],
	],
}

static var _box: ArrayMesh

var animal
var body := Node3D.new()
var parts := []                 # [MeshInstance3D, base colour]
var legs := []
var _light_timer := 0.0


static func box_mesh() -> ArrayMesh:
	if _box == null:
		Mesher._static_setup()
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		for f in 6:
			var shade: float = Mesher.FACES[f][1]
			for c in Mesher.face_corners[f]:
				verts.append(c)
				cols.append(Color(shade, shade, shade))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		_box = ArrayMesh.new()
		_box.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _box


func _init(a) -> void:
	animal = a
	add_child(body)
	for p in MODELS[a.kind]:
		var mi := MeshInstance3D.new()
		mi.mesh = box_mesh()
		mi.scale = p[2]
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.albedo_color = p[3]
		mi.material_override = m
		if p[0] == "leg":
			var hip := Node3D.new()
			hip.position = p[1]
			mi.position.y = -p[2].y / 2
			hip.add_child(mi)
			body.add_child(hip)
			legs.append(hip)
		else:
			mi.position = p[1]
			body.add_child(mi)
		parts.append([mi, p[3]])


func sync(dt: float, daylight: float, world: WorldData) -> void:
	position = animal.pos
	rotation.y = deg_to_rad(animal.yaw)
	var swing: float = sin(animal.walk_phase) if animal.moving else 0.0
	for i in legs.size():
		legs[i].rotation.x = swing * 0.6 * (1 if i % 2 == (i / 2) % 2 else -1)
	if animal.kind == "rabbit":
		body.position.y = absf(sin(animal.walk_phase * 0.5)) * 0.18 if animal.moving else 0.0
		for hip in legs:
			hip.rotation.x = 0
	_light_timer -= dt
	if animal.hurt_time > 0:
		for p in parts:
			p[0].material_override.albedo_color = Color(1, 0.25, 0.25)
		_light_timer = 0
	elif _light_timer <= 0:
		_light_timer = 0.3
		var col = world.column(Wildlife.cell(animal.pos.x), Wildlife.cell(animal.pos.z))
		var open_sky: bool = col != null and Wildlife.cell(animal.pos.y + 0.3) > col[0]
		var b := maxf(daylight * (1.0 if open_sky else 0.3), 0.07)
		for p in parts:
			p[0].material_override.albedo_color = Color(p[1].r * b, p[1].g * b, p[1].b * b)


## Distance along a ray to this animal's body (a rough box), or -1 if the ray misses.
func ray_hit(origin: Vector3, dir: Vector3, max_distance: float) -> float:
	var h: float = animal.spec["height"]
	var w: float = animal.spec["width"] / 2.0 + 0.1
	var aabb := AABB(animal.pos + Vector3(-w, 0, -w), Vector3(w * 2, h, w * 2))
	var hit = aabb.intersects_ray(origin, dir)
	if hit == null:
		return -1.0
	var d := origin.distance_to(hit)
	return d if d <= max_distance else -1.0
