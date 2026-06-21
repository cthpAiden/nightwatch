extends Control
## The night HUD: power + vía meters, clock, night label, the door/light/camera/
## offering/item controls, the Ma-da water buttons, and transient toasts/warnings.
## Built in code; reads the controller and listens to Events.

var _c   # NightController

var _power_bar: ProgressBar
var _via_bar: ProgressBar
var _clock: Label
var _night: Label
var _toast: Label
var _warn: Label
var _offerings_lbl: Label
var _crowd_bar: ProgressBar
var _water_bar: ProgressBar
var _item_icon: TextureRect
var _use_btn: Button
var _answer_btn: Button
var _drain_btn: Button
var _invite_btn: Button
var _help_panel: Control
var _help_lines: VBoxContainer
var _door_btn := {}
var _light_btn := {}
var _toast_t := 0.0
var _vendor_state := GameEnums.VendorState.IDLE

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
	UI.place(meters, 0, 0, 0, 0, 22, 16, 322, 110)
	add_child(meters)
	var prow := UI.hbox(8)
	prow.add_child(UI.texture_rect("res://assets/art/ui/power_icon.svg", TextureRect.STRETCH_KEEP_ASPECT))
	prow.get_child(0).custom_minimum_size = Vector2(26, 26)
	_power_bar = UI.progress(100.0, Color(0.91, 0.64, 0.24))
	_power_bar.custom_minimum_size = Vector2(240, 22)
	prow.add_child(_power_bar)
	meters.add_child(prow)
	var vrow := UI.hbox(8)
	vrow.add_child(UI.texture_rect("res://assets/art/ui/via_icon.svg", TextureRect.STRETCH_KEEP_ASPECT))
	vrow.get_child(0).custom_minimum_size = Vector2(26, 26)
	_via_bar = UI.progress(100.0, Color(0.6, 0.82, 0.78))
	_via_bar.custom_minimum_size = Vector2(240, 22)
	vrow.add_child(_via_bar)
	meters.add_child(vrow)

	# clock + night (top-center)
	var cbox := UI.vbox(0)
	UI.place(cbox, 0.5, 0, 0.5, 0, -140, 12, 140, 96)
	add_child(cbox)
	_clock = UI.text_label("12:00", 44, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_child(_clock)
	_night = UI.label("HUD_NIGHT", 18, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	cbox.add_child(_night)

	# offerings + crowd/water (top-right)
	var rbox := UI.vbox(6)
	UI.place(rbox, 1, 0, 1, 0, -260, 16, -22, 120)
	add_child(rbox)
	_offerings_lbl = UI.text_label("", 18, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	rbox.add_child(_offerings_lbl)
	_crowd_bar = UI.progress(1.0, Color(0.7, 0.66, 0.5))
	_crowd_bar.custom_minimum_size = Vector2(220, 14)
	_crowd_bar.value = 0
	_crowd_bar.visible = false
	rbox.add_child(_crowd_bar)
	_water_bar = UI.progress(1.0, Color(0.43, 0.6, 0.65))
	_water_bar.custom_minimum_size = Vector2(220, 14)
	_water_bar.value = 0
	_water_bar.visible = false
	rbox.add_child(_water_bar)

	# left controls
	var lbox := UI.vbox(8)
	UI.place(lbox, 0, 1, 0, 1, 22, -150, 210, -22)
	add_child(lbox)
	_light_btn[GameEnums.Side.LEFT] = _ctrl_btn("LIGHT_LEFT", func(): _c.request_toggle_light(GameEnums.Side.LEFT))
	_door_btn[GameEnums.Side.LEFT] = _ctrl_btn("DOOR_LEFT", func(): _c.request_toggle_door(GameEnums.Side.LEFT))
	lbox.add_child(_light_btn[GameEnums.Side.LEFT])
	lbox.add_child(_door_btn[GameEnums.Side.LEFT])

	# right controls
	var rcbox := UI.vbox(8)
	UI.place(rcbox, 1, 1, 1, 1, -210, -150, -22, -22)
	add_child(rcbox)
	_light_btn[GameEnums.Side.RIGHT] = _ctrl_btn("LIGHT_RIGHT", func(): _c.request_toggle_light(GameEnums.Side.RIGHT))
	_door_btn[GameEnums.Side.RIGHT] = _ctrl_btn("DOOR_RIGHT", func(): _c.request_toggle_door(GameEnums.Side.RIGHT))
	rcbox.add_child(_light_btn[GameEnums.Side.RIGHT])
	rcbox.add_child(_door_btn[GameEnums.Side.RIGHT])

	# center controls
	var center := UI.hbox(10)
	UI.place(center, 0.5, 1, 0.5, 1, -250, -86, 250, -26)
	add_child(center)
	center.add_child(_ctrl_btn("HUD_CAM", func(): _c.request_toggle_monitor(), 110))
	center.add_child(_ctrl_btn("OFFERING_PROMPT", func(): _c.request_offering(), 150))
	var slot := UI.hbox(4)
	_item_icon = UI.texture_rect("res://assets/art/ui/item_slot.svg", TextureRect.STRETCH_KEEP_ASPECT)
	_item_icon.custom_minimum_size = Vector2(48, 48)
	slot.add_child(_item_icon)
	_use_btn = _ctrl_btn("HUD_ITEM", func(): _c.request_use_item(), 120)
	_use_btn.disabled = true
	slot.add_child(_use_btn)
	center.add_child(slot)

	# Ma da water buttons (hidden until relevant)
	var water := UI.hbox(8)
	UI.place(water, 0.5, 1, 0.5, 1, -190, -150, 190, -100)
	add_child(water)
	_drain_btn = _ctrl_btn("ACTION_CLOSE_DRAIN", func(): Events.office_action.emit("close_drain"), 170)
	_drain_btn.visible = false
	_answer_btn = _ctrl_btn("ACTION_ANSWER", func(): Events.intercom_answered.emit(), 150)
	_answer_btn.visible = false
	_answer_btn.modulate = Color(1.0, 0.6, 0.5)
	water.add_child(_drain_btn)
	water.add_child(_answer_btn)

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
	_warn = UI.label("", 20, UI.COL_DANGER, HORIZONTAL_ALIGNMENT_CENTER)
	UI.place(_warn, 0.5, 1, 0.5, 1, -300, -190, 300, -156)
	add_child(_warn)

func _ctrl_btn(key: String, cb: Callable, w: float = 180.0) -> Button:
	var b := UI.button(key, w, 46)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(cb)
	return b

# Top-right keybindings cheat-sheet, under the offerings count. Toggle with the
# header button or the H key (request_toggle from NightController).
func _build_help() -> void:
	_help_panel = Control.new()
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.place(_help_panel, 1, 0, 1, 0, -288, 128, -22, 372)
	add_child(_help_panel)
	var bg := UI.color_rect(Color(0.04, 0.05, 0.07, 0.62))
	UI.full(bg)
	_help_panel.add_child(bg)
	var col := UI.vbox(3)
	UI.place(col, 0, 0, 1, 1, 12, 8, -12, -8)
	_help_panel.add_child(col)
	var hdr := UI.button("HELP_TITLE", 0, 30)
	hdr.flat = true
	hdr.mouse_filter = Control.MOUSE_FILTER_STOP
	hdr.add_theme_font_size_override("font_size", 16)
	hdr.pressed.connect(toggle_help)
	col.add_child(hdr)
	_help_lines = UI.vbox(2)
	col.add_child(_help_lines)
	for k in ["HELP_LOOK", "HELP_CAM", "HELP_DOORS", "HELP_LIGHTS", "HELP_OFFERING2", "HELP_PAUSE"]:
		_help_lines.add_child(UI.label(k, 15, UI.COL_DIM))

func toggle_help() -> void:
	if _help_lines:
		_help_lines.visible = not _help_lines.visible

func _connect() -> void:
	Events.power_changed.connect(func(c, m): _power_bar.value = c)
	Events.via_changed.connect(func(c, m): _via_bar.value = (c / m) * 100.0)
	Events.via_state_changed.connect(_on_via_state)
	Events.clock_advanced.connect(_refresh_clock)
	Events.door_toggled.connect(func(s, closed): _update_door(s, closed))
	Events.light_toggled.connect(func(s, on): _update_light(s, on))
	Events.notify.connect(_on_notify)
	Events.water_lure.connect(_on_water_lure)
	Events.water_level.connect(_on_water_level)
	Events.crowd_changed.connect(_on_crowd)
	Events.vendor_state_changed.connect(_on_vendor_state)
	_night.text = tr("NIGHT_LABEL").format([str(Game.current_night)])
	_offerings_lbl.text = "%s: %d" % [tr("HUD_OFFERINGS"), _c.offerings]
	Events.offering_placed.connect(func(_l): _offerings_lbl.text = "%s: %d" % [tr("HUD_OFFERINGS"), _c.offerings])

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	# persistent warnings
	var w := ""
	if _c.power <= 20.0 and _c.power > 0.0:
		w = tr("WARNING_LOW_POWER")
	if _c.via_state == GameEnums.ViaState.CRITICAL:
		w = tr("WARNING_LOW_VIA")
	if _vendor_state == GameEnums.VendorState.HOSTILE:
		w = tr("VENDOR_HOSTILE")
	if not _c._powered:
		w = tr("POWER_OUT")
	_warn.text = w

func _refresh_clock(m: int) -> void:
	var h := m / 60
	var mm := m % 60
	var disp_h := 12 if h == 0 else h
	_clock.text = "%d:%02d %s" % [disp_h, mm, tr("CLOCK_AM")]

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
	b.modulate = Color(0.5, 1.0, 0.6) if closed else Color(1, 1, 1)

func _update_light(side: int, on: bool) -> void:
	var b: Button = _light_btn[side]
	b.modulate = Color(1.0, 0.95, 0.5) if on else Color(1, 1, 1)

func _on_notify(key: String, args: Array) -> void:
	_toast.text = tr(key).format(args) if not args.is_empty() else tr(key)
	_toast_t = 2.6
	_toast.modulate.a = 1.0

func _on_water_lure(active: bool) -> void:
	_answer_btn.visible = active
	if active:
		_drain_btn.visible = true

func _on_water_level(level: float) -> void:
	_water_bar.visible = level > 0.01
	_water_bar.value = level
	if level > 0.01:
		_drain_btn.visible = true

func _on_crowd(level: float) -> void:
	_crowd_bar.visible = level > 0.01
	_crowd_bar.value = level

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
