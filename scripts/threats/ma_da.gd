extends ThreatBase
## Ma da — water ghost. Does NOT walk corridors and never touches the phone. A flood
## level rises through the night; a drowned water-cry periodically swells as a telegraph.
## Closing the drain (office action) lowers the flood; incense/offering calms it. At full
## flood it takes you. Counter = water management. Doors, cameras and the phone do nothing.

var flood := 0.0
var _lure_active := false
var _lure_t := 0.0
var _lure_cd := 6.0
var _warned := false          # one-shot rising-water telegraph when flood first crosses ~85

func _configure() -> void:
	spawn_location = MapGraph.RESTROOM
	counter_door = false
	counter_light = false
	via_drain_at_door = 0.0
	Events.office_action.connect(_on_action)

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := _ai_at(night_progress)
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
	# Telegraph: when the flood first crosses ~85, a one-shot rising-water audio cue so
	# the kill is signalled before it lands. Mirrors ma_troi's _warned one-shot.
	if flood >= 85.0 and not _warned:
		_warned = true
		Audio.play_sting("water_call", -4.0, 0.78)   # the water is rising (honors REDUCED/OFF tier)
	elif flood < 80.0:   # re-arm the rising-water telegraph (one offering's -22 from ~99 lands
		_warned = false  # ~77, so the cue re-fires before each subsequent near-kill — #33
	if flood >= 100.0:
		_kill()

func _start_lure() -> void:
	_lure_active = true
	_lure_t = 5.0
	Events.water_lure.emit(true)
	# Duck the night to near-silence for a beat, then a drowned, almost-worded cry rises
	# from the water — a telegraph that the flood is climbing. Lower the more it has flooded.
	Audio.duck(14.0, 0.15, 0.5, 0.8)
	var p: float = lerpf(1.05, 0.82, clampf(flood / 100.0, 0.0, 1.0))
	Audio.play_sting("water_call", -5.0, p)   # the drowned water cry (honors REDUCED/OFF tier)

func _end_lure() -> void:
	_lure_active = false
	_lure_cd = _rng.randf_range(8.0, 14.0)
	Events.water_lure.emit(false)

func _on_action(action: String) -> void:
	if action == "close_drain":
		flood = maxf(0.0, flood - 35.0)
		Audio.play_sfx("incense_whoosh", -8.0)

func on_offering(_location: String) -> void:
	flood = maxf(0.0, flood - 22.0)   # one offering eases the flood, but won't fully drain it

func on_calm() -> void:
	flood = maxf(0.0, flood - 30.0)   # incense at the pond shrine

func on_ward_save() -> void:
	flood = minf(flood, 25.0)         # a ward fully breaks the flood's hold

func current_texture() -> Texture2D:
	return tex_move if flood > 50.0 else tex_idle
