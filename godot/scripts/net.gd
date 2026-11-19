extends Node
## Playing with friends (autoload "Net"), over the local Wi-Fi or by IP.
##
## The host's game is the server (ENet, port 7777) and announces itself on the local network
## with a small UDP broadcast every second (port 7778), so friends see it in the menu.
## Joining: the friend asks for the world and gets it compressed (seed + every edit + chests +
## time + weather); the rest of the world is generated on the friend's own phone from the seed.
## While playing:
##   - block changes are batched and sent once per frame (reliable), from any player;
##   - each player sends its position / view 10 times a second (unreliable: a lost one is
##     replaced by the next);
##   - the host alone runs machines and growing plants and sends their results like any edit,
##     and sends the clock and weather every 2 seconds.

signal connected                         # we joined a host (now waiting for the world)
signal world_received(data: Dictionary)
signal failed(reason: String)
signal remote_edits(edits: Dictionary)   # Vector3i -> id
signal remote_container(pos: Vector3i, data)
signal player_state(id: int, state: Array)   # [position, yaw, pitch, held item, name]
signal player_left(id: int)
signal player_joined(id: int, name: String)
signal clock(time_of_day: float, weather: String)
signal animals(data: PackedFloat32Array)         # friend: the host's animals
signal animal_hit(from_id: int, uid: int, damage: int, held: int, from: Vector3)   # host
signal animal_drop(stack: Array)                 # friend: what the animal we hit dropped
signal hurt(damage: int)                         # friend: a night creature hit us on the host
signal chat_message(name: String, text: String)

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 8
const PART := 48000                      # bytes per world piece

var hosting := false
var joined := false
var world_name := ""
var player_name := ""
var found := {}                          # ip -> {"name": world name, "players": n, "seen": time}
var get_world_data: Callable             # host: func() -> Dictionary (the game provides it)
var _peer: ENetMultiplayerPeer
var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _announce := 0.0
var _outgoing := {}                      # edits to send this frame
var _parts := []
var _parts_total := 0
var _parts_size := 0
var names := {}                          # peer id -> name


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(func(id): names.erase(id); player_left.emit(id))
	multiplayer.connected_to_server.connect(func(): joined = true; connected.emit(); hello.rpc(_my_name()); request_world.rpc_id(1))
	multiplayer.connection_failed.connect(func(): stop(); failed.emit("connect"))
	multiplayer.server_disconnected.connect(func(): stop(); failed.emit("host_left"))


func active() -> bool:
	return hosting or joined


func is_host() -> bool:
	return hosting


func _my_name() -> String:
	if player_name != "":
		return player_name
	var n := str(I18n.settings.get("player_name", ""))
	if n == "":
		# a friendly name the first time (not the phone's model code), kept from then on
		n = "%s %d" % [I18n.t("default_player"), randi_range(10, 99)]
		I18n.settings["player_name"] = n
		I18n.save_settings()
	return n


# ---------------------------------------------------------------- hosting
func host(name: String) -> String:
	stop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		_peer = null
		return "port"
	multiplayer.multiplayer_peer = _peer
	hosting = true
	world_name = name
	_udp_out = PacketPeerUDP.new()
	_udp_out.set_broadcast_enabled(true)
	_udp_out.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	return ""


## This device's addresses on the local network (to tell friends).
func local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and ip.split(".")[1].to_int() in range(16, 32)):
			out.append(ip)
	if out.is_empty() and "127.0.0.1" in IP.get_local_addresses():
		out.append("127.0.0.1")
	return out


func _on_peer_connected(id: int) -> void:
	if hosting:
		hello.rpc_id(id, _my_name())


# ---------------------------------------------------------------- finding and joining
func start_listening() -> void:
	if _udp_in != null:
		return
	_udp_in = PacketPeerUDP.new()
	if _udp_in.bind(DISCOVERY_PORT) != OK:
		_udp_in = null


func stop_listening() -> void:
	if _udp_in != null:
		_udp_in.close()
		_udp_in = null


func join(ip: String) -> String:
	stop()
	_peer = ENetMultiplayerPeer.new()
	var err := _peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		_peer = null
		return "address"
	multiplayer.multiplayer_peer = _peer
	return ""


func stop() -> void:
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	hosting = false
	joined = false
	names.clear()
	_outgoing.clear()
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null


func _process(delta: float) -> void:
	if hosting and _udp_out != null:
		_announce -= delta
		if _announce <= 0.0:
			_announce = 1.0
			var msg := "BLOCKWORLD|%s|%d" % [world_name, names.size() + 1]
			_udp_out.put_packet(msg.to_utf8_buffer())
	if _udp_in != null:
		while _udp_in.get_available_packet_count() > 0:
			var text := _udp_in.get_packet().get_string_from_utf8()
			var ip := _udp_in.get_packet_ip()
			var parts := text.split("|")
			if parts.size() >= 3 and parts[0] == "BLOCKWORLD":
				found[ip] = {"name": parts[1], "players": parts[2].to_int(), "seen": Time.get_ticks_msec()}
		for ip in found.keys():
			if Time.get_ticks_msec() - int(found[ip]["seen"]) > 4000:
				found.erase(ip)
	if not _outgoing.is_empty() and active():
		var batch := _outgoing
		_outgoing = {}
		edits.rpc(_pack(batch))


# ---------------------------------------------------------------- the world for a new player
@rpc("any_peer", "reliable")
func request_world() -> void:
	if not hosting or not get_world_data.is_valid():
		return
	var raw := var_to_bytes(get_world_data.call())
	var packed := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var total := ceili(float(packed.size()) / PART)
	var to := multiplayer.get_remote_sender_id()
	for i in total:
		world_part.rpc_id(to, i, total, raw.size(), packed.slice(i * PART, mini((i + 1) * PART, packed.size())))


@rpc("authority", "reliable")
func world_part(i: int, total: int, size: int, bytes: PackedByteArray) -> void:
	if i == 0:
		_parts = []
	_parts.append(bytes)
	_parts_total = total
	_parts_size = size
	if _parts.size() == total:
		var packed := PackedByteArray()
		for p in _parts:
			packed.append_array(p)
		_parts = []
		var data = bytes_to_var(packed.decompress(size, FileAccess.COMPRESSION_DEFLATE))
		if data is Dictionary:
			world_received.emit(data)
		else:
			failed.emit("bad_world")


func world_progress() -> float:
	return float(_parts.size()) / maxf(_parts_total, 1)


# ---------------------------------------------------------------- while playing
@rpc("any_peer", "reliable")
func hello(name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	names[id] = name
	player_joined.emit(id, name)


## Called by the game for every block change it makes (not for ones it received).
func send_edit(pos: Vector3i, id: int) -> void:
	_outgoing[pos] = id


func _pack(batch: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in batch:
		out.append_array([p.x, p.y, p.z, batch[p]])
	return out


@rpc("any_peer", "reliable")
func edits(packed: PackedInt32Array) -> void:
	var out := {}
	for i in range(0, packed.size(), 4):
		out[Vector3i(packed[i], packed[i + 1], packed[i + 2])] = packed[i + 3]
	remote_edits.emit(out)


func send_container(pos: Vector3i, data) -> void:
	if active():
		container.rpc(pos, data)


@rpc("any_peer", "reliable")
func container(pos: Vector3i, data) -> void:
	remote_container.emit(pos, data)


func send_state(pos: Vector3, yaw: float, pitch: float, held: int, can_be_hit := true) -> void:
	if active():
		state.rpc([pos, yaw, pitch, held, _my_name(), can_be_hit])


@rpc("any_peer", "unreliable_ordered")
func state(s: Array) -> void:
	player_state.emit(multiplayer.get_remote_sender_id(), s)


func send_clock(time_of_day: float, weather: String) -> void:
	if hosting:
		clock_rpc.rpc(time_of_day, weather)


@rpc("authority", "unreliable_ordered")
func clock_rpc(time_of_day: float, weather: String) -> void:
	clock.emit(time_of_day, weather)


# ---------------------------------------------------------------- animals (the host owns them)
func send_animals(data: PackedFloat32Array) -> void:
	if hosting and not names.is_empty():
		animals_rpc.rpc(data)


@rpc("authority", "unreliable_ordered")
func animals_rpc(data: PackedFloat32Array) -> void:
	animals.emit(data)


func hit_animal(uid: int, damage: int, held: int, from: Vector3) -> void:
	if joined:
		hit_animal_rpc.rpc_id(1, uid, damage, held, from)


@rpc("any_peer", "reliable")
func hit_animal_rpc(uid: int, damage: int, held: int, from: Vector3) -> void:
	if hosting:
		animal_hit.emit(multiplayer.get_remote_sender_id(), uid, damage, held, from)


func send_drop(to: int, stack: Array) -> void:
	drop_rpc.rpc_id(to, stack)


@rpc("authority", "reliable")
func drop_rpc(stack: Array) -> void:
	animal_drop.emit(stack)


func send_hurt(to: int, damage: int) -> void:
	hurt_rpc.rpc_id(to, damage)


@rpc("authority", "reliable")
func hurt_rpc(damage: int) -> void:
	hurt.emit(damage)


# ---------------------------------------------------------------- chat
func say(text: String) -> void:
	text = text.strip_edges().left(160)
	if text == "" or not active():
		return
	chat_rpc.rpc(_my_name(), text)
	chat_message.emit(_my_name(), text)


@rpc("any_peer", "reliable")
func chat_rpc(name: String, text: String) -> void:
	chat_message.emit(name.left(24), text.left(160))


func player_names() -> Array:
	return [_my_name()] + names.values()
