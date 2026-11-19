class_name Minimap
extends Control
## A small top-down map around the player: the colour of the top block of each column,
## a little lighter where the ground is higher. The arrow is you; the house marks home
## (your bed, or where you started), stuck to the edge when it is far away.
## Only chunks already loaded are drawn, and the work is spread over several frames.

const R := 16                        # blocks from the centre to the edge
const N := R * 2 + 1
const ROWS_PER_FRAME := 3

var world: WorldData
var center := Vector2i.ZERO          # world x, z of the middle
var facing := Vector2(0, 1)          # player forward on the map (x right, z down)
var home := Vector3.ZERO
var _img: Image
var _tex: ImageTexture
var _row := 0
var _scan_center := Vector2i.ZERO
var _colors := {}                    # block id -> Color
var _atlas: Image
var _home_icon: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(132, 132)
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
		for i in ROWS_PER_FRAME:
			_scan_row(_row)
			_row = (_row + 1) % N
			if _row == 0:
				_tex.update(_img)
				_drawn[0] = Vector2i(-99999, 0)      # force a redraw
				break
	var key := [center, facing.snapped(Vector2(0.05, 0.05))]
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
		var s := _surface(x, z)
		if s.x == -1:
			_img.set_pixel(col, row, Color(0.05, 0.05, 0.07, 0.8))
			continue
		var c := _color_of(s.x)
		var north := _surface(x, z - 1)
		if north.x != -1:
			c = c.lightened(0.18) if s.y > north.y else (c.darkened(0.22) if s.y < north.y else c)
		_img.set_pixel(col, row, c)


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
	draw_texture_rect(_home_icon, Rect2(hp - Vector2(10, 10), Vector2(20, 20)), false, Color(1, 0.85, 0.4))
	# you
	var c := size / 2
	var side := Vector2(-facing.y, facing.x)
	var tip := c + facing * 9
	draw_colored_polygon(PackedVector2Array([tip, c - facing * 6 + side * 6, c - facing * 3, c - facing * 6 - side * 6]), Color(1, 0.25, 0.2))
	draw_polyline(PackedVector2Array([tip, c - facing * 6 + side * 6, c - facing * 3, c - facing * 6 - side * 6, tip]), Color.WHITE, 1.5)
