extends ThreatBase
## Ông kẹ — the bogeyman. Classic left-door rusher (teaches the door loop) with a
## second, power-free counter: behave ("ngoan") — kill the doorway light and stay
## still and he loses patience instead of advancing.

func _configure() -> void:
	movement_model = MODEL_PATH
	spawn_location = MapGraph.GATE
	path = [MapGraph.GATE, MapGraph.LEFT_HALL, MapGraph.LEFT_DOOR]
	move_interval = 5.0
	attack_time = 7.0
	counter_door = true
	via_drain_at_door = 4.0

func _process_attack(delta: float) -> void:
	if _is_repelled_now():
		repel()
		return
	# "Ngoan" stall: lights off on his side + not panning = he waits (no power cost).
	var behaving: bool = _controller != null \
		and not _controller.is_light_on(threatening_side) \
		and _controller.get_pan_speed() < 0.2
	if not behaving:
		_attack_accum += delta
		if _controller:
			_controller.add_via(-via_drain_at_door * delta)
	if _attack_accum >= attack_time:
		_kill()
