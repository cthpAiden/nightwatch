extends Control
## Main menu. New Game -> intro -> Night 1. Continue -> highest unlocked night.

func _ready() -> void:
	UI.full(self)
	add_child(_bg("res://assets/art/intro/title_bg.svg"))
	add_child(UI.texture_rect("res://assets/art/ui/vignette.svg", TextureRect.STRETCH_SCALE))

	var title := UI.text_label(tr("GAME_TITLE"), 72, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(title, 0.5, 0, 0.5, 0, -500, 70, 500, 170)
	title.add_theme_color_override("font_shadow_color", Color(0.7, 0.15, 0.15))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	add_child(title)
	var sub := UI.label("GAME_SUBTITLE", 22, Color(0.7, 0.74, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(sub, 0.5, 0, 0.5, 0, -300, 168, 300, 200)
	add_child(sub)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -150, -40, 150, 280)
	add_child(vb)

	var cleared_any := not Save.nights_cleared.is_empty()
	_add(vb, "MENU_NEW_GAME", func(): Router.to_intro())
	var cont := _add(vb, "MENU_CONTINUE", func(): Game.start_story_night(Save.highest_unlocked))
	cont.disabled = not cleared_any
	_add(vb, "MENU_NIGHTS", func(): Router.change_scene("res://scenes/screens/NightSelect.tscn"))
	var custom := _add(vb, "MENU_CUSTOM_NIGHT", func(): _start_custom())
	custom.disabled = not Save.nights_cleared.has(6)
	if custom.disabled:
		custom.text = "MENU_CUSTOM_NIGHT"
		custom.tooltip_text = tr("MENU_LOCKED")
	_add(vb, "MENU_SETTINGS", func(): Router.change_scene("res://scenes/screens/SettingsMenu.tscn"))
	_add(vb, "MENU_QUIT", func(): get_tree().quit())

	Audio.play_music("ambience_night")

func _bg(path: String) -> TextureRect:
	var t := UI.texture_rect(path, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(t)
	return t

func _add(vb: VBoxContainer, key: String, cb: Callable) -> Button:
	var b := UI.button(key, 300, 52)
	b.pressed.connect(func():
		Audio.play_sfx("ui_click", -6.0)
		cb.call())
	vb.add_child(b)
	return b

func _start_custom() -> void:
	# default custom-night preset: every threat at a moderate level
	var levels := {}
	for id in ThreatRegistry.ids():
		if id == "ba_hang_rong":
			continue
		levels[id] = 7
	Game.start_custom_night(levels)
