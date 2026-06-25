extends Control
## Options: language, audio volumes, fullscreen, brightness, scare intensity, difficulty.

func _ready() -> void:
	_build()

func _build() -> void:
	# Tear down any previous build (Reset rebuilds the screen in place). Detach
	# immediately so get_child indexing below doesn't see queued-but-not-freed nodes.
	for c in get_children():
		remove_child(c)
		c.queue_free()
	UI.full(self)
	var bg := UI.color_rect(Color(0.03, 0.04, 0.06, 1))
	add_child(bg)
	UI.full(bg)
	var panel := PanelContainer.new()
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -320, -300, 320, 300)
	add_child(panel)
	# A ScrollContainer keeps the rows reachable on short windows instead of clipping.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := UI.vbox(14)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	vb.add_child(UI.label("SET_TITLE", 36, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))

	var lang := _option(vb, "SET_LANGUAGE", ["LANG_VI", "LANG_EN"], (0 if Settings.language == "vi" else 1))
	lang.item_selected.connect(func(i): Settings.apply({"language": ("vi" if i == 0 else "en")}))

	_slider(vb, "SET_MASTER_VOLUME", Settings.master_volume, func(v): Settings.apply({"master_volume": v}))
	_slider(vb, "SET_MUSIC_VOLUME", Settings.music_volume, func(v): Settings.apply({"music_volume": v}))
	_slider(vb, "SET_SFX_VOLUME", Settings.sfx_volume, func(v): Settings.apply({"sfx_volume": v}))
	_slider(vb, "SET_BRIGHTNESS", (Settings.brightness - 0.5) / 1.0, func(v): Settings.apply({"brightness": 0.5 + v}), true)

	# Fullscreen toggle in the same label-column / control-column row pattern.
	var fs_row := _row(vb, "SET_FULLSCREEN")
	var fs := CheckButton.new()
	fs.button_pressed = Settings.fullscreen
	fs.toggled.connect(func(on): Settings.apply({"fullscreen": on}))
	fs_row.add_child(fs)

	var scare := _option(vb, "SET_SCARE_INTENSITY", ["SET_SCARE_FULL", "SET_SCARE_REDUCED", "SET_SCARE_OFF"], Settings.scare_intensity)
	scare.item_selected.connect(func(i): Settings.apply({"scare_intensity": i}))
	_help(vb, "SET_SCARE_HELP")

	var diff := _option(vb, "SET_DIFFICULTY", ["DIFF_EASY", "DIFF_NORMAL", "DIFF_HARD", "DIFF_NIGHTMARE"], Settings.difficulty)
	diff.item_selected.connect(func(i): Settings.apply({"difficulty": i}))
	_help(vb, "SET_DIFF_HELP")

	var buttons := UI.hbox(12)
	vb.add_child(buttons)
	var back := UI.button("SET_BACK", 240, 48)
	back.pressed.connect(func():
		Audio.play_sfx("ui_back", -4.0)
		Router.to_main_menu())
	buttons.add_child(back)
	var reset := UI.button("SET_RESET", 240, 48)
	reset.pressed.connect(func():
		Audio.play_sfx("ui_click", -6.0)
		Settings.apply({
			"master_volume": 0.45, "music_volume": 0.8, "sfx_volume": 1.0,
			"brightness": 1.0, "scare_intensity": Settings.Scare.FULL,
			"difficulty": GameEnums.Difficulty.NORMAL,
		})
		_build())
	buttons.add_child(reset)

	# Keyboard/gamepad cursor lands on Back with a visible focus ring.
	back.grab_focus()

func _row(vb: VBoxContainer, key: String) -> HBoxContainer:
	var h := UI.hbox(12)
	var l := UI.label(key, 18, UI.COL_TEXT)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	vb.add_child(h)
	return h

## Dim explanatory sub-label shown under an OptionButton row.
func _help(vb: VBoxContainer, key: String) -> void:
	var l := UI.label(key, 14, UI.COL_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(560, 0)
	vb.add_child(l)

func _slider(vb: VBoxContainer, key: String, value: float, cb: Callable, is_brightness: bool = false) -> void:
	var h := _row(vb, key)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(300, 24)
	# Live percentage readout to the right of the slider. Brightness maps its 0..1
	# slider back onto the 50..150% multiplier range it actually represents.
	var pct := UI.text_label(_pct_text(value, is_brightness), 16, UI.COL_DIM)
	pct.custom_minimum_size = Vector2(54, 0)
	s.value_changed.connect(func(v):
		pct.text = _pct_text(v, is_brightness)
		cb.call(v))
	h.add_child(s)
	h.add_child(pct)

func _pct_text(v: float, is_brightness: bool) -> String:
	var frac := (0.5 + v) if is_brightness else v
	return "%d%%" % roundi(frac * 100.0)

func _option(vb: VBoxContainer, key: String, items: Array, selected: int) -> OptionButton:
	var h := _row(vb, key)
	var o := OptionButton.new()
	for it in items:
		o.add_item(tr(it))
	o.selected = clampi(selected, 0, items.size() - 1)
	o.custom_minimum_size = Vector2(300, 0)
	h.add_child(o)
	return o
