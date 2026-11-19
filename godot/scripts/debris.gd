class_name Debris
extends MultiMeshInstance3D
## Little cubes that fly out of a broken block, in the block's own colours, and fall and
## fade. All of them are one MultiMesh (a single draw call) updated on the CPU; a pool of
## fixed size, so breaking many blocks never allocates.

const MAX := 96
const LIFE := 0.6
const PER_BLOCK := 10

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _col := PackedColorArray()
var _next := 0
var _active := 0
var _colors := {}                  # block id -> [Color, Color] (two shades from its texture)
var _atlas: Image


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3.ONE * 0.11
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = box
	multimesh.instance_count = MAX
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for arr in [_pos, _vel]:
		arr.resize(MAX)
	_age.resize(MAX)
	_age.fill(LIFE)
	_col.resize(MAX)
	var tex: Texture2D = load("res://data/atlas.png")
	_atlas = tex.get_image()
	if _atlas.is_compressed():
		_atlas.decompress()


func _shades(id: int) -> Array:
	if _colors.has(id):
		return _colors[id]
	var r := Blocks.tile_region(Blocks.tile_side[id])
	var a := _atlas.get_pixel(int(r.position.x) + 4, int(r.position.y) + 5)
	var b := _atlas.get_pixel(int(r.position.x) + 11, int(r.position.y) + 10)
	if a.a < 0.3:
		a = b
	if b.a < 0.3:
		b = a
	_colors[id] = [Color(a.r, a.g, a.b), Color(b.r, b.g, b.b)]
	return _colors[id]


## A burst of pieces from the block at `pos` (light: 0..1 to match the surroundings).
func burst(pos: Vector3, id: int, light := 1.0) -> void:
	var shades := _shades(id)
	for i in PER_BLOCK:
		var k := _next
		_next = (_next + 1) % MAX
		_pos[k] = pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
		_vel[k] = Vector3(randf_range(-2.2, 2.2), randf_range(1.5, 4.5), randf_range(-2.2, 2.2))
		_age[k] = 0.0
		var c: Color = shades[i % 2]
		_col[k] = Color(c.r * light, c.g * light, c.b * light)
	set_process(true)


func _process(delta: float) -> void:
	var shown := 0
	for k in MAX:
		if _age[k] >= LIFE:
			continue
		_age[k] += delta
		var v := _vel[k]
		v.y -= 14.0 * delta
		_vel[k] = v
		_pos[k] += v * delta
		var s := 1.0 - _age[k] / LIFE
		multimesh.set_instance_transform(shown, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * maxf(s, 0.05)), _pos[k]))
		multimesh.set_instance_color(shown, _col[k])
		shown += 1
	multimesh.visible_instance_count = shown
	if shown == 0:
		set_process(false)
