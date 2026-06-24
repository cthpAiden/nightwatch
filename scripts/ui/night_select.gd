extends Control
## Night picker. Unlocked nights playable; the rest are locked.

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	add_child(UI.color_rect(Color(0, 0, 0, 0.38)))
	UI.full(get_child(1))

	var vb := UI.vbox(14)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -240, -240, 240, 260)
	add_child(vb)
	vb.add_child(UI.label("MENU_NIGHTS", 40, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for n in range(1, Game.MAX_NIGHTS + 1):
		var b := UI.button("", 234, 56)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.add_theme_font_size_override("font_size", 18)
		var title := tr("NIGHT_TITLE_%d" % n)
		var unlocked := Save.is_night_unlocked(n)
		if unlocked:
			b.text = "%s · %s" % [tr("NIGHT_LABEL").format([str(n)]), title]
			b.pressed.connect(func(): Game.start_story_night(n))
		else:
			b.text = "🔒 " + tr("NIGHT_LABEL").format([str(n)])
			b.disabled = true
		grid.add_child(b)

	var shrine := UI.button("MENU_SHRINE", 220, 48)
	shrine.pressed.connect(func(): Router.change_scene("res://scenes/screens/ShrineScreen.tscn"))
	vb.add_child(shrine)
	var back := UI.button("SET_BACK", 220, 48)
	back.pressed.connect(func(): Router.to_main_menu())
	vb.add_child(back)
