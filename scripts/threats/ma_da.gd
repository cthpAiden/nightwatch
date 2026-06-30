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
var _at_door := false         # the drowned figure has risen to the doorway (flood critical)
var _drain_cd := 0.0          # the grate is shut & answering nothing until this hits 0
var _clog := 0.0              # 0..1 how backed-up the drain is; each close adds, time clears

const MANIFEST_AT := 85.0     # flood at which Ma da rises to the door as its 3D figure
const MANIFEST_OFF := 70.0    # flood it recedes below (hysteresis so it can't flicker)
const FLOOD_BASE := 0.55      # base flood rise/sec
const FLOOD_ACCEL := 0.65     # extra rise/sec that ramps in as the flood climbs (runaway pressure)
const DRAIN_RELIEF := 30.0    # flood a FRESH drain-close removes (scaled down by _clog)
const DRAIN_CD := 4.0         # seconds the grate stays shut before it answers a close again
const CLOG_PER_USE := 0.34    # each close backs the drain up; relief = DRAIN_RELIEF * (1 - clog)
const CLOG_EASE := 0.07       # clog cleared per second while you leave the drain alone
const DOOR_VIA_DRAIN := 7.5   # vía/sec dragged out of you while the figure looms at the door

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
	# Accelerating rise: the higher the water, the faster it climbs — a flood left alone
	# gets away from you instead of creeping, so Ma da is a live clock, not a slow drip.
	var rise := FLOOD_BASE + lvl * 0.11 + FLOOD_ACCEL * (flood / 100.0)
	flood = minf(100.0, flood + rise * delta * _meter_mult())
	Events.water_level.emit(flood / 100.0)

	# The drain stays shut for a beat after each close, and its backed-up "clog" clears
	# slowly while untouched — so you can't just pin the flood at zero by mashing it.
	if _drain_cd > 0.0:
		_drain_cd = maxf(0.0, _drain_cd - delta)
		if _drain_cd == 0.0:
			Events.water_drain_ready.emit(true)
	_clog = maxf(0.0, _clog - CLOG_EASE * delta)

	if _lure_active:
		_lure_t -= delta
		if _lure_t <= 0.0:
			_end_lure()
	else:
		_lure_cd -= delta
		if _lure_cd <= 0.0:
			_start_lure()

	# alternate the camera it appears under, for flavor (but once it has risen to the
	# doorway its location IS that door, so don't yank it back onto a camera)
	if not _at_door:
		current_location = MapGraph.RESTROOM if flood < 55.0 else MapGraph.COURTYARD

	# Rise to / recede from the doorway as the flood crosses the critical band. The drowned
	# figure looms at the right door (its restroom/courtyard source wing); the existing
	# door-figure pipeline then draws ma_da.glb. Doors don't repel it — only lowering the
	# flood (drain/offering/incense) sends it back under.
	if not _at_door and flood >= MANIFEST_AT:
		_rise_to_door()
	elif _at_door and flood < MANIFEST_OFF:
		_recede_from_door()

	# Vía pressure. While the drowned figure looms at the door it actively drags you under —
	# a hard bleed that freezes regen — so letting it stand there is dangerous, not a free
	# wait for the meter. Below that, only rising water seeps at you.
	if _at_door:
		if _controller:
			_controller.add_via(-DOOR_VIA_DRAIN * delta)
	elif flood > 70.0:
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

func _rise_to_door() -> void:
	_at_door = true
	threatening_side = GameEnums.Side.RIGHT
	current_location = MapGraph.side_door(threatening_side)
	phase = GameEnums.ThreatPhase.AT_DOOR
	Events.threat_relocated.emit(id, current_location)
	Events.threat_at_door.emit(id, threatening_side)   # door-figure render + arrival scare beat

func _recede_from_door() -> void:
	var side := threatening_side
	_at_door = false
	threatening_side = -1
	phase = GameEnums.ThreatPhase.ACTIVE
	Events.threat_left_door.emit(id, side)   # clears the doorway figure

func _on_action(action: String) -> void:
	if action != "close_drain":
		return
	if _drain_cd > 0.0:
		Audio.play_sfx("ui_back", -12.0)   # grate's already shut and backed up — nothing yet
		return
	# Fresh closes give real relief; lean on it and the clog chokes each one down toward
	# nothing, forcing you onto the heavier counters (offering / incense) instead.
	flood = maxf(0.0, flood - DRAIN_RELIEF * (1.0 - _clog))
	_clog = minf(1.0, _clog + CLOG_PER_USE)
	_drain_cd = DRAIN_CD
	Events.water_drain_ready.emit(false)
	Audio.play_sfx("incense_whoosh", -8.0)

func on_offering(_location: String) -> void:
	flood = maxf(0.0, flood - 22.0)   # one offering eases the flood, but won't fully drain it

func on_calm() -> void:
	flood = maxf(0.0, flood - 30.0)   # incense at the pond shrine

func on_ward_save() -> void:
	flood = minf(flood, 25.0)         # a ward fully breaks the flood's hold

func current_texture() -> Texture2D:
	return tex_move if flood > 50.0 else tex_idle
