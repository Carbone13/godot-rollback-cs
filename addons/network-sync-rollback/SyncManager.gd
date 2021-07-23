extends Node

const SpawnManager = preload("res://addons/network-sync-rollback/SpawnManager.gd")
const NetworkAdaptor = preload("res://addons/network-sync-rollback/NetworkAdaptor.gd")
const RPCNetworkAdaptor = preload("res://addons/network-sync-rollback/RPCNetworkAdaptor.gd")

class Peer extends Reference:
	var peer_id: int
	
	var rtt: int
	var last_ping_received: int
	var time_delta: float
	
	var last_remote_tick_received: int = 0
	var next_local_tick_requested: int = 1
	
	var remote_lag: int
	var local_lag: int
	
	var calculated_advantage: float
	var advantage_list := []
	
	func _init(_peer_id: int) -> void:
		peer_id = _peer_id
	
	func record_advantage(ticks_to_calculate_advantage: int) -> void:
		advantage_list.append(local_lag - remote_lag)
		if advantage_list.size() >= ticks_to_calculate_advantage:
			var total: float = 0
			for x in advantage_list:
				total += x
			calculated_advantage = total / advantage_list.size()
			advantage_list.clear()
	
	func clear_advantage() -> void:
		calculated_advantage = 0.0
		advantage_list.clear()
	
	func clear() -> void:
		rtt = 0
		last_ping_received = 0
		time_delta = 0
		last_remote_tick_received = 0
		next_local_tick_requested = 0
		remote_lag = 0
		local_lag = 0
		clear_advantage()

class InputForPlayer:
	var input := {}
	var predicted: bool
	
	func _init(_input: Dictionary, _predicted: bool) -> void:
		input = _input
		predicted = _predicted

class InputBufferFrame:
	var tick: int
	var players := {}
	
	func _init(_tick: int) -> void:
		tick = _tick
	
	func get_player_input(peer_id: int) -> Dictionary:
		if players.has(peer_id):
			return players[peer_id].input
		return {}
	
	func is_player_input_predicted(peer_id: int) -> bool:
		if players.has(peer_id):
			return players[peer_id].predicted
		return true
	
	func get_missing_peers(peers: Dictionary) -> Array:
		var missing := []
		for peer_id in peers:
			if not players.has(peer_id) or players[peer_id].predicted:
				missing.append(peer_id)
		return missing
	
	func is_complete(peers: Dictionary) -> bool:
		for peer_id in peers:
			if not players.has(peer_id) or players[peer_id].predicted:
				return false
		return true

class StateBufferFrame:
	var tick: int
	var data: Dictionary

	func _init(_tick, _data) -> void:
		tick = _tick
		data = _data

enum InputMessageKey {
	NEXT_TICK_REQUESTED,
	INPUT,
}

const DEFAULT_MESSAGE_BUFFER_SIZE = 1280

class MessageSerializer:
	func serialize_input(input: Dictionary) -> PoolByteArray:
		return var2bytes(input)

	func unserialize_input(serialized: PoolByteArray) -> Dictionary:
		return bytes2var(serialized)

	func serialize_message(msg: Dictionary) -> PoolByteArray:
		var buffer := StreamPeerBuffer.new()
		buffer.resize(DEFAULT_MESSAGE_BUFFER_SIZE)
	
		buffer.put_u32(msg[InputMessageKey.NEXT_TICK_REQUESTED])
		
		var input_ticks = msg[InputMessageKey.INPUT]
		buffer.put_u8(input_ticks.size())
		for tick in input_ticks:
			buffer.put_u32(tick)
			
			var input = input_ticks[tick]
			buffer.put_u16(input.size())
			buffer.put_data(input)
		
		buffer.resize(buffer.get_position())
		return buffer.data_array

	func unserialize_message(serialized) -> Dictionary:
		var buffer := StreamPeerBuffer.new()
		buffer.put_data(serialized)
		buffer.seek(0)
		
		var msg := {
			InputMessageKey.NEXT_TICK_REQUESTED: buffer.get_u32(),
			InputMessageKey.INPUT: {}
		}
		
		var tick_count = buffer.get_u8()
		for tick_index in range(tick_count):
			var tick = buffer.get_u32()
			
			var input_size = buffer.get_u16()
			msg[InputMessageKey.INPUT][tick] = buffer.get_data(input_size)[1]
		
		return msg

var network_adaptor: NetworkAdaptor setget set_network_adaptor
var message_serializer: MessageSerializer setget set_message_serializer

var peers := {}
var input_buffer := []
var state_buffer := []

var max_buffer_size := 20
var ticks_to_calculate_advantage := 60
var input_delay := 2 setget set_input_delay
var max_input_frames_per_message := 5
var max_messages_at_once := 2
var max_input_buffer_underruns := 300
var skip_ticks_after_sync_regained := 0
var interpolation := false
var rollback_debug_ticks := 0
var debug_message_bytes := 700
var log_state := false

# In seconds, because we don't want it to be dependent on the network tick.
var ping_frequency := 1.0 setget set_ping_frequency

var input_tick: int = 0 setget _set_readonly_variable
var current_tick: int = 0 setget _set_readonly_variable
var skip_ticks: int = 0 setget _set_readonly_variable
var rollback_ticks: int = 0 setget _set_readonly_variable
var input_buffer_underruns := 0 setget _set_readonly_variable
var started := false setget _set_readonly_variable

var _ping_timer: Timer
var _spawn_manager
var _tick_time: float
var _input_buffer_start_tick: int
var _state_buffer_start_tick: int
var _input_send_queue := []
var _input_send_queue_start_tick: int
var _interpolation_state := {}
var _time_since_last_tick := 0.0
var _logged_remote_state: Dictionary

signal sync_started ()
signal sync_stopped ()
signal sync_lost ()
signal sync_regained ()
signal sync_error (msg)

signal skip_ticks_flagged (count)
signal rollback_flagged (tick, peer_id, local_input, remote_input)
signal remote_state_mismatch (tick, peer_id, local_state, remote_state)

signal peer_added (peer_id)
signal peer_removed (peer_id)
signal peer_pinged_back (peer)

signal state_loaded (rollback_ticks)
signal tick_finished (is_rollback)
signal scene_spawned (name, spawned_node, scene, data)

func _ready() -> void:
	get_tree().connect("network_peer_disconnected", self, "remove_peer")
	get_tree().connect("server_disconnected", self, "stop")
	
	_ping_timer = Timer.new()
	_ping_timer.name = "PingTimer"
	_ping_timer.wait_time = ping_frequency
	_ping_timer.autostart = true
	_ping_timer.one_shot = false
	_ping_timer.pause_mode = Node.PAUSE_MODE_PROCESS
	_ping_timer.connect("timeout", self, "_on_ping_timer_timeout")
	add_child(_ping_timer)
	
	_spawn_manager = SpawnManager.new()
	_spawn_manager.name = "SpawnManager"
	add_child(_spawn_manager)
	_spawn_manager.connect("scene_spawned", self, "_on_SpawnManager_scene_spawned")
	
	if network_adaptor == null:
		set_network_adaptor(RPCNetworkAdaptor.new())
	if message_serializer == null:
		set_message_serializer(MessageSerializer.new())

func _set_readonly_variable(_value) -> void:
	pass

func set_network_adaptor(_network_adaptor: NetworkAdaptor) -> void:
	assert(not started, "Changing the network adaptor after SyncManager has started will probably break everything")
	
	if network_adaptor != null:
		network_adaptor.detach_network_adaptor(self)
		network_adaptor.disconnect("received_input_tick", self, "_receive_input_tick")
		remove_child(network_adaptor)
		network_adaptor.queue_free()
	
	network_adaptor = _network_adaptor
	network_adaptor.name = 'NetworkAdaptor'
	add_child(network_adaptor)
	network_adaptor.connect("received_input_tick", self, "_receive_input_tick")
	network_adaptor.attach_network_adaptor(self)

func set_message_serializer(_message_serializer: MessageSerializer) -> void:
	assert(not started, "Changing the message serializer after SyncManager has started will probably break everything")
	message_serializer = _message_serializer

func set_ping_frequency(_ping_frequency) -> void:
	ping_frequency = _ping_frequency
	if _ping_timer:
		_ping_timer.wait_time = _ping_frequency

func set_input_delay(_input_delay: int) -> void:
	if started:
		push_warning("Cannot change input delay after sync'ing has already started")
	input_delay = _input_delay

func add_peer(peer_id: int) -> void:
	assert(not peers.has(peer_id), "Peer with given id already exists")
	assert(peer_id != get_tree().get_network_unique_id(), "Cannot add ourselves as a peer in SyncManager")
	
	if peers.has(peer_id):
		return
	if peer_id == get_tree().get_network_unique_id():
		return
	
	peers[peer_id] = Peer.new(peer_id)
	emit_signal("peer_added", peer_id)

func has_peer(peer_id: int) -> bool:
	return peers.has(peer_id)

func get_peer(peer_id: int) -> Peer:
	return peers.get(peer_id)

func remove_peer(peer_id: int) -> void:
	if peers.has(peer_id):
		peers.erase(peer_id)
		emit_signal("peer_removed", peer_id)
	if peers.size() == 0:
		stop()

func clear_peers() -> void:
	for peer_id in peers.keys().duplicate():
		remove_peer(peer_id)

func _on_ping_timer_timeout() -> void:
	var system_time = OS.get_system_time_msecs()
	for peer_id in peers:
		assert(peer_id != get_tree().get_network_unique_id(), "Cannot ping ourselves")
		var msg = {
			local_time = system_time,
		}
		rpc_unreliable_id(peer_id, "_remote_ping", msg)

remote func _remote_ping(msg: Dictionary) -> void:
	var peer_id = get_tree().get_rpc_sender_id()
	assert(peer_id != get_tree().get_network_unique_id(), "Cannot ping back ourselves")
	msg['remote_time'] = OS.get_system_time_msecs()
	rpc_unreliable_id(peer_id, "_remote_ping_back", msg)

remote func _remote_ping_back(msg: Dictionary) -> void:
	var system_time = OS.get_system_time_msecs()
	var peer_id = get_tree().get_rpc_sender_id()
	var peer = peers[peer_id]
	peer.last_ping_received = system_time
	peer.rtt = system_time - msg['local_time']
	peer.time_delta = msg['remote_time'] - msg['local_time'] - (peer.rtt / 2.0)
	emit_signal("peer_pinged_back", peer)

func start() -> void:
	assert(get_tree().is_network_server(), "start() should only be called on the host")
	if started:
		return
	if get_tree().is_network_server():
		var highest_rtt: int = 0
		for peer in peers.values():
			highest_rtt = max(highest_rtt, peer.rtt)
		
		# Call _remote_start() on all the other peers.
		rpc("_remote_start")
		
		# Wait for half the highest RTT to start locally.
		print ("Delaying host start by %sms" % (highest_rtt / 2))
		yield(get_tree().create_timer(highest_rtt / 2000.0), 'timeout')
		_remote_start()

func _reset() -> void:
	input_tick = 0
	current_tick = input_tick - input_delay
	skip_ticks = 0
	rollback_ticks = 0
	input_buffer_underruns = 0
	input_buffer.clear()
	state_buffer.clear()
	_input_buffer_start_tick = 1
	_state_buffer_start_tick = 0
	_input_send_queue.clear()
	_input_send_queue_start_tick = 1
	_interpolation_state.clear()
	_time_since_last_tick = 0.0
	_logged_remote_state.clear()

remote func _remote_start() -> void:
	_reset()
	_tick_time = (1.0 / Engine.iterations_per_second)
	started = true
	network_adaptor.start_network_adaptor(self)
	emit_signal("sync_started")

func stop() -> void:
	if get_tree().is_network_server():
		rpc("_remote_stop")
	else:
		_remote_stop()

remotesync func _remote_stop() -> void:
	network_adaptor.stop_network_adaptor(self)
	started = false
	_reset()
	
	for peer in peers.values():
		peer.clear()
	
	emit_signal("sync_stopped")

func _handle_fatal_error(msg: String):
	emit_signal("sync_error", msg)
	push_error("NETWORK SYNC LOST: " + msg)
	stop()
	return null

func _call_get_local_input() -> Dictionary:
	var input := {}
	var nodes: Array = get_tree().get_nodes_in_group('network_sync')
	for node in nodes:
		if node.is_network_master() and node.has_method('_get_local_input') and node.is_inside_tree():
			var node_input = node._get_local_input()
			if node_input.size() > 0:
				input[str(node.get_path())] = node_input
	return input

func _call_predict_remote_input(previous_input: Dictionary, ticks_since_real_input: int) -> Dictionary:
	var input := {}
	var nodes: Array = get_tree().get_nodes_in_group('network_sync')
	for node in nodes:
		if node.is_network_master():
			continue
		
		var node_path_str := str(node.get_path())
		var has_predict_network_input: bool = node.has_method('_predict_remote_input')
		if has_predict_network_input or previous_input.has(node_path_str):
			var previous_input_for_node = previous_input.get(node_path_str, {})
			var predicted_input_for_node = node._predict_remote_input(previous_input_for_node, ticks_since_real_input) if has_predict_network_input else previous_input_for_node.duplicate()
			if predicted_input_for_node.size() > 0:
				input[node_path_str] = predicted_input_for_node
	
	return input

func _call_network_process(delta: float, input_frame: InputBufferFrame) -> void:
	var nodes: Array = get_tree().get_nodes_in_group('network_sync')
	var i = nodes.size()
	while i > 0:
		i -= 1
		var node = nodes[i]
		if node.has_method('_network_process') and node.is_inside_tree():
			var player_input = input_frame.get_player_input(node.get_network_master())
			node._network_process(delta, player_input.get(str(node.get_path()), {}))

func _call_save_state() -> Dictionary:
	var state := {}
	var nodes: Array = get_tree().get_nodes_in_group('network_sync')
	for node in nodes:
		if node.has_method('_save_state') and node.is_inside_tree() and not node.is_queued_for_deletion():
			var node_path = str(node.get_path())
			if node_path != "":
				state[node_path] = node._save_state()
	return state

func _call_load_state(state: Dictionary) -> void:
	for node_path in state:
		assert(has_node(node_path), "Unable to restore state to missing node: %s" % node_path)
		if has_node(node_path):
			var node = get_node(node_path)
			if node.has_method('_load_state'):
				node._load_state(state[node_path])

func _call_interpolate_state(weight: float) -> void:
	for node_path in _interpolation_state:
		if has_node(node_path):
			var node = get_node(node_path)
			if node.has_method('_interpolate_state'):
				var states = _interpolation_state[node_path]
				node._interpolate_state(states[0], states[1], weight)

func _save_current_state() -> void:
	assert(current_tick >= 0, "Attempting to store state for negative tick")
	if current_tick < 0:
		return
	
	var state_data = _call_save_state()
	state_buffer.append(StateBufferFrame.new(current_tick, state_data))
	
	if log_state and not get_tree().is_network_server() and is_player_input_complete(current_tick):
		rpc_id(1, "_log_saved_state", current_tick, state_data)

func _do_tick(delta: float, is_rollback: bool = false) -> void:
	var input_frame := get_input_frame(current_tick)
	var previous_frame := get_input_frame(current_tick - 1)
	
	assert(input_frame != null, "Input frame for current_tick is null")
	
	# Predict any missing input.
	for peer_id in peers:
		if not input_frame.players.has(peer_id) or input_frame.players[peer_id].predicted:
			var predicted_input := {}
			if previous_frame:
				var peer: Peer = peers[peer_id]
				var ticks_since_real_input = current_tick - peer.last_remote_tick_received
				predicted_input = _call_predict_remote_input(previous_frame.get_player_input(peer_id), ticks_since_real_input)
			_calculate_input_hash(predicted_input)
			input_frame.players[peer_id] = InputForPlayer.new(predicted_input, true)
	
	_call_network_process(delta, input_frame)
	_save_current_state()
	
	emit_signal("tick_finished", is_rollback)

func _get_or_create_input_frame(tick: int) -> InputBufferFrame:
	var input_frame: InputBufferFrame
	if input_buffer.size() == 0:
		input_frame = InputBufferFrame.new(tick)
		input_buffer.append(input_frame)
	elif tick > input_buffer[-1].tick:
		var highest = input_buffer[-1].tick
		while highest < tick:
			highest += 1
			input_frame = InputBufferFrame.new(highest)
			input_buffer.append(input_frame)
	else:
		input_frame = get_input_frame(tick)
		if input_frame == null:
			return _handle_fatal_error("Requested input frame (%s) not found in buffer" % tick)
	
	return input_frame

func _cleanup_buffers() -> bool:
	# Clean-up the input send queue.
	var min_next_tick_requested = _calculate_minimum_next_tick_requested()
	while _input_send_queue_start_tick < min_next_tick_requested:
		_input_send_queue.pop_front()
		_input_send_queue_start_tick += 1
	
	# Clean-up old state buffer frames.
	while state_buffer.size() > max_buffer_size:
		var state_frame_to_retire: StateBufferFrame = state_buffer[0]
		var input_frame = get_input_frame(state_frame_to_retire.tick + 1)
		if input_frame == null or not input_frame.is_complete(peers):
			var missing: Array = input_frame.get_missing_peers(peers)
			push_warning("Attempting to retire state frame %s, but input frame %s is still missing input (missing peer(s): %s)" % [state_frame_to_retire.tick, input_frame.tick, missing])
			return false
		
		state_buffer.pop_front()
		_state_buffer_start_tick += 1
	
	# Clean-up old input buffer frames. Unlike state frames, we can have many
	# frames from the future if we are running behind. We don't want having too
	# many future frames to end up discarding input for the current frame, so we
	# only count input frames before the current frame towards the buffer size.
	while (current_tick - _input_buffer_start_tick) > max_buffer_size:
		_input_buffer_start_tick += 1
		input_buffer.pop_front()
	
	return true

func get_input_frame(tick: int) -> InputBufferFrame:
	if tick < _input_buffer_start_tick:
		return null
	var index = tick - _input_buffer_start_tick
	if index >= input_buffer.size():
		return null
	var input_frame = input_buffer[index]
	assert(input_frame.tick == tick, "Input frame retreived from input buffer has mismatched tick number")
	return input_frame

func get_latest_input_from_peer(peer_id: int) -> Dictionary:
	if peers.has(peer_id):
		var peer: Peer = peers[peer_id]
		var input_frame = get_input_frame(peer.last_remote_tick_received)
		if input_frame:
			return input_frame.get_player_input(peer_id)
	return {}

func get_latest_input_for_node(node: Node) -> Dictionary:
	return get_latest_input_from_peer_for_path(node.get_network_master(), str(node.get_path()))

func get_latest_input_from_peer_for_path(peer_id: int, path: String) -> Dictionary:
	return get_latest_input_from_peer(peer_id).get(path, {})

func _get_state_frame(tick: int) -> StateBufferFrame:
	if tick < _state_buffer_start_tick:
		return null
	var index = tick - _state_buffer_start_tick
	if index >= state_buffer.size():
		return null
	var state_frame = state_buffer[index]
	assert(state_frame.tick == tick, "State frame retreived from state buffer has mismatched tick number")
	return state_frame

func is_player_input_complete(tick: int) -> bool:
	if tick > input_buffer[-1].tick:
		# We don't have any input for this tick.
		return false
	
	var input_frame = get_input_frame(tick)
	if input_frame == null:
		# This means this frame has already been removed from the buffer, which
		# we would never allow if it wasn't complete.
		return true
	return input_frame.is_complete(peers)

func is_current_player_input_complete() -> bool:
	return is_player_input_complete(current_tick)

func _get_input_messages_from_send_queue_in_range(first_index: int, last_index: int, reverse: bool = false) -> Array:
	var indexes = range(first_index, last_index + 1) if not reverse else range(last_index, first_index - 1, -1)

	var all_messages := []
	var msg := {}
	for index in indexes:

		msg[_input_send_queue_start_tick + index] = _input_send_queue[index]
		
		if max_input_frames_per_message > 0 and msg.size() == max_input_frames_per_message:
			all_messages.append(msg)
			msg = {}
	
	if msg.size() > 0:
		all_messages.append(msg)
	
	return all_messages

func _get_input_messages_from_send_queue_for_peer(peer: Peer) -> Array:
	var first_index := peer.next_local_tick_requested - _input_send_queue_start_tick
	var last_index := _input_send_queue.size() - 1
	var max_messages := (max_input_frames_per_message * max_messages_at_once)
	
	if (last_index + 1) - first_index <= max_messages:
		return _get_input_messages_from_send_queue_in_range(first_index, last_index, true)
	
	var new_messages = int(ceil(max_messages_at_once / 2.0))
	var old_messages = int(floor(max_messages_at_once / 2.0))
	
	return _get_input_messages_from_send_queue_in_range(last_index - (new_messages * max_input_frames_per_message) + 1, last_index, true) + \
		   _get_input_messages_from_send_queue_in_range(first_index, first_index + (old_messages * max_input_frames_per_message) - 1)

func _record_advantage(force_calculate_advantage: bool = false) -> void:
	var max_advantage: float
	for peer in peers.values():
		# Number of frames we are predicting for this peer.
		peer.local_lag = (input_tick + 1) - peer.last_remote_tick_received
		# Calculate the advantage the peer has over us.
		peer.record_advantage(ticks_to_calculate_advantage if not force_calculate_advantage else 0)
		# Attempt to find the greatest advantage.
		max_advantage = max(max_advantage, peer.calculated_advantage)

func _calculate_skip_ticks() -> bool:
	# Attempt to find the greatest advantage.
	var max_advantage: float
	for peer in peers.values():
		max_advantage = max(max_advantage, peer.calculated_advantage)
	
	if max_advantage >= 2.0 and skip_ticks == 0:
		skip_ticks = int(max_advantage / 2)
		emit_signal("skip_ticks_flagged", skip_ticks)
		return true
	
	return false

func _calculate_message_bytes(msg) -> int:
	return var2bytes(msg).size()

func _calculate_minimum_next_tick_requested() -> int:
	if peers.size() == 0:
		return 1
	var peer_list := peers.values().duplicate()
	var result: int = peer_list.pop_front().next_local_tick_requested
	for peer in peer_list:
		result = min(result, peer.next_local_tick_requested)
	return result

func _send_input_messages_to_peer(peer_id: int) -> void:
	assert(peer_id != get_tree().get_network_unique_id(), "Cannot send input to ourselves")
	var peer = peers[peer_id]
	
	for input in _get_input_messages_from_send_queue_for_peer(peer):
		var msg = {
			InputMessageKey.NEXT_TICK_REQUESTED: peer.last_remote_tick_received + 1,
			InputMessageKey.INPUT: input,
		}
		
		var bytes = message_serializer.serialize_message(msg)
		
		# See https://gafferongames.com/post/packet_fragmentation_and_reassembly/
		if debug_message_bytes:
			if bytes.size() > debug_message_bytes:
				push_error("Sending message w/ size %s bytes" % bytes.size())
		
		#var ticks = msg[InputMessageKey.INPUT].keys()
		#print ("[%s] Sending ticks %s - %s" % [current_tick, min(ticks[0], ticks[-1]), max(ticks[0], ticks[-1])])
		
		network_adaptor.send_input_tick(peer_id, bytes)

func _send_input_messages_to_all_peers() -> void:
	for peer_id in peers:
		_send_input_messages_to_peer(peer_id)

func _physics_process(delta: float) -> void:
	if not started:
		return
	
	if current_tick == 0:
		# Store an initial state before any ticks.
		_save_current_state()
	
	# We do this in _process() too, so hopefully all is good by now, but just in
	# case, we don't want to miss out on any data.
	network_adaptor.poll()
	
	if rollback_debug_ticks > 0 and current_tick >= rollback_debug_ticks:
		rollback_ticks = max(rollback_ticks, rollback_debug_ticks)
	
	# We need to resimulate the current tick since we did a partial rollback
	# to the previous tick in order to interpolate.
	if interpolation and current_tick > 1:
		rollback_ticks = max(rollback_ticks, 1)
	
	if rollback_ticks > 0:
		var original_tick = current_tick
		
		# Rollback our internal state.
		assert(rollback_ticks + 1 <= state_buffer.size(), "Not enough state in buffer to rollback requested number of frames")
		if rollback_ticks + 1 > state_buffer.size():
			_handle_fatal_error("Not enough state in buffer to rollback %s frames" % rollback_ticks)
			return
		
		_call_load_state(state_buffer[-rollback_ticks - 1].data)
		state_buffer.resize(state_buffer.size() - rollback_ticks)
		current_tick -= rollback_ticks
		
		emit_signal("state_loaded", rollback_ticks)
		
		# Iterate forward until we're at the same spot we left off.
		while rollback_ticks > 0:
			current_tick += 1
			_do_tick(delta, true)
			rollback_ticks -= 1
		assert(current_tick == original_tick, "Rollback didn't return to the original tick")
	
	if get_tree().is_network_server() and _logged_remote_state.size() > 0:
		_process_logged_remote_state()
	
	_record_advantage()
	
	# Negative numbers are used to skip some additional ticks after we've
	# technically regained sync, but we don't want to start back up again right
	# away.
	if input_buffer_underruns < 0:
		input_buffer_underruns += 1
		if input_buffer_underruns == 0:
			# Let the world know we've regained sync, and fall back to normal
			# operation. (This is the only branch that shouldn't 'return').
			emit_signal("sync_regained")
			# We don't want to skip ticks through the normal mechanism, because
			# any skips that were previously calculated don't apply anymore.
			skip_ticks = 0
		else:
			# Even when we're skipping ticks, still send input.
			_send_input_messages_to_all_peers()
			return
	# Attempt to clean up buffers, but if we can't, that means we've lost sync.
	elif not _cleanup_buffers():
		if input_buffer_underruns == 0:
			emit_signal("sync_lost")
		input_buffer_underruns += 1
		if input_buffer_underruns >= max_input_buffer_underruns:
			_handle_fatal_error("Unable to regain synchronization")
			return
		# Even when we're skipping ticks, still send input.
		_send_input_messages_to_all_peers()
		return
	elif input_buffer_underruns > 0:
		# We've technically regained sync, but we don't want to just fall out of
		# sync again next frame, so skip a few more frames for good luck.
		input_buffer_underruns = -skip_ticks_after_sync_regained
		return
	
	if skip_ticks > 0:
		skip_ticks -= 1
		if skip_ticks == 0:
			for peer in peers.values():
				peer.clear_advantage()
		else:
			# Even when we're skipping ticks, still send input.
			_send_input_messages_to_all_peers()
			return
	
	if _calculate_skip_ticks():
		# This means we need to skip some ticks, so may as well start now!
		return
	
	input_tick += 1
	current_tick += 1
	
	var input_frame := _get_or_create_input_frame(input_tick)
	# The underlying error would have already been reported in
	# _get_or_create_input_frame() so we can just return here.
	if input_frame == null:
		return
		
	var local_input = _call_get_local_input()
	_calculate_input_hash(local_input)
	input_frame.players[get_tree().get_network_unique_id()] = InputForPlayer.new(local_input, false)
	_input_send_queue.append(message_serializer.serialize_input(local_input))
	assert(input_tick == _input_send_queue_start_tick + _input_send_queue.size() - 1, "Input send queue ticks numbers are misaligned")
	_send_input_messages_to_all_peers()
	
	_time_since_last_tick = 0.0
	
	if current_tick > 0:
		_do_tick(delta)
		
		if interpolation:
			# Capture the state data to interpolate between.
			var to_state: Dictionary = state_buffer[-1].data
			var from_state: Dictionary = state_buffer[-2].data
			_interpolation_state.clear()
			for path in to_state:
				if from_state.has(path):
					_interpolation_state[path] = [from_state[path], to_state[path]]
			
			# Return to state from the previous frame, so we can interpolate
			# towards the state of the current frame.
			_call_load_state(state_buffer[-2].data)

func _process(delta: float) -> void:
	if not started:
		return
	
	_time_since_last_tick += delta
	
	network_adaptor.poll()
	
	if interpolation:
		var weight: float = _time_since_last_tick / _tick_time
		if weight > 1.0:
			weight = 1.0
		_call_interpolate_state(weight)

# Calculates the input hash without any keys that start with '_' (if string)
# or less than 0 (if integer) to allow some properties to not count when
# comparing predicted input with real input.
func _calculate_input_hash(input: Dictionary) -> void:
	var cleaned_input := input.duplicate(true)
	if cleaned_input.has('$'):
		cleaned_input.erase('$')
	for path in cleaned_input:
		for key in cleaned_input[path].keys():
			var value = cleaned_input[path]
			if key is String:
				if key.begins_with('_'):
					value.erase(key)
			elif key is int:
				if key < 0:
					value.erase(key)
	input['$'] = cleaned_input.hash()

func _receive_input_tick(peer_id: int, serialized_msg: PoolByteArray) -> void:
	if not started:
		return
	
	var msg = message_serializer.unserialize_message(serialized_msg)
	
	var all_remote_input: Dictionary = msg[InputMessageKey.INPUT]
	var all_remote_ticks = all_remote_input.keys()
	all_remote_ticks.sort()
	
	var first_remote_tick = all_remote_ticks[0]
	var last_remote_tick = all_remote_ticks[-1]

	if first_remote_tick >= input_tick + max_buffer_size:
		# This either happens because we are really far behind (but maybe, just
		# maybe could catch up) or we are receiving old ticks from a previous
		# round that hadn't yet arrived. Just discard the message and hope for
		# the best, but if we can't keep up, another one of the fail safes will
		# detect that we are out of sync.
		print ("Discarding message from the future")
		return
	
	var peer: Peer = peers[peer_id]
	
	# Integrate the input we received into the input buffer.
	for remote_tick in all_remote_ticks:
		# Skip ticks we already have.
		if remote_tick <= peer.last_remote_tick_received:
			continue
		# This means the input frame has already been retired, which can only
		# happen if we already had all the input.
		if remote_tick < _input_buffer_start_tick:
			continue
		
		var remote_input = message_serializer.unserialize_input(all_remote_input[remote_tick])
		var input_frame := _get_or_create_input_frame(remote_tick)
		if input_frame == null:
			# _get_or_create_input_frame() will have already flagged the error,
			# so we can just return here.
			return
		
		# If we already have non-predicted input for this peer, then skip it.
		if not input_frame.is_player_input_predicted(peer_id):
			continue
		
		#print ("Received remote tick %s from %s" % [remote_tick, peer_id])
		
		# If we received a tick in the past and we aren't already setup to
		# rollback earlier than that...
		var tick_delta = current_tick - remote_tick
		if tick_delta >= 0 and rollback_ticks <= tick_delta:
			# Grab our predicted input, and store the remote input.
			var local_input = input_frame.get_player_input(peer_id)
			input_frame.players[peer_id] = InputForPlayer.new(remote_input, false)
			
			# Check if the remote input matches what we had predicted, if not,
			# flag that we need to rollback.
			if local_input['$'] != remote_input['$']:
				rollback_ticks = tick_delta + 1
				emit_signal("rollback_flagged", remote_tick, peer_id, local_input, remote_input)
		else:
			# Otherwise, just store it.
			input_frame.players[peer_id] = InputForPlayer.new(remote_input, false)
	
	# Find what the last remote tick we received was after filling these in.
	var index = (peer.last_remote_tick_received - _input_buffer_start_tick) + 1
	while index < input_buffer.size() and not input_buffer[index].is_player_input_predicted(peer.peer_id):
		peer.last_remote_tick_received += 1
		index += 1
	
	# Record the next frame the other peer needs.
	peer.next_local_tick_requested = max(msg[InputMessageKey.NEXT_TICK_REQUESTED], peer.next_local_tick_requested)
	
	# Number of frames the remote is predicting for us.
	peer.remote_lag = (peer.last_remote_tick_received + 1) - peer.next_local_tick_requested

master func _log_saved_state(tick: int, remote_data: Dictionary) -> void:
	if not started:
		return
	
	var peer_id = get_tree().get_rpc_sender_id()
	if not _logged_remote_state.has(peer_id):
		_logged_remote_state[peer_id] = []
		
	# The logged state will be processed once we have complete player input in
	# the _process_logged_remote_state() and _check_remote_state() methods below.
	_logged_remote_state[peer_id].append(StateBufferFrame.new(tick, remote_data))

func _process_logged_remote_state() -> void:
	for peer_id in _logged_remote_state:
		var remote_state_buffer = _logged_remote_state[peer_id]
		while remote_state_buffer.size() > 0:
			var remote_tick = remote_state_buffer[0].tick
			if not is_player_input_complete(remote_tick):
				break
			
			var local_state = _get_state_frame(remote_tick)
			if local_state == null:
				break
			
			var remote_state = remote_state_buffer.pop_front()
			_check_remote_state(peer_id, remote_state, local_state)

func _check_remote_state(peer_id: int, remote_state: StateBufferFrame, local_state: StateBufferFrame) -> void:
	#print ("checking remote state for tick: %s" % remote_state.tick)
	if local_state.data.hash() != remote_state.data.hash():
		emit_signal("remote_state_mismatch", local_state.tick, peer_id, local_state.data, remote_state.data)

func spawn(name: String, parent: Node, scene: PackedScene, data: Dictionary = {}, rename: bool = true, signal_name: String = '') -> Node:
	return _spawn_manager.spawn(name, parent, scene, data, rename, signal_name)

func _on_SpawnManager_scene_spawned(name: String, spawned_node: Node, scene: PackedScene, data: Dictionary) -> void:
	emit_signal("scene_spawned", name, spawned_node, scene, data)
