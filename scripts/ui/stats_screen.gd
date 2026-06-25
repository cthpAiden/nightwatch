extends Control
## Statistics — a read-only look at the player's running tallies (Save.stats + clues).

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	var dim := UI.color_rect(Color(0, 0, 0, 0.45))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(14)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -260, -220, 260, 220)
	add_child(vb)
	vb.add_child(UI.label("STATS_TITLE", 40, Color(0.9, 0.86, 0.8), HORIZONTAL_ALIGNMENT_CENTER))

	var s: Dictionary = Save.stats
	_row(vb, "STATS_WON", str(int(s.get("nights_won", 0))))
	_row(vb, "STATS_DEATHS", str(int(s.get("deaths", 0))))
	_row(vb, "STATS_OUTAGES", str(int(s.get("power_outages", 0))))
	_row(vb, "STATS_OFFERINGS", str(int(s.get("offerings_made", 0))))
	_row(vb, "STATS_CLUES", "%d/3" % Save.clue_count())
	# Endings collected: mirror the clue tracker so completionists see what's left.
	var endings := int(Save.has_ending("survive")) + int(Save.has_ending("sieuthoat"))
	_row(vb, "STATS_ENDINGS", "%d/2" % endings)
	# Nemesis: which spirit has caught the player most. Only shown once there's a death
	# on record, so a fresh save isn't littered with an empty row.
	var by: Dictionary = s.get("deaths_by", {})
	if not by.is_empty():
		var worst_id := ""
		var worst_n := 0
		for id in by:
			var n := int(by[id])
			# Only real threats can be a "nemesis" — skip non-threat causes like "via"
			# (a nerve-loss defeat) so the row never shows a raw, untranslated id.
			if n > worst_n and ThreatRegistry.ids().has(id):
				worst_n = n
				worst_id = id
		if worst_id != "":
			_row(vb, "STATS_NEMESIS", "%s (%d)" % [tr(ThreatRegistry.name_key(worst_id)), worst_n])
	# Surface the existing custom-night-beaten flag.
	if Save.custom_night_beaten:
		_row(vb, "STATS_CUSTOM", tr("BTN_YES"))

	var back := UI.button("SET_BACK", 240, 48)
	back.pressed.connect(func(): Router.change_scene("res://scenes/screens/ExtrasScreen.tscn"))
	vb.add_child(back)
	Audio.play_music("ambience_night")

func _row(vb: VBoxContainer, key: String, value: String) -> void:
	var h := UI.hbox(10)
	h.custom_minimum_size = Vector2(440, 0)
	var name_lbl := UI.label(key, 20, UI.COL_TEXT)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)
	h.add_child(UI.text_label(value, 20, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_RIGHT))
	vb.add_child(h)
