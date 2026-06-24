extends Control
## Dawn / survived screen. Offers the next night (or "all done") and the menu.

func _ready() -> void:
	UI.full(self)
	var bg := UI.texture_rect("res://assets/art/intro/win_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)
	# Dawn warm-up: a cold pre-dawn wash that melts into warm amber, so surviving the
	# night reads as relief rather than a static card.
	var dawn := UI.color_rect(Color(0.15, 0.2, 0.32, 0.55))
	UI.full(dawn)
	add_child(dawn)
	var dtw := create_tween()
	dtw.tween_property(dawn, "color", Color(0.95, 0.72, 0.4, 0.0), 2.2).set_trans(Tween.TRANS_SINE)
	var vb := UI.vbox(14)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -260, -200, 260, 220)
	add_child(vb)
	vb.add_child(UI.label("WIN_TITLE", 64, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("DAWN_GREET", 22, Color(0.9, 0.88, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("WIN_SURVIVED", 26, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("WIN_THANKS", 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("WIN_SIGN", 16, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.text_label("%s: %d" % [tr("HUD_COINS"), Save.coins], 20, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER))

	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	if Game.has_next_night():
		var nxt := UI.button("WIN_NEXT_NIGHT", 240, 50)
		nxt.pressed.connect(func(): Game.go_next_night())
		row.add_child(nxt)
	else:
		vb.add_child(UI.label("WIN_ALL_DONE", 18, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	var shrine := UI.button("MENU_SHRINE", 200, 50)
	shrine.pressed.connect(func(): Router.change_scene("res://scenes/screens/ShrineScreen.tscn"))
	row.add_child(shrine)
	var menu := UI.button("PAUSE_MENU", 240, 50)
	menu.pressed.connect(func(): Router.to_main_menu())
	row.add_child(menu)
	Audio.play_music("ambience_night")
