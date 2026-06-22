extends ThreatBase
## Cô hồn — wandering hungry souls. Not a positional rusher and never a kill-screen:
## a crowd-pressure meter rises through the night. A stocked/incensed offering tray
## (place_offering) keeps them passive; neglect lets the crowd swell, smothering
## your view and draining vía. You feed them, you never "kill" them.

var crowd := 0.0

func _configure() -> void:
	spawn_location = MapGraph.GATE
	counter_offering = true
	via_drain_at_door = 0.0

func process_ai(delta: float, night_progress: float) -> void:
	if not _active:
		return
	var lvl := lerpf(ai_level, ai_level_end, clampf(night_progress, 0.0, 1.0))
	crowd = clampf(crowd + (0.35 + lvl * 0.13) * delta * _meter_mult(), 0.0, 100.0)
	Events.crowd_changed.emit(crowd / 100.0)
	current_location = MapGraph.GATE if crowd < 50.0 else MapGraph.CANTEEN
	if crowd > 60.0:
		_bleed_via(-(crowd - 60.0) * 0.05 * delta)

func on_offering(_location: String) -> void:
	crowd = maxf(0.0, crowd - 45.0)   # one tray reliably scatters them below the drain threshold

func on_calm() -> void:
	crowd = maxf(0.0, crowd - 30.0)   # incense settles the crowd a while

func on_ward_save() -> void:
	crowd = minf(crowd, 25.0)         # a ward scatters the pressing crowd

func on_via_state(state: int) -> void:
	# When the guard is already shaken, a big crowd presses harder (handled via drain).
	pass

func current_texture() -> Texture2D:
	return tex_move if crowd > 50.0 else tex_idle
