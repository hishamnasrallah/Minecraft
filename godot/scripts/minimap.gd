class_name Minimap
extends Control
## A small top-down map around the player: the colour of the top block of each column,
## a little lighter where the ground is higher. The arrow is you; the house marks home
## (your bed, or where you started), stuck to the edge when it is far away.
## Only chunks already loaded are drawn, and the work is spread over several frames.

var R := 24                          # blocks from the centre to the edge (the big map uses more)
var N := 49
var rows_per_frame := 3
var marker := 1.0                    # size of the arrow and the house (bigger on the big map)
var pixel := Vector2(132, 132)       # size on screen

var world: WorldData
var center := Vector2i.ZERO          # world x, z of the middle
var facing := Vector2(0, 1)          # player forward on the map (x right, z down)
var home := Vector3.ZERO
var others: Array = []               # friends' positions (blue dots)
var _img: Image
var _tex: ImageTexture
var _row := 0
var _scan_center := Vector2i.ZERO
var _colors := {}                    # block id -> Color
var _atlas: Image
var _home_icon: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	N = R * 2 + 1
	custom_minimum_size = pixel
	size = custom_minimum_size
	_img = Image.create(N, N, false, Image.FORMAT_RGBA8)
	_img.fill(Color(0, 0, 0, 0.5))
	_tex = ImageTexture.create_from_image(_img)
	var atlas: Texture2D = load("res://data/atlas.png")
	_atlas = atlas.get_image()
	if _atlas.is_compressed():
		_atlas.decompress()
	_home_icon = load("res://data/ui/home.png")


func _color_of(id: int) -> Color:
	if _colors.has(id):
		return _colors[id]
	var c := Color(0.2, 0.2, 0.2)
	var d: Dictionary = Blocks.defs.get(id, {})
	if not d.is_empty():
		var r := Blocks.tile_region(int(d["tiles"][0]))
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for x in range(int(r.position.x), int(r.end.x), 2):
			for y in range(int(r.position.y), int(r.end.y), 2):
				var p := _atlas.get_pixel(x, y)
				if p.a > 0.3:
					sum += p
					n += 1
		if n > 0:
			c = Color(sum.r / n, sum.g / n, sum.b / n)
	if id == WorldData.WATER:
		c = Color(0.2, 0.4, 0.85)
	_colors[id] = c
	return c


var _rest := 0.0                     # time since the last full pass while standing still
var _drawn := [Vector2i.ZERO, Vector2.ZERO]


func update_map(player_pos: Vector3, forward: Vector3, home_pos: Vector3) -> void:
	center = Vector2i(floori(player_pos.x + 0.5), floori(player_pos.z + 0.5))
	var f := Vector2(forward.x, forward.z)
	facing = f.normalized() if f.length() > 0.01 else facing
	home = home_pos
	# standing still with a finished map: only refresh every 2 s (blocks may change)
	var scanning := _row != 0 or center != _scan_center
	if not scanning:
		_rest += get_process_delta_time()
		scanning = _rest > 2.0
	if scanning:
		if _row == 0:
			_scan_center = center
			_rest = 0.0
		for i in rows_per_frame:
			_scan_row(_row)
			_row = (_row + 1) % N
			if _row == 0:
				_tex.update(_img)
				_drawn[0] = Vector2i(-99999, 0)      # force a redraw
				break
	var key := [center, facing.snapped(Vector2(0.05, 0.05)), others.size(), others.hash()]
	if key != _drawn:
		_drawn = key
		queue_redraw()


## The top block of a column from the world's per-chunk height cache (2 lookups, no scan).
func _surface(x: int, z: int) -> Vector2i:
	var c = world.column(x, z)
	if c == null:
		return Vector2i(-1, 0)
	var top: int = c[0]
	var water: int = c[1]
	if water > top:
		return Vector2i(WorldData.WATER, water)
	if top < 0:
		return Vector2i(-1, 0)
	return Vector2i(world.get_block(x, top, z), top)


func _scan_row(row: int) -> void:
	var z := _scan_center.y - R + row
	for col in N:
		var x := _scan_center.x - R + col
		var c = _pixel(x, z)
		if c == null:
			c = _remembered(x, z)
		_img.set_pixel(col, row, c)


## The colour of one column of the loaded world (with a little relief), or null if not loaded.
func _pixel(x: int, z: int):
	var s := _surface(x, z)
	if s.x == -1:
		return null
	var c := _color_of(s.x)
	var north := _surface(x, z - 1)
	if north.x != -1:
		c = c.lightened(0.18) if s.y > north.y else (c.darkened(0.22) if s.y < north.y else c)
	return c


# ---------------------------------------------------------------- remembered places
## Every chunk you have seen is kept as 16 x 16 colours (768 bytes), saved with the world,
## so the big map still shows where you have been after you walk away.
static var memory := {}              # Vector2i chunk -> PackedByteArray (RGB)
var _record_t := 0.0


func _remembered(x: int, z: int) -> Color:
	var m = memory.get(Vector2i(x >> 4, z >> 4))
	if m == null:
		return Color(0.05, 0.05, 0.07, 0.8)
	var i := ((x & 15) * 16 + (z & 15)) * 3
	return Color8(m[i], m[i + 1], m[i + 2]).darkened(0.18)        # a little dimmer: seen before


func record_chunk(key: Vector2i) -> void:
	var out := PackedByteArray()
	out.resize(768)
	for lx in 16:
		for lz in 16:
			var c = _pixel(key.x * 16 + lx, key.y * 16 + lz)
			var col: Color = c if c != null else Color(0.05, 0.05, 0.07)
			var i := (lx * 16 + lz) * 3
			out[i] = col.r8
			out[i + 1] = col.g8
			out[i + 2] = col.b8
	memory[key] = out


## Called every frame: notes one new loaded chunk around you, and every few seconds the one
## you stand in again (you may have built or dug there).
func record_some(delta: float, player_pos: Vector3, radius: int) -> void:
	var here := Vector2i(floori(player_pos.x + 0.5) >> 4, floori(player_pos.z + 0.5) >> 4)
	_record_t += delta
	if _record_t > 3.0 and world.chunks.has(here):
		_record_t = 0.0
		record_chunk(here)
		return
	for r in radius + 1:
		for dx in range(-r, r + 1):
			for dz in [-r, r] if absi(dx) != r else range(-r, r + 1):
				var k := here + Vector2i(dx, dz)
				if not memory.has(k) and world.chunks.has(k) and world.chunks.has(k + Vector2i(0, -1)):
					record_chunk(k)
					return


static func save_memory(path: String) -> void:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f:
		f.store_var(memory)


static func load_memory(path: String) -> void:
	memory = {}
	if FileAccess.file_exists(path):
		var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		if f:
			var d = f.get_var()
			if d is Dictionary:
				memory = d


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r.grow(3), Color(0, 0, 0, 0.55))
	# the image was scanned around _scan_center; shift it if the player moved since
	var cell := size.x / N
	var shift := Vector2(_scan_center - center) * cell
	draw_texture_rect(_tex, Rect2(shift, size), false)
	draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)
	# home
	var h := Vector2(home.x - center.x, home.z - center.y)
	var hp := size / 2 + h * cell
	if not r.grow(-8).has_point(hp):
		var d := h.normalized() if h.length() > 0 else Vector2.UP
		var k := minf((size.x / 2 - 10) / maxf(absf(d.x), 0.001), (size.y / 2 - 10) / maxf(absf(d.y), 0.001))
		hp = size / 2 + d * k
	draw_texture_rect(_home_icon, Rect2(hp - Vector2(10, 10) * marker, Vector2(20, 20) * marker), false, Color(1, 0.85, 0.4))
	for o in others:
		var op: Vector3 = o
		var dp := size / 2 + Vector2(op.x - center.x, op.z - center.y) * cell
		dp = dp.clamp(Vector2(4, 4), size - Vector2(4, 4))
		draw_circle(dp, 4.0 * marker, Color(0.3, 0.7, 1.0))
		draw_arc(dp, 4.0 * marker, 0, TAU, 12, Color.WHITE, 1.0)
	# you
	var c := size / 2
	var side := Vector2(-facing.y, facing.x)
	var m := marker
	var tip := c + facing * 9 * m
	var pts := [tip, c - facing * 6 * m + side * 6 * m, c - facing * 3 * m, c - facing * 6 * m - side * 6 * m]
	draw_colored_polygon(PackedVector2Array(pts), Color(1, 0.25, 0.2))
	draw_polyline(PackedVector2Array(pts + [tip]), Color.WHITE, 1.5)
