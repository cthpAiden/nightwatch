extends Control
## Night picker. Unlocked nights playable; the rest are locked.

func _ready() -> void:
	UI.full(self)
	add_child(UI.texture_rect("res://assets/art/intro/title_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED))
	UI.full(get_child(0))
	add_child(UI.color_rect(Color(0, 0, 0, 0.55)))
	UI.full(get_child(1))

	var vb := UI.vbox(14)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -240, -240, 240, 260)
	add_child(vb)
	vb.add_child(UI.label("MENU_NIGHTS", 40, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for n in range(1, Game.MAX_NIGHTS + 1):
		var b := UI.button("", 150, 64)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var unlocked := Save.is_night_unlocked(n)
		if unlocked:
			b.text = tr("NIGHT_LABEL").format([str(n)])
			b.pressed.connect(func(): Game.start_story_night(n))
		else:
			b.text = "🔒 " + tr("NIGHT_LABEL").format([str(n)])
			b.disabled = true
		grid.add_child(b)

	var back := UI.button("SET_BACK", 220, 48)
	back.pressed.connect(func(): Router.to_main_menu())
	vb.add_child(back)
