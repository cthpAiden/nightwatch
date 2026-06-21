extends ThreatBase
## Oan hồn — the wronged schoolgirl (white áo dài). A camera-attention paradox:
## watching her too long AND ignoring her too long both raise her grievance (agro).
## The knife-edge is brief glances. Incense/offering pacifies her. At full grievance
## she singles out the guard. She drifts only among camera zones (never the doors).
## (The cross-night investigation that lays her to rest is hinted via Save flags.)

var agro := 0.0
var _viewing := false

func _configure() -> void:
	movement_model = MODEL_WANDER
	spawn_location = MapGraph.CLASSROOM
	wander_zone = [MapGraph.CLASSROOM, MapGraph.LEFT_HALL, MapGraph.RIGHT_HALL, MapGraph.COURTYARD]
	counter_door = false
	counter_offering = true
	move_interval = 6.0

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := lerpf(ai_level, ai_level_end, clampf(night_progress, 0.0, 1.0))
	if _viewing:
		agro += (3.2 + lvl * 0.4) * delta      # watched too long
	else:
		agro += (0.9 + lvl * 0.12) * delta      # ignored too long (slower)
	agro = clampf(agro - 0.6 * delta, 0.0, 100.0)  # slow settle if you neither stare nor neglect
	# occasional drift for camera flavor
	_move_accum += delta
	if _move_accum >= move_interval:
		_move_accum = 0.0
		if _rng.randf() * 20.0 < lvl * 0.7:
			_wander()
	if agro > 80.0 and _controller:
		_controller.add_via(-(agro - 80.0) * 0.06 * delta)
	if agro >= 100.0:
		_attack()

func _attack() -> void:
	if not _active:
		return
	phase = GameEnums.ThreatPhase.ATTACKING
	_active = false
	Save.see_threat(id)
	Events.jumpscare_started.emit(id)

func on_view(is_viewing_my_cam: bool) -> void:
	_viewing = is_viewing_my_cam

func on_offering(_location: String) -> void:
	agro = maxf(0.0, agro - 45.0)

func on_calm() -> void:
	agro = maxf(0.0, agro - 40.0)   # incense pacifies her zone short-term

func current_texture() -> Texture2D:
	return tex_move if agro > 55.0 else tex_idle
