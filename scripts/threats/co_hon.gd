extends ThreatBase
## Cô hồn — wandering hungry souls. Not a positional rusher and never a kill-screen:
## a crowd-pressure meter rises through the night. A stocked/incensed offering tray
## (place_offering) keeps them passive; neglect lets the crowd swell, smothering
## your view and draining vía. You feed them, you never "kill" them.

var crowd := 0.0
var _taught := false   # teach the counter once, the first time the crowd starts hurting
var _warned := false   # one-shot telegraph when the crowd first crosses ~70

func _configure() -> void:
	spawn_location = MapGraph.GATE
	counter_offering = true
	via_drain_at_door = 0.0

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := _ai_at(night_progress)
	crowd = clampf(crowd + (0.35 + lvl * 0.13) * delta * _meter_mult(), 0.0, 100.0)
	Events.crowd_changed.emit(crowd / 100.0)
	current_location = MapGraph.GATE if crowd < 50.0 else MapGraph.CANTEEN
	if crowd > 60.0:
		# Teach the counter the first time the crowd actually starts bleeding you.
		if not _taught:
			_taught = true
			Events.notify.emit("COUNTER_CO_HON", [])
		# The bleed bites harder near full — neglect is a real via-zero threat, not a flat trickle.
		# Continuous ramp (was a two-branch coef with a ~1.5/s STEP at exactly crowd 85): same
		# endpoints (1.25/s at 85, ~2.75/s at 100) but it begins to bite gradually from ~80,
		# where vía regen starts losing — no invisible cliff. (balance #32)
		_bleed_via(-((crowd - 60.0) * 0.05 + maxf(0.0, crowd - 85.0) * 0.06) * delta)
	# Telegraph: when the crowd first crosses ~70, a one-shot murmur + a re-emit of the
	# counter prompt so the player can react before the bleed deepens. Mirrors ma_troi's
	# _warned one-shot (reuses COUNTER_CO_HON — no new string).
	if crowd >= 70.0 and not _warned:
		_warned = true
		Audio.play_sting("whisper", -10.0, 1.0)   # the murmuring crowd presses in (honors REDUCED/OFF tier)
		Events.notify.emit("COUNTER_CO_HON", [])
	elif crowd < 55.0:
		_warned = false

func on_offering(_location: String) -> void:
	crowd = maxf(0.0, crowd - 30.0)   # one tray thins the crowd, but won't fully scatter it

func on_calm() -> void:
	crowd = maxf(0.0, crowd - 30.0)   # incense settles the crowd a while

func on_ward_save() -> void:
	crowd = minf(crowd, 25.0)         # a ward scatters the pressing crowd

func on_via_state(_state: int) -> void:
	# When the guard is already shaken, a big crowd presses harder (handled via drain).
	pass

func current_texture() -> Texture2D:
	return tex_move if crowd > 50.0 else tex_idle
