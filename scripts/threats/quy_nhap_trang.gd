extends ThreatBase
## Quỷ nhập tràng — risen corpse, triggered by the black cat Mun leaping the body.
## You don't fight the corpse, you fight the CAUSE: keep Mun off the draped form.
## Mun pads toward it on a timer (visible on cameras); divert her by closing the
## RIGHT door or placing a thorny-branch barrier. If she crosses, the corpse sits
## up and rushes the RIGHT door — the same wing you watched Mun cross — for the rest
## of the night (close the right door). The telegraph and the rush are one wing.

var mun_progress := 0.0
var triggered := false
var _mun_tex: Texture2D
var _rest := 0.0   # time the risen corpse has been frozen (stillness only SLOWS it)

func _configure() -> void:
	movement_model = MODEL_PATH
	spawn_location = MapGraph.GATE
	# Authored down the right wing, the same wing Mun is seen crossing. randomize_side
	# only mirrors the pre-trigger spawn flavor; once Mun crosses, _trigger pins the
	# rush to this canonical right-wing route so the telegraph matches the kill.
	path = [MapGraph.GATE, MapGraph.GYM, MapGraph.RESTROOM, MapGraph.INFIRMARY, MapGraph.RIGHT_HALL, MapGraph.RIGHT_DOOR]
	randomize_side = true
	move_interval = 3.0
	attack_time = 6.0
	counter_door = true
	via_drain_at_door = 5.0
	approach_sfx = "approach_drag"   # a slow, wet drag down the corridor
	if ResourceLoader.exists("res://assets/art/threats/mun_walk.svg"):
		_mun_tex = load("res://assets/art/threats/mun_walk.svg")

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := _ai_at(night_progress)
	if not triggered:
		var diverted: bool = _controller != null and (_controller.is_barrier_active() \
			or _controller.is_door_closed(GameEnums.Side.RIGHT))
		if diverted:
			mun_progress = maxf(0.0, mun_progress - 11.0 * delta)
		else:
			mun_progress = minf(100.0, mun_progress + (2.6 + lvl * 0.5) * delta)
		current_location = MapGraph.RESTROOM if mun_progress < 50.0 else MapGraph.RIGHT_HALL
		Events.cat_moved.emit(current_location)
		if mun_progress >= 100.0:
			_trigger()
	else:
		super.process_ai(delta, night_progress)
		# A CREEPER only lurches while you pan, so a perfectly still player could
		# freeze the corpse at spawn forever. Guarantee a slow baseline creep so
		# stillness only SLOWS it — eventually it reaches the right door and you must
		# actually shut it.
		if not _player_panning and phase != GameEnums.ThreatPhase.AT_DOOR \
				and phase != GameEnums.ThreatPhase.ATTACKING:
			_rest += delta
			if _rest >= 22.0:
				_rest = 0.0
				_advance_path()
		else:
			_rest = 0.0

func _trigger() -> void:
	triggered = true
	# Now a conditional stalker: it only lurches forward while you move/pan; hold
	# still to keep it back. The RIGHT door remains a backup counter.
	movement_model = MODEL_CREEPER
	# DETERMINISTIC side: the corpse rushes the SAME wing Mun was seen crossing (the
	# authored right wing), so the on-camera telegraph pays off. Pin the path to the
	# canonical route and stop _apply_side from re-mirroring it on any later reset.
	randomize_side = false
	path = _base_path.duplicate()
	threatening_side = GameEnums.Side.RIGHT
	Events.cat_triggered.emit()
	Events.notify.emit("CAT_WARN", [])
	Audio.play_sting("sting_metal", -3.0, 1.0)   # the corpse sits up
	phase = GameEnums.ThreatPhase.ACTIVE
	current_location = spawn_location
	path_index = 0
	_move_accum = 0.0
	Events.threat_relocated.emit(id, current_location)

## A setback (salt line / repel item) genuinely pushes the cat back: before the
## corpse rises it knocks Mun's approach meter down, not just her on-camera position.
func reset_to_spawn() -> void:
	if not triggered:
		mun_progress = maxf(0.0, mun_progress - 35.0)
	_rest = 0.0
	super.reset_to_spawn()

func current_texture() -> Texture2D:
	if not triggered:
		return _mun_tex if _mun_tex else tex_idle
	return super.current_texture()
