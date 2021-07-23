extends "res://addons/network-sync-rollback/NetworkAdaptor.gd"

func send_input_tick(peer_id: int, msg: PoolByteArray) -> void:
	rpc_unreliable_id(peer_id, '_rit', msg)

# _rit is short for _receive_input_tick. The method name ends up in each message
# so, we're trying to keep it short.
remote func _rit(msg: PoolByteArray) -> void:
	emit_signal("received_input_tick", get_tree().get_rpc_sender_id(), msg)
