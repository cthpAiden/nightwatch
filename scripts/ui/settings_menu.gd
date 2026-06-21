extends Control
## Options: language, audio volumes, fullscreen, brightness, scare intensity, difficulty.

func _ready() -> void:
	UI.full(self)
	add_child(UI.color_rect(Color(0.03, 0.04, 0.06, 1)))
	UI.full(get_child(0))
	var panel := PanelContainer.new()
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -320, -300, 320, 300)
	add_child(panel)
	var vb := UI.vbox(12)
	panel.add_child(vb)
	vb.add_child(UI.label("SET_TITLE", 36, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))

	var lang := _option(vb, "SET_LANGUAGE", ["LANG_VI", "LANG_EN"], (0 if Settings.language == "vi" else 1))
	lang.item_selected.connect(func(i): Settings.apply({"language": ("vi" if i == 0 else "en")}))

	_slider(vb, "SET_MASTER_VOLUME", Settings.master_volume, func(v): Settings.apply({"master_volume": v}))
	_slider(vb, "SET_MUSIC_VOLUME", Settings.music_volume, func(v): Settings.apply({"music_volume": v}))
	_slider(vb, "SET_SFX_VOLUME", Settings.sfx_volume, func(v): Settings.apply({"sfx_volume": v}))
	_slider(vb, "SET_BRIGHTNESS", (Settings.brightness - 0.5) / 1.0, func(v): Settings.apply({"brightness": 0.5 + v}))

	var fs := CheckButton.new()
	fs.text = tr("SET_FULLSCREEN")
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.apply({"fullscreen": on}))
	vb.add_child(fs)

	var scare := _option(vb, "SET_SCARE_INTENSITY", ["SET_SCARE_FULL", "SET_SCARE_REDUCED", "SET_SCARE_OFF"], Settings.scare_intensity)
	scare.item_selected.connect(func(i): Settings.apply({"scare_intensity": i}))

	var diff := _option(vb, "SET_DIFFICULTY", ["DIFF_EASY", "DIFF_NORMAL", "DIFF_HARD", "DIFF_NIGHTMARE"], Settings.difficulty)
	diff.item_selected.connect(func(i): Settings.apply({"difficulty": i}))

	var back := UI.button("SET_BACK", 240, 48)
	back.pressed.connect(func(): Router.to_main_menu())
	vb.add_child(back)

func _row(vb: VBoxContainer, key: String) -> HBoxContainer:
	var h := UI.hbox(12)
	var l := UI.label(key, 18, UI.COL_TEXT)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	vb.add_child(h)
	return h

func _slider(vb: VBoxContainer, key: String, value: float, cb: Callable) -> void:
	var h := _row(vb, key)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(300, 24)
	s.value_changed.connect(func(v): cb.call(v))
	h.add_child(s)

func _option(vb: VBoxContainer, key: String, items: Array, selected: int) -> OptionButton:
	var h := _row(vb, key)
	var o := OptionButton.new()
	for it in items:
		o.add_item(tr(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.custom_minimum_size = Vector2(300, 0)
	h.add_child(o)
	return o
