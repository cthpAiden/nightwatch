extends ThreatBase
## Oan hồn — the wronged schoolgirl (white áo dài). A camera-attention paradox:
## watching her too long AND ignoring her too long both raise her grievance (agro).
## The knife-edge is brief glances. Incense/offering pacifies her. At full grievance
## she singles out the guard. She drifts only among camera zones (never the doors).
## (The cross-night investigation that lays her to rest is hinted via Save flags.)

var agro := 0.0
var _viewing := false
var _taught := false   # teach the counter once, the first time the grievance starts hurting

func _configure() -> void:
	movement_model = MODEL_WANDER
	spawn_location = MapGraph.CLASSROOM
	wander_zone = [MapGraph.CLASSROOM, MapGraph.LIBRARY, MapGraph.INFIRMARY, MapGraph.COURTYARD]
	counter_door = false
	counter_offering = true
	move_interval = 6.0

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := _ai_at(night_progress)
	var mult := _meter_mult()
	if _viewing:
		agro += (3.2 + lvl * 0.4) * delta * mult      # watched too long
	else:
		agro += (1.6 + lvl * 0.18) * delta * mult      # ignored too long (was 0.9+lvl*0.12; raised so neglect still nets positive vs the -0.6 settle even while incensed — keeps the paradox two-sided)
	agro = clampf(agro - 0.6 * delta, 0.0, 100.0)  # slow settle if you neither stare nor neglect
	Events.grievance_changed.emit(agro / 100.0)
	# occasional drift for camera flavor
	_move_accum += delta
	if _move_accum >= move_interval:
		_move_accum = 0.0
		if _rng.randf() * 20.0 < lvl * 0.7:
			_wander()
	if agro > 80.0:
		# Teach the counter the first time the grievance actually starts bleeding you.
		if not _taught:
			_taught = true
			Events.notify.emit("COUNTER_OAN_HON", [])
		_bleed_via(-(agro - 80.0) * 0.06 * delta)
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
	agro = maxf(0.0, agro - 30.0)

func on_calm() -> void:
	agro = maxf(0.0, agro - 40.0)   # incense pacifies her zone short-term

func on_ward_save() -> void:
	agro = minf(agro, 25.0)         # a ward fully quiets her grievance for now

func current_texture() -> Texture2D:
	return tex_move if agro > 55.0 else tex_idle
