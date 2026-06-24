extends Control
## The raise-able camera monitor: a 2D feed with CCTV static/scanlines, the threat
## drawn on its current feed, a bezel frame, and a clickable floor-plan map.

var _c   # NightController
var _feed: TextureRect
var _threat_host: Control
var _name_lbl: Label
var _map_buttons := {}
var _refresh_t := 0.0
var _fx_mat: ShaderMaterial         # the static/scanline shader (strength is animatable)
var _fx_burst := 0.0                # decaying static spike on channel change
const FX_BASE := 0.12
var _clue_btn: TextureButton        # classroom-camera investigation hotspot (her drawing)

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	_build()

func _build() -> void:
	var bg := UI.color_rect(Color(0.01, 0.012, 0.02))
	UI.full(bg)
	add_child(bg)

	# SCALE (not KEEP_ASPECT_COVERED) so the whole feed image fills the screen
	# without being zoomed in / cropped — the bezel art frames the edges.
	_feed = UI.texture_rect("res://assets/art/cameras/cam_gate.svg", TextureRect.STRETCH_SCALE)
	UI.place(_feed, 0, 0, 1, 1, 40, 36, -40, -36)
	add_child(_feed)

	_threat_host = Control.new()
	UI.place(_threat_host, 0, 0, 1, 1, 40, 36, -40, -36)
	_threat_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_threat_host)

	# CCTV static + scanline shader overlay
	var fx := UI.color_rect(Color(1, 1, 1, 1))
	UI.place(fx, 0, 0, 1, 1, 40, 36, -40, -36)
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.12;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	float n = rand(UV * vec2(900.0, 540.0) + vec2(TIME * 41.0, TIME * 13.0));
	float scan = sin(UV.y * 720.0) * 0.5 + 0.5;
	float a = (n * 0.6 + scan * 0.18) * strength;
	COLOR = vec4(vec3(n), a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("strength", FX_BASE)
	fx.material = mat
	_fx_mat = mat
	add_child(fx)

	var bezel := UI.texture_rect("res://assets/art/ui/monitor_bezel.svg", TextureRect.STRETCH_SCALE)
	UI.full(bezel)
	add_child(bezel)

	_name_lbl = UI.text_label("", 24, Color(0.8, 0.95, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	UI.place(_name_lbl, 0, 0, 0, 0, 64, 50, 400, 86)
	add_child(_name_lbl)

	# Investigation hotspot: a faint marker over the classroom chalkboard (her drawing).
	# Only appears on the classroom feed once the arc is in motion (night 3+).
	_clue_btn = UI.icon_button("res://assets/art/ui/cam_dot.svg", 56)
	UI.place(_clue_btn, 0.5, 0.5, 0.5, 0.5, -28, -40, 28, 16)
	_clue_btn.modulate = Color(0.9, 0.8, 0.55, 0.6)
	_clue_btn.tooltip_text = tr("ANOMALY_HINT")
	_clue_btn.visible = false
	_clue_btn.pressed.connect(_on_clue_pressed)
	add_child(_clue_btn)

	_build_map()

func _on_clue_pressed() -> void:
	if _c:
		_c.find_clue("clue_drawing", "CLUE_GOT_DRAWING")
	if _clue_btn:
		_clue_btn.visible = false

func _update_clue_hotspot(cam_id: String) -> void:
	if _clue_btn == null:
		return
	_clue_btn.visible = cam_id == MapGraph.CLASSROOM \
		and Game.current_night >= 3 \
		and not Save.has_clue("clue_drawing")

func _build_map() -> void:
	var map := Control.new()
	map.custom_minimum_size = Vector2(420, 340)
	UI.place(map, 1, 1, 1, 1, -452, -372, -32, -32)
	add_child(map)
	var bg := UI.texture_rect("res://assets/art/ui/map_panel.svg", TextureRect.STRETCH_KEEP_ASPECT)
	UI.full(bg)
	map.add_child(bg)
	# Click target is deliberately larger than the drawn dot so you don't have to
	# hit the circle exactly; the icon stays centered at a comfortable visual size.
	const DOT_HIT := 48.0   # clickable square (smaller now there are 10 cameras)
	for cam in MapGraph.CAMERAS:
		var pos: Vector2 = MapGraph.MAP_POS[cam]
		var b := UI.icon_button("res://assets/art/ui/cam_dot.svg", DOT_HIT)
		b.size = Vector2(DOT_HIT, DOT_HIT)
		b.position = pos - Vector2(DOT_HIT * 0.5, DOT_HIT * 0.5)
		b.tooltip_text = tr(MapGraph.name_key(cam))
		b.pressed.connect(_select.bind(cam))
		map.add_child(b)
		_map_buttons[cam] = b

func _select(cam_id: String) -> void:
	_c.on_camera_changed(cam_id)
	show_feed(cam_id)
	Audio.play_sfx("camera_switch", -10.0)

func show_feed(cam_id: String) -> void:
	var path := "res://assets/art/cameras/cam_%s.svg" % cam_id
	if ResourceLoader.exists(path):
		_feed.texture = load(path)
	_fx_burst = 0.5   # a burst of static as the channel resolves to the new feed
	if _fx_mat:
		_fx_mat.set_shader_parameter("strength", FX_BASE + _fx_burst)
	_name_lbl.text = "%s — %s" % [_cam_code(cam_id), tr(MapGraph.name_key(cam_id))]
	for cam in _map_buttons:
		_map_buttons[cam].modulate = Color(1, 0.85, 0.4) if cam == cam_id else Color(1, 1, 1)
	_update_clue_hotspot(cam_id)
	_refresh_threats()

func _cam_code(cam_id: String) -> String:
	return "CAM%d" % (MapGraph.CAMERAS.find(cam_id) + 1)

func _process(delta: float) -> void:
	if not visible:
		return
	# Ease the channel-change static burst back down to the resting noise level.
	if _fx_burst > 0.0 and _fx_mat:
		_fx_burst = maxf(0.0, _fx_burst - delta * 3.0)
		_fx_mat.set_shader_parameter("strength", FX_BASE + _fx_burst)
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		_refresh_threats()

func _refresh_threats() -> void:
	for c in _threat_host.get_children():
		c.queue_free()
	if _c == null or _c.director == null:
		return
	# Reset map dots to base every pass so reveal highlights never go stale.
	for cam in _map_buttons:
		_map_buttons[cam].modulate = Color(1, 0.85, 0.4) if cam == _c.current_cam else Color(1, 1, 1)
	var revealed: bool = _c.is_revealed()
	for t in _c.director.threats:
		var here: bool = t.current_location == _c.current_cam
		if not here:
			if revealed and _map_buttons.has(t.current_location):
				_map_buttons[t.current_location].modulate = Color(1, 0.3, 0.3)
			continue
		var tex: Texture2D = t.current_texture()
		if tex == null:
			continue
		var tr_node := TextureRect.new()
		tr_node.texture = tex
		tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_node.modulate = Color(0.85, 0.87, 0.87)
		UI.place(tr_node, 0.5, 1, 0.5, 1, -180, -440, 180, -20)
		_threat_host.add_child(tr_node)
		# Click the figure to "tag" the anomaly — a reward for actually watching the
		# cameras (sets a rusher back / settles a meter spirit + a brief reveal).
		var tag := Button.new()
		tag.flat = true
		tag.focus_mode = Control.FOCUS_NONE
		tag.mouse_filter = Control.MOUSE_FILTER_STOP
		tag.tooltip_text = tr("ANOMALY_HINT")
		UI.place(tag, 0.5, 1, 0.5, 1, -180, -440, 180, -20)
		var tid: String = t.id
		tag.pressed.connect(func(): _c.tag_anomaly(tid))
		_threat_host.add_child(tag)
