extends ThreatBase
## Ông kẹ — the bogeyman. Classic left-door rusher (teaches the door loop) with a
## second, power-free counter: behave ("ngoan") — kill the doorway light and stay
## still and he loses patience instead of advancing.

var _behave_t := 0.0

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
	# "Ngoan": behave at the door — monitor down, doorway light off, sit still — and
	# after a moment he loses interest and leaves (a power-free counter). Hiding in
	# the cameras does NOT count as behaving.
	var behaving: bool = _controller != null \
		and not _controller.is_monitor_open() \
		and not _controller.is_light_on(threatening_side) \
		and _controller.get_pan_speed() < 0.2
	if behaving:
		_behave_t += delta
		if _behave_t >= 3.0:
			repel()
		return
	_behave_t = 0.0
	_attack_accum += delta
	if _controller:
		_controller.add_via(-via_drain_at_door * delta)
	if _attack_accum >= attack_time:
		_kill()
