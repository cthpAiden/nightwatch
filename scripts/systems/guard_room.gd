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
var _altar_flames: Array = []     # candle/incense emissive mats, flicker with the light
var _screen_mat: ShaderMaterial      # desk CRT showing cycling camera feeds
var _screen_feeds: Array = []
var _screen_idx := 0
var _screen_timer := 0.0

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

func _ready() -> void:
	_build_environment()
	_build_room()
	_build_window()
	_build_chair()
	_build_doorway(GameEnums.Side.LEFT, -3.9)
	_build_doorway(GameEnums.Side.RIGHT, 3.9)
	_build_props()
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
	# a gentle wash on the upper front wall so the chalkboard / clock / calendar read
	# as intentional decor instead of vanishing into black (kept dim for mood)
	var wall_wash := OmniLight3D.new()
	wall_wash.position = Vector3(0, 2.5, -3.0)
	wall_wash.light_color = Color(0.5, 0.56, 0.68)
	wall_wash.light_energy = 0.7
	wall_wash.omni_range = 7.5
	add_child(wall_wash)

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

func _cyl(radius: float, height: float, pos: Vector3, mat: StandardMaterial3D,
		top_radius: float = -1.0, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_radius < 0.0 else top_radius
	cm.height = height
	cm.radial_segments = 18
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
	sm.radial_segments = 16
	sm.rings = 10
	mi.mesh = sm
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
	# Vietnamese ancestor altar / bàn thờ (the amber "safe zone"): a red-lacquered
	# shrine sitting on the desk's left end — gold-trimmed cabinet, raised backboard
	# with a gilt medallion, a brass incense burner with glowing joss sticks, two red
	# candles, a fruit offering plate and a flower vase. Its warm candle/ember light
	# survives a blackout, so it stays the one warm island when the mains die.
	var cx := -1.2
	var bz := -1.84               # altar back-to-front anchor (back wall side)
	var top := 1.52               # cabinet top surface height

	# --- materials ---
	var lacquer := _mat("", Color(0.46, 0.07, 0.06), 1.0, false, 0.32, 0.1)  # red lacquer
	_altar_mat = lacquer
	var gold := _mat("", Color(0.83, 0.66, 0.24), 1.0, false, 0.3, 0.9)
	gold.emission_enabled = true
	gold.emission = Color(0.7, 0.52, 0.16)
	gold.emission_energy_multiplier = 0.28      # faint glint even in the dark
	var darkwood := _mat("", Color(0.2, 0.12, 0.07), 1.0, false, 0.55)
	var brass := _mat("", Color(0.58, 0.43, 0.18), 1.0, false, 0.34, 0.85)
	var ash := _mat("", Color(0.62, 0.55, 0.46), 1.0, false, 1.0)
	var stick := _mat("", Color(0.45, 0.18, 0.12), 1.0, false, 0.9)
	var porcelain := _mat("", Color(0.86, 0.84, 0.8), 1.0, false, 0.35, 0.05)
	var vase_mat := _mat("", Color(0.74, 0.8, 0.88), 1.0, false, 0.28, 0.05)

	# --- cabinet body + gold trim ---
	_box(Vector3(0.84, 0.46, 0.44), Vector3(cx, 1.29, bz), lacquer)          # body
	_box(Vector3(0.9, 0.05, 0.5), Vector3(cx, top, bz), darkwood)            # top slab
	_box(Vector3(0.9, 0.06, 0.5), Vector3(cx, 1.07, bz), darkwood)           # base plinth
	_box(Vector3(0.86, 0.03, 0.46), Vector3(cx, 1.5, bz), gold)              # upper gold lip
	_box(Vector3(0.86, 0.03, 0.46), Vector3(cx, 1.11, bz), gold)             # lower gold lip
	for px in [-0.27, 0.0, 0.27]:                                            # gold panel dividers
		_box(Vector3(0.03, 0.36, 0.02), Vector3(cx + px, 1.29, bz + 0.22), gold)

	# --- backboard with gilt medallion ---
	_box(Vector3(0.78, 0.56, 0.04), Vector3(cx, 1.82, bz - 0.2), lacquer)
	_box(Vector3(0.82, 0.05, 0.05), Vector3(cx, 2.1, bz - 0.2), gold)        # crown rail
	var medallion := _cyl(0.13, 0.02, Vector3(cx, 1.82, bz - 0.17), gold)
	medallion.rotation = Vector3(PI / 2.0, 0, 0)
	medallion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere(0.05, Vector3(cx, 1.82, bz - 0.15), brass).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- brass incense burner (bát hương) with glowing joss sticks ---
	var burn_y := top + 0.1
	_cyl(0.13, 0.05, Vector3(cx, top + 0.05, bz + 0.05), brass)              # foot
	_cyl(0.12, 0.13, Vector3(cx, burn_y, bz + 0.05), brass, 0.14)            # bowl
	_cyl(0.1, 0.03, Vector3(cx, burn_y + 0.07, bz + 0.05), ash)             # ash bed
	for i in 3:
		var sx: float = cx + (i - 1) * 0.045
		var lean: float = (i - 1) * 0.05
		var st := _cyl(0.006, 0.34, Vector3(sx, burn_y + 0.24, bz + 0.05 + lean * 0.3), stick)
		st.rotation = Vector3(lean, 0, (i - 1) * -0.04)
		st.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ember := StandardMaterial3D.new()
		ember.albedo_color = Color(1.0, 0.4, 0.12)
		ember.emission_enabled = true
		ember.emission = Color(1.0, 0.35, 0.1)
		ember.emission_energy_multiplier = 5.0
		var tip := _sphere(0.013, Vector3(sx + sin(lean) * 0.17, burn_y + 0.41, bz + 0.05 + lean * 0.3), ember)
		tip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_altar_flames.append(ember)

	# --- two red candles flanking the burner ---
	for dx in [-0.3, 0.3]:
		var wax := _mat("", Color(0.66, 0.11, 0.09), 1.0, false, 0.5)
		_cyl(0.025, 0.02, Vector3(cx + dx, top + 0.04, bz - 0.02), gold)     # holder
		_cyl(0.022, 0.16, Vector3(cx + dx, top + 0.12, bz - 0.02), wax)      # candle
		var flame_mat := StandardMaterial3D.new()
		flame_mat.albedo_color = Color(1.0, 0.75, 0.35)
		flame_mat.emission_enabled = true
		flame_mat.emission = Color(1.0, 0.66, 0.28)
		flame_mat.emission_energy_multiplier = 4.5
		var fl := _sphere(0.028, Vector3(cx + dx, top + 0.23, bz - 0.02), flame_mat)
		fl.scale = Vector3(1, 1.7, 1)
		fl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_altar_flames.append(flame_mat)

	# --- fruit offering plate (mâm) ---
	_cyl(0.13, 0.025, Vector3(cx + 0.22, top + 0.04, bz + 0.18), porcelain)
	var fruit_cols := [Color(0.86, 0.46, 0.1), Color(0.3, 0.55, 0.18), Color(0.86, 0.72, 0.15), Color(0.72, 0.13, 0.1)]
	var fpos := [Vector2(-0.05, -0.03), Vector2(0.05, -0.03), Vector2(0.0, 0.05), Vector2(0.0, 0.0)]
	for i in 4:
		var fm := _mat("", fruit_cols[i], 1.0, false, 0.5)
		var fr := _sphere(0.038 if i == 3 else 0.032, Vector3(cx + 0.22 + fpos[i].x, top + 0.08 + (0.02 if i == 3 else 0.0), bz + 0.18 + fpos[i].y), fm)
		fr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- flower vase (lọ hoa) ---
	_cyl(0.045, 0.05, Vector3(cx - 0.26, top + 0.05, bz + 0.16), vase_mat, 0.035)  # foot
	_cyl(0.05, 0.18, Vector3(cx - 0.26, top + 0.15, bz + 0.16), vase_mat, 0.04)    # body
	for a in [Vector2(-0.05, 0.04), Vector2(0.05, 0.03), Vector2(0.0, -0.04)]:
		var stem := _cyl(0.005, 0.14, Vector3(cx - 0.26 + a.x, top + 0.3, bz + 0.16 + a.y), _mat("", Color(0.25, 0.45, 0.2), 1.0, false, 0.8))
		stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var bloom := _mat("", Color(0.92, 0.62, 0.16), 1.0, false, 0.5)
		_sphere(0.03, Vector3(cx - 0.26 + a.x, top + 0.38, bz + 0.16 + a.y), bloom).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# --- warm altar light (the blackout-proof island) ---
	_altar_light = OmniLight3D.new()
	_altar_light.position = Vector3(cx, top + 0.28, bz + 0.2)
	_altar_light.light_color = Color(1.0, 0.62, 0.24)
	_altar_light.light_energy = ALTAR_ENERGY
	_altar_light.omni_range = 3.8
	_altar_light.omni_attenuation = 1.3
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
	# a worn red seat cushion + a lumbar pad so the long shift looks a little comfier
	var cushion := _mat("", Color(0.46, 0.13, 0.12), 1.0, false, 0.92)
	_box(Vector3(0.5, 0.07, 0.48), Vector3(sx, 1.02, sz), cushion)
	_box(Vector3(0.5, 0.26, 0.06), Vector3(sx, 1.18, sz + 0.27), cushion)
	# arm rests (extend forward so they frame the bottom of your view)
	for ax in [-0.31, 0.31]:
		_box(Vector3(0.07, 0.09, 0.6), Vector3(sx + ax, 1.18, sz - 0.06), wood_dark)
		_box(Vector3(0.07, 0.26, 0.07), Vector3(sx + ax, 1.06, sz - 0.3), wood_dark)
	# four legs
	for lx in [-0.25, 0.25]:
		for lz in [sz - 0.24, sz + 0.24]:
			_box(Vector3(0.08, 0.92, 0.08), Vector3(sx + lx, 0.46, lz), wood_dark)

func _build_props() -> void:
	# Lived-in clutter so the booth reads as a real night-guard's post, not an empty
	# stage. Everything here is decorative; nothing is referenced by gameplay.
	var dy := 1.07     # desk surface top

	# --- floor mat under the desk/feet ---
	var rug := _mat("", Color(0.34, 0.1, 0.1), 1.0, false, 1.0)
	var rug_b := _mat("", Color(0.5, 0.16, 0.13), 1.0, false, 1.0)
	_box(Vector3(2.2, 0.02, 1.9), Vector3(0, 0.012, -0.1), rug_b)
	_box(Vector3(1.9, 0.03, 1.6), Vector3(0, 0.02, -0.1), rug)

	# --- logbook + pen (front-center of desk) ---
	_box(Vector3(0.34, 0.04, 0.24), Vector3(-0.05, dy + 0.02, -1.34), _mat("", Color(0.22, 0.26, 0.36), 1.0, false, 0.7))
	_box(Vector3(0.3, 0.02, 0.2), Vector3(-0.02, dy + 0.05, -1.34), _mat("", Color(0.85, 0.82, 0.72), 1.0, false, 0.9))
	var pen := _box(Vector3(0.15, 0.012, 0.012), Vector3(0.02, dy + 0.07, -1.3), _mat("", Color(0.1, 0.14, 0.4), 1.0, false, 0.4, 0.3))
	pen.rotation.y = 0.5

	# --- thermos + cup (the guard's tea) ---
	var cream := _mat("", Color(0.88, 0.85, 0.78), 1.0, false, 0.45)
	var red_lid := _mat("", Color(0.7, 0.13, 0.11), 1.0, false, 0.4)
	_cyl(0.065, 0.26, Vector3(0.5, dy + 0.13, -1.4), cream)
	_cyl(0.05, 0.06, Vector3(0.5, dy + 0.29, -1.4), red_lid)
	_box(Vector3(0.13, 0.04, 0.13), Vector3(0.5, dy + 0.17, -1.4), red_lid)   # red waist band
	_cyl(0.036, 0.07, Vector3(0.72, dy + 0.045, -1.3), cream)                 # cup

	# --- small desk fan (off) facing the guard ---
	var plastic := _mat("", Color(0.16, 0.17, 0.19), 1.0, false, 0.5)
	var cage := _mat("", Color(0.55, 0.57, 0.6), 1.0, false, 0.4, 0.6)
	_box(Vector3(0.22, 0.03, 0.16), Vector3(-0.62, dy + 0.02, -1.28), plastic)   # base
	_box(Vector3(0.04, 0.2, 0.04), Vector3(-0.62, dy + 0.12, -1.32), plastic)    # neck
	var head := _cyl(0.13, 0.05, Vector3(-0.62, dy + 0.26, -1.26), cage)         # cage ring
	head.rotation.x = PI / 2.0
	var hub := _cyl(0.04, 0.06, Vector3(-0.62, dy + 0.26, -1.27), plastic)
	hub.rotation.x = PI / 2.0
	for i in 3:
		var blade := _box(Vector3(0.02, 0.16, 0.02), Vector3(-0.62, dy + 0.26, -1.25), plastic)
		blade.rotation.z = i * (TAU / 3.0)

	# --- flashlight lying on the desk ---
	var torch := _cyl(0.026, 0.2, Vector3(0.28, dy + 0.03, -1.22), _mat("", Color(0.12, 0.12, 0.13), 1.0, false, 0.4, 0.5))
	torch.rotation.z = PI / 2.0
	var torch_head := _cyl(0.032, 0.05, Vector3(0.39, dy + 0.03, -1.22), _mat("", Color(0.7, 0.6, 0.2), 1.0, false, 0.3, 0.6))
	torch_head.rotation.z = PI / 2.0

	# --- wall clock (front wall, right of the chalkboard) ---
	var clock_rim := _mat("", Color(0.12, 0.12, 0.14), 1.0, false, 0.5, 0.3)
	var clock_face := _mat("", Color(0.9, 0.9, 0.85), 1.0, false, 0.6)
	var cf := _cyl(0.26, 0.05, Vector3(3.0, 2.25, -4.16), clock_rim)
	cf.rotation.x = PI / 2.0
	var face := _cyl(0.22, 0.02, Vector3(3.0, 2.25, -4.12), clock_face)
	face.rotation.x = PI / 2.0
	var hh := _box(Vector3(0.025, 0.13, 0.012), Vector3(3.0, 2.27, -4.1), clock_rim)   # hour hand
	hh.rotation.z = -0.6
	var mh := _box(Vector3(0.018, 0.19, 0.012), Vector3(3.0, 2.26, -4.1), clock_rim)   # minute hand
	mh.rotation.z = 1.4

	# --- paper wall calendar (front wall, left of the chalkboard) ---
	_box(Vector3(0.46, 0.66, 0.03), Vector3(-2.9, 1.95, -4.17), _mat("", Color(0.75, 0.2, 0.16), 1.0, false, 0.85))
	_box(Vector3(0.4, 0.46, 0.02), Vector3(-2.9, 1.82, -4.15), _mat("", Color(0.92, 0.9, 0.84), 1.0, false, 0.9))
	_box(Vector3(0.4, 0.12, 0.02), Vector3(-2.9, 2.12, -4.15), _mat("", Color(0.85, 0.7, 0.2), 1.0, false, 0.8))

	# --- baseboards along the front + back walls for grounding ---
	var base := _mat("", Color(0.16, 0.15, 0.17), 1.0, false, 0.7)
	_box(Vector3(9, 0.2, 0.06), Vector3(0, 0.1, -4.18), base)
	_box(Vector3(9, 0.2, 0.06), Vector3(0, 0.1, 4.18), base)

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
	# a sill ledge + a soft moon disc behind the pane for depth
	_box(Vector3(2.2, 0.08, 0.22), Vector3(0, 1.18, 4.12), frame)
	var moon_mat := StandardMaterial3D.new()
	moon_mat.albedo_color = Color(0.85, 0.9, 1.0)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.7, 0.8, 1.0)
	moon_mat.emission_energy_multiplier = 2.2
	var disc := _sphere(0.34, Vector3(0.5, 2.25, 4.7), moon_mat)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	if _look_enabled and not _look_locked:
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
		# the flames/embers breathe with the light so the shrine feels alive
		for i in _altar_flames.size():
			var m: StandardMaterial3D = _altar_flames[i]
			var base: float = 5.0 if i < 3 else 4.5
			m.emission_energy_multiplier = base * (0.8 + 0.25 * sin(_t * 8.0 + i * 1.7))
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
