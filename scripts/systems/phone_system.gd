extends Node
## The desk phone — the previous guard (bác Tư) calling in.
##
## REAL calls ring at a steady cadence and carry his lines (tutorial + slow-burn
## story) plus a small boon when you pick up (a steadier nerve + a brief reveal of
## who's where). A MISSED real call costs you a little vía (you wonder what he knew).
##
## Ma da imitates the ring as a LURE: a fake call. Answering a fake ring is the wrong
## reaction — it spikes the flood (Events.intercom_answered, which Ma da listens for).
## The tell is the warped ring tone + a red glow on the answer button. The real
## grandmother... pardon, the real bác Tư, is never the monster.

var _c
var _ringing := false
var _fake := false
var _ring_t := 0.0           # remaining seconds before an unanswered ring gives up
var _next_real := 0.0
var _real_idx := 0
var _lines: Array = []
var _rng := RandomNumberGenerator.new()

func setup(controller) -> void:
	_c = controller
	_rng.randomize()
	Events.water_lure.connect(_on_water_lure)

func begin() -> void:
	_lines = Lore.phone_lines(Game.current_night)
	_real_idx = 0
	_next_real = _rng.randf_range(13.0, 22.0)   # an early first call eases you in (wider chances)

func is_ringing() -> bool:
	return _ringing

func is_fake() -> bool:
	return _fake

func _process(delta: float) -> void:
	if _c == null:
		return
	# Use the controller's accessor (guarded) instead of touching _running directly.
	if _c.has_method("is_running") and not _c.is_running():
		return
	if _ringing:
		_ring_t -= delta
		if _ring_t <= 0.0:
			_missed()
	elif not _fake:
		_next_real -= delta
		if _next_real <= 0.0 and _real_idx < _lines.size():
			_start_real()

func _start_real() -> void:
	_ringing = true
	_fake = false
	_ring_t = 12.0
	Audio.play_sfx("phone_ring", -5.0)
	Events.phone_ring.emit(true, false)
	Events.notify.emit("PHONE_RING", [])

func _on_water_lure(active: bool) -> void:
	if active and not _ringing:
		_ringing = true
		_fake = true
		_ring_t = 5.0
		Audio.play_sfx("phone_ring_warp", -6.0)
		Events.phone_ring.emit(true, true)
	elif not active and _ringing and _fake:
		_stop()

func answer() -> void:
	if not _ringing:
		return
	if _fake:
		# took the bait — Ma da surges (it listens for intercom_answered)
		Events.intercom_answered.emit()
		Audio.play_sfx("sting_rise", -6.0, 1.0, Audio.VERB_BUS)   # you took the bait
		Events.notify.emit("PHONE_FAKE", [])
		_stop()
	else:
		if _real_idx < _lines.size():
			Events.notify.emit(_lines[_real_idx], [])
			_real_idx += 1
		_c.add_via(8.0)
		_c.start_reveal(5.0)        # bác Tư tells you where they're lurking
		Audio.play_sfx("offering_bell", -12.0)
		# From night 2 on, bác Tư's calls carry the girl's story — the first one you
		# pick up gives you her name (investigation clue 1 of 3).
		if Game.current_night >= 2:
			_c.find_clue("clue_name", "CLUE_GOT_NAME")
		_stop()
		_next_real = _rng.randf_range(40.0, 64.0)   # tighter re-arm: more genuine calls per night

func _missed() -> void:
	if _fake:
		_stop()
		return
	_c.add_via(-4.0)
	Events.notify.emit("PHONE_MISSED", [])
	_stop()
	_next_real = _rng.randf_range(37.0, 56.0)   # tighter re-arm after a miss: another chance sooner

func _stop() -> void:
	_ringing = false
	_fake = false
	Events.phone_ring.emit(false, false)
