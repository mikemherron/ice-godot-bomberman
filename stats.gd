extends Panel

func _ready():
	var t: Tween = get_tree().create_tween()
	t.tween_interval(1)
	t.tween_callback(update_stats)
	t.set_loops(0)

func update_stats() -> void:
	var output : String = ""
	var enet : ENetMultiplayerPeer = multiplayer.multiplayer_peer
	var conn : ENetConnection = enet.get_host()
	for peer_num in conn.get_peers().size():
		var peer : ENetPacketPeer = conn.get_peers()[peer_num]
		output += "Peer Num: %d\n" % [peer_num]
		output += " Packet Loss: %f\n" % [peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)]
		output += " Packet Loss Variance: %f\n" % [peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS_VARIANCE)]
		output += " RTT: %f\n" % [peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)]
		output += " RTT Variance: %f\n" % [peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME_VARIANCE)]
	$Label.text = output
