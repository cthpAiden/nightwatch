class_name ThreatBase
extends Node
## Base class for every folklore threat. A threat is pure logic + its 2D textures;
## the GuardRoom (3D) and the camera Monitor (2D) read its state to draw it.
##
## The ThreatDirector ticks process_ai() each frame and gives "movement
## opportunities" on this threat's cadence; whether it acts is a FNAF-style roll
## against ai_level (0..20). Subclasses set parameters in _configure() and may
## override the on_* hooks for unique behaviour.

# Movement models -----------------------------------------------------------
const MODEL_PATH := 0       # fixed ordered route to a door (Ma da, Ông kẹ)
const MODEL_WANDER := 1     # random walk on adjacency (Cô hồn)
const MODEL_FLYER := 2      # path, but ignores doors; countered by light/offering (Ma lai)
const MODEL_STALKER := 3    # advances only while NOT watched on its camera
const MODEL_CREEPER := 4    # advances only while the player is panning/moving

# --- identity / configuration (set by subclass _configure or director) ------
var id: String = "threat"
var name_key: String = ""
var fear_factor: int = 3
var accent_color: Color = Color(0.8, 0.2, 0.2)
var movement_model: int = MODEL_PATH
var spawn_location: String = MapGraph.CLASSROOM
var path: Array = []                       # for PATH / FLYER / STALKER / CREEPER
var wander_zone: Array = []                 # if set, WANDER stays within these locations
var move_interval: float = 5.0             # seconds between movement opportunities
var attack_time: float = 6.0               # seconds at a door before it kills
var via_drain_at_door: float = 6.0         # vía/sec drained while looming at a door

# How it is countered
var counter_door: bool = true
var counter_light: bool = false
var counter_offering: bool = false
var ignores_doors: bool = false

# Textures per state (loaded in _configure)
var tex_idle: Texture2D
var tex_move: Texture2D
var tex_attack: Texture2D

# --- runtime ---------------------------------------------------------------
var ai_level: float = 3.0
var ai_level_end: float = 5.0
var current_location: String = ""
var phase: int = GameEnums.ThreatPhase.DORMANT
var threatening_side: int = -1
var path_index: int = 0

var _controller                            # NightController (duck-typed)
var _rng := RandomNumberGenerator.new()
var _move_accum: float = 0.0
var _attack_accum: float = 0.0
var _speed_mult: float = 1.0
var _active: bool = false
var _player_viewing_me: bool = false
var _player_panning: bool = false
var _cooldown: float = 0.0

func setup(level: float, level_end: float, controller) -> void:
	_controller = controller
	_rng.randomize()
	_configure()
	ai_level = level
	ai_level_end = maxf(level_end, level)
	current_location = spawn_location
	path_index = 0
	phase = GameEnums.ThreatPhase.ACTIVE
	_active = true
	Events.threat_relocated.emit(id, current_location)

## Subclass hook: set model, spawn, path, intervals, counters, textures.
func _configure() -> void:
	pass

# --- per-frame AI (called by director) -------------------------------------
func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := lerpf(ai_level, ai_level_end, clampf(night_progress, 0.0, 1.0))

	if phase == GameEnums.ThreatPhase.AT_DOOR or phase == GameEnums.ThreatPhase.ATTACKING:
		_process_attack(delta)
		return

	if _cooldown > 0.0:
		_cooldown -= delta
		return

	_move_accum += delta * _speed_mult
	if _move_accum >= move_interval:
		_move_accum = 0.0
		if _rng.randf() * 20.0 < lvl:
			_behaviour_move()

func _behaviour_move() -> void:
	match movement_model:
		MODEL_WANDER:
			_wander()
		MODEL_STALKER:
			if not _player_viewing_me:
				_advance_path()
		MODEL_CREEPER:
			if _player_panning:
				_advance_path()
		_:
			_advance_path()

func _advance_path() -> void:
	if path.is_empty():
		_wander()
		return
	path_index = mini(path_index + 1, path.size() - 1)
	_enter_location(path[path_index])

func _wander() -> void:
	var opts: Array = MapGraph.neighbors(current_location).duplicate()
	if not wander_zone.is_empty():
		opts = opts.filter(func(l): return wander_zone.has(l))
		if opts.is_empty():
			opts = wander_zone.duplicate()
	if opts.is_empty():
		return
	var loc: String = opts[_rng.randi() % opts.size()]
	_enter_location(loc)

func _enter_location(loc: String) -> void:
	var side := MapGraph.door_side(loc)
	if side != -1:
		_arrive_at_door(side)
	elif loc == MapGraph.OFFICE:
		current_location = loc
		_kill()
	else:
		current_location = loc
		phase = GameEnums.ThreatPhase.APPROACHING if _adjacent_to_door() else GameEnums.ThreatPhase.ACTIVE
		Events.threat_relocated.emit(id, loc)

func _adjacent_to_door() -> bool:
	for nb in MapGraph.neighbors(current_location):
		if MapGraph.door_side(nb) != -1:
			return true
	return false

func _arrive_at_door(side: int) -> void:
	threatening_side = side
	current_location = MapGraph.side_door(side)
	phase = GameEnums.ThreatPhase.AT_DOOR
	_attack_accum = 0.0
	Events.threat_relocated.emit(id, current_location)
	Events.threat_at_door.emit(id, side)
	# Diegetic warning only: a knock + a vague unease. It does NOT say which door
	# or what it is — you have to check the doorway lights to find out, then react
	# (light it up and hold still, or shut the door). That's the tension.
	Audio.play_sfx("knock", -4.0)
	Events.notify.emit("THREAT_NEARBY", [])
	# If the relevant counter is already engaged, leave immediately.
	if _is_repelled_now():
		repel()

func _process_attack(delta: float) -> void:
	if _is_repelled_now():
		repel()
		return
	if _controller:
		_controller.add_via(-via_drain_at_door * delta)
	_attack_accum += delta
	if _attack_accum >= attack_time:
		_kill()

func _is_repelled_now() -> bool:
	if _controller == null or threatening_side == -1:
		return false
	if counter_door and not ignores_doors and _controller.is_door_closed(threatening_side):
		return true
	if counter_light and _controller.is_light_on(threatening_side):
		return true
	return false

func _kill() -> void:
	if not _active:
		return
	phase = GameEnums.ThreatPhase.ATTACKING
	_active = false
	Save.see_threat(id)
	# NightController orchestrates the jumpscare visual + the game over.
	Events.jumpscare_started.emit(id)

func repel() -> void:
	var side := threatening_side
	threatening_side = -1
	_attack_accum = 0.0
	phase = GameEnums.ThreatPhase.ACTIVE
	Events.threat_left_door.emit(id, side)
	Events.threat_repelled.emit(id)
	_reset_position()
	_cooldown = move_interval * _rng.randf_range(0.8, 1.6)

func reset_to_spawn() -> void:
	threatening_side = -1
	_attack_accum = 0.0
	phase = GameEnums.ThreatPhase.ACTIVE
	_active = true
	_reset_position()
	_cooldown = move_interval

func _reset_position() -> void:
	path_index = 0
	current_location = spawn_location
	Events.threat_relocated.emit(id, current_location)

# --- director / controller hooks -------------------------------------------
func set_speed_mult(m: float) -> void:
	_speed_mult = maxf(0.05, m)

func on_door(side: int, closed: bool) -> void:
	if closed and phase == GameEnums.ThreatPhase.AT_DOOR and side == threatening_side:
		if counter_door and not ignores_doors:
			repel()

func on_light(side: int, on: bool) -> void:
	if on and phase == GameEnums.ThreatPhase.AT_DOOR and side == threatening_side and counter_light:
		repel()

func on_view(is_viewing_my_cam: bool) -> void:
	_player_viewing_me = is_viewing_my_cam

func on_player_pan(is_panning: bool) -> void:
	_player_panning = is_panning

func on_offering(_location: String) -> void:
	if counter_offering and phase != GameEnums.ThreatPhase.ATTACKING:
		reset_to_spawn()
		_cooldown = move_interval * 2.0

func on_via_state(_state: int) -> void:
	pass

## Incense calm (item calm_zone). Default no-op; meter threats lower their meter.
func on_calm() -> void:
	pass

# --- queries for views / items ---------------------------------------------
func distance_to_office() -> int:
	return MapGraph.distance(current_location, MapGraph.OFFICE)

func is_at_door() -> bool:
	return phase == GameEnums.ThreatPhase.AT_DOOR

func current_texture() -> Texture2D:
	if phase == GameEnums.ThreatPhase.ATTACKING and tex_attack:
		return tex_attack
	if (phase == GameEnums.ThreatPhase.AT_DOOR or phase == GameEnums.ThreatPhase.APPROACHING) and tex_move:
		return tex_move
	return tex_idle if tex_idle else tex_move
