extends Node3D
## The 2.5D guard office. Builds simple 3D geometry in code, a pannable camera
## (mouse-to-edges or pan_left/right/reset keys), two doorways with animated
## shutters + lights, and a billboard for whatever threat is at each door.
## Pure "view + look controls" — gameplay rules live in NightController.

const YAW_MAX := 1.15
const PITCH_MAX := 0.42
const LOOK_LERP := 6.0
const EDGE := 0.14            # outer screen fraction that pans the view

const ROOM_TEX := "res://assets/art/room/"

var _pivot: Node3D
var _cam: Camera3D
var _doors := {}             # side -> Node3D
var _door_closed := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _lights := {}            # side -> SpotLight3D
var _light_on := {GameEnums.Side.LEFT: false, GameEnums.Side.RIGHT: false}
var _threat_sprites := {}    # side -> Sprite3D
var _ceiling: OmniLight3D
var _altar_light: OmniLight3D

var _yaw := 0.0
var _yaw_target := 0.0
var _pitch := 0.0
var _pitch_target := 0.0
var _look_enabled := true
var _powered := true
var _pan_speed := 0.0
var _kb_dir := 0.0

const DOOR_CLOSED_Y := 1.35
const DOOR_OPEN_Y := 3.7

func _ready() -> void:
	_build_environment()
	_build_room()
	_build_doorway(GameEnums.Side.LEFT, -3.9)
	_build_doorway(GameEnums.Side.RIGHT, 3.9)
	set_process(true)
	set_process_unhandled_input(true)

# --- build ------------------------------------------------------------------
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.18, 0.22, 0.3)
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.07, 0.1)
	env.fog_density = 0.04
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	add_child(we)

	_pivot = Node3D.new()
	_pivot.position = Vector3(0, 1.6, 0.5)
	add_child(_pivot)
	_cam = Camera3D.new()
	_cam.fov = 74.0
	_cam.current = true
	_pivot.add_child(_cam)

	_ceiling = OmniLight3D.new()
	_ceiling.position = Vector3(0, 2.8, -0.5)
	_ceiling.light_color = Color(0.7, 0.78, 0.85)
	_ceiling.light_energy = 0.5
	_ceiling.omni_range = 9.0
	add_child(_ceiling)

func _mat(tex: String, tint: Color = Color.WHITE, scale: float = 1.0,
		emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var path := ROOM_TEX + tex
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
	m.albedo_color = tint
	m.roughness = 0.95
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
	_box(Vector3(9, 0.2, 9), Vector3(0, -0.1, 0), _mat("floor.svg", Color(0.5, 0.5, 0.5), 3.0))
	_box(Vector3(9, 0.2, 9), Vector3(0, 3.0, 0), _mat("ceiling.svg", Color(0.4, 0.42, 0.45), 2.0))
	# front wall (what you face) with chalkboard + altar
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, -4.3), wall)
	_box(Vector3(3.4, 1.8, 0.06), Vector3(0.4, 1.7, -4.18), _mat("chalkboard.svg", Color(0.8, 0.85, 0.8)))
	# back wall (behind you)
	_box(Vector3(9, 3.2, 0.2), Vector3(0, 1.5, 4.3), wall)
	# desk
	_box(Vector3(3.2, 0.12, 1.2), Vector3(0, 1.0, -1.7), _mat("desk.svg", Color(0.7, 0.6, 0.45), 1.0))
	_box(Vector3(3.2, 0.9, 0.1), Vector3(0, 0.5, -1.2), _mat("desk.svg", Color(0.45, 0.38, 0.3)))
	# CRT monitor prop
	_box(Vector3(0.9, 0.7, 0.6), Vector3(0.9, 1.4, -1.8), _mat("", Color(0.06, 0.07, 0.09)))
	# desk altar (amber safe zone) + warm light
	var altar := _box(Vector3(0.6, 0.5, 0.4), Vector3(-1.2, 1.35, -1.8), _mat("", Color(0.5, 0.2, 0.08), 1.0, true))
	_altar_light = OmniLight3D.new()
	_altar_light.position = Vector3(-1.2, 1.7, -1.6)
	_altar_light.light_color = Color(1.0, 0.6, 0.2)
	_altar_light.light_energy = 1.2
	_altar_light.omni_range = 3.0
	add_child(_altar_light)

func _build_doorway(side: int, x: float) -> void:
	var wall := _mat("wall.svg", Color(0.5, 0.55, 0.5), 2.0)
	# wall segments leaving a doorway gap around z=0
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, -2.7), wall)
	_box(Vector3(0.2, 3.2, 2.8), Vector3(x, 1.5, 2.7), wall)
	_box(Vector3(0.2, 0.6, 2.6), Vector3(x, 2.7, 0), wall)
	# corridor backing (dark) seen through the doorway
	var back := _box(Vector3(0.1, 2.4, 2.4), Vector3(x + (0.6 if side == GameEnums.Side.LEFT else -0.6), 1.2, 0),
		_mat("", Color(0.02, 0.025, 0.04)))
	back.visible = true
	# threat billboard in the doorway (hidden until shown)
	var spr := Sprite3D.new()
	spr.pixel_size = 0.006
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.position = Vector3(x + (0.4 if side == GameEnums.Side.LEFT else -0.4), 1.35, 0)
	spr.modulate = Color(0.7, 0.72, 0.72)
	spr.visible = false
	add_child(spr)
	_threat_sprites[side] = spr
	# roller shutter door
	var door := _box(Vector3(0.16, 2.6, 2.5), Vector3(x, DOOR_OPEN_Y, 0),
		_mat("door.svg", Color(0.6, 0.62, 0.66)))
	_doors[side] = door
	# doorway spotlight
	var sl := SpotLight3D.new()
	sl.position = Vector3(x + (1.0 if side == GameEnums.Side.LEFT else -1.0), 1.6, 0)
	sl.rotation = Vector3(0, (PI / 2.0 if side == GameEnums.Side.LEFT else -PI / 2.0), 0)
	sl.light_color = Color(1.0, 0.95, 0.8)
	sl.light_energy = 0.0
	sl.spot_range = 6.0
	sl.spot_angle = 38.0
	add_child(sl)
	_lights[side] = sl

# --- look controls ----------------------------------------------------------
func _process(delta: float) -> void:
	if _look_enabled:
		_update_look_targets()
	var prev_yaw := _yaw
	_yaw = lerpf(_yaw, _yaw_target, clampf(delta * LOOK_LERP, 0, 1))
	_pitch = lerpf(_pitch, _pitch_target, clampf(delta * LOOK_LERP, 0, 1))
	_pivot.rotation.y = _yaw
	_pivot.rotation.x = _pitch
	_pan_speed = absf(_yaw - prev_yaw) / maxf(delta, 0.0001)
	# subtle ceiling flicker when unpowered
	if not _powered:
		_ceiling.light_energy = maxf(0.0, _ceiling.light_energy - delta * 2.0)

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
		_ceiling.light_energy = 0.5
	else:
		for s in _light_on:
			set_light(s, false)

func is_door_closed(side: int) -> bool:
	return _door_closed.get(side, false)

func set_door(side: int, closed: bool) -> void:
	if _door_closed.get(side) == closed:
		return
	_door_closed[side] = closed
	var door: Node3D = _doors[side]
	var ty := DOOR_CLOSED_Y if closed else DOOR_OPEN_Y
	var tw := create_tween()
	tw.tween_property(door, "position:y", ty, 0.35).set_trans(Tween.TRANS_QUAD)
	Audio.play_sfx("door_slam" if closed else "door_creak", -4.0)
	Events.door_toggled.emit(side, closed)

func is_light_on(side: int) -> bool:
	return _light_on.get(side, false)

func set_light(side: int, on: bool) -> void:
	if _light_on.get(side) == on:
		return
	_light_on[side] = on
	(_lights[side] as SpotLight3D).light_energy = 2.2 if on else 0.0
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
