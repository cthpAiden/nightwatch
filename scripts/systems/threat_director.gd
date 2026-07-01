class_name ThreatDirector
extends Node
## Spawns the night's threats from a NightConfig and ticks their AI each frame.
## Routes player actions (door/light/pan/view/offering) to every threat.

const _NO_THREAT_DIST := 1 << 30   # "infinity" stand-in for the nearest-threat scan

var threats: Array[ThreatBase] = []
var night_progress: float = 0.0

var _controller
var _paused := false

const _DOGPILE_CAP := 2          # engaged door-threats beyond which idle rushers are eased
var _engage_lull := 0.0          # seconds since any threat was APPROACHING / AT_DOOR
var _pincer_cd := 0.0            # cooldown gating the occasional two-door pincer

func setup(controller, cfg: NightConfig) -> void:
	_controller = controller
	for id in cfg.threat_levels:
		var lvl := float(cfg.threat_levels[id])
		if lvl <= 0.0:
			continue
		var meta := ThreatRegistry.info(id)
		if meta.is_empty() or not ResourceLoader.exists(meta.get("script", "")):
			push_warning("ThreatDirector: no script for '%s'" % id)
			continue
		var scr = load(meta["script"])
		var t: ThreatBase = scr.new()
		t.id = id
		t.name = id
		t.fear_factor = meta.get("fear", 3)
		t.accent_color = meta.get("accent", Color(0.8, 0.2, 0.2))
		t.tex_idle = ThreatRegistry.load_tex(id, "idle")
		t.tex_move = ThreatRegistry.load_tex(id, "active")
		t.tex_attack = ThreatRegistry.load_tex(id, "scare")
		add_child(t)
		t.setup(lvl, lvl + cfg.ai_ramp, controller)
		threats.append(t)

func _process(delta: float) -> void:
	if _paused:
		return
	_coordinate(delta)
	for t in threats:
		t.process_ai(delta, night_progress)

# --- coordination ----------------------------------------------------------
## A light pacing layer over the independent per-threat AI. It does NOT decide moves —
## the threats still roll their own — it just keeps pure RNG from either dog-piling a
## busy doorway or leaving long dead-air stretches, and stages the rare two-door pincer.
func _coordinate(delta: float) -> void:
	var engaged := 0
	var door_sides := {}
	for t in threats:
		if t.phase == GameEnums.ThreatPhase.AT_DOOR:
			engaged += 1
			door_sides[t.threatening_side] = true
		elif t.phase == GameEnums.ThreatPhase.APPROACHING:
			engaged += 1
	# Anti-dogpile: while the doors are already busy, ease the cadence of rushers that
	# haven't engaged yet — you stay pressured, but not pile-up-killed by a bad roll.
	var damp := engaged >= _DOGPILE_CAP
	for t in threats:
		if t.phase != GameEnums.ThreatPhase.AT_DOOR and t.phase != GameEnums.ThreatPhase.APPROACHING:
			t.set_coord_mult(0.55 if damp else 1.0)
	_pincer_cd = maxf(0.0, _pincer_cd - delta)
	if engaged > 0:
		_engage_lull = 0.0
		# Rare pincer: exactly one rusher holds a door — occasionally send an idle rusher
		# at the OTHER door for a deliberate two-front beat. Gated by a cooldown and scaled
		# by night progress so early nights stay gentle and it never spams.
		if door_sides.size() == 1 and _pincer_cd <= 0.0 and randf() < 0.03 * clampf(night_progress, 0.0, 1.0) * delta:
			if _nudge_one(_opposite(door_sides.keys()[0])):
				_pincer_cd = 50.0
		return
	# Anti-dead-air: nothing is looming. After a progress-scaled lull, license one idle
	# rusher to make a run so the night never flatlines into nothing-happening.
	_engage_lull += delta
	if _engage_lull >= lerpf(40.0, 18.0, clampf(night_progress, 0.0, 1.0)):
		_engage_lull = 0.0
		_nudge_one(-1)

## Stage one move for a random idle PATH door-rusher, optionally aimed at target_side
## (-1 = let it pick its own). Returns true if a threat was nudged.
func _nudge_one(target_side: int) -> bool:
	var pool: Array = []
	for t in threats:
		if t.movement_model == ThreatBase.MODEL_PATH and t.counter_door and t.can_nudge():
			pool.append(t)
	if pool.is_empty():
		return false
	var t: ThreatBase = pool[randi() % pool.size()]
	t.coord_advance(target_side)
	return true

func _opposite(side: int) -> int:
	return GameEnums.Side.RIGHT if side == GameEnums.Side.LEFT else GameEnums.Side.LEFT

func set_paused(p: bool) -> void:
	_paused = p

# --- queries ---------------------------------------------------------------
func get_threat(id: String) -> ThreatBase:
	for t in threats:
		if t.id == id:
			return t
	return null

func threat_at_door(side: int) -> ThreatBase:
	for t in threats:
		if t.is_at_door() and t.threatening_side == side:
			return t
	return null

func nearest_threat() -> ThreatBase:
	var best: ThreatBase = null
	var best_d := _NO_THREAT_DIST
	for t in threats:
		# Only positional rushers can be meaningfully "set back" to spawn; meter
		# threats store their danger in crowd/agro/lock, not in position.
		if t.movement_model != ThreatBase.MODEL_PATH and t.movement_model != ThreatBase.MODEL_FLYER:
			continue
		# A door-repel is the only meaningful setback; skip rushers whose counter isn't
		# the door (e.g. a light-countered flyer), where sending it to spawn does nothing.
		if not t.counter_door:
			continue
		if t.phase == GameEnums.ThreatPhase.ATTACKING or t.phase == GameEnums.ThreatPhase.DORMANT:
			continue
		var d := t.distance_to_office()
		if d < best_d:
			best_d = d
			best = t
	return best

func threats_at(location: String) -> Array:
	var out: Array = []
	for t in threats:
		if t.current_location == location:
			out.append(t)
	return out

# --- broadcasts ------------------------------------------------------------
func broadcast_door(side: int, closed: bool) -> void:
	for t in threats:
		t.on_door(side, closed)

func broadcast_light(side: int, on: bool) -> void:
	for t in threats:
		t.on_light(side, on)

func broadcast_pan(panning: bool) -> void:
	for t in threats:
		t.on_player_pan(panning)

func broadcast_view(cam_id: String) -> void:
	for t in threats:
		t.on_view(t.current_location == cam_id and cam_id != "")

func broadcast_via_state(state: int) -> void:
	for t in threats:
		t.on_via_state(state)

func broadcast_offering(location: String) -> void:
	for t in threats:
		t.on_offering(location)

func broadcast_calm() -> void:
	for t in threats:
		t.on_calm()

func set_speed_all(mult: float) -> void:
	for t in threats:
		t.set_speed_mult(mult)

func setback_nearest() -> ThreatBase:
	var t := nearest_threat()
	if t:
		t.reset_to_spawn()
	return t
