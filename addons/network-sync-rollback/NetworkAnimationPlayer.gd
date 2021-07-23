extends AnimationPlayer

func _ready() -> void:
	method_call_mode = AnimationPlayer.ANIMATION_METHOD_CALL_IMMEDIATE
	playback_process_mode = AnimationPlayer.ANIMATION_PROCESS_MANUAL
	add_to_group('network_sync')

func _network_process(delta: float, input: Dictionary) -> void:
	if is_playing():
		advance(delta)

func _save_state() -> Dictionary:
	if is_playing():
		return {
			is_playing = true,
			current_animation = current_animation,
			current_position = current_animation_position,
		}
	else:
		return {
			is_playing = false,
			current_animation = '',
			current_position = 0.0,
		}

func _load_state(state: Dictionary) -> void:
	stop()
	if state['is_playing']:
		play(state['current_animation'])
		seek(state['current_position'], true)
