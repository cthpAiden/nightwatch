extends Control
## A self-contained animated atmospheric backdrop for menus and end screens: a deep
## night sky with a glowing moon, drifting fog, rising embers, a warm glow from below
## (the altar / incense), vignette and film grain — all in ONE canvas_item shader so
## every screen gets real horror atmosphere instead of a flat grey gradient.
##
## Spawned via UI.backdrop("menu" | "dark" | "dawn"); set `mood` before add_child().
## It ignores the mouse, so it sits harmlessly behind a screen's buttons.

var mood := "menu"
var _mat: ShaderMaterial

func _ready() -> void:
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := ColorRect.new()
	UI.full(rect)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_apply_mood(_mat)
	rect.material = _mat
	add_child(rect)

## Keep the moon round at any window aspect (the backdrop fills the screen under `expand`).
func _process(_delta: float) -> void:
	if _mat:
		var s := get_viewport_rect().size
		if s.y > 1.0:
			_mat.set_shader_parameter("screen_aspect", s.x / s.y)

## Per-mood palette: menu = cold blue night + a faint warm altar glow; dark = a
## bruised red dread for the game-over card; dawn = a warm sunrise for survival/endings.
func _apply_mood(mat: ShaderMaterial) -> void:
	match mood:
		"dark":
			mat.set_shader_parameter("sky_top", Color(0.035, 0.03, 0.04))
			mat.set_shader_parameter("sky_bot", Color(0.075, 0.025, 0.035))
			mat.set_shader_parameter("glow_col", Color(0.5, 0.09, 0.10))
			mat.set_shader_parameter("moon_amt", 0.45)
			mat.set_shader_parameter("fog_amt", 1.15)
			mat.set_shader_parameter("ember_amt", 0.4)
		"dawn":
			mat.set_shader_parameter("sky_top", Color(0.06, 0.07, 0.13))
			mat.set_shader_parameter("sky_bot", Color(0.14, 0.11, 0.10))
			mat.set_shader_parameter("glow_col", Color(0.85, 0.55, 0.28))
			mat.set_shader_parameter("moon_amt", 0.3)
			mat.set_shader_parameter("fog_amt", 0.8)
			mat.set_shader_parameter("ember_amt", 1.2)
		_:
			mat.set_shader_parameter("sky_top", Color(0.04, 0.05, 0.10))
			mat.set_shader_parameter("sky_bot", Color(0.02, 0.03, 0.055))
			mat.set_shader_parameter("glow_col", Color(0.5, 0.22, 0.10))
			mat.set_shader_parameter("moon_amt", 1.0)
			mat.set_shader_parameter("fog_amt", 1.0)
			mat.set_shader_parameter("ember_amt", 1.0)

const SHADER := """
shader_type canvas_item;
uniform vec4 sky_top = vec4(0.04, 0.05, 0.10, 1.0);
uniform vec4 sky_bot = vec4(0.02, 0.03, 0.055, 1.0);
uniform vec4 glow_col = vec4(0.5, 0.22, 0.10, 1.0);
uniform vec2 moon_pos = vec2(0.76, 0.22);
uniform float moon_amt = 1.0;
uniform float fog_amt = 1.0;
uniform float ember_amt = 1.0;
uniform float screen_aspect = 1.7778;

float hash(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p){
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
	           mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p){
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++){ v += a * noise(p); p *= 2.0; a *= 0.5; }
	return v;
}
void fragment(){
	vec2 uv = UV;
	vec3 col = mix(sky_top.rgb, sky_bot.rgb, smoothstep(0.0, 1.0, uv.y));
	// Moon: a small soft disc with a contained halo (aspect-corrected so it's round).
	vec2 ar = vec2(1.0, 1.0 / max(screen_aspect, 0.1));
	float md = distance(uv * ar, moon_pos * ar);
	float disc = smoothstep(0.066, 0.05, md);              // filled disc, soft rim
	float surf = 0.82 + 0.18 * fbm(uv * 26.0);             // faint maria so it isn't a blob
	float halo = smoothstep(0.26, 0.0, md);
	col += (vec3(0.62, 0.66, 0.63) * disc * surf + vec3(0.17, 0.21, 0.27) * halo * halo) * moon_amt;
	// Drifting fog, pooled toward the lower half of the frame.
	float t = TIME * 0.012;
	float f = fbm(uv * vec2(3.0, 2.0) + vec2(t, t * 0.3));
	f *= fbm(uv * vec2(6.0, 3.0) - vec2(t * 1.7, 0.0));
	float band = smoothstep(0.2, 1.0, uv.y);
	col += vec3(0.05, 0.06, 0.085) * f * band * fog_amt;
	// Warm glow welling up from below — the unseen altar / incense.
	float gb = smoothstep(1.0, 0.45, uv.y);
	col += glow_col.rgb * gb * gb * 0.16;
	// Rising embers / dust motes.
	for (int i = 0; i < 7; i++){
		float fi = float(i);
		float ex = fract(hash(vec2(fi, 1.0)) + sin(fi * 1.3) * 0.4);
		float spd = 0.018 + 0.014 * hash(vec2(fi, 3.0));
		float ey = fract(hash(vec2(fi, 2.0)) - TIME * spd);
		float ed = distance(uv, vec2(ex, ey));
		float e = smoothstep(0.0055, 0.0, ed);
		col += vec3(1.0, 0.62, 0.28) * e * ember_amt * (0.5 + 0.5 * sin(TIME * 3.0 + fi));
	}
	// A low, ragged tree-line / rooftop silhouette across the foot of the frame so the
	// menu reads as a place — the dark grounds of the school — not an abstract gradient.
	float ridge = 0.9 + 0.045 * fbm(vec2(uv.x * 7.0, 1.3)) + 0.02 * fbm(vec2(uv.x * 23.0, 4.0));
	col = mix(col, vec3(0.008, 0.009, 0.014), smoothstep(ridge - 0.012, ridge + 0.012, uv.y));
	// Vignette + a whisper of film grain to match the in-game grade.
	float vig = distance(uv, vec2(0.5));
	col *= 1.0 - smoothstep(0.5, 1.1, vig) * 0.7;
	float g = hash(uv * vec2(900.0, 540.0) + vec2(TIME * 53.0, TIME * 29.0));
	col += (g - 0.5) * 0.025;
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
"""
