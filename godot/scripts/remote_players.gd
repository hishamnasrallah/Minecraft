class_name RemotePlayers
extends Node3D
## The other players: a simple blocky figure each (colour from the name) with the name
## above the head, moved smoothly towards the last position received (10 per second).

var _players := {}                 # peer id -> {"node", "target", "yaw", "pitch", "head", "seen"}
var _box: BoxMesh
var icon_for: Callable             # item id -> Texture2D (the HUD's icons) for what they hold


func _ready() -> void:
	_box = BoxMesh.new()


func _part(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _box
	m.scale = size
	m.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _make(name: String) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var hue := float(hash(name) % 1000) / 1000.0
	var shirt := Color.from_hsv(hue, 0.6, 0.85)
	var skin := Color(0.93, 0.76, 0.6)
	# the position is the player's feet; the figure looks towards -z, like the camera
	_part(root, Vector3(0.5, 0.7, 0.28), Vector3(0, 1.05, 0), shirt)            # body
	# legs and arms swing from the hip / shoulder (pivot nodes at the joint)
	var limbs := []
	for spec in [[Vector3(-0.13, 0.7, 0), Vector3(0.22, 0.7, 0.24), Color(0.2, 0.25, 0.45)],
			[Vector3(0.13, 0.7, 0), Vector3(0.22, 0.7, 0.24), Color(0.2, 0.25, 0.45)],
			[Vector3(-0.34, 1.38, 0), Vector3(0.18, 0.66, 0.2), shirt.darkened(0.2)],
			[Vector3(0.34, 1.38, 0), Vector3(0.18, 0.66, 0.2), shirt.darkened(0.2)]]:
		var joint := Node3D.new()
		joint.position = spec[0]
		root.add_child(joint)
		_part(joint, spec[1], Vector3(0, -spec[1].y / 2, 0), spec[2])
		limbs.append(joint)
	var held := Sprite3D.new()                 # what they hold, in the right hand
	held.pixel_size = 0.014
	held.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	held.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	held.shaded = false
	held.position = Vector3(0, -0.62, -0.18)
	limbs[3].add_child(held)
	var head := Node3D.new()
	head.position = Vector3(0, 1.62, 0)
	root.add_child(head)
	_part(head, Vector3(0.42, 0.42, 0.42), Vector3.ZERO, skin)
	_part(head, Vector3(0.08, 0.08, 0.02), Vector3(-0.1, 0.03, -0.215), Color(0.1, 0.1, 0.15))  # eyes
	_part(head, Vector3(0.08, 0.08, 0.02), Vector3(0.1, 0.03, -0.215), Color(0.1, 0.1, 0.15))
	var label := Label3D.new()
	label.text = name
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0, 2.2, 0)
	label.font_size = 48
	label.pixel_size = 0.006
	label.outline_size = 10
	label.no_depth_test = true
	root.add_child(label)
	return {"node": root, "head": head, "label": label, "target": Vector3.ZERO, "yaw": 0.0, "pitch": 0.0,
		"seen": Time.get_ticks_msec(), "fresh": true, "limbs": limbs, "held": held, "item": -1,
		"phase": 0.0, "can_hit": true, "worn": [], "armor_parts": []}


## [position, yaw, pitch, held item, name] from a player.
func update_state(id: int, s: Array) -> void:
	if s.size() < 5:
		return
	if not _players.has(id):
		_players[id] = _make(str(s[4]))
	var p: Dictionary = _players[id]
	p["target"] = s[0]
	p["yaw"] = float(s[1])
	p["pitch"] = float(s[2])
	p["seen"] = Time.get_ticks_msec()
	p["can_hit"] = bool(s[5]) if s.size() > 5 else true
	if p["label"].text != str(s[4]):
		p["label"].text = str(s[4])
	var worn: Array = s[6] if s.size() > 6 and s[6] is Array else []
	if worn != p["worn"]:
		p["worn"] = worn.duplicate()
		_dress(p, worn)
	var item := int(s[3])
	if item != int(p["item"]):
		p["item"] = item
		p["held"].texture = icon_for.call(item) if item > 0 and icon_for.is_valid() else null


## Armour they wear, drawn over the figure: [head, chest, legs, feet] item ids (0 = none).
## Iron is grey, diamond light blue; wings are two panels on the back.
func _dress(p: Dictionary, worn: Array) -> void:
	for part in p["armor_parts"]:
		part.queue_free()
	var parts: Array = []
	var limbs: Array = p["limbs"]
	var root: Node3D = p["node"]
	for i in mini(worn.size(), 4):
		var id := int(worn[i])
		if id <= 0:
			continue
		if id == 176:                                  # wings
			for side in [-1.0, 1.0]:
				var w := _part(root, Vector3(0.42, 0.95, 0.04), Vector3(side * 0.24, 1.15, 0.2), Color(0.9, 0.9, 0.95))
				w.rotation.y = side * 0.35
				parts.append(w)
			continue
		var c := Color(0.35, 0.85, 0.85) if id >= 164 else Color(0.78, 0.8, 0.83)
		match i:
			0:
				parts.append(_part(p["head"], Vector3(0.47, 0.24, 0.47), Vector3(0, 0.12, 0), c))
			1:
				parts.append(_part(root, Vector3(0.56, 0.6, 0.34), Vector3(0, 1.1, 0), c))
				for j in [2, 3]:
					parts.append(_part(limbs[j], Vector3(0.23, 0.3, 0.25), Vector3(0, -0.15, 0), c))
			2:
				for j in [0, 1]:
					parts.append(_part(limbs[j], Vector3(0.25, 0.45, 0.28), Vector3(0, -0.23, 0), c.darkened(0.1)))
			3:
				for j in [0, 1]:
					parts.append(_part(limbs[j], Vector3(0.26, 0.18, 0.3), Vector3(0, -0.62, 0.02), c.darkened(0.2)))
	p["armor_parts"] = parts


## How many armour pieces are drawn on a player (for tests).
func armor_parts_of(id: int) -> int:
	return (_players[id]["armor_parts"] as Array).size() if _players.has(id) else -1


func armor_parts_total() -> int:
	var n := 0
	for id in _players:
		n += (_players[id]["armor_parts"] as Array).size()
	return n


func remove(id: int) -> void:
	if _players.has(id):
		_players[id]["node"].queue_free()
		_players.erase(id)


func count() -> int:
	return _players.size()


func _process(delta: float) -> void:
	for id in _players.keys():
		var p: Dictionary = _players[id]
		var node: Node3D = p["node"]
		var target: Vector3 = p["target"]
		var before := node.position
		if p["fresh"]:
			node.position = target
			p["fresh"] = false
		else:
			node.position = node.position.lerp(target, minf(1.0, delta * 12.0))
		# walking: legs and arms swing with the speed
		var speed := Vector2(node.position.x - before.x, node.position.z - before.z).length() / maxf(delta, 0.001)
		p["phase"] += delta * clampf(speed, 0.0, 6.0) * 2.2
		var swing := sin(p["phase"]) * clampf(speed / 4.0, 0.0, 1.0) * 0.7
		var limbs: Array = p["limbs"]
		limbs[0].rotation.x = swing
		limbs[1].rotation.x = -swing
		limbs[2].rotation.x = -swing
		limbs[3].rotation.x = swing - (0.3 if int(p["item"]) > 0 else 0.0)
		node.rotation.y = p["yaw"]
		p["head"].rotation.x = float(p["pitch"])
		node.visible = Time.get_ticks_msec() - int(p["seen"]) < 5000


## For the host's animals: [peer id, position, can be attacked] of every friend.
func targets() -> Array:
	var out := []
	for id in _players:
		var p: Dictionary = _players[id]
		if p["node"].visible:
			out.append([id, p["target"], p["can_hit"]])
	return out


## For the mini map.
func positions() -> Array:
	var out := []
	for id in _players:
		if _players[id]["node"].visible:
			out.append(_players[id]["target"])
	return out
