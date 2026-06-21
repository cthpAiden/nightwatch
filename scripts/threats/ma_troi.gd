extends ThreatBase
## Ma trơi — will-o'-the-wisp. Governed by HOW you move, not where you are. Panning
## the view fast ("running") makes it lock on and drain vía + power; staying calm
## lets it drift away. Not a kill-screen on its own (lighter, "charming-creepy") —
## it bleeds you toward a via-zero loss if you panic. Teaches "don't run."

var lock := 0.0

func _configure() -> void:
	movement_model = MODEL_WANDER
	spawn_location = MapGraph.COURTYARD
	wander_zone = [MapGraph.COURTYARD, MapGraph.RIGHT_HALL, MapGraph.CLASSROOM]
	counter_door = false
	move_interval = 5.0

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := lerpf(ai_level, ai_level_end, clampf(night_progress, 0.0, 1.0))
	# "Running" = panic: fast panning OR rapid camera-flipping (works even on the
	# monitor, where raw pan speed is forced to ~0).
	var agit: float = _controller.get_agitation() if _controller else 0.0
	if agit > 0.4:
		lock = minf(100.0, lock + (7.0 + lvl) * delta)
	else:
		lock = maxf(0.0, lock - 8.0 * delta)
	if lock > 40.0 and _controller:
		_controller.add_via(-(lock - 40.0) * 0.05 * delta)
	_move_accum += delta
	if _move_accum >= move_interval:
		_move_accum = 0.0
		if _rng.randf() * 20.0 < lvl:
			_wander()
	if lock >= 100.0:
		_surge()

func _surge() -> void:
	# locks on: a hard vía + light hit, then resets — never an instant kill
	if _controller:
		_controller.add_startle(-26.0)
		_controller.add_power(-8.0)
	Audio.play_sfx("stinger", -4.0)
	Events.notify.emit("MATROI_RULE", [])
	lock = 45.0

func current_texture() -> Texture2D:
	return tex_move if lock > 45.0 else tex_idle
