class_name UI
## Small factory helpers for building Control UIs in code. Labels/Buttons set their
## .text to a STRING KEY and rely on Godot's automatic translation (the theme +
## strings.csv do the rest), so they update live when the locale changes.

const COL_TEXT := Color(0.88, 0.9, 0.85)
const COL_DIM := Color(0.6, 0.66, 0.62)
const COL_WARN := Color(0.95, 0.7, 0.25)
const COL_DANGER := Color(0.82, 0.2, 0.2)
const COL_GHOST := Color(0.81, 0.84, 0.81)

static func full(c: Control) -> Control:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c

static func place(c: Control, al: float, at: float, ar: float, ab: float,
		ol: float, ot: float, orr: float, ob: float) -> Control:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob
	return c

static func label(key: String = "", size: int = 20, color: Color = COL_TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = key
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l

## A label whose text is set literally (already-translated / formatted), not a key.
static func text_label(value: String, size: int = 20, color: Color = COL_TEXT,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label("", size, color, align)
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.text = value
	return l

static func button(key: String, min_w: float = 240.0, min_h: float = 52.0) -> Button:
	var b := Button.new()
	b.text = key
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_ALL
	return b

static func icon_button(tex_path: String, size: float = 84.0) -> TextureButton:
	var b := TextureButton.new()
	if ResourceLoader.exists(tex_path):
		b.texture_normal = load(tex_path)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	b.custom_minimum_size = Vector2(size, size)
	return b

static func texture_rect(path: String, stretch: int = TextureRect.STRETCH_KEEP_ASPECT_COVERED) -> TextureRect:
	var t := TextureRect.new()
	if ResourceLoader.exists(path):
		t.texture = load(path)
	t.stretch_mode = stretch
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func color_rect(color: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func panel() -> PanelContainer:
	return PanelContainer.new()

static func vbox(sep: int = 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h

static func progress(maxv: float, fill: Color) -> ProgressBar:
	var p := ProgressBar.new()
	p.max_value = maxv
	p.value = maxv
	p.show_percentage = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(5)
	p.add_theme_stylebox_override("fill", sb)
	return p

static func center(c: Control) -> CenterContainer:
	var cc := CenterContainer.new()
	full(cc)
	cc.add_child(c)
	return cc

## An animated atmospheric night backdrop for any screen (moon, fog, embers, vignette).
## mood: "menu" (cold night), "dark" (game-over red), "dawn" (survival/ending warmth).
static func backdrop(mood: String = "menu") -> Control:
	var b: Control = load("res://scripts/ui/menu_backdrop.gd").new()
	b.mood = mood
	return b
