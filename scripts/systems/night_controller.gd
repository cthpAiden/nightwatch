extends Node
## Root of scenes/Night.tscn. Builds the whole night in code and runs it:
## the 12AM->6AM clock, power + vía economies, input routing, the win/lose and
## jumpscare flow, and wiring between the room, director, vendor, items and UI.
## Threats call the small public API at the bottom (is_door_closed, add_via, ...).

const NIGHT_MINUTES := 360.0            # 00:00 -> 06:00

var config: NightConfig
var room                                 # guard_room.gd (Node3D)
var director: ThreatDirector
var vendor                               # vendor.gd
var item_system                          # item_system.gd

var hud
var monitor
var shop
var cassette
var pause
var _ui_layer: CanvasLayer
var _jumpscare_rect: TextureRect
var _flash: ColorRect              # white burst on a jumpscare
var _jump_jitter_t := 0.0          # seconds of remaining jumpscare position-jitter
var _vignette: TextureRect
var _drone_on := false             # tension drone bed currently faded in

var power := 100.0
var via := 100.0
var via_max := 100.0
var via_state := GameEnums.ViaState.NORMAL
var game_minutes := 0.0
var _last_minute := -1
var _last_hour := -1

var monitor_open := false
var current_cam := MapGraph.GATE
var offerings := 0
var item_held: ItemDef = null
var ward_tokens := 0
var via_drain_mult := 1.0
var startle_resist := 0.0
var reveal_timer := 0.0
var barrier_timer := 0.0
var speed_timer := 0.0
var taint_timer := 0.0
var _via_drain_cd := 0.0     # pauses vía regen briefly after any drain
var _agitation := 0.0        # "panic" signal (fast pan + rapid cam-switching) for Ma trơi

# Living-altar ritual ("hương" incense protection) — the core active defense.
var huong := 100.0
var huong_max := 100.0
var altar_lit := true        # false = candles guttered by a cold draft; relight!
var coins := 0               # vàng mã (spirit money): shop + shrine-upgrade currency
var phone                    # phone_system.gd
var _aggro_mult := 1.0       # global threat aggression (bánh lạ curse) read by meters
var _huong_decay := 1.3      # incense burn rate /s (set per night + upgrades at begin)
var _bright_altar := false   # shrine upgrade: stronger suppression while lit
var _door_drain_mult := 1.0  # shrine upgrade: sturdier doors
var _incense_cd := 0.0
var _nhang := 0              # incense sticks in hand — each manual relight burns one
var _bell_cd := 0.0
var _bell_cd_max := 18.0
var _draft_cd := 35.0
var _auto_relight := false   # shrine upgrade: one free relight when it gutters
var _tag_cds := {}           # threat_id -> camera-anomaly tag cooldown
var _hex_t := 0.0            # Ma trơi lock-on jinx: doors/lights flail open briefly
var _crowd_level := 0.0      # Cô hồn smother (0..1) driving the view-blocking overlay
var _crowd_layer: CanvasLayer
var _crowd_overlay: TextureRect

var _running := false
var _ending := false
var _powered := true
var _low_power_warned := false
var _tut_step := -1          # -1 = no tutorial running; otherwise index into TUT_STEPS
var _tut_incense := false    # set when the player hand-lights incense (tutorial step)

func _ready() -> void:
	if OS.has_environment("NW_NIGHT"):
		Game.current_night = int(OS.get_environment("NW_NIGHT"))
		Game.active_config = null
	config = Game.active_config if Game.active_config else Game.get_night_config(Game.current_night)
	if OS.has_environment("NW_FASTWIN"):   # debug: race to 06:00 with no threats
		config.seconds_per_hour = 1.0
		config.threat_levels = {}
		config.vendor_enabled = false
	via_max = config.via_max
	via = via_max
	power = 100.0
	offerings = config.offerings_start
	_build_world()
	_build_ui()
	item_system = load("res://scripts/systems/item_system.gd").new()
	item_system.name = "ItemSystem"
	add_child(item_system)
	item_system.setup(self)
	director.setup(self, config)
	director.set_paused(true)
	_connect_events()
	_start_audio()
	set_process(true)
	set_process_unhandled_input(true)
	_start_sequence()

# --- build ------------------------------------------------------------------
func _build_world() -> void:
	room = load("res://scripts/systems/guard_room.gd").new()
	room.name = "GuardRoom"
	add_child(room)
	room.set_look_enabled(false)   # locked until the night begins
	director = ThreatDirector.new()
	director.name = "Director"
	add_child(director)
	vendor = load("res://scripts/systems/vendor.gd").new()
	vendor.name = "Vendor"
	add_child(vendor)
	vendor.setup(self, config)
	phone = load("res://scripts/systems/phone_system.gd").new()
	phone.name = "Phone"
	add_child(phone)
	phone.setup(self)

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)

	_vignette = UI.texture_rect("res://assets/art/ui/vignette.svg", TextureRect.STRETCH_SCALE)
	UI.full(_vignette)
	_ui_layer.add_child(_vignette)

	hud = load("res://scripts/ui/hud.gd").new()
	_ui_layer.add_child(hud)
	hud.setup(self)

	monitor = load("res://scripts/systems/camera_system.gd").new()
	_ui_layer.add_child(monitor)
	monitor.setup(self)
	monitor.visible = false

	shop = load("res://scripts/ui/shop_ui.gd").new()
	_ui_layer.add_child(shop)
	shop.setup(self)
	shop.visible = false

	cassette = load("res://scripts/ui/cassette_ui.gd").new()
	_ui_layer.add_child(cassette)
	cassette.setup(self)
	cassette.visible = false

	pause = load("res://scripts/ui/pause_menu.gd").new()
	_ui_layer.add_child(pause)
	pause.setup(self)
	pause.visible = false

	# Cô hồn "smother": a wall of pressing faces that fades in over the whole screen
	# (and the camera feed) as the crowd swells — information denial until you feed them.
	_crowd_layer = CanvasLayer.new()
	_crowd_layer.layer = 12   # above the monitor/HUD (10), below jumpscare (50)
	add_child(_crowd_layer)
	_crowd_overlay = UI.texture_rect("res://assets/art/threats/co_hon_crowd.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(_crowd_overlay)
	_crowd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crowd_overlay.modulate.a = 0.0
	_crowd_layer.add_child(_crowd_overlay)

	var jl := CanvasLayer.new()
	jl.layer = 50
	add_child(jl)
	_jumpscare_rect = TextureRect.new()
	UI.full(_jumpscare_rect)
	_jumpscare_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_jumpscare_rect.visible = false
	jl.add_child(_jumpscare_rect)
	_flash = ColorRect.new()
	UI.full(_flash)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jl.add_child(_flash)

func _connect_events() -> void:
	Events.jumpscare_started.connect(_on_jumpscare)
	Events.threat_at_door.connect(func(_id, side): _on_threat_at_door(side))
	Events.threat_left_door.connect(func(_id, side): _refresh_door_sprite(side))
	Events.crowd_changed.connect(func(level): _crowd_level = level)
	Events.via_state_changed.connect(_on_via_state_fx)

## A figure arriving at the door: refresh its sprite, and land a small scare beat
## (jolt + low sting) so the doorway threat has weight instead of a silent pop-in.
func _on_threat_at_door(side: int) -> void:
	_refresh_door_sprite(side)
	if room:
		room.add_shake(0.32)
	Audio.play_sfx("stinger", -16.0)

## Reactive vignette: the screen edges bruise toward red as your vía fails.
func _on_via_state_fx(state: int) -> void:
	if _vignette == null:
		return
	var tw := create_tween()
	if state == GameEnums.ViaState.CRITICAL:
		tw.tween_property(_vignette, "modulate", Color(1.0, 0.46, 0.46, 1.0), 0.4)
	elif state == GameEnums.ViaState.SHAKEN:
		tw.tween_property(_vignette, "modulate", Color(1.0, 0.78, 0.78, 1.0), 0.6)
	else:
		tw.tween_property(_vignette, "modulate", Color(1, 1, 1, 1), 0.8)

func _start_audio() -> void:
	Audio.play_music("ambience_dread" if config.night_index >= 3 else "ambience_night")

func _start_sequence() -> void:
	# Debug: NW_SKIP_TAPE=1 begins the night immediately (used for headless tests).
	if OS.has_environment("NW_SKIP_TAPE"):
		_begin_night()
		return
	# Show the previous guard's tape first (tutorial + lore), then begin the night.
	if config.has_tape and Save.tapes_unlocked.has(config.night_index):
		cassette.show_tape(config.night_index)
		cassette.closed.connect(_begin_night, CONNECT_ONE_SHOT)
	else:
		_begin_night()

func _begin_night() -> void:
	_running = true
	_init_altar()
	_apply_shrine_upgrades()
	coins = Save.coins
	Events.coins_changed.emit(coins)
	# Record every spirit on tonight's roster so its Bestiary (Hồ Sơ Ma) file unlocks.
	for id in config.threat_levels:
		Save.see_threat(id)
	if config.vendor_enabled:
		Save.see_threat("ba_hang_rong")
	# Start with one stick of incense (nhang) in hand so the player always has the
	# calm tool available and learns what it does.
	if item_held == null:
		var nhang := ItemRegistry.get_def("nhang")
		if nhang:
			acquire_item(nhang)
	# Night 1 runs a short, safe, hands-on lesson (no threats act until it's done);
	# every other night (and headless tests) goes live immediately.
	if not OS.has_environment("NW_SKIP_TAPE") and not Game.is_custom and Game.current_night == 1:
		_begin_tutorial()
	else:
		_engage_night()
	if OS.has_environment("NW_OPEN_CAM"):   # dev: raise the camera panel for screenshots
		_set_monitor(true)

## Go live: unpause the director, start the vendor + phone, and announce the shift.
func _engage_night() -> void:
	director.set_paused(false)
	vendor.begin()
	if phone:
		phone.begin()
	Events.notify.emit("NIGHT_BEGIN", [])

# --- Night-1 hands-on tutorial ---------------------------------------------
const TUT_STEPS := ["TUT_LOOK", "TUT_INCENSE", "TUT_DOOR", "TUT_CAM"]

func _begin_tutorial() -> void:
	_tut_step = 0
	_tut_incense = false
	director.set_paused(true)
	Events.notify.emit(TUT_STEPS[0], [])

## Advance the lesson when the current step's action is performed. The rest of the
## sim is frozen (see _process) so nothing can hurt the player mid-lesson.
func _check_tutorial() -> void:
	var done := false
	match _tut_step:
		0: done = get_pan_speed() > 0.5            # look around (mouse to edges)
		1: done = _tut_incense                     # press R to light incense
		2: done = room.is_door_closed(GameEnums.Side.LEFT) or room.is_door_closed(GameEnums.Side.RIGHT)
		3: done = monitor_open                      # press C to raise the cameras
	if not done:
		return
	_tut_step += 1
	if _tut_step >= TUT_STEPS.size():
		_tut_step = -1
		Events.notify.emit("TUT_DONE", [])
		_engage_night()
	else:
		Events.notify.emit(TUT_STEPS[_tut_step], [])

func _init_altar() -> void:
	huong = huong_max
	altar_lit = true
	# Later nights burn the incense down faster, so you must tend it more often.
	_huong_decay = 1.0 + 0.14 * float(config.night_index)
	# Incense is now a real resource: a finite bundle of nhang per night. Each manual
	# relight burns one and only tops the meter up part-way, so you must spend them
	# deliberately rather than reflex-tapping a free "win button".
	_nhang = 5
	Events.incense_changed.emit(_nhang)
	if room:
		room.set_huong(1.0)
		room.set_altar_lit(true)
	Events.huong_changed.emit(1.0)
	Events.altar_lit_changed.emit(true)

func _apply_shrine_upgrades() -> void:
	var up: Dictionary = Save.upgrades
	if up.get("incense_slow", false):
		_huong_decay *= 0.7
	if up.get("bright_altar", false):
		_bright_altar = true
	if up.get("sturdy_doors", false):
		_door_drain_mult = 0.7
	if up.get("fast_bell", false):
		_bell_cd_max *= 0.6
	if up.get("auto_relight", false):
		_auto_relight = true
	if up.get("extra_ward", false):
		ward_tokens += 1
	if up.get("more_offerings", false):
		offerings += 2

# --- main loop --------------------------------------------------------------
func _process(delta: float) -> void:
	# Jumpscare jitter runs even after the night has ended (death freeze) so the scare
	# keeps twitching during its hold.
	if _jump_jitter_t > 0.0:
		_jump_jitter_t -= delta
		var k := clampf(_jump_jitter_t / 0.5, 0.0, 1.0)
		_jumpscare_rect.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 16.0 * k
		if _jump_jitter_t <= 0.0:
			_jumpscare_rect.position = Vector2.ZERO
	if not _running:
		return
	# During the Night-1 lesson the whole sim is frozen except looking around and the
	# step we're teaching — nothing drains, no threats act, the clock doesn't move.
	if _tut_step >= 0:
		room.set_look_enabled(not monitor_open and not shop.visible and not pause.visible and not cassette.visible)
		_check_tutorial()
		return
	_advance_clock(delta)
	_update_power(delta)
	_update_via(delta)
	_update_timers(delta)
	# Panic/agitation: fast panning raises it (rapid cam-switching does too, in
	# on_camera_changed); it decays over time. Drives Ma trơi.
	if room.get_pan_speed() > 0.7:
		_agitation = minf(1.0, _agitation + delta * 2.0)
	_agitation = maxf(0.0, _agitation - delta * 0.7)
	# Look-pan only during free play — not on the monitor or behind a modal overlay.
	room.set_look_enabled(not monitor_open and not shop.visible and not pause.visible and not cassette.visible)
	director.night_progress = night_progress()
	director.broadcast_pan(room.get_pan_speed() > 0.7)
	# Re-broadcast the watched camera every frame so a threat that wanders under a
	# held view (e.g. Oan hồn) is correctly seen/unseen — fixes the stale _viewing flag.
	director.broadcast_view(current_cam if monitor_open else "")
	if monitor_open:
		room.set_desk_threat(_desk_threat_tex())   # mirror the threat onto the desk CRT
	_update_altar(delta)
	_refresh_door_sprite(GameEnums.Side.LEFT)
	_refresh_door_sprite(GameEnums.Side.RIGHT)
	_update_crowd_overlay(delta)
	_update_atmosphere()

## Drives the room's danger grade and the tension drone from how close to losing you
## are: low vía / low hương / a blackout sour the colour; a rusher at the door or a
## critical vía fades a low drone in under everything.
func _update_atmosphere() -> void:
	var via_danger := 1.0 - clampf(via / via_max, 0.0, 1.0)
	var huong_danger := 1.0 - clampf(huong / huong_max, 0.0, 1.0)
	var d := maxf(via_danger * 1.1, huong_danger * 0.6)
	if not _powered:
		d = maxf(d, 0.85)
	if room:
		room.set_dread(clampf(d, 0.0, 1.0))
	var looming := director.threat_at_door(GameEnums.Side.LEFT) != null \
		or director.threat_at_door(GameEnums.Side.RIGHT) != null
	var want_drone := looming or via_state == GameEnums.ViaState.CRITICAL
	if want_drone and not _drone_on:
		_drone_on = true
		Audio.start_loop("drone_tension", -16.0)
	elif not want_drone and _drone_on:
		_drone_on = false
		Audio.stop_loop("drone_tension")

func _advance_clock(delta: float) -> void:
	var rate := 60.0 / maxf(config.seconds_per_hour, 1.0)   # game-minutes per real second
	game_minutes += delta * rate
	var m := int(game_minutes)
	if m != _last_minute:
		_last_minute = m
		Events.clock_advanced.emit(m)
	# Fire every hour actually crossed so a long frame can never skip the chime
	# or, critically, the 06:00 win (which would softlock the night).
	var h := int(game_minutes) / 60
	while _last_hour < h:
		_last_hour += 1
		Events.hour_reached.emit(_last_hour)
		if _last_hour > 0 and _last_hour < 6:
			Audio.play_sfx("clock_chime", -10.0)
			_earn_coins(6)   # vàng mã for each hour you survive
	if game_minutes >= NIGHT_MINUTES:
		_win()

func _update_power(delta: float) -> void:
	if not _powered:
		return
	var drain := config.power_drain_idle
	var door_cost := config.power_drain_per_door * _door_drain_mult
	if room.is_door_closed(GameEnums.Side.LEFT):
		drain += door_cost
	if room.is_door_closed(GameEnums.Side.RIGHT):
		drain += door_cost
	if room.is_light_on(GameEnums.Side.LEFT):
		drain += config.power_drain_per_light
	if room.is_light_on(GameEnums.Side.RIGHT):
		drain += config.power_drain_per_light
	if monitor_open:
		drain += config.power_drain_camera
	power = maxf(0.0, power - drain * delta)
	Events.power_changed.emit(power, 100.0)
	# One-shot warning beep the first time power dips into the red.
	if power <= 20.0 and power > 0.0 and not _low_power_warned:
		_low_power_warned = true
		Audio.play_sfx("low_power_beep", -4.0)
	elif power > 26.0:
		_low_power_warned = false
	if power <= 0.0:
		_power_out()

func _power_out() -> void:
	if not _powered:
		return
	_powered = false
	Save.record_power_outage()
	room.set_powered(false)
	room.set_door(GameEnums.Side.LEFT, false)
	room.set_door(GameEnums.Side.RIGHT, false)
	director.broadcast_door(GameEnums.Side.LEFT, false)
	director.broadcast_door(GameEnums.Side.RIGHT, false)
	if monitor_open:
		_set_monitor(false)
	Audio.play_sfx("power_down", -2.0)
	if room:
		room.add_shake(0.6)
	Events.power_depleted.emit()
	Events.notify.emit("POWER_OUT", [])

func _update_via(delta: float) -> void:
	if _via_drain_cd > 0.0:
		_via_drain_cd = maxf(0.0, _via_drain_cd - delta)
	var looming := director.threat_at_door(GameEnums.Side.LEFT) != null \
		or director.threat_at_door(GameEnums.Side.RIGHT) != null
	# Regen only when nothing looms AND no drain happened very recently, so active
	# meter pressure (cô hồn / ma da / oan hồn) is a genuine net loss, not cancelled.
	if not looming and _via_drain_cd <= 0.0:
		var regen := 1.0 + night_progress() * 1.8
		via = minf(via_max, via + regen * delta)
		Events.via_changed.emit(via, via_max)
	if not _powered:
		add_via(-2.0 * delta)
	_update_via_state()
	if via <= 0.0:
		_via_zero()

func _update_via_state() -> void:
	var frac := via / via_max
	var st := GameEnums.ViaState.NORMAL
	if frac <= 0.15:
		st = GameEnums.ViaState.CRITICAL
	elif frac <= 0.4:
		st = GameEnums.ViaState.SHAKEN
	if st != via_state:
		via_state = st
		Events.via_state_changed.emit(st)
		director.broadcast_via_state(st)
		if st == GameEnums.ViaState.CRITICAL:
			Audio.start_loop("heartbeat", -6.0)
		else:
			Audio.stop_loop("heartbeat")

func _via_zero() -> void:
	if try_block_death("via"):
		via = via_max * 0.4
		# A meter threat (flood/crowd/agro) bled you to zero; without breaking its
		# hold the refilled vía is drained right back. Spend the ward to clear it.
		for t in director.threats:
			t.on_ward_save()
		Events.via_changed.emit(via, via_max)
		return
	_caught("via")

func _update_timers(delta: float) -> void:
	if reveal_timer > 0.0:
		reveal_timer = maxf(0.0, reveal_timer - delta)
	if barrier_timer > 0.0:
		barrier_timer = maxf(0.0, barrier_timer - delta)
	if taint_timer > 0.0:
		taint_timer = maxf(0.0, taint_timer - delta)
		if taint_timer == 0.0:
			via_drain_mult = 1.0
	if speed_timer > 0.0:
		speed_timer = maxf(0.0, speed_timer - delta)
		if speed_timer == 0.0:
			director.set_speed_all(1.0)
			_aggro_mult = 1.0
	for k in _tag_cds.keys():
		if _tag_cds[k] > 0.0:
			_tag_cds[k] = maxf(0.0, _tag_cds[k] - delta)
	if _hex_t > 0.0:
		_hex_t = maxf(0.0, _hex_t - delta)

## Cô hồn smother: blind the office (and especially the camera feed) as the crowd
## swells past ~55%. Hidden behind any modal so it can't trap the player off-screen.
func _update_crowd_overlay(delta: float) -> void:
	if _crowd_overlay == null:
		return
	var target := 0.0
	if not (shop.visible or cassette.visible or pause.visible):
		var press := clampf((_crowd_level - 0.55) / 0.45, 0.0, 1.0)
		# Pressing harder while you're trying to watch cameras — true information denial.
		target = press * (0.78 if monitor_open else 0.6)
	_crowd_overlay.modulate.a = move_toward(_crowd_overlay.modulate.a, target, delta * 1.5)

# --- input ------------------------------------------------------------------
func _unhandled_input(e: InputEvent) -> void:
	if _ending:
		return
	if e.is_action_pressed("pause_game"):
		request_pause()
		return
	if e.is_action_pressed("toggle_help"):
		hud.toggle_help()
		return
	if shop.visible or cassette.visible or pause.visible:
		return
	if not _running:
		return
	if e.is_action_pressed("toggle_cameras"):
		request_toggle_monitor()
		return
	if monitor_open:
		return
	if e.is_action_pressed("left_door"):
		request_toggle_door(GameEnums.Side.LEFT)
	elif e.is_action_pressed("right_door"):
		request_toggle_door(GameEnums.Side.RIGHT)
	elif e.is_action_pressed("left_light"):
		request_toggle_light(GameEnums.Side.LEFT)
	elif e.is_action_pressed("right_light"):
		request_toggle_light(GameEnums.Side.RIGHT)
	elif e.is_action_pressed("place_offering"):
		request_offering()
	elif e.is_action_pressed("light_incense"):
		request_light_incense()
	elif e.is_action_pressed("ring_bell"):
		request_ring_bell()
	elif e.is_action_pressed("answer_phone"):
		request_answer_phone()
	elif e.is_action_pressed("use_item"):
		request_use_item()
	elif e.is_action_pressed("close_drain"):
		Events.office_action.emit("close_drain")

# --- requests from UI / input ----------------------------------------------
func request_toggle_door(side: int) -> void:
	if not _powered or not _running:
		return
	if _hex_t > 0.0:
		Events.notify.emit("CONTROLS_HEXED", [])
		return
	var closed: bool = not room.is_door_closed(side)
	room.set_door(side, closed)
	director.broadcast_door(side, closed)

func request_toggle_light(side: int) -> void:
	if not _powered or not _running:
		return
	if _hex_t > 0.0:
		Events.notify.emit("CONTROLS_HEXED", [])
		return
	var on: bool = not room.is_light_on(side)
	room.set_light(side, on)
	director.broadcast_light(side, on)
	_refresh_door_sprite(side)

## Ma trơi lock-on: the wisp's panic jinx flails your doors/lights open and jams them
## for a moment, leaving you exposed to whatever is approaching. Punishes running.
func hex_controls(d: float) -> void:
	if not _running or not _powered:
		return
	_hex_t = maxf(_hex_t, d)
	room.set_door(GameEnums.Side.LEFT, false)
	room.set_door(GameEnums.Side.RIGHT, false)
	director.broadcast_door(GameEnums.Side.LEFT, false)
	director.broadcast_door(GameEnums.Side.RIGHT, false)
	Audio.play_sfx("power_down", -10.0)
	Events.notify.emit("CONTROLS_HEXED", [])

func request_toggle_monitor() -> void:
	if not _running or shop.visible or cassette.visible:
		return
	_set_monitor(not monitor_open)

func _set_monitor(open: bool) -> void:
	monitor_open = open
	monitor.visible = open
	room.set_look_enabled(not open)
	if open:
		monitor.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(monitor, "modulate:a", 1.0, 0.12)
		Audio.play_sfx("camera_up", -6.0)
		Audio.start_loop("static_loop", -22.0)
		monitor.show_feed(current_cam)
		director.broadcast_view(current_cam)
		room.set_desk_mirror(current_cam)   # desk CRT mirrors what you're watching
	else:
		Audio.play_sfx("camera_down", -6.0)
		Audio.stop_loop("static_loop")
		director.broadcast_view("")
		room.set_desk_idle()                # back to the idle slideshow
	Events.cameras_toggled.emit(open)

func on_camera_changed(cam_id: String) -> void:
	current_cam = cam_id
	_agitation = minf(1.0, _agitation + 0.45)   # flipping channels fast = panic
	director.broadcast_view(cam_id)
	room.set_desk_mirror(cam_id)
	Events.camera_changed.emit(cam_id)

## The threat texture (if any) to composite on the desk CRT for the watched camera.
func _desk_threat_tex() -> Texture2D:
	for t in director.threats:
		if t.current_location == current_cam:
			return t.current_texture()
	return null

func request_offering() -> void:
	if not _running:
		return
	if offerings <= 0:
		Events.notify.emit("OFFERING_NONE", [])
		return
	offerings -= 1
	Events.offering_placed.emit(MapGraph.GATE)
	director.broadcast_offering(MapGraph.GATE)
	add_via(14.0)
	Save.record_offering()
	Audio.play_sfx("offering_bell", -4.0)
	Events.notify.emit("OFFERING_DONE", [])

func request_use_item() -> void:
	if item_held == null or not _running:
		return
	var def := item_held
	item_held = null
	hud.set_item(null)
	item_system.apply(def)

func request_pause() -> void:
	if _ending:
		return
	if pause.visible:
		pause.close()
		get_tree().paused = false
	else:
		pause.open()
		get_tree().paused = true

func open_shop() -> void:
	if vendor == null or vendor.state != GameEnums.VendorState.SHOP:
		return
	shop.open(vendor.stock, vendor.counterfeit, Callable(vendor, "on_bought"))

func acquire_item(def: ItemDef) -> void:
	item_held = def
	hud.set_item(def)
	Events.item_added.emit(def.id)
	Events.notify.emit("ITEM_GOT", [tr(def.name_key)])

# --- door billboards --------------------------------------------------------
func _refresh_door_sprite(side: int) -> void:
	if room == null:
		return
	var t := director.threat_at_door(side)
	if t:
		room.refresh_threat_visibility(side, true, t.current_texture(), true)
	else:
		room.refresh_threat_visibility(side, false)

# --- outcomes ---------------------------------------------------------------
func _on_jumpscare(threat_id: String) -> void:
	if _ending:
		return
	# Bùa thật / bánh chưng "save": spend a ward to survive the grab once.
	if try_block_death(threat_id):
		# The counterfeit vendor isn't a director threat, so try_block_death can't
		# repel her — send her off explicitly or she re-fires the grab immediately.
		if threat_id == "ba_hang_rong" and vendor:
			vendor.repel_to_idle()
		var t := director.get_threat(threat_id)
		if t:
			t.reset_to_spawn()
			t.on_ward_save()   # fully clears the meter/position that triggered the kill
		via = maxf(via, via_max * 0.4)
		Events.via_changed.emit(via, via_max)
		return
	_caught(threat_id)

func _caught(cause: String) -> void:
	if _ending:
		return
	_ending = true
	_running = false
	director.set_paused(true)
	Audio.stop_loop("heartbeat")
	Audio.stop_loop("drone_tension")
	_drone_on = false
	Audio.stop_music(0.2)
	# Even a failed night still pays a little vàng mã for the hours you held — so a
	# loss feeds the shrine meta instead of being pure wasted time.
	if _last_hour > 0:
		_earn_coins(_last_hour * 2)
	var meta := ThreatRegistry.info(cause)
	var scare_path: String = meta.get("scare", "") if not meta.is_empty() else ""
	if Settings.allow_jumpscares() and scare_path != "" and ResourceLoader.exists(scare_path):
		# Punch it in: a white flash, a scale-snap from oversized to fit, a few frames
		# of position jitter, and a hard camera jolt — so the scare actually lands.
		_jumpscare_rect.texture = load(scare_path)
		_jumpscare_rect.pivot_offset = _jumpscare_rect.size * 0.5
		_jumpscare_rect.scale = Vector2(1.4, 1.4)
		_jumpscare_rect.visible = true
		var ts := create_tween()
		ts.tween_property(_jumpscare_rect, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_jump_jitter_t = 0.5
		_flash.color = Color(1, 1, 1, 0.9)
		var tf := create_tween()
		tf.tween_property(_flash, "color:a", 0.0, 0.25)
		if room:
			room.add_shake(1.0)
		Audio.play_jumpscare()
	else:
		# accessibility / non-lethal cause: a soft red wash + low cue, no jump image.
		Audio.play_sfx("stinger", -6.0)
		_flash.color = Color(0.35, 0.02, 0.02, 0.55)
		var tfade := create_tween()
		tfade.tween_property(_flash, "color:a", 0.0, 0.9)
		if room:
			room.add_shake(0.4)
	Events.game_over.emit(cause)
	await get_tree().create_timer(1.3).timeout
	Save.record_death(cause)
	Router.to_game_over(cause)

func _win() -> void:
	if _ending:
		return
	_ending = true
	_running = false
	director.set_paused(true)
	Audio.stop_loop("heartbeat")
	Audio.stop_loop("drone_tension")
	_drone_on = false
	Audio.stop_music(0.2)   # let the win/ending screen start its own ambience cleanly
	Audio.play_sfx("rooster", -3.0)
	_earn_coins(25)   # survival bonus toward shrine upgrades
	Events.night_survived.emit()
	Game.notify_night_survived()
	await get_tree().create_timer(0.6).timeout
	# Clearing the final story night resolves the campaign with a proper ending
	# (siêu thoát if the investigation is complete, otherwise the survive epilogue).
	if not Game.is_custom and Game.current_night >= Game.MAX_NIGHTS:
		Router.to_ending()
	else:
		Router.to_win()

# --- public API used by threats & items ------------------------------------
func is_door_closed(side: int) -> bool:
	return room.is_door_closed(side)

func is_light_on(side: int) -> bool:
	return room.is_light_on(side)

func get_pan_speed() -> float:
	return room.get_pan_speed()

func is_monitor_open() -> bool:
	return monitor_open

func get_agitation() -> float:
	return _agitation

## Incense/calm effect: lower the appeasement meters of nearby meter-threats.
func broadcast_calm() -> void:
	director.broadcast_calm()

func night_progress() -> float:
	return clampf(game_minutes / NIGHT_MINUTES, 0.0, 1.0)

func add_via(amount: float) -> void:
	if amount < 0.0:
		amount *= via_drain_mult
		_via_drain_cd = 0.7
	via = clampf(via + amount, 0.0, via_max)
	Events.via_changed.emit(via, via_max)

## Burst/startle vía hit. The mulberry bracelet (child_ward) reduces only these,
## not the continuous meter drains.
func add_startle(amount: float) -> void:
	add_via(amount * (1.0 - clampf(startle_resist, 0.0, 0.8)))

func add_power(amount: float) -> void:
	power = clampf(power + amount, 0.0, 100.0)
	Events.power_changed.emit(power, 100.0)

func try_block_death(_cause: String) -> bool:
	if ward_tokens > 0:
		ward_tokens -= 1
		Audio.play_sfx("item_good", -2.0)
		Events.notify.emit("WARD_SAVED", [])
		# clear anything currently at a door
		var l := director.threat_at_door(GameEnums.Side.LEFT)
		var r := director.threat_at_door(GameEnums.Side.RIGHT)
		if l: l.repel()
		if r: r.repel()
		return true
	return false

func is_revealed() -> bool:
	return reveal_timer > 0.0

func is_barrier_active() -> bool:
	return barrier_timer > 0.0

# --- effect hooks called by ItemSystem -------------------------------------
func grant_ward(n: int) -> void:
	ward_tokens += n

func start_reveal(d: float) -> void:
	reveal_timer = maxf(reveal_timer, d)

func set_global_speed(mult: float, d: float) -> void:
	director.set_speed_all(mult)       # positional cadence (path/wander threats)
	_aggro_mult = mult                 # meter-growth multiplier (flood/crowd/agro/lock)
	speed_timer = d

func add_taint(d: float) -> void:
	via_drain_mult = 1.6
	taint_timer = d

func cleanse() -> void:
	via_drain_mult = 1.0
	taint_timer = 0.0
	speed_timer = 0.0
	_aggro_mult = 1.0
	director.set_speed_all(1.0)

func set_barrier(d: float) -> void:
	barrier_timer = maxf(barrier_timer, d)

func add_startle_resist(v: float) -> void:
	startle_resist = clampf(startle_resist + v, 0.0, 0.8)

func setback_nearest() -> void:
	director.setback_nearest()

# --- living-altar ritual ----------------------------------------------------
## Per-frame incense burn, cold-draft events, and the low-protection vía bleed.
func _update_altar(delta: float) -> void:
	# Cold-draft event: a gust snuffs the candles. Likelier (and meaner) late at night.
	_draft_cd -= delta
	if _draft_cd <= 0.0:
		_draft_cd = randf_range(32.0, 62.0) * (1.0 - 0.35 * night_progress())
		if altar_lit and randf() < 0.45 + 0.35 * night_progress():
			_gutter_candles()
	if altar_lit:
		huong = maxf(0.0, huong - _huong_decay * delta)
		if huong <= 0.0:
			if _auto_relight:
				_auto_relight = false
				_light_incense(true)
				Events.notify.emit("ALTAR_AUTORELIGHT", [])
			else:
				_gutter_candles()
	# When the altar is dark — or the incense is nearly out — the spirits press in.
	# Routed through add_via_drain so vía regen can still fight it (no hard lockout).
	if not altar_lit:
		add_via_drain(-3.0 * delta)
	elif huong <= 20.0:
		add_via_drain(-1.2 * delta)
	if room:
		room.set_huong(huong / huong_max)
		room.set_altar_lit(altar_lit)
	Events.huong_changed.emit(huong / huong_max)
	if _incense_cd > 0.0:
		_incense_cd = maxf(0.0, _incense_cd - delta)
	if _bell_cd > 0.0:
		_bell_cd = maxf(0.0, _bell_cd - delta)

func _gutter_candles() -> void:
	if not altar_lit:
		return
	altar_lit = false
	huong = 0.0
	Audio.play_sfx("candle_gust", -3.0)
	Audio.play_sfx("stinger", -10.0)
	if room:
		room.add_shake(0.5)
	Events.altar_lit_changed.emit(false)
	Events.huong_changed.emit(0.0)
	Events.notify.emit("ALTAR_DRAFT", [])

func request_light_incense() -> void:
	if not _running or _incense_cd > 0.0:
		return
	if _nhang <= 0:
		Audio.play_sfx("stinger", -16.0)
		Events.notify.emit("ALTAR_NO_NHANG", [])
		return
	_nhang -= 1
	_tut_incense = true
	Events.incense_changed.emit(_nhang)
	_light_incense(false)

## silent/free relight (auto_relight upgrade) restores the altar fully; a hand-lit
## stick only tops the meter up part-way, so a finite bundle can't trivialise a night.
func _light_incense(silent: bool) -> void:
	altar_lit = true
	if silent:
		huong = huong_max
		_incense_cd = 0.0
	else:
		huong = minf(huong_max, huong + 58.0)
		_incense_cd = 4.0
	if room:
		room.set_huong(huong / huong_max)
		room.set_altar_lit(true)
	Events.altar_lit_changed.emit(true)
	Events.huong_changed.emit(huong / huong_max)
	if not silent:
		Audio.play_sfx("incense_whoosh", -3.0)
		Events.notify.emit("ALTAR_LIT", [])

## Replenish the incense bundle (the held "nhang" item is a fresh handful of sticks).
func add_nhang(n: int) -> void:
	_nhang += n
	Events.incense_changed.emit(_nhang)

func request_ring_bell() -> void:
	if not _running or _bell_cd > 0.0:
		return
	_bell_cd = _bell_cd_max
	Audio.play_sfx("offering_bell", -2.0)
	# The bell now does ONE job — shove the nearest rusher back from the door — so it's
	# a positioning tool, not a second free altar. (Meter spirits are the incense's job.)
	director.setback_nearest()
	add_via(6.0)
	Events.notify.emit("BELL_RUNG", [])

## Combined threat-aggression multiplier (read by the meter threats each frame):
## tending the incense suppresses them; a guttered altar or the bánh-lạ curse
## whips them up. This is what makes the altar your primary, active defense.
func meter_mult() -> float:
	var m := _aggro_mult
	if not altar_lit:
		m *= 1.35
	elif huong >= 60.0:
		m *= (0.4 if _bright_altar else 0.5)
	elif huong <= 25.0:
		m *= 1.3
	return m

# --- phone ------------------------------------------------------------------
func request_answer_phone() -> void:
	if not _running or phone == null:
		return
	phone.answer()

# --- camera anomaly tagging -------------------------------------------------
## Spotting a threat on its camera and "tagging" it: a small reward for active
## camera use — sets a rusher back / settles a meter spirit, briefly reveals the
## map, and steadies your nerve. Per-threat cooldown so it can't be spammed.
func tag_anomaly(threat_id: String) -> void:
	if not _running:
		return
	var t := director.get_threat(threat_id)
	if t == null:
		return
	if float(_tag_cds.get(threat_id, 0.0)) > 0.0:
		return
	_tag_cds[threat_id] = 12.0
	if t.counter_door:
		t.reset_to_spawn()
	else:
		t.on_calm()
	start_reveal(4.0)
	add_via(4.0)
	Audio.play_sfx("camera_switch", -4.0)
	Events.anomaly_tagged.emit(threat_id)
	Events.notify.emit("ANOMALY_TAGGED", [])
	# Tagging the wronged soul on camera reveals her face — an investigation clue.
	if threat_id == "oan_hon":
		find_clue("clue_photo", "CLUE_GOT_PHOTO")

## Oan hồn investigation: record a clue (idempotent), announce it, advance progress.
## Gather all three (name / drawing / photo) before clearing Night 6 for the good ending.
func find_clue(clue_id: String, msg_key: String) -> void:
	if not _running:
		return
	if Save.find_clue(clue_id):
		Events.investigation_updated.emit(Save.clue_count())
		Events.notify.emit(msg_key, [])
		Audio.play_sfx("item_good", -5.0)

# --- vía / currency ---------------------------------------------------------
## Continuous meter drain that does NOT freeze vía regen (see _update_via). Slow
## meter pressure is a net bleed you can offset, not an unrecoverable lockout.
func add_via_drain(amount: float) -> void:
	if amount < 0.0:
		amount *= via_drain_mult
	via = clampf(via + amount, 0.0, via_max)
	Events.via_changed.emit(via, via_max)

func _earn_coins(n: int) -> void:
	coins += n
	Save.coins = coins
	Save.save_progress()
	Events.coins_changed.emit(coins)
	Audio.play_sfx("coin_chime", -16.0)

func try_spend_coins(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	Save.coins = coins
	Save.save_progress()
	Events.coins_changed.emit(coins)
	return true

func get_coins() -> int:
	return coins

func get_huong() -> float:
	return huong
