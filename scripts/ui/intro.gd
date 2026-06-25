extends Control
## Opening cutscene: lines fade in over the school gate, then Night 1 begins.

const LINES := ["INTRO_L1", "INTRO_L2", "INTRO_L3", "INTRO_L4"]
var _index := 0
var _label: Label
var _prompt: Label
var _done := false

func _ready() -> void:
	UI.full(self)
	# Animated base layer so the intro breathes like the menus, with the static
	# gate art (and its vignette) sitting on top.
	add_child(UI.backdrop("menu"))
	var bg := UI.texture_rect("res://assets/art/intro/intro_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)
	add_child(UI.texture_rect("res://assets/art/ui/vignette.svg", TextureRect.STRETCH_SCALE))
	_label = UI.text_label("", 30, Color(0.9, 0.9, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	UI.place(_label, 0.5, 0.5, 0.5, 0.5, -460, -60, 460, 120)
	add_child(_label)
	_prompt = UI.label("PROMPT_ANY_KEY", 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(_prompt, 0.5, 1, 0.5, 1, -300, -80, 300, -40)
	_prompt.visible = false
	add_child(_prompt)
	Audio.play_music("ambience_dread")
	_next()

func _next() -> void:
	if _index >= LINES.size():
		_prompt.visible = true
		_done = true
		return
	_label.text = tr(LINES[_index])
	_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_label, "modulate:a", 1.0, 1.0)
	tw.tween_interval(1.8)
	tw.tween_callback(func():
		_index += 1
		_next())

func _unhandled_input(e: InputEvent) -> void:
	if (e is InputEventKey or e is InputEventMouseButton) and e.is_pressed():
		if _done:
			Game.start_story_night(1)
		else:
			# skip straight to the prompt
			_index = LINES.size()
			_label.text = tr(LINES[LINES.size() - 1])
			_prompt.visible = true
			_done = true
