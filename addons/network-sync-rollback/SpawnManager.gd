extends Node

var spawn_records := {}
var spawned_nodes := {}
var counter := {}

signal scene_spawned (name, spawned_node, scene, data)

func _ready() -> void:
	add_to_group('network_sync')
	SyncManager.connect("sync_stopped", self, "_on_SyncManager_sync_stopped")

func _on_SyncManager_sync_stopped() -> void:
	spawn_records.clear()
	spawned_nodes.clear()

func _rename_node(name: String) -> String:
	if not counter.has(name):
		counter[name] = 0
	counter[name] += 1
	return name + str(counter[name])

func spawn(name: String, parent: Node, scene: PackedScene, data: Dictionary, rename: bool = true, signal_name: String = '') -> Node:
	var spawned_node = scene.instance()
	if signal_name == '':
		signal_name = name
	if rename:
		name = _rename_node(name)
	spawned_node.name = name
	parent.add_child(spawned_node)
	
	if spawned_node.has_method('_network_spawn_preprocess'):
		data = spawned_node._network_spawn_preprocess(data)
	
	if spawned_node.has_method('_network_spawn'):
		spawned_node._network_spawn(data)
	
	var spawn_record := {
		name = spawned_node.name,
		parent = parent.get_path(),
		scene = scene.resource_path,
		data = data,
		signal_name = signal_name,
	}
	
	var node_path = str(spawned_node.get_path())
	spawn_records[node_path] = spawn_record
	spawned_nodes[node_path] = spawned_node
	
	#print ("[%s] spawned: %s" % [SyncManager.current_tick, spawned_node.name])
	
	emit_signal("scene_spawned", signal_name, spawned_node, scene, data)
	
	return spawned_node

func _save_state() -> Dictionary:
	for node_path in spawned_nodes.keys():
		var node = spawned_nodes[node_path]
		if not is_instance_valid(node):
			spawned_nodes.erase(node_path)
			spawn_records.erase(node_path)
			#print ("[SAVE] removing invalid: %s" % node_path)
		elif node.is_queued_for_deletion():
			#print ("[SAVE] removing deleted: %s" % node_path)
			if node.get_parent():
				node.get_parent().remove_child(node)
			spawned_nodes.erase(node_path)
			spawn_records.erase(node_path)
	
	return {
		spawn_records = spawn_records.duplicate(),
		counter = counter.duplicate(),
	}

func _load_state(state: Dictionary) -> void:
	spawn_records = state['spawn_records'].duplicate()
	counter = state['counter'].duplicate()
	
	# Remove nodes that aren't in the state we are loading.
	for node_path in spawned_nodes.keys():
		if not spawn_records.has(node_path):
			var node = spawned_nodes[node_path]
			if node.has_method('_network_despawn'):
				node._network_despawn()
			if node.get_parent():
				node.get_parent().remove_child(node)
			node.queue_free()
			spawned_nodes.erase(node_path)
			#print ("[LOAD] de-spawned: %s" % node.name)
	
	# Spawn nodes that don't already exist.
	for node_path in spawn_records.keys():
		if spawned_nodes.has(node_path):
			var old_node = spawned_nodes[node_path]
			if not is_instance_valid(old_node) or old_node.is_queued_for_deletion():
				spawned_nodes.erase(node_path)
		
		if not spawned_nodes.has(node_path):
			var spawn_record = spawn_records[node_path]
			
			var parent = get_tree().current_scene.get_node(spawn_record['parent'])
			var scene = load(spawn_record['scene'])
			
			var spawned_node = scene.instance()
			spawned_node.name = spawn_record['name']
			parent.add_child(spawned_node)
			
			if spawned_node.has_method('_network_spawn'):
				spawned_node._network_spawn(spawn_record['data'])
			
			spawned_nodes[node_path] = spawned_node
			emit_signal("scene_spawned", spawn_record['signal_name'], spawned_node, scene, spawn_record['data'])
			
			#print ("[LOAD] re-spawned: %s" % spawned_node.name)
