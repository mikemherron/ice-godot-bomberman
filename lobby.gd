extends Control

var _turn_client : TurnClient

func _ready():
	# Called every time the node is added to the scene.
	gamestate.connection_failed.connect(self._on_connection_failed)
	gamestate.connection_succeeded.connect(self._on_connection_success)
	gamestate.player_list_changed.connect(self.refresh_lobby)
	gamestate.game_ended.connect(self._on_game_ended)
	gamestate.game_error.connect(self._on_game_error)
	# Set the player name according to the system username. Fallback to the path.
	if OS.has_environment("USERNAME"):
		$Connect/Name.text = OS.get_environment("USERNAME")
	else:
		var desktop_path = OS.get_system_dir(0).replace("\\", "/").split("/")
		$Connect/Name.text = desktop_path[desktop_path.size() - 2]


func _on_host_pressed():
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	$Connect.hide()
	$Players.show()
	$Connect/ErrorLabel.text = ""

	var player_name = $Connect/Name.text
	gamestate.host_game(player_name, _turn_client)
	refresh_lobby()


func _on_join_pressed():
	if $Connect/Name.text == "":
		$Connect/ErrorLabel.text = "Invalid name!"
		return

	var ip = $Connect/IPAddress.text
#	if not ip.is_valid_ip_address():
#		$Connect/ErrorLabel.text = "Invalid IP address!"
#		return

	$Connect/ErrorLabel.text = ""
	$Connect/Host.disabled = true
	$Connect/Join.disabled = true

	var player_name = $Connect/Name.text
	gamestate.join_game(ip, player_name, _turn_client)

func _on_connection_success():
	$Connect.hide()
	$Players.show()


func _on_connection_failed():
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false
	$Connect/ErrorLabel.set_text("Connection failed.")


func _on_game_ended():
	show()
	$Connect.show()
	$Players.hide()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false


func _on_game_error(errtxt):
	$ErrorDialog.dialog_text = errtxt
	$ErrorDialog.popup_centered()
	$Connect/Host.disabled = false
	$Connect/Join.disabled = false

func refresh_lobby():
	var players = gamestate.get_player_list()
	players.sort()
	$Players/List.clear()
	$Players/List.add_item(gamestate.get_player_name() + " (You)")
	for p in players:
		$Players/List.add_item(p)

	$Players/Start.disabled = not multiplayer.is_server()

func _process(delta):
	if _turn_client!=null:
		_turn_client.poll(delta)
		
func _on_start_pressed():
	gamestate.begin_game()

func _on_find_public_ip_pressed():
	OS.shell_open("https://icanhazip.com/")

func _on_turn_connect_pressed():
	
	_turn_client = TurnClient.new(
		$Turn/IPAddress.text,
		int($Turn/Port.text),
		$Turn/Username.text,
		$Turn/Password.text,
		$Turn/Realm.text
	)

	_turn_client.connect("allocate_success", _on_turn_allocate_success)
	_turn_client.connect("allocate_error", _on_turn_allocate_error)
	_turn_client.connect("channel_bind_success", _on_turn_channel_bind_success)
	_turn_client.send_allocate_request()
	_turn_debug( "➡ Sent allocation request")
	
func _on_turn_allocate_success() -> void:
	$Turn/RelayedIPAddress.text = "%s:%d" % [_turn_client._relayed_transport_address.ip, _turn_client._relayed_transport_address.port]
	$Turn/Connect.disabled = true
	$Turn/IPAddress.editable = false
	$Turn/Port.editable = false
	$Turn/Username.editable = false
	$Turn/Password.editable = false
	$Turn/Realm.editable = false
	
	$Turn/ChannelPeerIP.editable = true
	$Turn/ChannelPeerPort.editable = true
	$Turn/ChannelCreate.disabled = false
	
	_turn_debug( "✅ Created allocation")

func _on_turn_allocate_error() -> void:
	_turn_debug( "❌ Allocation Error")

func _on_turn_channel_bind_success(channel, ip, port) -> void:
	_turn_debug( "✅ Created channel bind")

func _on_clipboard_pressed():
	DisplayServer.clipboard_set($Turn/RelayedIPAddress.text)

func _turn_debug(msg : String) -> void:
	$Turn/Debug.text = $Turn/Debug.text + msg + "\n"

func _on_channel_create_pressed():
	_turn_client.send_channel_bind_request($Turn/ChannelPeerIP.text, int($Turn/ChannelPeerPort.text))
	_turn_debug( "➡ Sent Create Channel")
