extends ThreatBase
## Ông kẹ — the bogeyman. Classic door rusher (teaches the door loop); he comes
## down either the left OR right corridor (randomize_side), so you must check both.
## Second, power-free counter: behave ("ngoan") — kill the doorway light and stay
## still and he loses patience instead of advancing.

var _behave_t := 0.0

func _configure() -> void:
	movement_model = MODEL_PATH
	spawn_location = MapGraph.GATE
	# Authored as the full left-wing route; randomize_side mirrors it to the right
	# wing ~half the time, so he rushes either door and you must watch both wings.
	# He now strolls the whole wing node-by-node (gate→canteen→classroom→library→
	# hall→door) instead of teleporting two tiles to the door.
	path = [MapGraph.GATE, MapGraph.CANTEEN, MapGraph.CLASSROOM, MapGraph.LIBRARY, MapGraph.LEFT_HALL, MapGraph.LEFT_DOOR]
	randomize_side = true
	move_interval = 2.2   # shorter step cadence so the longer route still arrives on time
	attack_time = 7.0
	counter_door = true
	via_drain_at_door = 4.0
	approach_sfx = "approach_heavy"   # three slow, descending knocks

func _process_attack(delta: float) -> void:
	# Closing the door is his panic counter — but he now lingers against it for
	# linger_time before giving up (shared logic), so you must HOLD the door shut.
	if _handle_door_block(delta):
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
	# While Ma trơi's panic-hex jams the controls (doors flung open), ông kẹ does
	# nothing — no grab, no vía drain — so the hex is never a death by itself.
	if _controller and _controller.has_method("is_hexed") and _controller.is_hexed():
		return
	_attack_accum += delta
	if _controller:
		_controller.add_via(-via_drain_at_door * delta)
	if _attack_accum >= attack_time:
		_kill()
