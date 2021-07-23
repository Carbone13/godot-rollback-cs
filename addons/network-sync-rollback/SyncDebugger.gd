extends Node

func _ready() -> void:
	SyncManager.connect("RollbackFlagged", self, "_on_SyncManager_rollback_flagged")
	SyncManager.connect("SkipTickFlagged", self, "_on_SyncManager_skip_ticks_flagged")
	#SyncManager.connect("RemoteStateMismatch", self, "_on_SyncManager_remote_state_mismatch")
	SyncManager.connect("PeerPingedBack", self, "_on_SyncManager_peer_pinged_back")
	SyncManager.connect("StateLoaded", self, "_on_SyncManager_state_loaded")
	SyncManager.connect("TickFinished", self, "_on_SyncManager_tick_finished")

func _on_SyncManager_skip_ticks_flagged(count: int) -> void:
	print ("-----")
	print ("Skipping %s local tick(s) to adjust for peer advantage" % count)

func _on_SyncManager_rollback_flagged(tick: int, peer_id: int, local_input: Dictionary, remote_input: Dictionary) -> void:
	print ("-----")
	print ("Correcting prediction on tick %s for peer %s (rollback %s tick(s))" % [tick, peer_id, SyncManager.get("rollbackTicks")])
	print ("Received input: %s" % remote_input)
	print ("Predicted input: %s" % local_input)

func _on_SyncManager_remote_state_mismatch(tick: int, peer_id: int, local_state: Dictionary, remote_state: Dictionary) -> void:
	print ("-----")
	print ("On tick %s, remote state from %s doesn't match local state" % [tick, peer_id])
	print ("Remote data: %s" % remote_state)
	print ("Local data: %s" % local_state)
	
func _on_SyncManager_peer_pinged_back(peer) -> void:
	pass
	print ("-----")
	print ("Peer %s: RTT %s ms | local lag %s | remote lag %s | advantage %s" % [peer.get("PeerID"), peer.get("RTT"), peer.get("LocalLag"), peer.get("RemoteLag"), peer.get("CalculatedAdvantage")])

func _on_SyncManager_state_loaded(rollback_ticks: int) -> void:
	#print ("-----")
	#print ("Rolled back %s ticks in order to re-run from tick %s" % [rollback_ticks, SyncManager.get("currentTick")])
	pass

func _on_SyncManager_tick_finished(is_rollback: bool) -> void:
	#if is_rollback:
	#	print ("Finished replay of tick %s" % SyncManager.get("currentTick"))
	pass
