extends Control
## Pause overlay. Works while the tree is paused (PROCESS_MODE_ALWAYS).

var _c

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := UI.color_rect(Color(0, 0, 0, 0.7))
	UI.full(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var vb := UI.vbox(14)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -160, -160, 160, 160)
	dim.add_child(vb)
	vb.add_child(UI.label("PAUSE_TITLE", 34, Color(0.95, 0.8, 0.5), HORIZONTAL_ALIGNMENT_CENTER))
	if Save.clue_count() > 0 and not Save.investigation_complete():
		vb.add_child(UI.text_label(tr("HUD_CLUES") % Save.clue_count(), 18, Color(0.86, 0.78, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
	var resume := UI.button("PAUSE_RESUME", 280, 50)
	resume.pressed.connect(func(): _c.request_pause())
	vb.add_child(resume)
	var restart := UI.button("GO_RETRY", 280, 50)
	restart.pressed.connect(_restart)
	vb.add_child(restart)
	var menu := UI.button("PAUSE_MENU", 280, 50)
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)

func open() -> void:
	visible = true

func close() -> void:
	visible = false

func _restart() -> void:
	get_tree().paused = false
	if Game.is_custom:
		Game.start_custom_night(Game.custom_levels)
	else:
		Game.start_story_night(Game.current_night)

func _to_menu() -> void:
	get_tree().paused = false
	Router.to_main_menu()
