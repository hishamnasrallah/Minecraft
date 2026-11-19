class_name Builder
extends RefCounted
## Creative bulk building: selection, fill / replace / hollow / clear, copy & paste with
## rotate and mirror, and undo. Port of building.py.

const MAX_BLOCKS := 32768
const UNDO_STEPS := 20

var corner1 = null
var corner2 = null
var clipboard := {}          # Vector3i offset -> id
var undo_stack := []


static func rotate_block(id: int) -> int:
	var d: Dictionary = Blocks.defs.get(id, {})
	match d.get("shape", ""):
		"stair":
			var f := int(d["facing"])
			return id - f + (f + 1) % 4
		"ladder":
			return 500 + (id - 500 + 1) % 4
		"door":
			return id + 4 if int(d["door"]["axis"]) == 0 else id - 4
	return id


static func mirror_block(id: int) -> int:
	var d: Dictionary = Blocks.defs.get(id, {})
	var shape: String = d.get("shape", "")
	if shape == "stair" or shape == "ladder":
		var f := int(d["facing"])
		var swapped: int = {1: 3, 3: 1}.get(f, f)
		return id - f + swapped
	return id


func bounds():
	if corner1 == null or corner2 == null:
		return null
	return [Vector3i(mini(corner1.x, corner2.x), mini(corner1.y, corner2.y), mini(corner1.z, corner2.z)),
		Vector3i(maxi(corner1.x, corner2.x), maxi(corner1.y, corner2.y), maxi(corner1.z, corner2.z))]


func size():
	var b = bounds()
	return null if b == null else b[1] - b[0] + Vector3i.ONE


func volume() -> int:
	var s = size()
	return 0 if s == null else s.x * s.y * s.z


func _check() -> String:
	if bounds() == null:
		return I18n.t("select_first")
	if volume() > MAX_BLOCKS:
		return I18n.f("too_big", [volume(), MAX_BLOCKS])
	return ""


func _apply(world: WorldData, edits: Dictionary) -> Array:
	var r := world.bulk_set(edits)
	if not r[1].is_empty():
		undo_stack.append(r[1])
		if undo_stack.size() > UNDO_STEPS:
			undo_stack.pop_front()
	return [r[0], r[1].size()]


## Returns [chunk keys to rebuild, message].
func fill(world: WorldData, id: int, hollow := false, replace := -1) -> Array:
	var problem := _check()
	if problem != "":
		return [[], problem]
	var b = bounds()
	var lo: Vector3i = b[0]
	var hi: Vector3i = b[1]
	var edits := {}
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if hollow and x > lo.x and x < hi.x and y > lo.y and y < hi.y and z > lo.z and z < hi.z:
					continue
				if replace >= 0 and world.get_block(x, y, z) != replace:
					continue
				edits[Vector3i(x, y, z)] = id
	var r := _apply(world, edits)
	return [r[0], I18n.f("changed", r[1])]


func copy(world: WorldData) -> String:
	var problem := _check()
	if problem != "":
		return problem
	var b = bounds()
	clipboard = {}
	var solid := 0
	for x in range(b[0].x, b[1].x + 1):
		for y in range(b[0].y, b[1].y + 1):
			for z in range(b[0].z, b[1].z + 1):
				var id := world.get_block(x, y, z)
				clipboard[Vector3i(x, y, z) - b[0]] = id
				if id != 0:
					solid += 1
	var s = size()
	return I18n.f("copied", [s.x, s.y, s.z, solid])


func clipboard_size():
	if clipboard.is_empty():
		return null
	var m := Vector3i.ZERO
	for p in clipboard:
		m = Vector3i(maxi(m.x, p.x), maxi(m.y, p.y), maxi(m.z, p.z))
	return m + Vector3i.ONE


func paste(world: WorldData, origin: Vector3i, include_air := false) -> Array:
	if clipboard.is_empty():
		return [[], I18n.t("nothing_copied")]
	var edits := {}
	for p in clipboard:
		if clipboard[p] != 0 or include_air:
			edits[origin + p] = clipboard[p]
	var r := _apply(world, edits)
	return [r[0], I18n.f("pasted", r[1])]


func rotate() -> String:
	if clipboard.is_empty():
		return I18n.t("nothing_copied")
	var sx: int = clipboard_size().x
	var out := {}
	for p in clipboard:
		out[Vector3i(p.z, p.y, sx - 1 - p.x)] = rotate_block(clipboard[p])
	clipboard = out
	return I18n.t("rotated")


func mirror() -> String:
	if clipboard.is_empty():
		return I18n.t("nothing_copied")
	var sx: int = clipboard_size().x
	var out := {}
	for p in clipboard:
		out[Vector3i(sx - 1 - p.x, p.y, p.z)] = mirror_block(clipboard[p])
	clipboard = out
	return I18n.t("mirrored")


func undo(world: WorldData) -> Array:
	if undo_stack.is_empty():
		return [[], I18n.t("nothing_undo")]
	var previous: Dictionary = undo_stack.pop_back()
	var r := world.bulk_set(previous)
	return [r[0], I18n.f("undid", previous.size())]
