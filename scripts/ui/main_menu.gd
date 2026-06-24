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

	var vb := UI.vbox(9)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -160, -150, 160, 330)
	add_child(vb)

	var cleared_any := not Save.nights_cleared.is_empty()
	_add(vb, "MENU_NEW_GAME", func(): Router.to_intro())
	var cont := _add(vb, "MENU_CONTINUE", func(): Game.start_story_night(Save.highest_unlocked))
	cont.disabled = not cleared_any
	_add(vb, "MENU_NIGHTS", func(): Router.change_scene("res://scenes/screens/NightSelect.tscn"))
	_add(vb, "MENU_SHRINE", func(): Router.change_scene("res://scenes/screens/ShrineScreen.tscn"))
	var custom := _add(vb, "MENU_CUSTOM_NIGHT", func(): Router.change_scene("res://scenes/screens/CustomNightScreen.tscn"))
	custom.disabled = not Save.nights_cleared.has(6)
	if custom.disabled:
		custom.tooltip_text = tr("MENU_LOCKED")
	_add(vb, "MENU_EXTRAS", func(): Router.change_scene("res://scenes/screens/ExtrasScreen.tscn"))
	_add(vb, "MENU_SETTINGS", func(): Router.change_scene("res://scenes/screens/SettingsMenu.tscn"))
	_add(vb, "MENU_QUIT", func(): get_tree().quit())

	# Version stamp (dim, bottom-right) — sourced from project settings.
	var ver := "v" + str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
	var ver_lbl := UI.text_label(ver, 14, Color(0.5, 0.55, 0.52), HORIZONTAL_ALIGNMENT_RIGHT)
	UI.place(ver_lbl, 1, 1, 1, 1, -160, -34, -16, -12)
	add_child(ver_lbl)

	Audio.play_music("ambience_night")

	# First launch ever: let the (possibly non-Vietnamese) player choose a language
	# before they land on an all-Vietnamese menu.
	if Settings.first_run:
		_show_lang_picker()

func _show_lang_picker() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	var dim := UI.color_rect(Color(0, 0, 0, 0.84))
	UI.full(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(dim)
	var vb := UI.vbox(16)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -200, -120, 200, 120)
	layer.add_child(vb)
	vb.add_child(UI.text_label(tr("LANG_CHOOSE"), 26, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))
	var vi := UI.button("", 300, 54)
	vi.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	vi.text = "Tiếng Việt"
	vi.pressed.connect(func(): _pick_lang("vi"))
	vb.add_child(vi)
	var en := UI.button("", 300, 54)
	en.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	en.text = "English"
	en.pressed.connect(func(): _pick_lang("en"))
	vb.add_child(en)
	vi.grab_focus()   # keyboard/gamepad lands on the picker, not a hidden menu button

func _pick_lang(code: String) -> void:
	Audio.play_sfx("ui_confirm", -4.0)
	Settings.apply({"language": code, "first_run": false})
	get_tree().reload_current_scene()

func _bg(path: String) -> TextureRect:
	var t := UI.texture_rect(path, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(t)
	return t

func _add(vb: VBoxContainer, key: String, cb: Callable) -> Button:
	var b := UI.button(key, 300, 46)
	b.pressed.connect(func():
		# The menu is inert until the first-run language picker is dismissed, so a
		# keyboard/gamepad player can't tab to a button behind the modal.
		if Settings.first_run:
			return
		Audio.play_sfx("ui_click", -6.0)
		cb.call())
	vb.add_child(b)
	return b
