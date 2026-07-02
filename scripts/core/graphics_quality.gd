extends Node
## Runtime graphics-quality applier (autoload "Graphics").
##
## Rooms author their own Environment mood values (background, fog colour, ambient),
## and we deliberately do NOT centralise those. Instead this overlays the preset's
## PERFORMANCE knobs on top of whatever a scene shipped — SSAO/glow/volumetrics on the
## Environment, render-scale/AA/shadow-atlas on the Viewport — so quality and FPS are
## tuned globally without editing 10 duplicated Environment resources.
##
## Read Settings.graphics_quality (0=Low,1=Medium,2=High). Whoever owns a live
## Environment or Viewport calls the apply_* helpers at mount time and again on
## Events.settings_changed so a mid-session preset switch takes effect without a reload.
## Low is the integrated-GPU floor: no GI, no volumetrics, render at 70% + FSR2.

enum { LOW, MEDIUM, HIGH }

func quality() -> int:
	return clampi(Settings.graphics_quality, LOW, HIGH)

## Overlay preset knobs onto a LIVE (already-instanced) Environment. Leaves the
## room's authored mood values (colours, fog density, tonemap, grade) untouched.
func apply_to_env(env: Environment, _ctx := "") -> void:
	if env == null:
		return
	var q := quality()
	# SSAO + glow are full-screen passes — the cheapest big win to drop on Low.
	env.ssao_enabled = q >= MEDIUM
	env.glow_enabled = q >= MEDIUM
	# Volumetric fog is High-only atmosphere; the authored DEPTH fog stays on at all tiers.
	env.volumetric_fog_enabled = q >= HIGH
	if q >= HIGH:
		env.volumetric_fog_density = 0.02
		env.volumetric_fog_albedo = Color(0.55, 0.62, 0.75)
		env.volumetric_fog_length = 48.0
		env.volumetric_fog_gi_inject = 0.0
	# Real-time GI stays opt-in even on High (the integrated-GPU floor rules it out by default).
	env.sdfgi_enabled = q >= HIGH and Settings.sdfgi_enabled

## Overlay preset knobs onto a Viewport. `is_root` = the main window viewport (gets
## render-scaling, TAA and the positional-shadow atlas); false = a CCTV/CRT SubViewport
## (AA only — those feeds are small and carry their own CCTV grain, so TAA would just smear).
func apply_to_viewport(vp: Viewport, is_root: bool) -> void:
	if vp == null:
		return
	var q := quality()
	if is_root:
		# Render-scaling is the primary Low lever: draw 3D at 70% and FSR2-upscale to native.
		if q == LOW:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			vp.scaling_3d_scale = 0.7
		else:
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = 1.0
		vp.use_taa = q == HIGH
		# Positional (omni/spot) shadow atlas: the office runs 8-10 shadow-casters at once.
		vp.positional_shadow_atlas_size = [2048, 4096, 8192][q]
		# Root AA: FXAA is cheap cover for the upscaled Low image; TAA does the smoothing on High.
		match q:
			LOW: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
			_: vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.msaa_3d = Viewport.MSAA_DISABLED if q == LOW else Viewport.MSAA_2X

## Shadow-caster budget for a scene's lights. Positional (omni/spot) shadows are the
## expensive ones — a room/office can run several at once — so they're dropped below
## Medium; the single directional moon cascade is cheap and kept at every tier. The
## light's ORIGINAL shadow flag is stashed in meta on first pass so a live preset switch
## restores exactly what the scene authored (we never enable a light the scene left dark).
func apply_to_lights(root: Node) -> void:
	if root == null:
		return
	var q := quality()
	for light in _lights_under(root):
		if not light.has_meta("nw_shadow"):
			light.set_meta("nw_shadow", light.shadow_enabled)
		var authored: bool = light.get_meta("nw_shadow")
		if light is DirectionalLight3D:
			light.shadow_enabled = authored
		else:
			light.shadow_enabled = authored and q >= MEDIUM

func _lights_under(node: Node, out: Array = []) -> Array:
	for child in node.get_children():
		if child is Light3D:
			out.append(child)
		if child.get_child_count() > 0:
			_lights_under(child, out)
	return out

## CCTV feed render resolution — half-res on Low so 9 idle rooms + 1 live feed stay cheap.
func cctv_viewport_size() -> Vector2i:
	return Vector2i(640, 360) if quality() == LOW else Vector2i(960, 540)

## Desk-CRT feed resolution (already a quarter of the monitor); drop further on Low.
func crt_viewport_size() -> Vector2i:
	return Vector2i(320, 180) if quality() == LOW else Vector2i(480, 270)
