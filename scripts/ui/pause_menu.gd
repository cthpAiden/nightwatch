extends Control
## Pause overlay. Works while the tree is paused (PROCESS_MODE_ALWAYS).

var _c
var _resume: Button

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
	if not Save.investigation_complete():
		# A 3-line checklist so the player sees which clues are still missing.
		vb.add_child(UI.text_label(tr("HUD_CLUES") % Save.clue_count(), 18, Color(0.86, 0.78, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
		_clue_line(vb, "clue_name", "CLUE_NAME_LABEL")
		_clue_line(vb, "clue_drawing", "CLUE_DRAWING_LABEL")
		_clue_line(vb, "clue_photo", "CLUE_PHOTO_LABEL")
	var resume := UI.button("PAUSE_RESUME", 280, 50)
	resume.pressed.connect(func():
		Audio.play_sfx("ui_back", -4.0)
		_c.request_pause())
	vb.add_child(resume)
	_resume = resume
	var restart := UI.button("GO_RETRY", 280, 50)
	restart.pressed.connect(_restart)
	vb.add_child(restart)
	var settings := UI.button("MENU_SETTINGS", 280, 50)
	settings.pressed.connect(func():
		Audio.play_sfx("ui_click", -6.0)
		get_tree().paused = false
		Router.change_scene("res://scenes/screens/SettingsMenu.tscn"))
	vb.add_child(settings)
	var menu := UI.button("PAUSE_MENU", 280, 50)
	menu.pressed.connect(_to_menu)
	vb.add_child(menu)

## One checklist row: a check mark + the clue's label if owned, else an open
## marker + the label (which names what's still to find).
func _clue_line(vb: VBoxContainer, clue_id: String, label_key: String) -> void:
	var got: bool = Save.has_clue(clue_id)
	var mark := "✓ " if got else "○ "
	var col := Color(0.6, 0.82, 0.5) if got else Color(0.7, 0.66, 0.58)
	var line := UI.text_label(mark + tr(label_key), 16, col, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(line)

func open() -> void:
	visible = true
	# Keyboard/gamepad cursor lands on Resume with a visible focus ring each time
	# the overlay appears (it's hidden during setup, so focus must be grabbed here).
	if is_instance_valid(_resume):
		_resume.grab_focus()

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
