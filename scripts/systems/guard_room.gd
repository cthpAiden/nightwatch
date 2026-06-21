extends Node3D
## The 2.5D guard office. Builds the 3D scene in code: a pannable camera
## (mouse-to-edges or pan_left/right/reset keys), two doorways with animated
## shutters + real wall lamps, a lit desk, an ancestor altar, and a moonlit window.
## Pure "view + look controls" — gameplay rules live in NightController.

const YAW_MAX := 1.15
const PITCH_MAX := 0.62      # enough downward tilt to see your own chair/lap
const LOOK_LERP := 6.0
const EDGE := 0.14            # outer screen fraction that pans the view

const ROOM_TEX := "res://assets/art/room/"

# Light energies (kept as named constants so power-loss / restore is consistent).
const CEILING_ENERGY := 2.6
const DOOR_LIGHT_ENERGY := 7.0
const DESK_LAMP_ENERGY := 3.2
const ALTAR_ENERGY := 2.0
const TUBE_EMISSION := 1.6

const DOOR_CLOSED_Y := 1.35
const DOOR_OPEN_Y := 3.45   # raised, but a visible lip remains so you see the shutter

var _pivot: Node3D
var _cam: Camera3D
var _doors := {}             # side -> Node3D
var _door_closed := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _lights := {}            # side -> SpotLight3D
var _light_on := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _lamp_mats := {}         # side -> StandardMaterial3D (visible wall fixture glow)
var _threat_sprites := {}    # side -> Sprite3D

var _ceiling: OmniLight3D
var _tube_mat: StandardMaterial3D
var _desk_lamp: SpotLight3D
var _desk_lamp_mat: StandardMaterial3D
var _altar_light: OmniLight3D
var _altar_mat: StandardMaterial3D
var _screen_mat: ShaderMaterial      # desk CRT showing cycling camera feeds
var _screen_feeds: Array = []
var _screen_idx := 0
var _screen_timer := 0.0

var _yaw := 0.0
var _yaw_target := 0.0
var _pitch := 0.0
var _pitch_target := 0.0
var _look_enabled := true
var _powered := true
var _pan_speed := 0.0
var _kb_dir := 0.0
var _t := 0.0

func _ready() -> void:
	_build_environment()
	_build_room()
	_build_window()
	_build_chair()
	_build_doorway(GameEnums.Side.LEFT, -3.9)
	_build_doorway(GameEnums.Side.RIGHT, 3.9)
	set_process(true)
	set_process_unhandled_input(true)

# --- build ------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.3, 0.4)
	env.ambient_light_energy = 0.95
	# Atmospheric depth, but lighter than before so the room reads clearly.
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.13)
	env.fog_density = 0.012
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.tonemap_white = 3.0
	# Gentle bloom so lamps read as light sources — kept low so the ceiling tube
	# no longer blows out into a giant white blob.
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_strength = 0.9
	env.glow_bloom = 0.06
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.3
	# Contact shadows / grounding.
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	# Subtle grade: a touch of contrast + slight desaturation for the night mood.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.02
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 0.94
	we.environment = env
	add_child(we)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.6, 0.5)
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 74.0
	_cam.current = true
	_pivot.add_child(_cam)

	# Main ceiling light + a visible fluorescent tube so there is a real source.
	_ceiling = OmniLight3D.new()
	_ceiling.position = Vector3(0, 2.82, -0.6)
	_ceiling.light_color = Color(0.78, 0.84, 0.92)
	_ceiling.light_energy = CEILING_ENERGY
	_ceiling.omni_range = 15.0
	_ceiling.omni_attenuation = 1.0
	_ceiling.shadow_enabled = true
	add_child(_ceiling)
	# soft fills so the floor and corners aren't pitch black
	for fp in [Vector3(0, 2.5, 1.8), Vector3(-2.4, 2.4, -1.5), Vector3(2.4, 2.4, -1.5)]:
		var fill := OmniLight3D.new()
		fill.position = fp
		fill.light_color = Color(0.55, 0.62, 0.76)
		fill.light_energy = 1.0
		fill.omni_range = 9.0
		add_child(fill)

	_tube_mat = StandardMaterial3D.new()
	_tube_mat.albedo_color = Color(0.9, 0.95, 1.0)
	_tube_mat.emission_enabled = true
	_tube_mat.emission = Color(0.85, 0.92, 1.0)
	_tube_mat.emission_energy_multiplier = TUBE_EMISSION
	var tube := _box(Vector3(2.4, 0.08, 0.2), Vector3(0, 2.92, -0.6), _tube_mat)
	tube.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _mat(tex: String, tint: Color = Color.WHITE, scale: float = 1.0,
		emissive: bool = false, rough: float = 0.95, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var path := ROOM_TEX + tex
	if tex != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = metal
	if scale != 1.0:
		m.uv1_scale = Vector3(scale, scale, 1.0)
	if emissive:
		m.emission_enabled = true
		m.emission = tint
		m.emission_energy_multiplier = 1.5
	return m

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi

func _build_room() -> void:
	var wall := _mat("wall.svg", Color(0.55, 0.6, 0.55), 2.0)
	_box(Vector3(9, 0.2, 9), Vector3(0, -0.1, 0), _mat("floor.svg", Color(0.5, 0.5, 0.5), 3.0, false, 0.85))
	_box(Vector3(9, 0.2, 9), Vector3(0, 3.0, 0), _mat("ceiling.svg", Color(0.4, 0.42, 0.45), 2.0))
	# front wall (what you face) with chalkboard + altar
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, -4.3), wall)
	_box(Vector3(3.4, 1.8, 0.06), Vector3(0.4, 1.7, -4.18), _mat("chalkboard.svg", Color(0.8, 0.85, 0.8)))
	# back wall (behind you)
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, 4.3), wall)
	# desk
	_box(Vector3(3.2, 0.12, 1.2), Vector3(0, 1.0, -1.7), _mat("desk.svg", Color(0.7, 0.6, 0.45), 1.0, false, 0.7))
	_box(Vector3(3.2, 0.9, 0.1), Vector3(0, 0.5, -1.2), _mat("desk.svg", Color(0.45, 0.38, 0.3)))
	# CRT security monitor on the desk — a real-looking screen with live, cycling
	# camera feeds (not a black block).
	var case_mat := _mat("", Color(0.07, 0.075, 0.09), 1.0, false, 0.5, 0.2)
	_box(Vector3(0.98, 0.76, 0.62), Vector3(0.9, 1.45, -1.78), case_mat)   # casing
	_box(Vector3(0.16, 0.14, 0.16), Vector3(0.9, 1.02, -1.74), case_mat)   # neck
	_box(Vector3(0.4, 0.05, 0.3), Vector3(0.9, 0.96, -1.68), case_mat)     # base
	_build_monitor_screen()

	_build_desk_lamp()
	_build_altar()

func _build_monitor_screen() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D feed : source_color;
uniform float t = 0.0;
uniform float lit = 1.0;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = UV;
	vec3 col = texture(feed, uv).rgb;
	col *= 0.86 + 0.14 * sin(uv.y * 240.0);              // scanlines
	vec2 d = uv - 0.5;
	col *= 1.0 - dot(d, d) * 0.7;                        // vignette
	col *= 0.92 + 0.08 * sin(t * 7.0);                  // flicker
	col += rand(uv * vec2(91.0, 75.0) + fract(t)) * 0.035;  // faint static
	col *= vec3(0.82, 1.0, 0.92);                        // cool CRT tint
	col *= lit;                                          // dies on blackout
	ALBEDO = col;
	EMISSION = col * 0.7;
}
"""
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = sh
	for cam in MapGraph.CAMERAS:
		var p := "res://assets/art/cameras/cam_%s.svg" % cam
		if ResourceLoader.exists(p):
			_screen_feeds.append(load(p))
	if not _screen_feeds.is_empty():
		_screen_mat.set_shader_parameter("feed", _screen_feeds[0])
	_screen_mat.set_shader_parameter("t", 0.0)
	_screen_timer = 2.6
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.8, 0.6, 0.02)
	mi.mesh = bm
	mi.material_override = _screen_mat
	mi.position = Vector3(0.9, 1.47, -1.46)
	add_child(mi)

func _build_desk_lamp() -> void:
	# A warm desk lamp pooling light over the desk — the cozy island in the dark.
	var arm := _mat("", Color(0.12, 0.12, 0.14), 1.0, false, 0.4, 0.6)
	_box(Vector3(0.06, 0.5, 0.06), Vector3(-0.7, 1.3, -2.0), arm)
	_desk_lamp_mat = StandardMaterial3D.new()
	_desk_lamp_mat.albedo_color = Color(0.9, 0.7, 0.4)
	_desk_lamp_mat.emission_enabled = true
	_desk_lamp_mat.emission = Color(1.0, 0.75, 0.4)
	_desk_lamp_mat.emission_energy_multiplier = 3.0
	var shade := _box(Vector3(0.34, 0.14, 0.34), Vector3(-0.7, 1.6, -2.0), _desk_lamp_mat)
	shade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_desk_lamp = SpotLight3D.new()
	_desk_lamp.position = Vector3(-0.7, 1.55, -1.9)
	_desk_lamp.rotation = Vector3(-PI / 2.0 + 0.25, 0, 0)
	_desk_lamp.light_color = Color(1.0, 0.82, 0.55)
	_desk_lamp.light_energy = DESK_LAMP_ENERGY
	_desk_lamp.spot_range = 4.0
	_desk_lamp.spot_angle = 55.0
	_desk_lamp.spot_attenuation = 1.2
	_desk_lamp.shadow_enabled = true
	add_child(_desk_lamp)

func _build_altar() -> void:
	# Ancestor altar (amber safe zone) — warm candlelight that survives a blackout.
	_altar_mat = _mat("", Color(0.55, 0.22, 0.09), 1.0, true)
	_altar_mat.emission_energy_multiplier = 2.2
	_box(Vector3(0.6, 0.5, 0.4), Vector3(-1.2, 1.35, -1.8), _altar_mat)
	# two little candle flames
	for dx in [-0.12, 0.12]:
		var flame := _mat("", Color(1.0, 0.6, 0.2), 1.0, true)
		flame.emission_energy_multiplier = 5.0
		var f := _box(Vector3(0.05, 0.12, 0.05), Vector3(-1.2 + dx, 1.66, -1.7), flame)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_altar_light = OmniLight3D.new()
	_altar_light.position = Vector3(-1.2, 1.75, -1.6)
	_altar_light.light_color = Color(1.0, 0.6, 0.22)
	_altar_light.light_energy = ALTAR_ENERGY
	_altar_light.omni_range = 3.6
	add_child(_altar_light)

func _build_chair() -> void:
	# The guard's wooden chair, right under the camera pivot (≈0,1.6,0.5) so when
	# you look down you see you're sitting in it.
	var wood := _mat("desk.svg", Color(0.5, 0.36, 0.22), 1.0, false, 0.65)
	var wood_dark := _mat("desk.svg", Color(0.4, 0.28, 0.17), 1.0, false, 0.65)
	var sx := 0.0
	var sz := 0.45
	_box(Vector3(0.56, 0.09, 0.54), Vector3(sx, 0.95, sz), wood)         # seat
	_box(Vector3(0.56, 0.72, 0.09), Vector3(sx, 1.33, sz + 0.3), wood)   # backrest
	# arm rests (extend forward so they frame the bottom of your view)
	for ax in [-0.31, 0.31]:
		_box(Vector3(0.07, 0.09, 0.6), Vector3(sx + ax, 1.18, sz - 0.06), wood_dark)
		_box(Vector3(0.07, 0.26, 0.07), Vector3(sx + ax, 1.06, sz - 0.3), wood_dark)
	# four legs
	for lx in [-0.25, 0.25]:
		for lz in [sz - 0.24, sz + 0.24]:
			_box(Vector3(0.08, 0.92, 0.08), Vector3(sx + lx, 0.46, lz), wood_dark)

func _build_window() -> void:
	# A barred window on the back wall lets cool moonlight rake across the room,
	# giving depth and a cold rim opposite the warm desk.
	var frame := _mat("", Color(0.1, 0.11, 0.13), 1.0, false, 0.5, 0.4)
	_box(Vector3(2.0, 1.4, 0.08), Vector3(0, 1.9, 4.22), frame)
	var pane := StandardMaterial3D.new()
	pane.albedo_color = Color(0.2, 0.3, 0.45)
	pane.emission_enabled = true
	pane.emission = Color(0.3, 0.42, 0.62)
	pane.emission_energy_multiplier = 1.4
	var p := _box(Vector3(1.8, 1.2, 0.04), Vector3(0, 1.9, 4.18), pane)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# window bars
	for bx in [-0.45, 0.0, 0.45]:
		_box(Vector3(0.05, 1.2, 0.06), Vector3(bx, 1.9, 4.14), frame)
	var moon := SpotLight3D.new()
	moon.position = Vector3(0, 2.4, 3.9)
	moon.rotation = Vector3(0.35, PI, 0)   # shine forward (-z) and slightly down
	moon.light_color = Color(0.55, 0.66, 0.9)
	moon.light_energy = 2.6
	moon.spot_range = 9.0
	moon.spot_angle = 42.0
	moon.spot_attenuation = 1.0
	moon.shadow_enabled = true
	add_child(moon)

func _build_doorway(side: int, x: float) -> void:
	var wall := _mat("wall.svg", Color(0.5, 0.55, 0.5), 2.0)
	# wall segments leaving a doorway gap around z=0
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, -2.7), wall)
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, 2.7), wall)
	_box(Vector3(0.2, 0.6, 2.6), Vector3(x, 2.7, 0), wall)
	# dir points OUT of the room (the corridor is BEYOND the door, never in front
	# of it — the old layout put a dark slab between the camera and the door, which
	# hid the door and the threat entirely).
	var dir := -1.0 if side == GameEnums.Side.LEFT else 1.0
	# A long, very dark hallway that recedes into black (NOT a shallow lit
	# deadend). Materials are near-black so it stays pitch black by default; only
	# the doorway lamp (when you switch it on) reveals the near stretch + whatever
	# is standing in it. The far end fades to black, so it reads as "leads away".
	var depth := 7.0
	var cx := x + dir * (depth * 0.5)
	var hall := _mat("wall.svg", Color(0.07, 0.075, 0.085), 2.0)
	var hall_floor := _mat("floor.svg", Color(0.06, 0.06, 0.07), 2.0)
	_box(Vector3(depth, 2.8, 0.2), Vector3(cx, 1.3, -1.3), hall)            # side wall
	_box(Vector3(depth, 2.8, 0.2), Vector3(cx, 1.3, 1.3), hall)            # side wall
	_box(Vector3(depth, 0.2, 2.4), Vector3(cx, -0.1, 0), hall_floor)        # floor
	_box(Vector3(depth, 0.2, 2.4), Vector3(cx, 2.6, 0), hall)              # ceiling
	# faint cross-corridor at the far end so the hall clearly turns/continues
	var ex := x + dir * depth
	_box(Vector3(0.2, 2.8, 5.0), Vector3(ex + dir * 0.1, 1.3, 0), _mat("", Color(0.03, 0.03, 0.035)))
	_box(Vector3(2.2, 0.2, 5.0), Vector3(ex - dir * 1.0, -0.1, 0), hall_floor)
	# threat billboard standing just OUTSIDE the door, in the corridor mouth
	var spr := Sprite3D.new()
	spr.pixel_size = 0.007
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.position = Vector3(x + dir * 0.45, 1.35, 0)
	spr.modulate = Color(0.7, 0.72, 0.72)
	spr.visible = false
	add_child(spr)
	_threat_sprites[side] = spr
	# roller shutter door
	var door := _box(Vector3(0.16, 2.6, 2.5), Vector3(x, DOOR_OPEN_Y, 0),
		_mat("door.svg", Color(0.6, 0.62, 0.66), 1.0, false, 0.5, 0.5))
	_doors[side] = door
	# visible wall lamp fixture beside the doorway (glows when switched on)
	var inward := -0.7 if side == GameEnums.Side.LEFT else 0.7
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.18, 0.18, 0.2)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.93, 0.7)
	lamp_mat.emission_energy_multiplier = 0.0   # off until lit
	var fixture := _box(Vector3(0.16, 0.3, 0.16), Vector3(x + inward, 2.3, 0.0), lamp_mat)
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_mats[side] = lamp_mat
	# doorway spotlight — wide + bright so it truly illuminates the doorway
	var sl := SpotLight3D.new()
	sl.position = Vector3(x + (0.9 if side == GameEnums.Side.LEFT else -0.9), 2.1, 0)
	sl.rotation = Vector3(-0.35, (PI / 2.0 if side == GameEnums.Side.LEFT else -PI / 2.0), 0)
	sl.light_color = Color(1.0, 0.95, 0.82)
	sl.light_energy = 0.0
	sl.spot_range = 8.5
	sl.spot_angle = 50.0
	sl.spot_attenuation = 0.8
	sl.shadow_enabled = true
	add_child(sl)
	_lights[side] = sl

# --- look controls ----------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	if _look_enabled:
		_update_look_targets()
	var prev_yaw := _yaw
	_yaw = lerpf(_yaw, _yaw_target, clampf(delta * LOOK_LERP, 0, 1))
	_pitch = lerpf(_pitch, _pitch_target, clampf(delta * LOOK_LERP, 0, 1))
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = _pitch
	_pan_speed = absf(_yaw - prev_yaw) / maxf(delta, 0.0001)
	# candle flicker (always — it's fire, not mains power)
	if _altar_light:
		var f := 0.85 + 0.1 * sin(_t * 7.3) + 0.05 * sin(_t * 19.0)
		_altar_light.light_energy = ALTAR_ENERGY * f
	if not _powered:
		# blackout: mains lights die out, only the altar candle remains
		_ceiling.light_energy = maxf(0.0, _ceiling.light_energy - delta * 2.5)
		if _tube_mat:
			_tube_mat.emission_energy_multiplier = maxf(0.0, _tube_mat.emission_energy_multiplier - delta * 6.0)
	else:
		# subtle fluorescent flutter while powered
		_ceiling.light_energy = CEILING_ENERGY * (0.96 + 0.04 * sin(_t * 9.0))
	# desk CRT: animate scanlines/flicker and cycle through the camera feeds
	if _screen_mat:
		_screen_mat.set_shader_parameter("t", _t)
		_screen_mat.set_shader_parameter("lit", 1.0 if _powered else 0.0)
		_screen_timer -= delta
		if _screen_timer <= 0.0 and not _screen_feeds.is_empty():
			_screen_timer = 2.6
			_screen_idx = (_screen_idx + 1) % _screen_feeds.size()
			_screen_mat.set_shader_parameter("feed", _screen_feeds[_screen_idx])

func _update_look_targets() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var mp := vp.get_mouse_position()
	var vs := vp.get_visible_rect().size
	var nx := mp.x / maxf(vs.x, 1.0)
	var ny := mp.y / maxf(vs.y, 1.0)
	var yaw_mouse := 0.0
	if nx < EDGE:
		yaw_mouse = (EDGE - nx) / EDGE          # left edge -> look left (+yaw)
	elif nx > 1.0 - EDGE:
		yaw_mouse = -((nx - (1.0 - EDGE)) / EDGE)
	var pitch_mouse := 0.0
	if ny < EDGE:
		pitch_mouse = (EDGE - ny) / EDGE         # top -> look up
	elif ny > 1.0 - EDGE:
		pitch_mouse = -((ny - (1.0 - EDGE)) / EDGE)
	_yaw_target = clampf(_kb_dir + yaw_mouse, -1.0, 1.0) * YAW_MAX
	_pitch_target = clampf(pitch_mouse, -1.0, 1.0) * PITCH_MAX

func _unhandled_input(_e: InputEvent) -> void:
	if not _look_enabled:
		_kb_dir = 0.0
		return
	var d := 0.0
	if Input.is_action_pressed("pan_left"):
		d += 1.0
	if Input.is_action_pressed("pan_right"):
		d -= 1.0
	_kb_dir = d
	if Input.is_action_just_pressed("pan_reset"):
		_yaw_target = 0.0
		_pitch_target = 0.0

# --- public API -------------------------------------------------------------
func facing_side() -> int:
	if _yaw > 0.55:
		return GameEnums.Side.LEFT
	if _yaw < -0.55:
		return GameEnums.Side.RIGHT
	return -1

func get_pan_speed() -> float:
	return _pan_speed

func set_look_enabled(on: bool) -> void:
	_look_enabled = on
	if not on:
		_kb_dir = 0.0

func set_powered(on: bool) -> void:
	_powered = on
	if on:
		_ceiling.light_energy = CEILING_ENERGY
		if _tube_mat:
			_tube_mat.emission_energy_multiplier = TUBE_EMISSION
		if _desk_lamp:
			_desk_lamp.light_energy = DESK_LAMP_ENERGY
		if _desk_lamp_mat:
			_desk_lamp_mat.emission_energy_multiplier = 3.0
	else:
		if _desk_lamp:
			_desk_lamp.light_energy = 0.0
		if _desk_lamp_mat:
			_desk_lamp_mat.emission_energy_multiplier = 0.0
		for s in _light_on.keys():
			set_light(s, false)

func is_door_closed(side: int) -> bool:
	return _door_closed.get(side, false)

func set_door(side: int, closed: bool) -> void:
	if _door_closed.get(side) == closed:
		return
	_door_closed[side] = closed
	var door: Node3D = _doors[side]
	var ty := DOOR_CLOSED_Y if closed else DOOR_OPEN_Y
	# A visible roller-shutter slide: down with a firm settle when closing, up
	# (a touch slower) when opening. Always retargets cleanly if toggled mid-slide.
	var tw := create_tween()
	if closed:
		tw.tween_property(door, "position:y", ty, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(door, "position:y", ty, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	Audio.play_sfx("door_slam" if closed else "door_creak", -4.0)
	Events.door_toggled.emit(side, closed)

func is_light_on(side: int) -> bool:
	return _light_on.get(side, false)

func set_light(side: int, on: bool) -> void:
	if _light_on.get(side) == on:
		return
	_light_on[side] = on
	(_lights[side] as SpotLight3D).light_energy = DOOR_LIGHT_ENERGY if on else 0.0
	if _lamp_mats.has(side):
		(_lamp_mats[side] as StandardMaterial3D).emission_energy_multiplier = 3.5 if on else 0.0
	Audio.play_sfx("light_switch", -8.0)
	Events.light_toggled.emit(side, on)

func show_threat(side: int, tex: Texture2D, hostile: bool = false) -> void:
	var spr: Sprite3D = _threat_sprites[side]
	if tex == null:
		spr.visible = false
		return
	spr.texture = tex
	spr.modulate = Color(0.85, 0.3, 0.3) if hostile else Color(0.72, 0.74, 0.74)
	spr.visible = _light_on.get(side, false)

func refresh_threat_visibility(side: int, has_threat: bool, tex: Texture2D = null, hostile: bool = false) -> void:
	var spr: Sprite3D = _threat_sprites[side]
	if has_threat and tex:
		spr.texture = tex
	spr.modulate = Color(0.85, 0.3, 0.3) if hostile else Color(0.72, 0.74, 0.74)
	spr.visible = has_threat and _light_on.get(side, false)
