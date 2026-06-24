extends ThreatBase
## Ma da — water ghost. Does NOT walk corridors. A flood level rises through the
## night; periodically a false "help me" cry plays. ANSWERING the intercom (the
## wrong reaction) spikes the flood; closing the drain (office action) lowers it;
## incense/offering calms it. At full flood it takes you. Counter = inaction done
## right + water management. Doors and cameras do nothing.

var flood := 0.0
var _lure_active := false
var _lure_t := 0.0
var _lure_cd := 6.0

func _configure() -> void:
	spawn_location = MapGraph.RESTROOM
	counter_door = false
	counter_light = false
	via_drain_at_door = 0.0
	Events.intercom_answered.connect(_on_answer)
	Events.office_action.connect(_on_action)

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := lerpf(ai_level, ai_level_end, clampf(night_progress, 0.0, 1.0))
	flood = minf(100.0, flood + (0.35 + lvl * 0.11) * delta * _meter_mult())
	Events.water_level.emit(flood / 100.0)

	if _lure_active:
		_lure_t -= delta
		if _lure_t <= 0.0:
			_end_lure()
	else:
		_lure_cd -= delta
		if _lure_cd <= 0.0:
			_start_lure()

	# alternate the camera it appears under, for flavor
	current_location = MapGraph.RESTROOM if flood < 55.0 else MapGraph.COURTYARD

	if flood > 70.0:
		_bleed_via(-(flood - 70.0) * 0.05 * delta)
	if flood >= 100.0:
		_kill()

func _start_lure() -> void:
	_lure_active = true
	_lure_t = 5.0
	Events.water_lure.emit(true)
	# Duck the night to near-silence for a beat, then a drowned, almost-worded cry rises
	# from the water — the lure you must NOT answer. Harder/lower the more it has flooded.
	Audio.duck(14.0, 0.15, 0.5, 0.8)
	var p: float = lerpf(1.05, 0.82, clampf(flood / 100.0, 0.0, 1.0))
	Audio.play_sfx("water_call", -5.0, p, Audio.VERB_BUS)
	Events.notify.emit("MADA_LURE", [])

func _end_lure() -> void:
	_lure_active = false
	_lure_cd = _rng.randf_range(8.0, 14.0)
	Events.water_lure.emit(false)

func _on_answer() -> void:
	if _lure_active:
		flood = minf(100.0, flood + 28.0)
		Audio.play_sfx("sting_rise", -8.0, 1.0, Audio.VERB_BUS)   # you answered the water
		_end_lure()

func _on_action(action: String) -> void:
	if action == "close_drain":
		flood = maxf(0.0, flood - 35.0)
		Audio.play_sfx("incense_whoosh", -8.0)

func on_offering(_location: String) -> void:
	flood = maxf(0.0, flood - 32.0)   # one offering reliably drops it below the drain threshold

func on_calm() -> void:
	flood = maxf(0.0, flood - 30.0)   # incense at the pond shrine

func on_ward_save() -> void:
	flood = minf(flood, 25.0)         # a ward fully breaks the flood's hold

func current_texture() -> Texture2D:
	return tex_move if flood > 50.0 else tex_idle
