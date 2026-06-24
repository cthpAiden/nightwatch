extends Control
## Standing credits over the quiet incense-smoke backdrop. Reached from the ending
## screen (or the Extras menu). One button back to the main menu.

func _ready() -> void:
	UI.full(self)
	var bg := UI.texture_rect("res://assets/art/screens/credits_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -320, -230, 320, 250)
	add_child(vb)
	vb.add_child(UI.label("CREDITS_TITLE", 56, Color(0.92, 0.88, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("GAME_TITLE", 30, Color(0.85, 0.5, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_spacer(8))
	vb.add_child(UI.label("CREDITS_MADE_BY", 20, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.text_label("Aiden", 24, Color(1, 0.85, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_spacer(8))
	vb.add_child(UI.label("CREDITS_BUILT_WITH", 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("CREDITS_FONT", 16, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_spacer(12))
	vb.add_child(UI.label("CREDITS_THANKS", 22, Color(0.9, 0.88, 0.8), HORIZONTAL_ALIGNMENT_CENTER))

	var row := UI.hbox(0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var menu := UI.button("PAUSE_MENU", 240, 52)
	menu.pressed.connect(func(): Router.to_main_menu())
	row.add_child(menu)

	Audio.play_music("ambience_night")

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
