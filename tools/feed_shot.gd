extends Node
## Dev-only screenshot harness for the 3D camera feed. Renders Classroom.tscn into a
## SubViewport and pipes it through a copy of camera_system.gd's CCTV shader, so the PNG
## shows what the classroom cam looks like in-game. Run via tools/FeedShot.tscn.
## Env: NW_SHOT_OUT (png path), optional NW_SHOT_DELAY.

const SHADER := """
shader_type canvas_item;
uniform float strength = 0.10;
uniform float glitch = 0.0;
uniform float rect_aspect = 1.7778;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	vec2 guv = UV;
	guv.x += (rand(vec2(floor(UV.y * 120.0), floor(TIME * 18.0))) - 0.5) * glitch * 0.04;
	vec2 fuv = guv;
	float r = rect_aspect / 1.7778;
	if (r > 1.0) fuv.y = (fuv.y - 0.5) / r + 0.5;
	else fuv.x = (fuv.x - 0.5) * r + 0.5;
	vec4 src = texture(TEXTURE, fuv);
	vec3 c = src.rgb;
	c = (c - 0.5) * 1.16 + 0.5;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, 1.5);
	c *= vec3(0.93, 1.05, 1.01);
	c += vec3(0.015, 0.024, 0.022);
	float n = rand(UV * vec2(900.0, 540.0) + vec2(TIME * 41.0, TIME * 13.0));
	c += (n - 0.5) * (strength + glitch * 0.12);
	c -= (sin(UV.y * 720.0) * 0.5 + 0.5) * strength * 0.10;
	float roll = fract(UV.y - TIME * glitch);
	c *= 1.0 - smoothstep(0.0, 0.14, roll) * (1.0 - smoothstep(0.14, 0.28, roll)) * glitch * 0.6;
	float vig = distance(UV, vec2(0.5));
	c *= 1.0 - smoothstep(0.6, 1.05, vig) * 0.5;
	COLOR = vec4(clamp(c, 0.0, 1.0), src.a);
}
"""

func _ready() -> void:
	var out_path := OS.get_environment("NW_SHOT_OUT")
	if out_path == "":
		get_tree().quit()
		return
	var room := OS.get_environment("NW_SHOT_ROOM")
	if room == "":
		room = "res://scenes/rooms/Classroom.tscn"

	var vp := SubViewport.new()
	vp.size = Vector2i(960, 540)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.add_child(load(room).instantiate())
	add_child(vp)

	var feed := TextureRect.new()
	feed.texture = vp.get_texture()
	feed.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	feed.stretch_mode = TextureRect.STRETCH_SCALE
	feed.set_anchors_preset(Control.PRESET_FULL_RECT)
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	mat.set_shader_parameter("strength", 0.06)
	feed.material = mat
	get_tree().root.add_child.call_deferred(feed)

	var delay := 1.6
	if OS.has_environment("NW_SHOT_DELAY"):
		delay = float(OS.get_environment("NW_SHOT_DELAY"))
	await get_tree().create_timer(delay).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	await get_tree().process_frame
	get_tree().quit()
