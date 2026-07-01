extends Control
## The night HUD: power + vía meters, clock, night label, the door/light/camera/
## offering/item controls, the phone answer button, and transient toasts/warnings.
## Built in code; reads the controller and listens to Events.

var _c   # NightController

var _power_bar: ProgressBar
var _via_bar: ProgressBar
var _clock: Label
var _night: Label
var _toast: Label
var _warn: Label
var _warn_panel: Control
var _warn_key := ""
var _offerings_lbl: Label
var _coins_lbl: Label
var _clue_lbl: Label
var _clue_flash := 0.0
var _tut_panel: Control
var _tut_label: Label
var _crowd_bar: ProgressBar
var _huong_bar: ProgressBar
var _grievance_bar: ProgressBar
var _item_icon: TextureRect
var _use_btn: Button
var _answer_btn: Button
var _incense_btn: Button
var _bell_btn: Button
var _offering_btn: Button
var _invite_btn: Button
var _help_panel: Control
var _help_lines: VBoxContainer
var _help_col: VBoxContainer
var _door_btn := {}
var _light_btn := {}
var _toast_t := 0.0
var _toast_queue: Array = []    # small FIFO of {key,text}; teaching lines jump ahead (backlog#10)
var _huong_danger := false
var _vendor_state := GameEnums.VendorState.IDLE
var _light_on := {}             # side -> bool, for the persistent which-door cue
var _pulse_t := 0.0             # drives the looming-door amber pulse
var _bell_cooling := false      # bell-button cooldown dim state (change-guarded)
var _calm_t := 0.0              # brief post-offering window: tracked meter drops read as relief
var _power_num: Label
var _dawn_bar: ProgressBar

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	_connect()
	_refresh_clock(0)

func _build() -> void:
	# meters (top-left)
	var meters := UI.vbox(8)
	UI.place(meters, 0, 0, 0, 0, 22, 16, 322, 156)
	add_child(meters)
	var prow := UI.hbox(8)
	prow.add_child(UI.texture_rect("res://assets/art/ui/power_icon.svg", TextureRect.STRETCH_KEEP_ASPECT))
	prow.get_child(0).custom_minimum_size = Vector2(26, 26)
	_power_bar = UI.progress(100.0, Color(0.91, 0.64, 0.24))
	_power_bar.custom_minimum_size = Vector2(240, 22)
	prow.add_child(_power_bar)
	# Numeric readout on the power bar (it is a hard budget you could only eyeball). (backlog#15)
	_power_num = UI.text_label("100", 13, Color(0.08, 0.06, 0.04), HORIZONTAL_ALIGNMENT_RIGHT)
	_power_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_power_num, 0, 0, 1, 1, 0, 3, -8, 0)
	_power_bar.add_child(_power_num)
	meters.add_child(prow)
	var vrow := UI.hbox(8)
	vrow.add_child(UI.texture_rect("res://assets/art/ui/via_icon.svg", TextureRect.STRETCH_KEEP_ASPECT))
	vrow.get_child(0).custom_minimum_size = Vector2(26, 26)
	_via_bar = UI.progress(100.0, Color(0.6, 0.82, 0.78))
	_via_bar.custom_minimum_size = Vector2(240, 22)
	vrow.add_child(_via_bar)
	meters.add_child(vrow)
	# hương (incense protection) — your active altar defense
	var hrow := UI.hbox(8)
	hrow.add_child(UI.texture_rect("res://assets/art/ui/btn_offering.svg", TextureRect.STRETCH_KEEP_ASPECT))
	hrow.get_child(0).custom_minimum_size = Vector2(26, 26)
	_huong_bar = UI.progress(1.0, Color(1.0, 0.62, 0.2))
	_huong_bar.custom_minimum_size = Vector2(240, 18)
	_huong_bar.value = 1.0
	hrow.add_child(_huong_bar)
	meters.add_child(hrow)

	# clock + night (top-center)
	var cbox := UI.vbox(0)
	UI.place(cbox, 0.5, 0, 0.5, 0, -140, 12, 140, 96)
	add_child(cbox)
	_clock = UI.text_label("12:00", 44, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_child(_clock)
	_night = UI.label("HUD_NIGHT", 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	cbox.add_child(_night)
	# Investigation tracker — the visible spine of the two-ending arc. Hidden until the
	# first clue is found, then persists (Save.clue_count) so the goal is always legible.
	_clue_lbl = UI.text_label("", 16, Color(0.86, 0.78, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_clue_lbl.visible = false
	cbox.add_child(_clue_lbl)
	# Thin dawn-progress sliver under the clock — fills toward 06:00 so "how close am I to
	# surviving" has a shape during the calm stretches. (backlog#15 / AUDIT#29)
	_dawn_bar = UI.progress(1.0, Color(0.5, 0.62, 0.78))
	_dawn_bar.custom_minimum_size = Vector2(150, 4)
	_dawn_bar.value = 0.0
	_dawn_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cbox.add_child(_dawn_bar)

	# coins + offerings + crowd/water/grievance (top-right)
	var rbox := UI.vbox(6)
	UI.place(rbox, 1, 0, 1, 0, -260, 16, -22, 186)
	add_child(rbox)
	_coins_lbl = UI.text_label("", 18, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	rbox.add_child(_coins_lbl)
	_offerings_lbl = UI.text_label("", 18, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	rbox.add_child(_offerings_lbl)
	# Each conditional meter gets a short label so a new player can tell what the bar
	# that just popped in is actually tracking (no more anonymous coloured bars).
	_crowd_bar = _bar_row(rbox, "HUD_CROWD", Color(0.7, 0.66, 0.5))
	_grievance_bar = _bar_row(rbox, "HUD_GRIEVANCE", Color(0.85, 0.86, 0.9))

	# left controls
	var lbox := UI.vbox(8)
	UI.place(lbox, 0, 1, 0, 1, 22, -150, 210, -22)
	add_child(lbox)
	_light_btn[GameEnums.Side.LEFT] = _ctrl_btn("LIGHT_LEFT", func(): _c.request_toggle_light(GameEnums.Side.LEFT))
	_door_btn[GameEnums.Side.LEFT] = _ctrl_btn("DOOR_LEFT", func(): _c.request_toggle_door(GameEnums.Side.LEFT))
	_light_btn[GameEnums.Side.LEFT].clip_text = true
	_door_btn[GameEnums.Side.LEFT].clip_text = true
	lbox.add_child(_light_btn[GameEnums.Side.LEFT])
	lbox.add_child(_door_btn[GameEnums.Side.LEFT])

	# right controls
	var rcbox := UI.vbox(8)
	UI.place(rcbox, 1, 1, 1, 1, -210, -150, -22, -22)
	add_child(rcbox)
	_light_btn[GameEnums.Side.RIGHT] = _ctrl_btn("LIGHT_RIGHT", func(): _c.request_toggle_light(GameEnums.Side.RIGHT))
	_door_btn[GameEnums.Side.RIGHT] = _ctrl_btn("DOOR_RIGHT", func(): _c.request_toggle_door(GameEnums.Side.RIGHT))
	_light_btn[GameEnums.Side.RIGHT].clip_text = true
	_door_btn[GameEnums.Side.RIGHT].clip_text = true
	rcbox.add_child(_light_btn[GameEnums.Side.RIGHT])
	rcbox.add_child(_door_btn[GameEnums.Side.RIGHT])

	# center controls (widened so the key-glyph labels fit between the door/light columns)
	var center := UI.hbox(10)
	UI.place(center, 0.5, 1, 0.5, 1, -420, -86, 420, -26)
	add_child(center)
	var cam_btn := _ctrl_btn("HUD_CAM", func(): _c.request_toggle_monitor(), 100, "toggle_cameras")
	center.add_child(cam_btn)
	_incense_btn = _ctrl_btn("HUD_INCENSE", _press_incense, 195, "light_incense")
	center.add_child(_incense_btn)
	_bell_btn = _ctrl_btn("HUD_BELL", _press_bell, 120, "ring_bell")
	center.add_child(_bell_btn)
	_offering_btn = _ctrl_btn("OFFERING_PROMPT", _press_offering, 195, "place_offering")
	center.add_child(_offering_btn)
	var slot := UI.hbox(4)
	_item_icon = UI.texture_rect("res://assets/art/ui/item_slot.svg", TextureRect.STRETCH_KEEP_ASPECT)
	_item_icon.custom_minimum_size = Vector2(48, 48)
	slot.add_child(_item_icon)
	_use_btn = _ctrl_btn("HUD_ITEM", func(): _c.request_use_item(), 110, "use_item")
	_use_btn.disabled = true
	slot.add_child(_use_btn)
	center.add_child(slot)

	# Ma da water buttons (hidden until relevant)
	var phone_row := UI.hbox(8)
	UI.place(phone_row, 0.5, 1, 0.5, 1, -190, -150, 190, -100)
	add_child(phone_row)
	_answer_btn = _ctrl_btn("ACTION_ANSWER", func(): _c.request_answer_phone(), 160, "answer_phone")
	_answer_btn.visible = false
	_answer_btn.modulate = Color(0.6, 0.9, 0.7)
	phone_row.add_child(_answer_btn)

	# vendor invite (top-center, under clock; shown only while she is at the gate)
	_invite_btn = _ctrl_btn("SHOP_INVITE", func(): _c.open_shop(), 160)
	UI.place(_invite_btn, 0.5, 0, 0.5, 0, -80, 100, 80, 146)
	_invite_btn.visible = false
	_invite_btn.modulate = Color(1.0, 0.85, 0.5)
	add_child(_invite_btn)

	_build_help()

	# toast + warning (center)
	_toast = UI.text_label("", 22, Color(1, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(_toast, 0.5, 0, 0.5, 0, -400, 112, 400, 150)
	_toast.modulate.a = 0.0
	add_child(_toast)
	# A dark plate behind the persistent red warning so it always has contrast (like the
	# tutorial banner's tbg). Sits low-centre, clear of the mid-screen tutorial banner;
	# the plate only shows while there's warning text (driven in _process).
	_warn_panel = Control.new()
	_warn_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_warn_panel, 0.5, 1, 0.5, 1, -300, -192, 300, -152)
	_warn_panel.visible = false
	add_child(_warn_panel)
	var wbg := UI.color_rect(Color(0.06, 0.03, 0.04, 0.6))
	UI.full(wbg)
	_warn_panel.add_child(wbg)
	_warn = UI.label("", 20, UI.COL_DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	_warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UI.place(_warn, 0, 0, 1, 1, 8, 2, -8, -2)
	_warn_panel.add_child(_warn)

	# Persistent tutorial prompt: a banner that names the exact key for the current
	# Night-1 step and stays put until the action is done (no more 2.6s blink-and-miss).
	_tut_panel = Control.new()
	_tut_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_tut_panel, 0.5, 0.5, 0.5, 0.5, -360, -52, 360, 8)
	_tut_panel.visible = false
	add_child(_tut_panel)
	var tbg := UI.color_rect(Color(0.05, 0.06, 0.09, 0.82))
	UI.full(tbg)
	_tut_panel.add_child(tbg)
	_tut_label = UI.label("", 22, Color(1.0, 0.92, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	_tut_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UI.place(_tut_label, 0, 0, 1, 1, 12, 8, -12, -8)
	_tut_panel.add_child(_tut_label)

## A labelled conditional meter (icon-free, just a short name + bar). The whole row
## is hidden until the threat it tracks is active; toggle via bar.get_parent().visible.
func _bar_row(parent: VBoxContainer, label_key: String, color: Color) -> ProgressBar:
	var row := UI.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(UI.label(label_key, 13, color))
	var bar := UI.progress(1.0, color)
	bar.custom_minimum_size = Vector2(168, 14)
	bar.value = 0
	row.add_child(bar)
	row.visible = false
	parent.add_child(row)
	return bar

var _bar_tween := {}   # per-bar value tween, killed before retweening so they don't stack

## Smoothly move a meter to a new value; on a meaningful drop, flash it to signal damage.
func _set_bar(bar: ProgressBar, new_value: float) -> void:
	if bar == null:
		return
	var old: float = bar.value
	var prev = _bar_tween.get(bar)
	if prev != null and prev.is_valid():
		prev.kill()
	var tw := create_tween()
	tw.tween_property(bar, "value", new_value, 0.18)
	_bar_tween[bar] = tw
	if old - new_value > 2.0:
		# A drop on a tracked meter right after an offering is RELIEF (calm green), not a hit
		# (red) — so feeding the souls doesn't read like taking damage. (AUDIT#28)
		var relief := _calm_t > 0.0 and (bar == _crowd_bar or bar == _grievance_bar)
		var flash := Color(0.6, 1.3, 0.7) if relief else Color(1.4, 0.7, 0.7)
		var ft := create_tween()
		ft.tween_property(bar, "modulate", flash, 0.06)
		ft.tween_property(bar, "modulate", Color(1, 1, 1), 0.15)

func _ctrl_btn(key: String, cb: Callable, w: float = 180.0, action: String = "") -> Button:
	var b := UI.button(key, w, 46)
	b.add_theme_font_size_override("font_size", 14)   # compact so label + key glyph fit
	b.clip_text = true
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	# Every control press now gives an audible click — the most-pressed surface in the game
	# was silent, so a cooldown/empty no-op read as a broken button. (backlog#12)
	b.pressed.connect(func():
		Audio.play_sfx("ui_click", -12.0)
		cb.call())
	# Stamp the bound key on the button so the keyboard-first design is visible without
	# opening the help panel; read from the InputMap so it survives rebinds. (backlog#11)
	if action != "":
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr(key) + _key_suffix(action)
	return b

## The bound key letter for an action, e.g. "A" (or "" if unbound). Survives rebinds.
func _key_glyph(action: String) -> String:
	if not InputMap.has_action(action):
		return ""
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var kc: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
			return OS.get_keycode_string(kc)
	return ""

func _key_suffix(action: String) -> String:
	var g := _key_glyph(action)
	return "  [%s]" % g if g != "" else ""

## Brief danger-flash when a press can't act (cooldown / out of resource), so a no-op
## never reads as a broken button. (backlog#12)
func _deny_flash(b: Button) -> void:
	if b == null:
		return
	var base := b.modulate
	var tw := create_tween()
	tw.tween_property(b, "modulate", UI.COL_DANGER, 0.08)
	tw.tween_property(b, "modulate", base, 0.14)

func _press_incense() -> void:
	if _c._nhang <= 0:
		_deny_flash(_incense_btn)
	else:
		_c.request_light_incense()

func _press_bell() -> void:
	if _c._bell_cd > 0.0:
		_deny_flash(_bell_btn)
	else:
		_c.request_ring_bell()

func _press_offering() -> void:
	if _c.offerings <= 0:
		_deny_flash(_offering_btn)
	else:
		_c.request_offering()

# Top-right keybindings cheat-sheet, under the offerings count. Toggle with the
# header button or the H key (request_toggle from NightController).
func _build_help() -> void:
	_help_panel = Control.new()
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_help_panel, 1, 0, 1, 0, -288, 210, -22, 454)
	add_child(_help_panel)
	var bg := UI.color_rect(Color(0.04, 0.05, 0.07, 0.75))
	UI.full(bg)
	_help_panel.add_child(bg)
	var col := UI.vbox(3)
	UI.place(col, 0, 0, 1, 1, 12, 8, -12, -8)
	_help_panel.add_child(col)
	_help_col = col
	var hdr := UI.button("HELP_TITLE", 0, 30)
	hdr.flat = true
	hdr.mouse_filter = Control.MOUSE_FILTER_STOP
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.pressed.connect(toggle_help)
	col.add_child(hdr)
	_help_lines = UI.vbox(2)
	col.add_child(_help_lines)
	for k in ["HELP_LOOK", "HELP_CAM", "HELP_DOORS", "HELP_LIGHTS", "HELP_RITUAL", "HELP_ITEM", "HELP_PHONE", "HELP_OFFERING2", "HELP_PAUSE"]:
		_help_lines.add_child(UI.label(k, 15, UI.COL_DIM))
	_fit_help_panel()

func toggle_help() -> void:
	if _help_lines:
		_help_lines.visible = not _help_lines.visible
		_fit_help_panel()

# Shrink/grow the panel so its background covers only the visible content. With
# the hint lines hidden the box wraps just the "Phím tắt" title instead of
# leaving an empty rectangle. col is inset 8px top + 8px bottom inside the panel.
func _fit_help_panel() -> void:
	if not (_help_panel and _help_col):
		return
	await get_tree().process_frame
	_help_panel.offset_bottom = _help_panel.offset_top + _help_col.get_combined_minimum_size().y + 16

## Drive the persistent Night-1 tutorial banner. Empty key hides it.
func set_tutorial_prompt(key: String, step: int = -1, total: int = 0) -> void:
	if _tut_panel == null:
		return
	if key == "":
		_tut_panel.visible = false
		return
	_tut_panel.visible = true
	# Show "(2/5)" progress so the lesson has a sense of length and the freeze reads as
	# deliberate, not stuck. (AUDIT#26)
	var prefix := "(%d/%d)  " % [step + 1, total] if step >= 0 and total > 0 else ""
	_tut_label.text = prefix + tr(key)

func _connect() -> void:
	Events.power_changed.connect(func(c, m): _set_bar(_power_bar, c); _power_num.text = "%d" % int(round(c)))
	Events.via_changed.connect(func(c, m): _set_bar(_via_bar, (c / m) * 100.0))
	Events.via_state_changed.connect(_on_via_state)
	Events.clock_advanced.connect(_refresh_clock)
	Events.hour_reached.connect(_on_hour_reached)
	Events.door_toggled.connect(func(s, closed): _update_door(s, closed))
	Events.light_toggled.connect(func(s, on): _update_light(s, on))
	Events.notify.connect(_on_notify)
	Events.crowd_changed.connect(_on_crowd)
	Events.grievance_changed.connect(_on_grievance)
	Events.huong_changed.connect(_on_huong)
	Events.incense_changed.connect(_on_incense)
	Events.phone_ring.connect(_on_phone_ring)
	Events.coins_changed.connect(_on_coins)
	Events.vendor_state_changed.connect(_on_vendor_state)
	Events.investigation_updated.connect(_on_investigation)
	Events.anomaly_tagged.connect(func(_id): _clue_flash = 1.0)
	_on_investigation(Save.clue_count())   # show progress carried in from earlier nights
	_night.text = tr("NIGHT_LABEL").format([str(Game.current_night)])
	_refresh_offerings()
	_coins_lbl.text = "%s: %d" % [tr("HUD_COINS"), _c.coins]
	# Seed the door/light buttons with their written state from the start.
	_update_door(GameEnums.Side.LEFT, false)
	_update_door(GameEnums.Side.RIGHT, false)
	_update_light(GameEnums.Side.LEFT, false)
	_update_light(GameEnums.Side.RIGHT, false)
	Events.offering_placed.connect(func(_l): _refresh_offerings(); _calm_t = 0.6)

## Refresh the offerings count, tinting it red when only 1-2 remain (mirrors the
## incense-out tint) so a player notices they're nearly out of altar fuel.
func _refresh_offerings() -> void:
	var n: int = _c.offerings
	_offerings_lbl.text = "%s: %d" % [tr("HUD_OFFERINGS"), n]
	_offerings_lbl.modulate = Color(0.95, 0.45, 0.4) if (n >= 1 and n <= 2) else Color(1, 1, 1)

func _process(delta: float) -> void:
	_pulse_t += delta
	if _calm_t > 0.0:
		_calm_t = maxf(0.0, _calm_t - delta)
	_update_door_cue()
	_update_bell_cooldown()
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	# When nothing is showing, pull the next queued toast (teaching lines were pushed to
	# the front so a survival hint always wins over flavor). (backlog#10)
	if _toast_t <= 0.0 and not _toast_queue.is_empty():
		var item: Dictionary = _toast_queue.pop_front()
		_show_toast(item["key"], item["text"])
	if _clue_flash > 0.0 and _clue_lbl:
		_clue_flash = maxf(0.0, _clue_flash - delta * 1.5)
		_clue_lbl.modulate = Color(1, 1, 1).lerp(Color(1.0, 0.92, 0.5), _clue_flash)
		_clue_lbl.scale = Vector2.ONE * (1.0 + 0.12 * _clue_flash)
	# Persistent warnings — pick the active KEY from cheap state first, and only re-resolve
	# the string + touch the Label/Panel when it actually changes (was: up to 4 tr() lookups
	# + two unconditional writes every frame, on a banner that is usually empty). (AUDIT#3)
	var key := ""
	if _c.power <= 20.0 and _c.power > 0.0:
		key = "WARNING_LOW_POWER"
	if _c.via_state == GameEnums.ViaState.SHAKEN:
		key = "WARNING_VIA_SHAKEN"   # softer amber tier before the red CRITICAL (AUDIT#24)
	if _c.via_state == GameEnums.ViaState.CRITICAL:
		key = "WARNING_LOW_VIA"
	if _vendor_state == GameEnums.VendorState.HOSTILE:
		key = "VENDOR_HOSTILE"
	if not _c._powered:
		key = "POWER_OUT"
	if key != _warn_key:
		_warn_key = key
		_warn.text = tr(key) if key != "" else ""
		_warn.add_theme_color_override("font_color", UI.COL_WARN if key == "WARNING_VIA_SHAKEN" else UI.COL_DANGER)
		if _warn_panel:
			_warn_panel.visible = key != ""

func _refresh_clock(m: int) -> void:
	var h := int(float(m) / 60.0)
	var mm := m % 60
	var disp_h := 12 if h == 0 else h
	_clock.text = "%d:%02d %s" % [disp_h, mm, tr("CLOCK_AM")]
	if _dawn_bar:
		_dawn_bar.value = _c.night_progress()

## Each in-game hour, briefly pulse the clock toward warm gold so time passing reads
## as a beat (same flash feel as the clue tracker).
func _on_hour_reached(_hour: int) -> void:
	if _clock == null:
		return
	_clock.pivot_offset = _clock.size * 0.5
	var gold := Color(1.0, 0.86, 0.45)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_clock, "modulate", gold, 0.18)
	tw.tween_property(_clock, "scale", Vector2.ONE * 1.12, 0.18)
	tw.chain().set_parallel(true)
	tw.tween_property(_clock, "modulate", Color(1, 1, 1), 0.22)
	tw.tween_property(_clock, "scale", Vector2.ONE, 0.22)

func _on_via_state(state: int) -> void:
	# tint the vía bar by state
	var col := Color(0.6, 0.82, 0.78)
	if state == GameEnums.ViaState.SHAKEN:
		col = Color(0.9, 0.75, 0.3)
	elif state == GameEnums.ViaState.CRITICAL:
		col = Color(0.85, 0.25, 0.25)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(5)
	_via_bar.add_theme_stylebox_override("fill", sb)

func _update_door(side: int, closed: bool) -> void:
	var b: Button = _door_btn[side]
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var base := "DOOR_LEFT" if side == GameEnums.Side.LEFT else "DOOR_RIGHT"
	var act := "left_door" if side == GameEnums.Side.LEFT else "right_door"
	# Pair the colour with a written state so it's readable under pressure / colour-blind,
	# and stamp the bound key so the control is self-documenting. (backlog#11)
	b.text = "%s · %s%s" % [tr(base), tr("DOOR_SHUT") if closed else tr("DOOR_OPEN"), _key_suffix(act)]
	b.modulate = Color(0.5, 1.0, 0.6) if closed else Color(1, 1, 1)

func _update_light(side: int, on: bool) -> void:
	var b: Button = _light_btn[side]
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var base := "LIGHT_LEFT" if side == GameEnums.Side.LEFT else "LIGHT_RIGHT"
	var act := "left_light" if side == GameEnums.Side.LEFT else "right_light"
	b.text = "%s · %s%s" % [tr(base), tr("LIGHT_ON") if on else tr("LIGHT_OFF"), _key_suffix(act)]
	b.modulate = Color(1.0, 0.95, 0.5) if on else Color(1, 1, 1)
	_light_on[side] = on   # remembered so the per-frame door cue can restore the right tint

## Briefly pulse a doorway light button toward warm amber so a threat's arrival side
## is visible. Called (guarded) by night_controller when a threat reaches a door.
func flash_side(side: int) -> void:
	var b: Button = _light_btn.get(side)
	if b == null:
		return
	var base := b.modulate
	var amber := Color(1.0, 0.78, 0.35)
	var tw := create_tween()
	tw.tween_property(b, "modulate", amber, 0.12)
	tw.tween_property(b, "modulate", base, 0.13)

## Persistent which-door cue: while a path-threat looms at a door, pulse that side's light
## button amber so the threatened side stays legible after the arrival blink/toast fade —
## without revealing the threat itself (you still flick the light to see it). (AUDIT#23)
func _update_door_cue() -> void:
	if _c.director == null:
		return
	var glow := 0.5 + 0.5 * sin(_pulse_t * 6.0)
	var amber := Color(1.0, 0.55, 0.2).lerp(Color(1.0, 0.82, 0.4), glow)
	for side in [GameEnums.Side.LEFT, GameEnums.Side.RIGHT]:
		var b: Button = _light_btn.get(side)
		if b == null:
			continue
		if _c.director.threat_at_door(side) != null:
			b.modulate = amber
		else:
			b.modulate = Color(1.0, 0.95, 0.5) if _light_on.get(side, false) else Color(1, 1, 1)

## Dim the bell button while its 18s cooldown runs so a mashed press reads as "waiting",
## not a broken button. Change-guarded so it never stomps a denied-press flash. (AUDIT#25)
func _update_bell_cooldown() -> void:
	if _bell_btn == null:
		return
	var cooling: bool = _c._bell_cd > 0.0
	if cooling != _bell_cooling:
		_bell_cooling = cooling
		_bell_btn.modulate = Color(0.55, 0.55, 0.62) if cooling else Color(1, 1, 1)

func _is_teaching(key: String) -> bool:
	return key.begins_with("COUNTER_") or key == "ALTAR_DRAFT" or key == "CONTROLS_HEXED"

## Story/lesson keys hold longer so the player can actually read them.
const _TOAST_STORY_KEYS := ["MATROI_RULE", "CAT_WARN", "INVEST_GOAL"]

func _toast_hold(key: String, tr_text: String) -> float:
	# Scale dwell to text length, with a longer floor for story/lesson beats.
	var t := clampf(2.6 + tr_text.length() * 0.04, 2.6, 6.0)
	if key.begins_with("PHONE_N") or key.begins_with("COUNTER_") or key in _TOAST_STORY_KEYS:
		t = maxf(t, 5.5)
	return t

func _show_toast(key: String, tr_text: String) -> void:
	_toast.text = tr_text
	_toast_t = _toast_hold(key, tr_text)
	_toast.modulate.a = 1.0

func _on_notify(key: String, args: Array) -> void:
	var tr_text: String = tr(key).format(args) if not args.is_empty() else tr(key)
	# If a toast is still comfortably on screen, QUEUE rather than clobber. Teaching lines
	# (COUNTER_*, altar/hex warnings) jump ahead of flavor so a survival hint is never lost
	# behind a quip; the backlog caps at 3. (backlog#10)
	if _toast_t > 1.0:
		var item := {"key": key, "text": tr_text}
		if _is_teaching(key):
			_toast_queue.push_front(item)
		else:
			_toast_queue.push_back(item)
		if _toast_queue.size() > 3:
			_toast_queue = _toast_queue.slice(0, 3)
		return
	_show_toast(key, tr_text)

func _on_crowd(level: float) -> void:
	_crowd_bar.get_parent().visible = level > 0.01
	_crowd_bar.value = level

func _on_grievance(level: float) -> void:
	_grievance_bar.get_parent().visible = level > 0.01
	_grievance_bar.value = level

func _on_huong(level: float) -> void:
	_huong_bar.value = level
	# tint toward danger as the incense burns down (only swap the stylebox when the
	# danger bucket actually changes — this fires every frame)
	var danger := level <= 0.25
	if danger == _huong_danger:
		return
	_huong_danger = danger
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.85, 0.3, 0.2) if danger else Color(1.0, 0.62, 0.2)
	sb.set_corner_radius_all(5)
	_huong_bar.add_theme_stylebox_override("fill", sb)

func _on_incense(stock: int) -> void:
	# Surface the finite nhang count on the incense button; red when you're out.
	if _incense_btn:
		_incense_btn.text = "%s (%d)%s" % [tr("HUD_INCENSE"), stock, _key_suffix("light_incense")]
		_incense_btn.modulate = Color(1, 1, 1) if stock > 0 else Color(0.95, 0.45, 0.4)

func _on_phone_ring(active: bool, fake: bool) -> void:
	_answer_btn.visible = active
	# A warped ring is conveyed by text, not just the red tint (colour-blind safe).
	_answer_btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_answer_btn.text = tr("ACTION_ANSWER") + ("  (?!)" if fake else "") + _key_suffix("answer_phone")
	_answer_btn.modulate = Color(0.95, 0.4, 0.35) if fake else Color(0.6, 0.9, 0.7)

func _on_coins(amount: int) -> void:
	_coins_lbl.text = "%s: %d" % [tr("HUD_COINS"), amount]

func _on_investigation(count: int) -> void:
	if _clue_lbl == null:
		return
	_clue_lbl.text = tr("HUD_CLUES") % count
	_clue_lbl.visible = count > 0
	_clue_flash = 1.0

func _on_vendor_state(state: int) -> void:
	_vendor_state = state
	_invite_btn.visible = state == GameEnums.VendorState.SHOP

func set_item(def: ItemDef) -> void:
	if def == null:
		_item_icon.texture = load("res://assets/art/ui/item_slot.svg")
		_use_btn.disabled = true
	else:
		if ResourceLoader.exists(def.icon_path):
			_item_icon.texture = load(def.icon_path)
		_use_btn.disabled = false
