extends Control
## Đêm Tùy Chỉnh — build your own night: a 0–20 slider per spirit, three presets, and
## a Begin button. The backend (Game.start_custom_night) already accepts an arbitrary
## levels dict; this is the missing front-end. Unlocked after clearing Night 6.

var _sliders := {}

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	var dim := UI.color_rect(Color(0, 0, 0, 0.45))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -380, -290, 380, 300)
	add_child(vb)
	vb.add_child(UI.label("CUSTOM_TITLE", 40, Color(0.95, 0.82, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("CUSTOM_HINT", 15, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for id in ThreatRegistry.ids():
		if id == "ba_hang_rong":
			continue   # the counterfeit vendor isn't a director threat
		var name_lbl := UI.label(ThreatRegistry.name_key(id), 18, UI.COL_TEXT)
		name_lbl.custom_minimum_size = Vector2(250, 0)
		grid.add_child(name_lbl)
		var sl := HSlider.new()
		sl.min_value = 0
		sl.max_value = 20
		sl.step = 1
		# Restore the last-built night so reopening the screen doesn't wipe the dial back
		# to default; falls back to 5 for spirits not in the saved levels dict.
		var seed_lv := int(Game.custom_levels.get(id, 5))
		sl.value = seed_lv
		sl.custom_minimum_size = Vector2(300, 24)
		grid.add_child(sl)
		var val := UI.text_label(str(seed_lv), 18, Color(1.0, 0.85, 0.45), HORIZONTAL_ALIGNMENT_RIGHT)
		val.custom_minimum_size = Vector2(40, 0)
		grid.add_child(val)
		sl.value_changed.connect(func(v): val.text = str(int(v)))
		_sliders[id] = sl

	var presets := UI.hbox(10)
	presets.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(presets)
	_preset_btn(presets, "CUSTOM_PRESET_CALM", 4)
	_preset_btn(presets, "CUSTOM_PRESET_HARD", 12)
	_preset_btn(presets, "CUSTOM_PRESET_MAX", 20)

	var row := UI.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var start := UI.button("CUSTOM_START", 240, 50)
	start.pressed.connect(_start)
	row.add_child(start)
	var back := UI.button("SET_BACK", 200, 50)
	back.pressed.connect(func(): Router.to_main_menu())
	row.add_child(back)
	Audio.play_music("ambience_night")

func _preset_btn(box: HBoxContainer, key: String, level: int) -> void:
	var b := UI.button(key, 150, 40)
	b.pressed.connect(func(): _set_all(level))
	box.add_child(b)

func _set_all(level: int) -> void:
	for id in _sliders:
		_sliders[id].value = level

func _start() -> void:
	var levels := {}
	for id in _sliders:
		var lv := int(_sliders[id].value)
		if lv > 0:
			levels[id] = lv
	if levels.is_empty():
		Audio.play_sfx("ui_back", -4.0)
		return
	Audio.play_sfx("ui_confirm", -4.0)
	Game.start_custom_night(levels)
