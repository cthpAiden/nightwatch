extends Control
## Game over. Shows who caught you, retry the same night, or return to menu.

func _ready() -> void:
	UI.full(self)
	var bg := UI.texture_rect("res://assets/art/intro/gameover_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)
	var vb := UI.vbox(16)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -280, -160, 280, 160)
	add_child(vb)
	vb.add_child(UI.label("GO_TITLE", 46, Color(0.85, 0.2, 0.2), HORIZONTAL_ALIGNMENT_CENTER))

	var cause := Game.last_cause
	if cause != "" and cause != "via":
		var meta := ThreatRegistry.info(cause)
		if not meta.is_empty():
			var caught := UI.text_label(tr("GO_CAUGHT_BY").format([tr(meta.get("name_key", cause))]),
				20, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
			vb.add_child(caught)

	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var retry := UI.button("GO_RETRY", 220, 50)
	retry.pressed.connect(func():
		if Game.is_custom:
			Game.start_custom_night(Game.custom_levels)
		else:
			Game.start_story_night(Game.current_night))
	row.add_child(retry)
	var menu := UI.button("GO_MENU", 220, 50)
	menu.pressed.connect(func(): Router.to_main_menu())
	row.add_child(menu)
