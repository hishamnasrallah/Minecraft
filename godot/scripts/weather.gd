class_name Weather
extends Node3D
## Weather: blocky drifting clouds, rain streaks around the player and a rain loop.
##
## Self-contained: the host adds it to the scene, sets `column_top` (optional) and calls
## `update(delta, player.position, daylight)` every frame. Everything is cheap on mobile GPUs:
##   * clouds are one prebuilt mesh (one box per cloud cell) drawn as 2x2 tiles by a single
##     MultiMesh that only moves; coverage changes in the vertex shader (cells below the
##     coverage threshold collapse to a point), so the mesh is never rebuilt;
##   * rain is one MultiMesh of crossed quads whose transforms are written into one buffer
##     per frame (no GPU particles, which are flaky with GL Compatibility on some phones);
##   * nothing casts shadows.
## States: "clear" -> "cloudy" -> "rain" ..., changing at random every few minutes.

const KINDS := ["clear", "cloudy", "rain"]
const CLOUD_Y := WorldData.SURFACE_OFFSET + 58.0   # bottom of the cloud layer (well above the highest peaks)
const CLOUD_H := 2.0               # cloud thickness
const CELL := 12.0                 # size of one cloud block
const CN := 32                     # cells per side of one cloud tile (tile = 384 m, repeats)
const V_MIN := 0.40                # cells below this value are never cloud
const COVER_CLEAR := 0.56          # coverage threshold on a clear day (higher = fewer)
const COVER_CLOUDY := 0.43         # ... when cloudy or raining
const RAIN_N := 420                # rain streaks at full intensity
const RAIN_R := 14.0               # half-size of the square around the player where it rains
const RAIN_TOP := 16.0             # streaks start this high above the player
const RAIN_LEN := 0.9              # streak length
const RAIN_SPEED := 15.0
const MAX_DIM := 0.35

## func(x: int, z: int) -> int: y of the highest solid block in a column (e.g. world.top_y).
## Rain stops one block above it, so it does not fall inside caves or under roofs.
var column_top: Callable

var kind := "clear"
var rain_amount := 0.0             # 0..1, smoothed
var snow_line := 1 << 20           # above this height it snows instead of raining (the game sets it)
var snowing := false
var cloud_amount := 0.0            # 0..1, smoothed (0 = few clouds, 1 = overcast)
var drift := 0.0                   # how far the clouds have drifted along +x (metres)
var exposure := 1.0                # 1 under open sky, 0 deep underground (smoothed)

var _timer := 240.0                # seconds until the next weather change
var _wind := Vector2(2.0, 0.6)     # rain slant (m/s) for the current shower
var _rng := RandomNumberGenerator.new()

var _clouds: MultiMeshInstance3D
var _cloud_mat: ShaderMaterial
var _rain: MultiMeshInstance3D
var _rain_mat: StandardMaterial3D
var _drops := PackedVector3Array()
var _floors := PackedFloat32Array()
var _buf := PackedFloat32Array()
var _floor_cache := {}
var _cache_age := 0.0
var _sound: AudioStreamPlayer


func _init() -> void:
	_rng.randomize()
	_timer = _duration("clear")


func _ready() -> void:
	if _clouds != null:
		return
	_build_clouds()
	_build_rain()
	_build_sound()


# ------------------------------------------------------------------------------ public API
func update(delta: float, player_pos: Vector3, daylight: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_change()
	cloud_amount = move_toward(cloud_amount, 0.0 if kind == "clear" else 1.0, delta / 25.0)
	rain_amount = move_toward(rain_amount, 1.0 if kind == "rain" else 0.0, delta / 8.0)
	drift += delta * (1.2 + 2.5 * rain_amount)
	_cache_age += delta
	if _cache_age > 3.0:               # blocks get placed and broken: forget old columns
		_cache_age = 0.0
		_floor_cache.clear()
	var depth := _floor_at(floori(player_pos.x), floori(player_pos.z)) - (player_pos.y + 1.0)
	var target := 1.0 if depth <= 0.0 else clampf(0.45 - depth / 20.0, 0.0, 0.45)
	exposure = move_toward(exposure, target, delta * 2.0)
	_update_clouds(player_pos, daylight)
	_update_rain(minf(delta, 0.1), player_pos, daylight)
	_update_sound()


## "clear", "cloudy" or "rain" (for testing and creative). Amounts fade, they do not jump.
func set_weather(new_kind: String) -> void:
	if not new_kind in KINDS:
		return
	kind = new_kind
	_timer = _duration(kind)
	if kind == "rain":
		_wind = Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))


## How much the host should darken the sky, fog and daylight (0 .. 0.35).
func sky_dim() -> float:
	return minf(MAX_DIM, 0.08 * cloud_amount + 0.27 * rain_amount)


## A sky / fog colour greyed and darkened for the current weather.
func tint_sky(c: Color) -> Color:
	var dim := sky_dim()
	var g := c.get_luminance()
	var out := c.lerp(Color(g, g, g), clampf(dim * 2.2, 0.0, 1.0)) * (1.0 - dim)
	out.a = c.a
	return out


func save_data() -> Dictionary:
	return {"kind": kind, "timer": _timer, "rain": rain_amount, "clouds": cloud_amount,
		"drift": drift, "wind": [_wind.x, _wind.y]}


func load_data(d: Dictionary) -> void:
	var k := str(d.get("kind", "clear"))
	kind = k if k in KINDS else "clear"
	_timer = float(d.get("timer", _duration(kind)))
	rain_amount = clampf(float(d.get("rain", 0.0)), 0.0, 1.0)
	cloud_amount = clampf(float(d.get("clouds", 0.0)), 0.0, 1.0)
	drift = float(d.get("drift", 0.0))
	var w: Variant = d.get("wind")
	if w is Array and (w as Array).size() == 2:
		_wind = Vector2(float(w[0]), float(w[1]))


# ------------------------------------------------------------------------------ state machine
func _duration(k: String) -> float:
	match k:
		"rain":
			return _rng.randf_range(90.0, 240.0)
		"cloudy":
			return _rng.randf_range(120.0, 300.0)
	return _rng.randf_range(240.0, 600.0)


func _change() -> void:
	var r := _rng.randf()
	match kind:
		"clear":
			set_weather("rain" if r < 0.25 else "cloudy")
		"cloudy":
			set_weather("rain" if r < 0.45 else "clear")
		_:
			set_weather("clear" if r < 0.3 else "cloudy")


func _floor_at(x: int, z: int) -> float:
	if not column_top.is_valid():
		return -1000.0
	var key := Vector2i(x, z)
	var f: Variant = _floor_cache.get(key)
	if f == null:
		f = float(column_top.call(x, z)) + 1.0
		_floor_cache[key] = f
	return float(f)


# ------------------------------------------------------------------------------ clouds
const CLOUD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 tint : source_color = vec4(1.0);
uniform float threshold = 0.6;
void vertex() {
	// UV.x = the cell's cloud value, UV2 = the cell's centre: cells under the threshold
	// collapse to a point (nothing drawn), cells just above it grow in smoothly.
	float s = clamp((UV.x - threshold) / 0.05, 0.0, 1.0);
	vec3 c = vec3(UV2.x, 1.0, UV2.y);
	VERTEX = mix(c, VERTEX, s);
}
void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
}
"""


func _hash(i: int, j: int, s: int) -> float:
	var h := (i * 73856093) ^ (j * 19349663) ^ (s * 83492791)
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Value noise that repeats every `period` lattice cells, so the cloud tile is seamless.
func _vnoise(x: float, z: float, period: int, s: int) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var x0 := posmod(ix, period)
	var x1 := posmod(ix + 1, period)
	var z0 := posmod(iz, period)
	var z1 := posmod(iz + 1, period)
	var a := lerpf(_hash(x0, z0, s), _hash(x1, z0, s), fx)
	var b := lerpf(_hash(x0, z1, s), _hash(x1, z1, s), fx)
	return lerpf(a, b, fz)


func cloud_value(x: int, z: int) -> float:
	var v := 0.0
	var w := 0.6
	for o in 3:
		var spacing := 8 >> o
		v += w * _vnoise(float(x) / spacing, float(z) / spacing, CN >> (3 - o), 17 + o)
		w *= 0.5
	return v / 1.05


func _build_cloud_mesh() -> ArrayMesh:
	var vals := PackedFloat32Array()
	vals.resize(CN * CN)
	for z in CN:
		for x in CN:
			vals[z * CN + x] = cloud_value(x, z)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var top := Color(1, 1, 1)
	var bottom := Color(0.8, 0.8, 0.83)
	var side_x := Color(0.92, 0.92, 0.94)
	var side_z := Color(0.86, 0.86, 0.89)
	for z in CN:
		for x in CN:
			var v := vals[z * CN + x]
			if v < V_MIN:
				continue
			var x0 := x * CELL
			var z0 := z * CELL
			var x1 := x0 + CELL
			var z1 := z0 + CELL
			var c := Vector2(x0 + CELL * 0.5, z0 + CELL * 0.5)
			var quads := []
			quads.append([Vector3(x0, CLOUD_H, z0), Vector3(x1, CLOUD_H, z0), Vector3(x1, CLOUD_H, z1), Vector3(x0, CLOUD_H, z1), Vector3.UP, top])
			quads.append([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.DOWN, bottom])
			# a side is needed only where the neighbour can be hidden while this cell shows
			if vals[z * CN + posmod(x - 1, CN)] < v:
				quads.append([Vector3(x0, 0, z0), Vector3(x0, CLOUD_H, z0), Vector3(x0, CLOUD_H, z1), Vector3(x0, 0, z1), Vector3.LEFT, side_x])
			if vals[z * CN + posmod(x + 1, CN)] < v:
				quads.append([Vector3(x1, 0, z0), Vector3(x1, CLOUD_H, z0), Vector3(x1, CLOUD_H, z1), Vector3(x1, 0, z1), Vector3.RIGHT, side_x])
			if vals[posmod(z - 1, CN) * CN + x] < v:
				quads.append([Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, CLOUD_H, z0), Vector3(x0, CLOUD_H, z0), Vector3.FORWARD, side_z])
			if vals[posmod(z + 1, CN) * CN + x] < v:
				quads.append([Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, CLOUD_H, z1), Vector3(x0, CLOUD_H, z1), Vector3.BACK, side_z])
			for q in quads:
				var p: Array = [q[0], q[1], q[2], q[3]]
				var n: Vector3 = q[4]
				# Godot's front faces wind clockwise as seen from outside
				if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
					p.reverse()
				for k in [0, 1, 2, 0, 2, 3]:
					verts.append(p[k])
					cols.append(q[5])
					uv.append(Vector2(v, 0))
					uv2.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_clouds() -> void:
	var shader := Shader.new()
	shader.code = CLOUD_SHADER
	_cloud_mat = ShaderMaterial.new()
	_cloud_mat.shader = shader
	var mesh := _build_cloud_mesh()
	mesh.surface_set_material(0, _cloud_mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 4
	var t := CN * CELL
	for i in 4:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3((i & 1) * t, 0, (i >> 1) * t)))
	_clouds = MultiMeshInstance3D.new()
	_clouds.multimesh = mm
	_clouds.top_level = true
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)


func _update_clouds(player_pos: Vector3, daylight: float) -> void:
	if _clouds == null:
		return
	var t := CN * CELL
	# 2x2 tiles placed so the player is always at least half a tile from the edge
	var ox := (roundf((player_pos.x - drift) / t) - 1.0) * t + drift
	var oz := (roundf(player_pos.z / t) - 1.0) * t
	_clouds.position = Vector3(ox, CLOUD_Y, oz)
	var day := clampf((daylight - 0.16) / 0.84, 0.0, 1.0)
	var c := Color(0.16, 0.18, 0.25).lerp(Color(1, 1, 1), day)
	var grey := c.get_luminance()
	c = c.lerp(Color(grey, grey, grey), 0.6 * rain_amount) * (1.0 - 0.12 * cloud_amount - 0.3 * rain_amount)
	_cloud_mat.set_shader_parameter("tint", c)
	_cloud_mat.set_shader_parameter("threshold", lerpf(COVER_CLEAR, COVER_CLOUDY, cloud_amount))


# ------------------------------------------------------------------------------ rain
func _build_rain() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var w := 0.025
	var quads := [[Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, RAIN_LEN, 0), Vector3(-w, RAIN_LEN, 0)],
		[Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, RAIN_LEN, w), Vector3(0, RAIN_LEN, -w)]]
	for q in quads:
		for k in [0, 1, 2, 0, 2, 3]:
			var p: Vector3 = q[k]
			verts.append(p)
			cols.append(Color(1, 1, 1, 1.0 if p.y < 0.01 else 0.0))   # fades out at the top
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rain_mat.vertex_color_use_as_albedo = true
	_rain_mat.albedo_color = Color(0.75, 0.8, 0.92, 0.55)
	mesh.surface_set_material(0, _rain_mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = RAIN_N
	mm.visible_instance_count = 0
	mm.custom_aabb = AABB(Vector3(-RAIN_R - 4, -14, -RAIN_R - 4), Vector3(RAIN_R * 2 + 8, RAIN_TOP + 16, RAIN_R * 2 + 8))
	_rain = MultiMeshInstance3D.new()
	_rain.multimesh = mm
	_rain.top_level = true
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visible = false
	add_child(_rain)
	_drops.resize(RAIN_N)
	_floors.resize(RAIN_N)
	_buf.resize(RAIN_N * 12)
	for i in RAIN_N:
		_drops[i] = Vector3(0, -1e6, 0)          # dead: respawns on first use


func _respawn(i: int, p: Vector3, anywhere: bool) -> void:
	var x := p.x + _rng.randf_range(-RAIN_R, RAIN_R)
	var z := p.z + _rng.randf_range(-RAIN_R, RAIN_R)
	if absf(x - p.x) < 1.5 and absf(z - p.z) < 1.5:     # no huge streaks right in the eye
		x += 3.0 if x > p.x else -3.0
	var y := p.y + (_rng.randf_range(-6.0, RAIN_TOP) if anywhere else _rng.randf_range(RAIN_TOP - 3.0, RAIN_TOP))
	var f := _floor_at(floori(x), floori(z))
	_drops[i] = Vector3(x, y, z)
	_floors[i] = f            # if the column is roofed above y the drop stays hidden


func _update_rain(delta: float, p: Vector3, daylight: float) -> void:
	if _rain == null:
		return
	snowing = p.y >= snow_line
	var active := int(RAIN_N * rain_amount * minf(1.0, exposure * 3.0))
	_rain.visible = active > 0
	if active == 0:
		return
	var mm := _rain.multimesh
	_rain.position = p
	var fall := RAIN_SPEED * (0.13 if snowing else 1.0)     # snowflakes drift down slowly
	var vel := Vector3(_wind.x * (0.4 if snowing else 1.0), -fall, _wind.y * (0.4 if snowing else 1.0))
	var sx := _wind.x / RAIN_SPEED
	var sz := _wind.y / RAIN_SPEED
	var tall := 0.14 if snowing else 1.0                    # a flake, not a streak
	for i in active:
		var d := _drops[i]
		if d.y < -1e5:
			_respawn(i, p, true)
			d = _drops[i]
		else:
			d += vel * (delta * (1.0 + 0.04 * (i % 7)))
			if d.y < _floors[i] or d.y < p.y - 12.0 or absf(d.x - p.x) > RAIN_R + 3.0 or absf(d.z - p.z) > RAIN_R + 3.0:
				_respawn(i, p, false)
				d = _drops[i]
			else:
				_drops[i] = d
		var o := i * 12
		var shown := 1.0 if d.y >= _floors[i] else 0.0
		var l := d - p
		_buf[o] = shown
		_buf[o + 1] = sx * shown
		_buf[o + 2] = 0.0
		_buf[o + 3] = l.x
		_buf[o + 4] = 0.0
		_buf[o + 5] = shown * tall
		_buf[o + 6] = 0.0
		_buf[o + 7] = l.y
		_buf[o + 8] = 0.0
		_buf[o + 9] = sz * shown
		_buf[o + 10] = shown
		_buf[o + 11] = l.z
	mm.buffer = _buf
	mm.visible_instance_count = active
	var light := 0.35 + 0.65 * clampf((daylight - 0.16) / 0.84, 0.0, 1.0)
	_rain_mat.albedo_color = Color(0.95 * light, 0.97 * light, 1.0 * light, 0.9) if snowing else Color(0.72 * light, 0.78 * light, 0.9 * light, 0.5)


# ------------------------------------------------------------------------------ sound
func _build_sound() -> void:
	_sound = AudioStreamPlayer.new()
	var s: Variant = load("res://data/sounds/rain.wav") if ResourceLoader.exists("res://data/sounds/rain.wav") else null
	if s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		var frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = floori(float(wav.data.size()) / frame)
		_sound.stream = wav
	add_child(_sound)


func _update_sound() -> void:
	if _sound == null or _sound.stream == null or not _sound.is_inside_tree():
		return
	# the master bus already follows the volume setting (Sfx.apply_volume); here we only
	# stop the loop when sound is off so it costs nothing
	var setting := 0.8
	var i18n := get_node_or_null("/root/I18n")     # the I18n autoload (absent in bare scenes)
	if i18n != null:
		var st: Variant = i18n.get("settings")
		if st is Dictionary:
			setting = float((st as Dictionary).get("sound", 0.8))
	var v := rain_amount * exposure * (0.0 if snowing else 1.0)
	if v < 0.01 or setting <= 0.01:
		if _sound.playing:
			_sound.stop()
		return
	_sound.volume_db = linear_to_db(v * 0.6)
	if not _sound.playing:
		_sound.play()
