extends Control
## Campaign ending. Two outcomes, decided by the Oan hồn investigation:
##   siêu thoát (all three clues gathered) — the wronged soul is freed; warm dawn.
##   survive (clues incomplete) — you lived, but she is still trapped; cold daybreak.
## Reached from NightController._win() when the final story night is cleared.

func _ready() -> void:
	UI.full(self)
	var good := Save.investigation_complete()
	Save.mark_ending_seen("sieuthoat" if good else "survive")

	var bg_path := "res://assets/art/screens/ending_sieuthoat.svg" if good else "res://assets/art/screens/ending_survive.svg"
	var bg := UI.texture_rect(bg_path, TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)
	var vig := UI.texture_rect("res://assets/art/ui/vignette.svg", TextureRect.STRETCH_SCALE)
	UI.full(vig)
	add_child(vig)

	var vb := UI.vbox(16)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -470, -250, 470, 250)
	add_child(vb)

	var title_key := "WIN_SIEU_TITLE" if good else "EPILOGUE_TITLE"
	var title_col := Color(1.0, 0.86, 0.5) if good else Color(0.78, 0.84, 0.92)
	vb.add_child(UI.label(title_key, 60, title_col, HORIZONTAL_ALIGNMENT_CENTER))

	var lines: Array = ["ENDING_GOOD_L1", "ENDING_GOOD_L2", "ENDING_GOOD_L3", "ENDING_GOOD_L4", "ENDING_GOOD_SIGN"] if good \
		else ["ENDING_SURV_L1", "ENDING_SURV_L2", "ENDING_SURV_L3", "ENDING_SURV_L4"]
	var crawl := UI.vbox(10)
	vb.add_child(crawl)
	var fade_targets: Array = []
	for k in lines:
		var l := UI.label(k, 22, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(880, 0)
		l.modulate.a = 0.0
		crawl.add_child(l)
		fade_targets.append(l)
	if not good:
		# Name exactly which clues she still needs, so the player knows what to chase
		# on a replay instead of guessing why the good ending didn't trigger.
		var missing: Array = []
		if not Save.has_clue("clue_name"): missing.append(tr("CLUE_NAME_LABEL"))
		if not Save.has_clue("clue_drawing"): missing.append(tr("CLUE_DRAWING_LABEL"))
		if not Save.has_clue("clue_photo"): missing.append(tr("CLUE_PHOTO_LABEL"))
		var hint_text := tr("ENDING_CLUE_HINT") % Save.clue_count()
		if not missing.is_empty():
			hint_text += "\n" + (tr("ENDING_MISSING") % ", ".join(missing))
		var hint := UI.text_label(hint_text, 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(880, 0)
		hint.modulate.a = 0.0
		crawl.add_child(hint)
		fade_targets.append(hint)

	# Fade the epilogue in line by line for a quiet, deliberate reveal.
	var tw := create_tween()
	for l in fade_targets:
		tw.tween_interval(0.45)
		tw.tween_property(l, "modulate:a", 1.0, 0.9)

	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var credits := UI.button("MENU_CREDITS", 220, 50)
	credits.pressed.connect(func(): Router.to_credits())
	row.add_child(credits)
	var menu := UI.button("PAUSE_MENU", 220, 50)
	menu.pressed.connect(func(): Router.to_main_menu())
	row.add_child(menu)

	Audio.play_music("ambience_night")
	if good:
		Audio.play_sfx("rooster", -8.0)
		Audio.play_sfx("offering_bell", -8.0)
