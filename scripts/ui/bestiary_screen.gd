extends Control
## Hồ Sơ Ma — the bestiary. One card per spirit; locked to a black silhouette + "???"
## until you've encountered it on a shift (Save.bestiary_seen). All data/strings exist
## in ThreatRegistry + strings.csv; this only surfaces them.

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	var dim := UI.color_rect(Color(0, 0, 0, 0.45))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(10)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -440, -300, 440, 320)
	add_child(vb)
	vb.add_child(UI.label("BESTIARY_TITLE", 40, Color(0.9, 0.86, 0.8), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("BESTIARY_HINT", 15, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	# Discovered-count subtitle so collection progress is visible at a glance.
	var all_ids: Array = ThreatRegistry.ids()
	var seen_n := 0
	for id in all_ids:
		if Save.bestiary_seen.get(id, false):
			seen_n += 1
	vb.add_child(UI.text_label("%s %d/%d" % [tr("BESTIARY_DISCOVERED"), seen_n, all_ids.size()],
		15, Color(0.86, 0.78, 0.55), HORIZONTAL_ALIGNMENT_CENTER))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(852, 430)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for id in ThreatRegistry.ids():
		grid.add_child(_card(id))

	var back := UI.button("SET_BACK", 220, 46)
	back.pressed.connect(func(): Router.change_scene("res://scenes/screens/ExtrasScreen.tscn"))
	vb.add_child(back)
	Audio.play_music("ambience_night")

func _card(id: String) -> Control:
	var seen: bool = Save.bestiary_seen.get(id, false)
	var info := ThreatRegistry.info(id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(410, 150)
	var hb := UI.hbox(12)
	card.add_child(hb)

	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(100, 130)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.texture = ThreatRegistry.load_tex(id, "idle")
	if not seen:
		pic.modulate = Color(0.03, 0.03, 0.05, 1.0)   # black silhouette tease
	hb.add_child(pic)

	var col := UI.vbox(4)
	hb.add_child(col)
	if seen:
		var accent: Color = info.get("accent", UI.COL_TEXT)
		col.add_child(UI.label(info.get("name_key", id), 20, accent))
		# Fear rating as filled/empty dots in the spirit's accent colour (language-neutral,
		# display-only over the existing ThreatRegistry "fear" field).
		var fear := int(info.get("fear", 0))
		if fear > 0:
			col.add_child(UI.text_label("●".repeat(fear) + "○".repeat(maxi(0, 5 - fear)), 14, accent))
		col.add_child(UI.label(info.get("tag_key", ""), 13, Color(0.72, 0.7, 0.5)))
		var d := UI.label(info.get("desc_key", ""), 14, UI.COL_DIM)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(272, 44)
		col.add_child(d)
		# Actionable "how to counter" line in real-button terms (the poetic desc above
		# is flavor; this tells the player what to actually do).
		var counter := UI.label("COUNTER_" + id.to_upper(), 13, Color(0.62, 0.82, 0.66))
		counter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		counter.custom_minimum_size = Vector2(272, 0)
		col.add_child(counter)
	else:
		col.add_child(UI.label("BESTIARY_UNKNOWN", 22, UI.COL_TEXT))
		col.add_child(UI.label("BESTIARY_LOCKED", 14, UI.COL_DIM))
	return card
