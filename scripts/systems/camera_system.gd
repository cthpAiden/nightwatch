extends Control
## The raise-able camera monitor: a 2D feed with CCTV static/scanlines, the threat
## drawn on its current feed, a bezel frame, and a clickable floor-plan map.

var _c   # NightController
var _feed: TextureRect
var _threat_host: Control
var _name_lbl: Label
var _ts_lbl: Label                  # ticking CCTV timestamp so the feed reads as live, not a still
var _map_buttons := {}
var _refresh_t := 0.0
var _fx_mat: ShaderMaterial         # the static/scanline shader (strength is animatable)
var _fx_burst := 0.0                # decaying static spike on channel change
var _glitch := 0.0                  # signal-tear amount, ramped while a threat is on the watched feed (backlog#21)
var _fog := 0.0                     # extra baseline static on a "fog" night
# A camera whose feed has a 3D blockout renders it into its own SubViewport (isolated
# 3D world) and pipes the live texture through the same CCTV shader as the SVG feeds.
# Cameras without a scene here (or whose scene file is missing) fall back to the SVG.
const ROOM_SCENES := {
	"gate": "res://scenes/rooms/Gate.tscn",
	"courtyard": "res://scenes/rooms/Courtyard.tscn",
	"canteen": "res://scenes/rooms/Canteen.tscn",
	"classroom": "res://scenes/rooms/Classroom.tscn",
	"library": "res://scenes/rooms/Library.tscn",
	"left_hall": "res://scenes/rooms/LeftHall.tscn",
	"gym": "res://scenes/rooms/Gym.tscn",
	"restroom": "res://scenes/rooms/Restroom.tscn",
	"infirmary": "res://scenes/rooms/Infirmary.tscn",
	"right_hall": "res://scenes/rooms/RightHall.tscn",
}
var _room_vps := {}                 # cam_id -> SubViewport (created on first visit)
var _room_cur := ""                 # cam_id of the room currently rendering
var _last_feed_size := Vector2.ZERO # last feed rect size — re-upload rect_aspect only on resize
const FX_BASE := 0.06
var _clue_btn: TextureButton        # classroom-camera investigation hotspot (her drawing)
var _clue_pulse := 0.0              # animates the unclaimed hotspot so the eye catches it
var _oan_hint_shown := false        # one-time "tag her" hint on first oan_hon sighting

## A foggy night runs every feed heavier with static (set once at night start).
func set_fog_level(v: float) -> void:
	_fog = maxf(0.0, v)
	if _fx_mat:
		_fx_mat.set_shader_parameter("strength", FX_BASE + _fog + _fx_burst)

## Per-camera depth tier for the threat billboard: deeper rooms render the figure
## smaller and higher up the frame, near rooms larger and lower — sells the 2.5D space.
const CAM_DEPTH := {
	"gate": {"s": 1.0, "y": 0.0},
	"courtyard": {"s": 0.86, "y": -30.0},
	"canteen": {"s": 0.86, "y": -24.0},
	"classroom": {"s": 0.74, "y": -54.0},
	"library": {"s": 0.72, "y": -60.0},
	"left_hall": {"s": 0.95, "y": -8.0},
	"gym": {"s": 0.86, "y": -24.0},
	"restroom": {"s": 0.78, "y": -46.0},
	"infirmary": {"s": 0.72, "y": -60.0},
	"right_hall": {"s": 0.95, "y": -8.0},
}

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	_build()

func _notification(what: int) -> void:
	# Re-assert a full-screen rect whenever the panel is shown (cheap insurance so the
	# CCTV always covers the whole viewport).
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		if visible:
			UI.full(self)
			# Resume the live 3D feed for the room being watched (paused while lowered).
			if _room_cur != "" and _room_vps.has(_room_cur):
				_room_vps[_room_cur].render_target_update_mode = SubViewport.UPDATE_ALWAYS
		else:
			# Monitor lowered: stop every 3D room rendering so hidden feeds cost nothing.
			for id in _room_vps:
				_room_vps[id].render_target_update_mode = SubViewport.UPDATE_DISABLED

func _build() -> void:
	var bg := UI.color_rect(Color(0.01, 0.012, 0.02))
	UI.full(bg)
	add_child(bg)

	# The feed fills the WHOLE screen edge-to-edge (only a hair of inset for the bezel).
	# Aspect is handled in-shader by a COVER fit (object-fit: cover) keyed off rect_aspect,
	# so the 16:9 art fills any window aspect without the tall/squashed stretch the old
	# STRETCH_SCALE gave under `expand`. The material also grades the feed (live CCTV, not
	# flat grey) and lays the noise/scanline over it in one pass.
	_feed = UI.texture_rect("res://assets/art/cameras/cam_gate.svg", TextureRect.STRETCH_SCALE)
	UI.full(_feed)   # fill the whole screen edge-to-edge — the shader vignette is the frame
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float strength = 0.10;
uniform float glitch = 0.0;          // signal-tear amount, ramped while a threat is on this feed
uniform float rect_aspect = 1.7778;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	// Signal-tear: shift whole rows sideways by a per-row random amount. (backlog#21)
	vec2 guv = UV;
	guv.x += (rand(vec2(floor(UV.y * 120.0), floor(TIME * 18.0))) - 0.5) * glitch * 0.04;
	// COVER fit: centre-crop the 16:9 source to fill the rect at any aspect, no stretch.
	vec2 fuv = guv;
	float r = rect_aspect / 1.7778;
	if (r > 1.0) fuv.y = (fuv.y - 0.5) / r + 0.5;
	else fuv.x = (fuv.x - 0.5) * r + 0.5;
	vec4 src = texture(TEXTURE, fuv);
	vec3 c = src.rgb;
	// De-grey grade: add contrast, restore saturation the night art crushes out, give
	// the feed a faint cold-CCTV cast, and lift the blacks so it isn't a dead grey slab.
	c = (c - 0.5) * 1.16 + 0.5;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.5);
	c *= vec3(0.93, 1.05, 1.01);
	c += vec3(0.015, 0.024, 0.022);
	// Animated CCTV noise + scanline; `strength` spikes on channel change, `glitch` punches it.
	float n = rand(UV * vec2(900.0, 540.0) + vec2(TIME * 41.0, TIME * 13.0));
	c += (n - 0.5) * (strength + glitch * 0.12);
	c -= (sin(UV.y * 720.0) * 0.5 + 0.5) * strength * 0.10;
	// A dark roll bar scrolling down the feed while the signal tears. (backlog#21)
	float roll = fract(UV.y - TIME * glitch);
	c *= 1.0 - smoothstep(0.0, 0.14, roll) * (1.0 - smoothstep(0.14, 0.28, roll)) * glitch * 0.6;
	// Soft vignette draws the eye to the centre of the frame.
	float vig = distance(UV, vec2(0.5));
	c *= 1.0 - smoothstep(0.6, 1.05, vig) * 0.5;
	COLOR = vec4(clamp(c, 0.0, 1.0), src.a);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("strength", FX_BASE)
	mat.set_shader_parameter("glitch", 0.0)
	_feed.material = mat
	_fx_mat = mat
	add_child(_feed)

	_threat_host = Control.new()
	UI.full(_threat_host)
	_threat_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_threat_host)

	# A faint REC dot keeps the CCTV cue the old bezel used to provide (top-left, by the
	# camera name) now that the heavy frame — which boxed the feed in — is gone.
	var rec := UI.color_rect(Color(0.78, 0.16, 0.18, 0.9))
	UI.place(rec, 0, 0, 0, 0, 36, 58, 50, 72)
	rec.pivot_offset = Vector2(7, 7)
	add_child(rec)

	_name_lbl = UI.text_label("", 24, Color(0.8, 0.95, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	UI.place(_name_lbl, 0, 0, 0, 0, 64, 50, 400, 86)
	add_child(_name_lbl)
	# A ticking timestamp under the cam name sells "a live haunted-school feed at 3 AM"
	# rather than a gallery of stills. (backlog#34)
	_ts_lbl = UI.text_label("", 16, Color(0.55, 0.78, 0.7), HORIZONTAL_ALIGNMENT_LEFT)
	UI.place(_ts_lbl, 0, 0, 0, 0, 64, 84, 400, 108)
	add_child(_ts_lbl)

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

# The map art is authored in a MAP_W x MAP_H viewBox; MapGraph.MAP_POS is in the same
# space. Dots are anchored PROPORTIONALLY (pos / MAP_W,H) and the bg uses STRETCH_SCALE,
# so both fill the panel identically and the dots land dead-centre on the drawn rooms no
# matter the panel's actual rendered size — the old KEEP_ASPECT + absolute-pixel combo
# drifted the rooms away from the dots whenever the panel wasn't exactly 420x340.
const MAP_W := 420.0
const MAP_H := 340.0

# Office + door nodes aren't camera positions, but the corridors wire home to them.
const _OFFICE_POS := Vector2(210, 313)
const _LEFT_DOOR_POS := Vector2(183, 303)
const _RIGHT_DOOR_POS := Vector2(237, 303)

func _build_map() -> void:
	var map := Control.new()
	map.custom_minimum_size = Vector2(MAP_W, MAP_H)
	UI.place(map, 1, 1, 1, 1, -MAP_W - 32.0, -MAP_H - 32.0, -32, -32)
	add_child(map)
	# Rounded panel backing.
	var panel := Panel.new()
	UI.full(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.063, 0.094, 0.94)
	sb.border_color = Color(0.17, 0.21, 0.27)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	map.add_child(panel)
	# Corridors + rooms are DRAWN from MapGraph.MAP_POS/ADJ — the very same coordinates
	# the dots use — so they can never drift apart (the old SVG floor-plan rasterised
	# off-register from the dots). A draw-layer Control renders under the dot buttons.
	var layer := Control.new()
	UI.full(layer)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.draw.connect(_draw_map.bind(layer))
	map.add_child(layer)
	layer.queue_redraw()
	# Clickable camera dots (larger hit box than the drawn circle).
	const DOT_HIT := 48.0
	for cam in MapGraph.CAMERAS:
		var pos: Vector2 = MapGraph.MAP_POS[cam]
		var nx: float = pos.x / MAP_W
		var ny: float = pos.y / MAP_H
		var b := UI.icon_button("res://assets/art/ui/cam_dot.svg", DOT_HIT)
		UI.place(b, nx, ny, nx, ny, -DOT_HIT * 0.5, -DOT_HIT * 0.5, DOT_HIT * 0.5, DOT_HIT * 0.5)
		b.tooltip_text = tr(MapGraph.name_key(cam))
		b.pressed.connect(_select.bind(cam))
		map.add_child(b)
		_map_buttons[cam] = b

## Draw the floor plan (corridors, room plates, the doors and the you-are-here office)
## directly from the graph, so every element shares the dots' coordinate space.
func _draw_map(layer: Control) -> void:
	var extra := {
		MapGraph.OFFICE: _OFFICE_POS,
		MapGraph.LEFT_DOOR: _LEFT_DOOR_POS,
		MapGraph.RIGHT_DOOR: _RIGHT_DOOR_POS,
	}
	var pos_of := func(id: String) -> Vector2:
		return MapGraph.MAP_POS[id] if MapGraph.MAP_POS.has(id) else extra.get(id, Vector2.ZERO)
	# corridors — each undirected edge once
	var seen := {}
	for a in MapGraph.ADJ:
		for b in MapGraph.ADJ[a]:
			var key: String = (a + "|" + b) if a < b else (b + "|" + a)
			if seen.has(key):
				continue
			seen[key] = true
			layer.draw_line(pos_of.call(a), pos_of.call(b), Color(0.17, 0.22, 0.30), 5.0)
	# room plates, centred on each camera's MAP_POS
	for cam in MapGraph.CAMERAS:
		var p: Vector2 = MapGraph.MAP_POS[cam]
		var r := Rect2(p - Vector2(27, 17), Vector2(54, 34))
		layer.draw_rect(r, Color(0.086, 0.125, 0.18))
		layer.draw_rect(r, Color(0.20, 0.28, 0.38), false, 2.0)
	# door squares
	for d in [_LEFT_DOOR_POS, _RIGHT_DOOR_POS]:
		layer.draw_rect(Rect2(d - Vector2(7, 7), Vector2(14, 14)), Color(0.15, 0.21, 0.29))
	# the office (you are here)
	var orc := Rect2(_OFFICE_POS - Vector2(28, 15), Vector2(56, 30))
	layer.draw_rect(orc, Color(0.227, 0.184, 0.102))
	layer.draw_rect(orc, Color(0.604, 0.478, 0.173), false, 2.0)
	layer.draw_circle(_OFFICE_POS, 6.0, Color(0.949, 0.757, 0.306))

func _select(cam_id: String) -> void:
	_c.on_camera_changed(cam_id)
	show_feed(cam_id)
	Audio.play_sfx("camera_switch", -10.0)

func show_feed(cam_id: String) -> void:
	if not _mount_room(cam_id):
		var path := "res://assets/art/cameras/cam_%s.svg" % cam_id
		if ResourceLoader.exists(path):
			_feed.texture = load(path)
	_fx_burst = 0.5   # a burst of static as the channel resolves to the new feed
	if _fx_mat:
		_fx_mat.set_shader_parameter("strength", FX_BASE + _fog + _fx_burst)
	_name_lbl.text = "%s — %s" % [_cam_code(cam_id), tr(MapGraph.name_key(cam_id))]
	for cam in _map_buttons:
		_map_buttons[cam].modulate = Color(1, 0.85, 0.4) if cam == cam_id else Color(1, 1, 1)
	_update_clue_hotspot(cam_id)
	_refresh_threats()

## Point _feed at the live 3D render for a camera that has a blockout scene. Returns
## false (so the caller uses the SVG) when the cam has no scene or the file is missing.
## Only the active room renders; the rest are held at UPDATE_DISABLED to save the GPU.
func _mount_room(cam_id: String) -> bool:
	if not ROOM_SCENES.has(cam_id):
		return false
	var scene_path: String = ROOM_SCENES[cam_id]
	if not ResourceLoader.exists(scene_path):
		return false
	if not _room_vps.has(cam_id):
		var vp := SubViewport.new()
		vp.size = Vector2i(960, 540)
		vp.own_world_3d = true
		vp.add_child(load(scene_path).instantiate())
		add_child(vp)
		_room_vps[cam_id] = vp
	for id in _room_vps:
		_room_vps[id].render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cur: SubViewport = _room_vps[cam_id]
	cur.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_feed.texture = cur.get_texture()
	_room_cur = cam_id
	return true

## Confirm an anomaly tag with a brief static/brightness spike on the live feed —
## reuses the same channel-change burst so the feed "pops" when you nail a tag.
func tag_confirm() -> void:
	if _fx_mat == null:
		return
	_fx_burst = maxf(_fx_burst, 0.6)
	_fx_mat.set_shader_parameter("strength", FX_BASE + _fog + _fx_burst)

func _cam_code(cam_id: String) -> String:
	return "CAM%d" % (MapGraph.CAMERAS.find(cam_id) + 1)

## REC-style HH:MM:SS from the in-game clock (game_minutes), seconds ticking off the
## fractional minute so the feed reads as live.
func _fmt_ts(gm: float) -> String:
	var total := int(gm)
	var disp_h := 12 if (total / 60) == 0 else (total / 60)
	return "● REC  %02d:%02d:%02d" % [disp_h, total % 60, int((gm - float(total)) * 60.0)]

func _process(delta: float) -> void:
	if not visible:
		return
	if _ts_lbl and _c:
		_ts_lbl.text = _fmt_ts(_c.game_minutes)
	# Keep the feed's COVER fit correct for the live window aspect (so it fills any screen
	# under `expand` without stretching) — cheap, just a uniform write.
	if _fx_mat and _feed and _feed.size.y > 1.0 and _feed.size != _last_feed_size:
		_last_feed_size = _feed.size
		_fx_mat.set_shader_parameter("rect_aspect", _feed.size.x / _feed.size.y)
	# Ease the channel-change static burst back down to the resting noise level.
	if _fx_burst > 0.0 and _fx_mat:
		_fx_burst = maxf(0.0, _fx_burst - delta * 3.0)
		_fx_mat.set_shader_parameter("strength", FX_BASE + _fog + _fx_burst)
	# Signal-tear glitch decays each frame; _refresh_threats re-ramps it while a threat is on
	# the watched feed, so it tears continuously then resolves once the figure leaves. (backlog#21)
	if _glitch > 0.0 and _fx_mat:
		_glitch = maxf(0.0, _glitch - delta * 1.2)
		_fx_mat.set_shader_parameter("glitch", _glitch)
	# Pulse the unclaimed clue hotspot so a player actually notices it.
	if _clue_btn and _clue_btn.visible:
		_clue_pulse += delta * 3.0
		var a := 0.55 + 0.4 * (0.5 + 0.5 * sin(_clue_pulse))
		_clue_btn.modulate = Color(1.0, 0.88, 0.5, a)
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
		# A threat is on the feed we're watching — tear the signal (ramped here, decayed in
		# _process so it holds while present then resolves when she leaves). (backlog#21)
		_glitch = maxf(_glitch, 0.6)
		if _fx_mat:
			_fx_mat.set_shader_parameter("glitch", _glitch)
		# First time the wronged soul appears on a feed this night, tell the player she
		# can be tagged (the one clue most likely to be missed). The per-instance
		# _oan_hint_shown flag keeps it to one nudge per night.
		if t.id == "oan_hon" and not _oan_hint_shown:
			_oan_hint_shown = true
			Events.notify.emit("CLUE_HINT_TAG", [])
		var d: Dictionary = CAM_DEPTH.get(_c.current_cam, {"s": 1.0, "y": 0.0})
		var hw: float = 180.0 * float(d["s"])
		var hh: float = 420.0 * float(d["s"])
		var yo: float = float(d["y"])
		var tr_node := TextureRect.new()
		tr_node.texture = tex
		tr_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Keep the figure bright and present on the feed (a faint cold cast to sit in the
		# CCTV grade) instead of the old dishwater grey that made threats hard to read.
		# The two pale full-height ghosts get split temperatures (cool oan_hon /
		# warm quy_nhap_trang) so they read apart instantly at the small feed scale
		# instead of blurring together; everything else keeps the flat cold cast.
		match t.id:
			"oan_hon":
				tr_node.modulate = Color(0.9, 0.95, 1.0)
			"quy_nhap_trang":
				tr_node.modulate = Color(1.0, 0.97, 0.9)
			_:
				tr_node.modulate = Color(0.95, 0.98, 0.97)
		UI.place(tr_node, 0.5, 1, 0.5, 1, -hw, -(hh + 20.0) + yo, hw, -20.0 + yo)
		_threat_host.add_child(tr_node)
		# Click the figure to "tag" the anomaly — a reward for actually watching the
		# cameras (sets a rusher back / settles a meter spirit + a brief reveal).
		var tag := Button.new()
		tag.flat = true
		tag.focus_mode = Control.FOCUS_NONE
		tag.mouse_filter = Control.MOUSE_FILTER_STOP
		tag.tooltip_text = tr("ANOMALY_HINT")
		UI.place(tag, 0.5, 1, 0.5, 1, -hw, -(hh + 20.0) + yo, hw, -20.0 + yo)
		var tid: String = t.id
		tag.pressed.connect(func(): _c.tag_anomaly(tid))
		_threat_host.add_child(tag)
	# The roaming vendor shows on the gate feed while she's at the window (shop/hostile).
	if _c.vendor and _c.vendor.has_method("on_camera") and _c.vendor.on_camera() and _c.current_cam == MapGraph.GATE:
		var vtex: Texture2D = _c.vendor.cam_texture()
		if vtex:
			var vd: Dictionary = CAM_DEPTH.get(MapGraph.GATE, {"s": 1.0, "y": 0.0})
			var vhw: float = 150.0 * float(vd["s"])
			var vhh: float = 360.0 * float(vd["s"])
			var vyo: float = float(vd["y"])
			var vr := TextureRect.new()
			vr.texture = vtex
			vr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vr.modulate = Color(1.0, 0.96, 0.92)
			vr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# Off to the right of any cô hồn crowd at the gate, a touch smaller.
			UI.place(vr, 0.7, 1, 0.7, 1, -vhw, -(vhh + 20.0) + vyo, vhw, -20.0 + vyo)
			_threat_host.add_child(vr)
