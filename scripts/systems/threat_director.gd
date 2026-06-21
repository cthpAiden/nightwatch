class_name ThreatDirector
extends Node
## Spawns the night's threats from a NightConfig and ticks their AI each frame.
## Routes player actions (door/light/pan/view/offering) to every threat.

var threats: Array[ThreatBase] = []
var night_progress: float = 0.0

var _controller
var _paused := false

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
		t.name_key = meta.get("name_key", id)
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
	for t in threats:
		t.process_ai(delta, night_progress)

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
	var best_d := 99999
	for t in threats:
		if t.phase == GameEnums.ThreatPhase.ATTACKING:
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

func set_speed_all(mult: float) -> void:
	for t in threats:
		t.set_speed_mult(mult)

func setback_nearest() -> void:
	var t := nearest_threat()
	if t:
		t.reset_to_spawn()
