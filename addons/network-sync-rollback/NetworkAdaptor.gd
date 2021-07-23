extends Node

signal received_input_tick (peer_id, msg)

func attach_network_adaptor(sync_manager) -> void:
	pass

func detach_network_adaptor(sync_manager) -> void:
	pass

func start_network_adaptor(sync_manager) -> void:
	pass

func stop_network_adaptor(sync_manager) -> void:
	pass

func send_input_tick(peer_id: int, msg: PoolByteArray) -> void:
	push_error("UNIMPLEMENTED ERROR: NetworkAdaptor.send_input_tick")

func poll() -> void:
	pass

