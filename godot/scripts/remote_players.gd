class_name RemotePlayers
extends Node3D
## The other players: a simple blocky figure each (colour from the name) with the name
## above the head, moved smoothly towards the last position received (10 per second).

var _players := {}                 # peer id -> {"node", "target", "yaw", "pitch", "head", "seen"}
var _box: BoxMesh


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
	_part(root, Vector3(0.22, 0.7, 0.24), Vector3(-0.13, 0.35, 0), Color(0.2, 0.25, 0.45))
	_part(root, Vector3(0.22, 0.7, 0.24), Vector3(0.13, 0.35, 0), Color(0.2, 0.25, 0.45))
	_part(root, Vector3(0.18, 0.66, 0.2), Vector3(-0.34, 1.05, 0), shirt.darkened(0.2))
	_part(root, Vector3(0.18, 0.66, 0.2), Vector3(0.34, 1.05, 0), shirt.darkened(0.2))
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
		"seen": Time.get_ticks_msec(), "fresh": true}


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
	if p["label"].text != str(s[4]):
		p["label"].text = str(s[4])


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
		if p["fresh"]:
			node.position = target
			p["fresh"] = false
		else:
			node.position = node.position.lerp(target, minf(1.0, delta * 12.0))
		node.rotation.y = p["yaw"]
		p["head"].rotation.x = float(p["pitch"])
		node.visible = Time.get_ticks_msec() - int(p["seen"]) < 5000
