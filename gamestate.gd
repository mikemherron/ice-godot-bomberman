extends Node

# Default game server port. Can be any number between 1024 and 49151.
# Not on the list of registered or common ports as of November 2020:
# https://en.wikipedia.org/wiki/List_of_TCP_and_UDP_port_numbers
const DEFAULT_SERVER_PORT = 10567


# When using TURN proxy, the port that client ENet sockets will listen 
# on. We need to specify this when using TURN proxy so we know what sockets
# to send incoming channel data messages to. In real implementation, we should
# update ENetMultiplayerPeer to return this information so it can be 
# automatically assigned by the OS.
const PROXIED_ENET_CLIENT_LOCAL_PORT = 11500
const PROXIED_ENET_CLIENT_SERVER_PORT = 12000

# Max number of players.
const MAX_PEERS = 12

var peer = null
var turn_proxy : TurnEnetProxy

# Name for my player.
var player_name = "The Warrior"

# Names for remote players in id:name format.
var players = {}
var players_ready = []

# Signals to let lobby GUI know what's going on.
signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)

func _process(delta):
	if turn_proxy!=null:
		turn_proxy.poll()
		
# Callback from SceneTree.
func _player_connected(id):
	# Registration of a client beings here, tell the connected player that we are here.
	register_player.rpc_id(id, player_name)


# Callback from SceneTree.
func _player_disconnected(id):
	if has_node("/root/World"): # Game is in progress.
		if multiplayer.is_server():
			game_error.emit("Player " + players[id] + " disconnected")
			end_game()
	else: # Game is not in progress.
		# Unregister this player.
		unregister_player(id)


# Callback from SceneTree, only for clients (not server).
func _connected_ok():
	# We just connected to a server
	connection_succeeded.emit()


# Callback from SceneTree, only for clients (not server).
func _server_disconnected():
	game_error.emit("Server disconnected")
	end_game()


# Callback from SceneTree, only for clients (not server).
func _connected_fail():
	multiplayer.set_network_peer(null) # Remove peer
	connection_failed.emit()


# Lobby management functions.
@rpc("any_peer")
func register_player(new_player_name):
	var id = multiplayer.get_remote_sender_id()
	players[id] = new_player_name
	player_list_changed.emit()


func unregister_player(id):
	players.erase(id)
	player_list_changed.emit()

@rpc("call_local")
func load_world():
	# Change scene.
	var world = load("res://world.tscn").instantiate()
	get_tree().get_root().add_child(world)
	get_tree().get_root().get_node("Lobby").hide()

	# Set up score.
	world.get_node("Score").add_player(multiplayer.get_unique_id(), player_name)
	for pn in players:
		world.get_node("Score").add_player(pn, players[pn])
	get_tree().set_pause(false) # Unpause and unleash the game!
	
func host_game(new_player_name, turn_client : TurnClient = null):
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	
	if turn_client!=null:
		peer.set_bind_ip("127.0.0.1")
		peer.create_server(DEFAULT_SERVER_PORT)
		# Start the proxy providing the server port
		turn_proxy = TurnEnetProxy.new(turn_client)
		turn_proxy.create_server_proxy(DEFAULT_SERVER_PORT)
	else:
		peer.create_server(DEFAULT_SERVER_PORT, MAX_PEERS)
	multiplayer.set_multiplayer_peer(peer)

func join_game(ip, new_player_name, turn_client : TurnClient = null):
	player_name = new_player_name
	peer = ENetMultiplayerPeer.new()
	
	# If turn client provided, assume this player is behind a turn relay
	# and set up proxy socket
	if turn_client!=null:
		if turn_client._active_channels.size() !=1:
			print("Can't create Turn ENet proxy, must have single TURN channel setup to server")
			return
			
		# Create ENet client that thinks server is on local host - this will
		# actually be the TURN proxy. Do some funky stuff to keep trying local
		# port numbers so we can run more than one client on the same host
		# for testing. In real implementation, we should try to update the 
		# ENet peer to return the port so can rely on the OS to assign
		var proxied_enet_client_local_port : int = PROXIED_ENET_CLIENT_LOCAL_PORT
		var proxied_enet_client_server_port : int = PROXIED_ENET_CLIENT_SERVER_PORT
		var max_local_port : int = PROXIED_ENET_CLIENT_LOCAL_PORT + 10
		var peer_created : bool = false
		while proxied_enet_client_local_port < max_local_port:
			if peer.create_client("127.0.0.1", proxied_enet_client_server_port, 0, 0, 0, proxied_enet_client_local_port)==OK:
				peer_created = true	
				break
			proxied_enet_client_server_port+=1
			proxied_enet_client_local_port+=1
			
		if !peer_created:
			print("Can't create ENet local client")
			return

		var turn_server_channel : int = turn_client._active_channels.keys()[0]
		turn_proxy = TurnEnetProxy.new(turn_client)
		print("Creating enet client proxy listening to server port %d on local port %d" % [proxied_enet_client_server_port, proxied_enet_client_local_port])
		turn_proxy.create_client_proxy(proxied_enet_client_server_port, proxied_enet_client_local_port, turn_server_channel)
	else:
		peer.create_client(ip, DEFAULT_SERVER_PORT)
	multiplayer.set_multiplayer_peer(peer)


func get_player_list():
	return players.values()


func get_player_name():
	return player_name


func begin_game():
	assert(multiplayer.is_server())
	load_world.rpc()

	var world = get_tree().get_root().get_node("World")
	var player_scene = load("res://player.tscn")

	# Create a dictionary with peer id and respective spawn points, could be improved by randomizing.
	var spawn_points = {}
	spawn_points[1] = 0 # Server in spawn point 0.
	var spawn_point_idx = 1
	for p in players:
		spawn_points[p] = spawn_point_idx
		spawn_point_idx += 1

	for p_id in spawn_points:
		var spawn_pos = world.get_node("SpawnPoints/" + str(spawn_points[p_id])).position
		var player = player_scene.instantiate()
		player.synced_position = spawn_pos
		player.name = str(p_id)
		player.set_player_name(player_name if p_id == multiplayer.get_unique_id() else players[p_id])
		world.get_node("Players").add_child(player)


func end_game():
	if has_node("/root/World"): # Game is in progress.
		# End it
		get_node("/root/World").queue_free()

	game_ended.emit()
	players.clear()


func _ready():
	multiplayer.peer_connected.connect(self._player_connected)
	multiplayer.peer_disconnected.connect(self._player_disconnected)
	multiplayer.connected_to_server.connect(self._connected_ok)
	multiplayer.connection_failed.connect(self._connected_fail)
	multiplayer.server_disconnected.connect(self._server_disconnected)
