extends Node3D
## The 2.5D guard office. Builds the 3D scene in code: a pannable camera
## (mouse-to-edges or pan_left/right/reset keys), two doorways with animated
## shutters + real wall lamps, a lit desk, a full ancestor SHRINE (bàn thờ), a
## ceiling fan, a ticking wall clock and assorted clutter, plus a moonlit window.
## Pure "view + look controls" — gameplay rules live in NightController. The altar
## also exposes set_huong()/set_altar_lit() so the incense-ritual mechanic can drive
## its candlelight, ember glow and rising smoke.

const YAW_MAX := 1.15
const PITCH_MAX := 0.62      # enough downward tilt to see your own chair/lap
const LOOK_LERP := 6.0
const EDGE := 0.14            # outer screen fraction that pans the view

const ROOM_TEX := "res://assets/art/room/"

# Light energies (kept as named constants so power-loss / restore is consistent).
const CEILING_ENERGY := 2.35
const DOOR_LIGHT_ENERGY := 7.0
const DESK_LAMP_ENERGY := 3.2
const ALTAR_ENERGY := 2.2
const CANDLE_ENERGY := 1.5
const TUBE_EMISSION := 1.5

const DOOR_CLOSED_Y := 1.35
const DOOR_OPEN_Y := 3.45   # raised, but a visible lip remains so you see the shutter

# Altar anchor (front-left, against the front wall).
const ALTAR_X := -2.5
const ALTAR_Z := -3.62

var _pivot: Node3D
var _cam: Camera3D
var _doors := {}             # side -> Node3D
var _door_closed := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _lights := {}            # side -> SpotLight3D
var _light_on := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _lamp_mats := {}         # side -> StandardMaterial3D (visible wall fixture glow)
var _threat_sprites := {}    # side -> Sprite3D
var _threat_base_pos := {}   # side -> Vector3 (rest pose; sprites sway around it)

# Front-wall apparition: a faint shape that briefly bleeds through over the
# chalkboard for atmosphere. Purely cosmetic — no gameplay effect, no counter.
var _apparition: Sprite3D
var _appar_tex: Texture2D
var _appar_cd := 14.0        # seconds until the next flicker
var _appar_t := 0.0          # progress through the current flicker (0 = idle)
var _appar_dur := 1.6
var _appar_peak := 0.3       # max alpha of the flicker

var _ceiling: OmniLight3D
var _tube_mat: StandardMaterial3D
var _desk_lamp: SpotLight3D
var _desk_lamp_mat: StandardMaterial3D
var _altar_light: OmniLight3D
var _altar_mat: StandardMaterial3D
var _portrait_mat: StandardMaterial3D
var _candles: Array = []     # [{light, flame, mat, phase}]
var _incense_tips: Array = []  # StandardMaterial3D for the glowing stick tips
var _smoke: Array = []       # [{node, base, phase}]
var _fan: Node3D
var _hand_min: Node3D
var _hand_hr: Node3D
var _screen_mat: ShaderMaterial      # desk CRT showing cycling camera feeds
var _screen_feeds: Array = []
var _screen_idx := 0
var _screen_timer := 0.0

var _huong := 1.0            # incense-protection fraction (set by NightController)
var _altar_lit := true       # false = candles guttered out (cold-draft event)

var _yaw := 0.0
var _yaw_target := 0.0
var _pitch := 0.0
var _pitch_target := 0.0
var _look_enabled := true
var _look_locked := false     # dev: hold a fixed framing for screenshots
var _powered := true
var _pan_speed := 0.0
var _kb_dir := 0.0
var _t := 0.0
var _stutter_cd := 7.0
var _stutter_t := 0.0

func _ready() -> void:
	_build_environment()
	_build_room()
	_build_window()
	_build_chair()
	_build_props()
	_build_ceiling_fan()
	_build_doorway(GameEnums.Side.LEFT, -3.9)
	_build_doorway(GameEnums.Side.RIGHT, 3.9)
	_build_apparition()
	set_process(true)
	set_process_unhandled_input(true)
	# Dev framing hook for the screenshot harness: hold a fixed look angle.
	if OS.has_environment("NW_LOOK_YAW"):
		_look_locked = true
		_yaw_target = float(OS.get_environment("NW_LOOK_YAW"))
		_yaw = _yaw_target
		if OS.has_environment("NW_LOOK_PITCH"):
			_pitch_target = float(OS.get_environment("NW_LOOK_PITCH"))
			_pitch = _pitch_target
	if OS.has_environment("NW_LOOK_FOV"):
		_cam.fov = float(OS.get_environment("NW_LOOK_FOV"))

# --- build ------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.013, 0.022)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.2, 0.24, 0.34)
	# Darker, scarier base — the warm desk/altar islands now read against real gloom.
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.11)
	env.fog_density = 0.018
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 3.0
	# Gentle bloom so lamps/candles read as light sources without blowing out.
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_strength = 0.95
	env.glow_bloom = 0.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.25
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.9
	# Cold, contrasty night grade.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.13
	env.adjustment_saturation = 0.9
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
	_ceiling.light_color = Color(0.74, 0.8, 0.9)
	_ceiling.light_energy = CEILING_ENERGY
	_ceiling.omni_range = 14.0
	_ceiling.omni_attenuation = 1.1
	_ceiling.shadow_enabled = true
	add_child(_ceiling)
	# soft fills so the floor and corners aren't pitch black (but dimmer than before)
	for fp in [Vector3(0, 2.5, 1.8), Vector3(-2.4, 2.4, -1.5), Vector3(2.4, 2.4, -1.5)]:
		var fill := OmniLight3D.new()
		fill.position = fp
		fill.light_color = Color(0.48, 0.55, 0.7)
		fill.light_energy = 0.62
		fill.omni_range = 9.0
		add_child(fill)

	_tube_mat = StandardMaterial3D.new()
	_tube_mat.albedo_color = Color(0.9, 0.95, 1.0)
	_tube_mat.emission_enabled = true
	_tube_mat.emission = Color(0.82, 0.9, 1.0)
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

func _emat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
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

func _cyl(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D,
		parent: Node3D = null, top_radius: float = -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 16
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi

func _sphere(radius: float, pos: Vector3, mat: StandardMaterial3D, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 8
	mi.mesh = sm
	mi.material_override = mat
	mi.position = pos
	(parent if parent else self).add_child(mi)
	return mi

func _build_room() -> void:
	var wall := _mat("wall.svg", Color(0.46, 0.5, 0.47), 2.0)
	_box(Vector3(9, 0.2, 9), Vector3(0, -0.1, 0), _mat("floor.svg", Color(0.42, 0.42, 0.43), 3.0, false, 0.85))
	_box(Vector3(9, 0.2, 9), Vector3(0, 3.0, 0), _mat("ceiling.svg", Color(0.34, 0.36, 0.39), 2.0))
	# front wall (what you face) with chalkboard
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, -4.3), wall)
	# Near-white tint so the slate's own dark green + wood frame read true (a heavy
	# tint here used to wash it into a flat pale-green panel). Matte, non-metal.
	_box(Vector3(3.4, 1.8, 0.06), Vector3(0.6, 1.7, -4.18), _mat("chalkboard.svg", Color(0.96, 0.98, 0.96), 1.0, false, 0.97))
	# back wall (behind you)
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, 4.3), wall)
	# a couple of damp stains so the walls aren't flat (subtle, semi-transparent)
	var stain := StandardMaterial3D.new()
	stain.albedo_color = Color(0.04, 0.05, 0.05, 0.5)
	stain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var st1 := _box(Vector3(1.4, 1.6, 0.02), Vector3(2.7, 1.9, -4.17), stain)
	st1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var st2 := _box(Vector3(1.0, 2.0, 0.02), Vector3(-3.2, 1.4, 4.18), stain)
	st2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# desk
	_box(Vector3(3.2, 0.12, 1.2), Vector3(0, 1.0, -1.7), _mat("desk.svg", Color(0.66, 0.55, 0.4), 1.0, false, 0.7))
	_box(Vector3(3.2, 0.9, 0.1), Vector3(0, 0.5, -1.2), _mat("desk.svg", Color(0.42, 0.35, 0.27)))
	# CRT security monitor on the desk — a real-looking screen with live, cycling feeds.
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
	# A full Vietnamese ancestor shrine (bàn thờ): red-lacquer cabinet with gold trim,
	# a tiered back riser holding a framed photo + hoành phi board, a brass incense
	# burner with three glowing joss sticks and rising smoke, flanking candles, and
	# offerings (fruit tray, flower vase, tea cups). Warm light that survives a
	# blackout. set_huong()/set_altar_lit() drive the candlelight + smoke at runtime.
	var ax := ALTAR_X
	var az := ALTAR_Z
	var lacquer := _mat("", Color(0.32, 0.05, 0.04), 1.0, false, 0.45, 0.1)  # deep ox-blood red
	var lacquer_lit := _emat(Color(0.45, 0.08, 0.06), 0.35)
	var gold := _emat(Color(0.85, 0.62, 0.16), 0.7)
	var darkwood := _mat("", Color(0.16, 0.1, 0.07), 1.0, false, 0.6)
	var brass := _mat("", Color(0.7, 0.55, 0.2), 1.0, false, 0.35, 0.7)

	# lower cabinet
	_box(Vector3(1.5, 1.5, 0.9), Vector3(ax, 0.75, az), lacquer)
	# carved gold front panels + central medallion
	for px in [-0.42, 0.42]:
		var panel := _box(Vector3(0.5, 1.1, 0.04), Vector3(ax + px, 0.78, az + 0.46), lacquer_lit)
		panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var med := _sphere(0.12, Vector3(ax, 0.78, az + 0.48), gold)
	med.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# gold trim strips along the cabinet front edges
	var trim_top := _box(Vector3(1.5, 0.04, 0.04), Vector3(ax, 1.46, az + 0.46), gold)
	trim_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var trim_bot := _box(Vector3(1.5, 0.04, 0.04), Vector3(ax, 0.06, az + 0.46), gold)
	trim_bot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# red altar cloth draping the front, gold fringe at the hem
	var cloth := _box(Vector3(1.54, 0.62, 0.02), Vector3(ax, 1.2, az + 0.47), _emat(Color(0.4, 0.06, 0.05), 0.25))
	cloth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fringe := _box(Vector3(1.54, 0.05, 0.03), Vector3(ax, 0.9, az + 0.48), gold)
	fringe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# tabletop overhang
	_box(Vector3(1.64, 0.08, 1.0), Vector3(ax, 1.54, az), darkwood)
	# tiered back riser (where photo + board sit higher)
	_box(Vector3(1.5, 0.46, 0.32), Vector3(ax, 1.79, az - 0.3), lacquer)

	# framed ancestor photo
	_portrait_mat = StandardMaterial3D.new()
	var pp := ROOM_TEX + "altar_portrait.svg"
	if ResourceLoader.exists(pp):
		_portrait_mat.albedo_texture = load(pp)
	_portrait_mat.emission_enabled = true
	_portrait_mat.emission = Color(0.5, 0.46, 0.4)
	_portrait_mat.emission_energy_multiplier = 0.3   # faintly self-lit so it reads in the gloom
	_box(Vector3(0.54, 0.66, 0.06), Vector3(ax, 2.2, az - 0.42), gold)            # frame
	var portrait := MeshInstance3D.new()
	var pq := QuadMesh.new()
	pq.size = Vector2(0.44, 0.56)
	portrait.mesh = pq
	portrait.material_override = _portrait_mat
	portrait.position = Vector3(ax, 2.2, az - 0.38)
	portrait.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(portrait)
	# hoành phi (horizontal gilt board) above the photo
	var board := _box(Vector3(1.2, 0.2, 0.05), Vector3(ax, 2.62, az - 0.45), gold)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# incense burner (bát hương) with sand and three joss sticks
	_cyl(0.17, 0.18, Vector3(ax, 1.66, az + 0.15), brass)
	var sand := _cyl(0.15, 0.04, Vector3(ax, 1.76, az + 0.15), _mat("", Color(0.5, 0.42, 0.32)))
	sand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var stick_mat := _mat("", Color(0.35, 0.1, 0.08), 1.0, false, 0.7)
	for s in [Vector3(-0.05, 0, 0.02), Vector3(0.05, 0, -0.02), Vector3(0.0, 0, 0.06)]:
		var stk := _cyl(0.006, 0.5, Vector3(ax + s.x, 2.0, az + 0.15 + s.z), stick_mat)
		stk.rotation = Vector3(s.z * 1.2, 0, -s.x * 1.2)
		stk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tip_mat := _emat(Color(1.0, 0.35, 0.1), 6.0)
		_incense_tips.append(tip_mat)
		var tip := _sphere(0.013, Vector3(ax + s.x, 2.24, az + 0.15 + s.z), tip_mat)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# rising incense smoke (soft billboard puffs, animated in _process)
	if ResourceLoader.exists(ROOM_TEX + "smoke_puff.svg"):
		var smoke_tex: Texture2D = load(ROOM_TEX + "smoke_puff.svg")
		for i in 4:
			var puff := Sprite3D.new()
			puff.texture = smoke_tex
			puff.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			puff.pixel_size = 0.0032
			puff.modulate = Color(0.8, 0.8, 0.85, 0.0)
			puff.shaded = false
			var base := Vector3(ax, 2.28, az + 0.15)
			puff.position = base
			add_child(puff)
			_smoke.append({"node": puff, "base": base, "phase": float(i) * 0.85})

	# flanking candles (these are the ones a cold draft can gutter out)
	for cx in [-0.56, 0.56]:
		var stem := _cyl(0.05, 0.4, Vector3(ax + cx, 1.78, az + 0.1), _mat("", Color(0.45, 0.06, 0.05)))
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var flame_mat := _emat(Color(1.0, 0.6, 0.18), 5.0)
		var flame := _cyl(0.03, 0.11, Vector3(ax + cx, 2.04, az + 0.1), flame_mat, null, 0.001)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cl := OmniLight3D.new()
		cl.position = Vector3(ax + cx, 2.06, az + 0.2)
		cl.light_color = Color(1.0, 0.62, 0.26)
		cl.light_energy = CANDLE_ENERGY
		cl.omni_range = 2.6
		add_child(cl)
		_candles.append({"light": cl, "flame": flame, "mat": flame_mat, "phase": cx * 5.0})

	# offerings: fruit tray (ngũ quả)
	var tray := _cyl(0.22, 0.04, Vector3(ax - 0.45, 1.62, az + 0.3), brass)
	tray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fruit_cols := [Color(0.85, 0.45, 0.1), Color(0.3, 0.5, 0.15), Color(0.8, 0.7, 0.15), Color(0.6, 0.15, 0.12), Color(0.35, 0.45, 0.2)]
	var fpos := [Vector3(-0.08, 0, -0.06), Vector3(0.08, 0, -0.05), Vector3(-0.05, 0, 0.07), Vector3(0.07, 0, 0.06), Vector3(0.0, 0.06, 0.0)]
	for i in fruit_cols.size():
		_sphere(0.07, Vector3(ax - 0.45 + fpos[i].x, 1.7 + fpos[i].y, az + 0.3 + fpos[i].z), _mat("", fruit_cols[i], 1.0, false, 0.5))
	# flower vase (chrysanthemums)
	_cyl(0.07, 0.26, Vector3(ax + 0.5, 1.71, az + 0.32), _mat("", Color(0.15, 0.2, 0.3), 1.0, false, 0.3, 0.4))
	for fl in [Vector3(0, 0.16, 0), Vector3(-0.05, 0.14, 0.03), Vector3(0.05, 0.13, -0.03)]:
		_sphere(0.045, Vector3(ax + 0.5 + fl.x, 1.84 + fl.y, az + 0.32 + fl.z), _emat(Color(0.9, 0.75, 0.15), 0.4))
	# three tea cups
	for tx in [-0.18, 0.0, 0.18]:
		var cup := _cyl(0.03, 0.05, Vector3(ax + tx, 1.6, az + 0.42), _mat("", Color(0.8, 0.78, 0.7), 1.0, false, 0.4))
		cup.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# warm ember light at the heart of the altar
	_altar_mat = _emat(Color(0.55, 0.22, 0.09), 2.2)
	_altar_light = OmniLight3D.new()
	_altar_light.position = Vector3(ax, 1.95, az + 0.35)
	_altar_light.light_color = Color(1.0, 0.58, 0.22)
	_altar_light.light_energy = ALTAR_ENERGY
	_altar_light.omni_range = 4.2
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
	for ax in [-0.31, 0.31]:
		_box(Vector3(0.07, 0.09, 0.6), Vector3(sx + ax, 1.18, sz - 0.06), wood_dark)
		_box(Vector3(0.07, 0.26, 0.07), Vector3(sx + ax, 1.06, sz - 0.3), wood_dark)
	for lx in [-0.25, 0.25]:
		for lz in [sz - 0.24, sz + 0.24]:
			_box(Vector3(0.08, 0.92, 0.08), Vector3(sx + lx, 0.46, lz), wood_dark)

func _build_props() -> void:
	# Clutter that makes the office feel lived-in (and a little forsaken).
	var metal := _mat("", Color(0.3, 0.32, 0.34), 1.0, false, 0.5, 0.5)
	var metal_dark := _mat("", Color(0.18, 0.19, 0.2), 1.0, false, 0.5, 0.5)
	# filing cabinet (back-right corner)
	_box(Vector3(0.74, 1.5, 0.62), Vector3(3.0, 0.75, 3.1), metal)
	for dy in [0.35, 0.75, 1.15]:
		var drawer := _box(Vector3(0.66, 0.36, 0.04), Vector3(3.0, dy, 3.42), metal_dark)
		drawer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var handle := _box(Vector3(0.16, 0.04, 0.04), Vector3(3.0, dy, 3.45), _mat("", Color(0.1, 0.1, 0.11)))
		handle.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# a cardboard box on top
	_box(Vector3(0.5, 0.34, 0.4), Vector3(2.95, 1.67, 3.05), _mat("", Color(0.55, 0.44, 0.3), 1.0, false, 0.85))

	# wall clock on the front wall (right of the chalkboard) — hands tick in _process
	_cyl(0.28, 0.03, Vector3(3.1, 2.35, -4.18), _mat("", Color(0.1, 0.1, 0.12))).rotation = Vector3(PI / 2.0, 0, 0)
	var clock_face := _cyl(0.26, 0.05, Vector3(3.1, 2.35, -4.16), _mat("", Color(0.88, 0.88, 0.85)))
	clock_face.rotation = Vector3(PI / 2.0, 0, 0)
	clock_face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hand_mat := _mat("", Color(0.08, 0.08, 0.1))
	_hand_min = Node3D.new()
	_hand_min.position = Vector3(3.1, 2.35, -4.13)
	add_child(_hand_min)
	_box(Vector3(0.018, 0.2, 0.01), Vector3(0, 0.09, 0), hand_mat, _hand_min).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand_hr = Node3D.new()
	_hand_hr.position = Vector3(3.1, 2.35, -4.135)
	add_child(_hand_hr)
	_box(Vector3(0.022, 0.13, 0.01), Vector3(0, 0.06, 0), hand_mat, _hand_hr).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# exposed ceiling pipes
	var pipe := _mat("", Color(0.26, 0.24, 0.22), 1.0, false, 0.6, 0.4)
	var pa := _cyl(0.06, 5.0, Vector3(-3.4, 2.78, 0.0), pipe)
	pa.rotation = Vector3(PI / 2.0, 0, 0)
	var pb := _cyl(0.05, 4.2, Vector3(3.3, 2.7, 1.2), pipe)
	pb.rotation = Vector3(PI / 2.0, 0, 0)

	# mop + bucket (back-left corner)
	_cyl(0.18, 0.3, Vector3(-3.1, 0.15, 3.0), _mat("", Color(0.2, 0.35, 0.4), 1.0, false, 0.6))
	var mop := _cyl(0.025, 1.4, Vector3(-3.25, 0.7, 2.7), _mat("", Color(0.5, 0.38, 0.24)))
	mop.rotation = Vector3(0.22, 0, 0.12)
	var mophead := _sphere(0.12, Vector3(-3.1, 0.18, 3.0), _mat("", Color(0.7, 0.68, 0.55), 1.0, false, 0.9))
	mophead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# thermos + cup + clipboard on the desk
	_cyl(0.06, 0.26, Vector3(-1.15, 1.19, -1.55), _mat("", Color(0.15, 0.4, 0.25), 1.0, false, 0.4, 0.3))
	_cyl(0.04, 0.07, Vector3(-0.85, 1.1, -1.45), _mat("", Color(0.82, 0.8, 0.74)))
	var clip := _box(Vector3(0.3, 0.02, 0.42), Vector3(0.35, 1.07, -1.5), _mat("", Color(0.85, 0.83, 0.76)))
	clip.rotation = Vector3(0, 0.3, 0)
	clip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# trash bin near the desk
	_cyl(0.15, 0.4, Vector3(1.6, 0.2, -1.0), metal_dark, null, 0.17)

	# a dead potted plant in the front-right corner
	_cyl(0.16, 0.3, Vector3(3.0, 0.15, -2.9), _mat("", Color(0.4, 0.25, 0.16)))
	for st in [Vector3(0, 0.5, 0), Vector3(0.08, 0.42, 0.04), Vector3(-0.07, 0.46, -0.03)]:
		var stalk := _cyl(0.012, 0.5, Vector3(3.0 + st.x, 0.3 + st.y, -2.9 + st.z), _mat("", Color(0.25, 0.22, 0.12)))
		stalk.rotation = Vector3(st.z * 3.0, 0, -st.x * 3.0)
		stalk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_ceiling_fan() -> void:
	# Slow ceiling fan — its turning shadow rakes the room (animated in _process).
	_fan = Node3D.new()
	_fan.position = Vector3(0, 2.74, 0.7)
	add_child(_fan)
	var fan_mat := _mat("", Color(0.22, 0.2, 0.18), 1.0, false, 0.5, 0.3)
	_box(Vector3(0.08, 0.18, 0.08), Vector3(0, 0.12, 0), fan_mat, _fan)   # down-rod
	_cyl(0.14, 0.1, Vector3(0, 0, 0), fan_mat, _fan)                       # hub
	for i in 4:
		var a := deg_to_rad(90.0 * i)
		var blade := _box(Vector3(1.5, 0.02, 0.22), Vector3(cos(a) * 0.82, 0.0, sin(a) * 0.82), fan_mat, _fan)
		blade.rotation = Vector3(0, a, 0)

func _build_apparition() -> void:
	# A faint face that occasionally bleeds through the front wall, just over the
	# chalkboard. It sits flush to the wall and faces the desk; alpha is driven in
	# _process so it fades in and out. Cosmetic dread only — nothing reacts to it.
	var p := "res://assets/art/room/wall_face.svg"
	if ResourceLoader.exists(p):
		_appar_tex = load(p)
	_apparition = Sprite3D.new()
	_apparition.texture = _appar_tex
	_apparition.pixel_size = 0.0055
	_apparition.position = Vector3(0.4, 1.75, -4.12)   # on the front wall, over the board
	_apparition.modulate = Color(0.8, 0.85, 0.95, 0.0) # starts invisible
	_apparition.shaded = false                          # self-lit haze, ignores room lights
	_apparition.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_apparition)

func _update_apparition(delta: float) -> void:
	if _apparition == null or _appar_tex == null:
		return
	if _appar_t > 0.0:
		# Active flicker: fade up to the peak, hold a beat, fade back down.
		_appar_t += delta
		var f: float = _appar_t / _appar_dur
		var a := 0.0
		if f < 0.35:
			a = (f / 0.35)                       # fade in
		elif f < 0.6:
			a = 1.0                              # brief hold
		elif f < 1.0:
			a = 1.0 - (f - 0.6) / 0.4           # fade out
		else:
			_appar_t = 0.0
			# Next sighting sooner in a blackout, rarer while the lights hold.
			_appar_cd = _rng_range(20.0, 45.0) * (0.5 if not _powered else 1.0)
		# a slow drift + breathing so it never looks like a static decal
		_apparition.position.x = 0.4 + sin(_t * 0.7) * 0.25
		_apparition.modulate.a = a * _appar_peak
	else:
		_appar_cd -= delta
		if _appar_cd <= 0.0:
			_appar_t = 0.0001                   # begin a flicker next branch
			_appar_dur = _rng_range(1.2, 2.2)

func _rng_range(a: float, b: float) -> float:
	return a + (b - a) * fmod(absf(sin(_t * 12.9898) * 43758.5453), 1.0)

func _build_window() -> void:
	var frame := _mat("", Color(0.1, 0.11, 0.13), 1.0, false, 0.5, 0.4)
	_box(Vector3(2.0, 1.4, 0.08), Vector3(0, 1.9, 4.22), frame)
	var pane := StandardMaterial3D.new()
	pane.albedo_color = Color(0.16, 0.24, 0.4)
	pane.emission_enabled = true
	pane.emission = Color(0.26, 0.36, 0.56)
	pane.emission_energy_multiplier = 1.3
	var p := _box(Vector3(1.8, 1.2, 0.04), Vector3(0, 1.9, 4.18), pane)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for bx in [-0.45, 0.0, 0.45]:
		_box(Vector3(0.05, 1.2, 0.06), Vector3(bx, 1.9, 4.14), frame)
	var moon := SpotLight3D.new()
	moon.position = Vector3(0, 2.4, 3.9)
	moon.rotation = Vector3(0.35, PI, 0)
	moon.light_color = Color(0.5, 0.62, 0.88)
	moon.light_energy = 2.4
	moon.spot_range = 9.0
	moon.spot_angle = 42.0
	moon.spot_attenuation = 1.0
	moon.shadow_enabled = true
	add_child(moon)

func _build_doorway(side: int, x: float) -> void:
	var wall := _mat("wall.svg", Color(0.44, 0.49, 0.45), 2.0)
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, -2.7), wall)
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, 2.7), wall)
	_box(Vector3(0.2, 0.6, 2.6), Vector3(x, 2.7, 0), wall)
	var dir := -1.0 if side == GameEnums.Side.LEFT else 1.0
	# A long, very dark hallway that recedes into black (the doorway lamp reveals
	# the near stretch + whatever is standing in it).
	var depth := 7.0
	var cx := x + dir * (depth * 0.5)
	var hall := _mat("wall.svg", Color(0.06, 0.065, 0.075), 2.0)
	var hall_floor := _mat("floor.svg", Color(0.05, 0.05, 0.06), 2.0)
	_box(Vector3(depth, 2.8, 0.2), Vector3(cx, 1.3, -1.3), hall)
	_box(Vector3(depth, 2.8, 0.2), Vector3(cx, 1.3, 1.3), hall)
	_box(Vector3(depth, 0.2, 2.4), Vector3(cx, -0.1, 0), hall_floor)
	_box(Vector3(depth, 0.2, 2.4), Vector3(cx, 2.6, 0), hall)
	var ex := x + dir * depth
	_box(Vector3(0.2, 2.8, 5.0), Vector3(ex + dir * 0.1, 1.3, 0), _mat("", Color(0.025, 0.025, 0.03)))
	_box(Vector3(2.2, 0.2, 5.0), Vector3(ex - dir * 1.0, -0.1, 0), hall_floor)
	# threat billboard standing just OUTSIDE the door, in the corridor mouth.
	# shaded=true lets the doorway spotlight actually rim-light it, and alpha_cut
	# gives crisp edges + proper depth sorting — together they read far more 3D
	# than a flat unlit decal (our no-Meshy 2.5D pass).
	var spr := Sprite3D.new()
	spr.pixel_size = 0.007
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.shaded = true
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	spr.position = Vector3(x + dir * 0.45, 1.35, 0)
	spr.modulate = Color(0.7, 0.72, 0.72)
	spr.visible = false
	add_child(spr)
	_threat_sprites[side] = spr
	_threat_base_pos[side] = spr.position
	# roller shutter door
	var door := _box(Vector3(0.16, 2.6, 2.5), Vector3(x, DOOR_OPEN_Y, 0),
		_mat("door.svg", Color(0.55, 0.57, 0.62), 1.0, false, 0.5, 0.5))
	_doors[side] = door
	# visible wall lamp fixture beside the doorway (glows when switched on)
	var inward := -0.7 if side == GameEnums.Side.LEFT else 0.7
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(0.18, 0.18, 0.2)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.93, 0.7)
	lamp_mat.emission_energy_multiplier = 0.0
	var fixture := _box(Vector3(0.16, 0.3, 0.16), Vector3(x + inward, 2.3, 0.0), lamp_mat)
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_mats[side] = lamp_mat
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
	if _look_enabled and not _look_locked:
		_update_look_targets()
	var prev_yaw := _yaw
	_yaw = lerpf(_yaw, _yaw_target, clampf(delta * LOOK_LERP, 0, 1))
	_pitch = lerpf(_pitch, _pitch_target, clampf(delta * LOOK_LERP, 0, 1))
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = _pitch
	_pan_speed = absf(_yaw - prev_yaw) / maxf(delta, 0.0001)
	_animate_altar(delta)
	_animate_props(delta)
	_animate_mains(delta)
	_animate_screen(delta)
	_update_apparition(delta)
	_update_threat_sprites()

func _animate_altar(_delta: float) -> void:
	var lit := _altar_lit
	var glow := 0.35 + 0.65 * _huong
	# candle flicker (fire — independent of mains power)
	for c in _candles:
		var fl := 0.78 + 0.16 * sin(_t * 11.0 + c.phase) + 0.1 * sin(_t * 23.0 + c.phase)
		var light: OmniLight3D = c.light
		var flame: MeshInstance3D = c.flame
		var mat: StandardMaterial3D = c.mat
		light.light_energy = (CANDLE_ENERGY * glow * fl) if lit else 0.0
		flame.visible = lit
		if lit:
			flame.scale = Vector3(1.0, 0.82 + 0.32 * fl, 1.0)
			mat.emission_energy_multiplier = 5.0 * fl
	# ember light at the altar heart
	if _altar_light:
		var f := 0.85 + 0.1 * sin(_t * 7.3) + 0.05 * sin(_t * 19.0)
		_altar_light.light_energy = (ALTAR_ENERGY * glow * f) if lit else ALTAR_ENERGY * 0.14
	# joss-stick tips dim as the incense burns down
	for tip in _incense_tips:
		tip.emission_energy_multiplier = (6.0 * (0.4 + 0.6 * _huong)) if lit else 0.6
	# rising smoke
	for s in _smoke:
		var node: Sprite3D = s.node
		var cyc := 3.0
		var ph: float = fmod(_t + s.phase, cyc) / cyc
		node.position = s.base + Vector3(sin((_t + s.phase) * 1.3) * 0.06 * ph, ph * 0.85, 0)
		node.modulate.a = (sin(ph * PI) * 0.45 * _huong) if lit else 0.0
		node.scale = Vector3.ONE * (0.5 + ph * 1.2)

func _animate_props(delta: float) -> void:
	if _fan:
		_fan.rotation.y += delta * (0.9 if _powered else 0.15)
	if _hand_min:
		_hand_min.rotation.z = -_t * 0.5
	if _hand_hr:
		_hand_hr.rotation.z = -_t * 0.042

func _animate_mains(delta: float) -> void:
	if not _powered:
		# blackout: mains lights die out, only the altar candle remains
		_ceiling.light_energy = maxf(0.0, _ceiling.light_energy - delta * 2.5)
		if _tube_mat:
			_tube_mat.emission_energy_multiplier = maxf(0.0, _tube_mat.emission_energy_multiplier - delta * 6.0)
		return
	# powered: subtle flutter + rare hard stutter for dread
	_stutter_cd -= delta
	if _stutter_cd <= 0.0:
		_stutter_cd = randf_range(6.0, 16.0)
		_stutter_t = randf_range(0.12, 0.45)
	var base := CEILING_ENERGY * (0.96 + 0.04 * sin(_t * 9.0))
	if _stutter_t > 0.0:
		_stutter_t -= delta
		base *= 0.25 + 0.6 * randf()
	_ceiling.light_energy = base
	if _tube_mat:
		_tube_mat.emission_energy_multiplier = TUBE_EMISSION * (base / CEILING_ENERGY)

func _animate_screen(delta: float) -> void:
	if not _screen_mat:
		return
	_screen_mat.set_shader_parameter("t", _t)
	_screen_mat.set_shader_parameter("lit", 1.0 if _powered else 0.0)
	_screen_timer -= delta
	if _screen_timer <= 0.0 and not _screen_feeds.is_empty():
		_screen_timer = 2.6
		_screen_idx = (_screen_idx + 1) % _screen_feeds.size()
		_screen_mat.set_shader_parameter("feed", _screen_feeds[_screen_idx])
func _update_threat_sprites() -> void:
	# A visible threat sways/breathes around its rest pose so the billboard reads as
	# a living silhouette in the doorway, not a flat decal pinned to the wall.
	for side in _threat_sprites:
		var spr: Sprite3D = _threat_sprites[side]
		if not spr.visible:
			continue
		var base: Vector3 = _threat_base_pos[side]
		var ph: float = _t + side * 1.7
		spr.position.x = base.x + sin(ph * 1.3) * 0.035
		spr.position.y = base.y + sin(ph * 2.1) * 0.045
		var s := 1.0 + 0.025 * sin(ph * 2.7)
		spr.scale = Vector3(s, s, 1.0)

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
		yaw_mouse = (EDGE - nx) / EDGE
	elif nx > 1.0 - EDGE:
		yaw_mouse = -((nx - (1.0 - EDGE)) / EDGE)
	var pitch_mouse := 0.0
	if ny < EDGE:
		pitch_mouse = (EDGE - ny) / EDGE
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

## Incense protection 0..1 — drives candle/ember brightness + smoke density.
func set_huong(frac: float) -> void:
	_huong = clampf(frac, 0.0, 1.0)

## Candles lit vs guttered out (cold-draft event).
func set_altar_lit(lit: bool) -> void:
	_altar_lit = lit

func is_door_closed(side: int) -> bool:
	return _door_closed.get(side, false)

func set_door(side: int, closed: bool) -> void:
	if _door_closed.get(side) == closed:
		return
	_door_closed[side] = closed
	var door: Node3D = _doors[side]
	var ty := DOOR_CLOSED_Y if closed else DOOR_OPEN_Y
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
