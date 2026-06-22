extends ThreatBase
## Ông kẹ — the bogeyman. Classic door rusher (teaches the door loop); he comes
## down either the left OR right corridor (randomize_side), so you must check both.
## Second, power-free counter: behave ("ngoan") — kill the doorway light and stay
## still and he loses patience instead of advancing.

var _behave_t := 0.0

func _configure() -> void:
	movement_model = MODEL_PATH
	spawn_location = MapGraph.GATE
	# Authored as a left route; randomize_side mirrors it to the right ~half the
	# time, so he rushes either door (you can't camp the left one).
	path = [MapGraph.GATE, MapGraph.LEFT_HALL, MapGraph.LEFT_DOOR]
	randomize_side = true
	move_interval = 5.0
	attack_time = 7.0
	counter_door = true
	via_drain_at_door = 4.0

func _process_attack(delta: float) -> void:
	# Closing the door always repels him (the panic / power-hungry counter).
	if _is_repelled_now():
		repel()
		return
	# "Ngoan": stand your ground — shine the doorway LIGHT on him and stay calm
	# (monitor down, don't whip the view around). Faced and unafraid, he loses
	# interest and leaves: a low-power counter that still demands you react.
	# Ignoring him in the dark is NOT safe — he keeps advancing and takes you.
	var facing_him_calmly: bool = _controller != null \
		and _controller.is_light_on(threatening_side) \
		and not _controller.is_monitor_open() \
		and _controller.get_pan_speed() < 0.3
	if facing_him_calmly:
		_behave_t += delta
		if _behave_t >= 2.5:
			repel()
		return
	_behave_t = 0.0
	_attack_accum += delta
	if _controller:
		_controller.add_via(-via_drain_at_door * delta)
	if _attack_accum >= attack_time:
		_kill()
