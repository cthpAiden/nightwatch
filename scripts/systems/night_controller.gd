extends Node
## Root of scenes/Night.tscn. Builds the whole night in code and runs it:
## the 12AM->6AM clock, power + vía economies, input routing, the win/lose and
## jumpscare flow, and wiring between the room, director, vendor, items and UI.
## Threats call the small public API at the bottom (is_door_closed, add_via, ...).

const NIGHT_MINUTES := 360.0            # 00:00 -> 06:00
const BLACKOUT_GAP := Vector2(45.0, 75.0)   # seconds between rolling-blackout windows
const BLACKOUT_LEN := Vector2(9.0, 14.0)    # seconds a blackout window lasts

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
var _scare_mat: ShaderMaterial     # chromatic-split + UV-jitter on the scare image ("hit" 1->0)
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
var _monitor_tw: Tween         # raise/lower alpha tween; killed on re-toggle to avoid a stale hide
var current_cam := MapGraph.GATE
var offerings := 0
var _scramble_t := 0.0       # giật cô hồn: window to guard the tray (else the child-spirits take it for lộc)
var _rich_tray := false      # forbidden-offering: the current tray is mặn/lavish — the souls refuse it
var _rich_cd := 0.0          # time until the next "wrong tray" event (cô hồn nights only)
var _rich_expire := 0.0      # time before the rookie swaps a rich tray back to a humble one
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
var _last_cam_switch_ms := -10000   # Time.get_ticks_msec() of the last camera change (recency gate)

# Living-altar ritual ("hương" incense protection) — the core active defense.
var huong := 100.0
var huong_max := 100.0
var altar_lit := true        # false = candles guttered by a cold draft; relight!
var coins := 0               # vàng mã (spirit money): shop + shrine-upgrade currency
var _run_earned := 0         # gross coins earned this run (for the anti-farm best check)
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
var _draft_warn_t := 0.0     # cold-draft telegraph: counts down a warning beat, then snuffs (backlog#22)
var _unease_cd := 30.0       # creeping-dread poke scheduler: one cheap diegetic false-alarm in calm windows (backlog#24)
var _auto_relight := false   # shrine upgrade: one free relight when it gutters
var _tag_cds := {}           # threat_id -> camera-anomaly tag cooldown
var _hex_t := 0.0            # Ma trơi lock-on jinx: doors/lights flail open briefly
var _crowd_level := 0.0      # Cô hồn smother (0..1) driving the view-blocking overlay
var _crowd_layer: CanvasLayer
var _crowd_overlay: TextureRect
var _crowd_pulse_t := 0.0    # phase for the subtle surge of the crowd overlay
var _hb_on := false          # heartbeat loop currently playing (ramped with danger)
var _breath_on := false      # proximity-breathing loop (a threat looms at a door)
var _strain_on := false      # shutter-strain loop (a closed door is being pressed)
var _water_on := false       # ma da rising-water loop (driven by flood level)
var _offering_count := 0       # backlog#30: offerings placed this night (drives the first-offering + cycled lines)
var _post_layer: CanvasLayer
var _post_mat: ShaderMaterial  # full-screen grain/scanline/vignette over the 3D office
var _post_rect: Control        # the grain ColorRect itself, hidden when safe or occluded

var _running := false
var _ending := false
var _powered := true
var _low_power_warned := false
var _tut_step := -1          # -1 = no tutorial running; otherwise index into TUT_STEPS
var _tut_look_t := 0.0       # accumulates sustained-look time so step 0 needs intent, not a twitch
var _tut_incense := false    # set when the player hand-lights incense (tutorial step)
var _tut_bell := false       # set when the player rings the bell (tutorial step)
var _first_door := {}        # threat_id -> true once it has reached a door (first-contact hint)
# Per-night flavor modifiers (config.mods): blackout windows, foggy cameras, wisp storm.
var _mod_blackout := false
var _mod_fog := false
var _mod_wisp := false
var _blk_cd := 0.0           # seconds until the next blackout window
var _blk_t := 0.0            # seconds remaining in the current blackout window

func _ready() -> void:
	if OS.has_environment("NW_NIGHT"):
		Game.current_night = int(OS.get_environment("NW_NIGHT"))
		Game.is_custom = false   # env-launched story night must not inherit a prior custom run
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

	# Full-screen post pass over the live 3D office (layer 8 = above the 3D, below the
	# HUD/monitor at 10): subtle film grain + scanline + vignette so the office matches
	# the grainy CCTV feeds instead of looking too clean. Intensity rises with dread.
	_post_layer = CanvasLayer.new()
	_post_layer.layer = 8
	add_child(_post_layer)
	var post_rect := UI.color_rect(Color(1, 1, 1, 1))
	UI.full(post_rect)
	var psh := Shader.new()
	psh.code = """
shader_type canvas_item;
uniform float strength = 0.0;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	float grain = rand(UV * vec2(800.0, 450.0) + vec2(TIME * 53.0, TIME * 29.0));
	float scan = sin(UV.y * 900.0) * 0.5 + 0.5;
	float edge = distance(UV, vec2(0.5));
	float vig = clamp((edge - 0.36) * 1.5, 0.0, 1.0);
	// Near-invisible at rest (0.045) so the clean office keeps its colour; the film of
	// grain + vignette + scanline only crowds in as danger (strength) rises.
	float base = 0.045 + 0.72 * strength;
	float a = vig * 0.55 * base + (grain * 0.5 + scan * 0.12) * 0.16 * base;
	COLOR = vec4(vec3(0.01, 0.01, 0.014) + vec3(grain * 0.05), a);
}
"""
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = psh
	_post_mat.set_shader_parameter("strength", 0.0)
	post_rect.material = _post_mat
	_post_layer.add_child(post_rect)
	_post_rect = post_rect

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
	# The grab image distorts on impact: a hard chromatic R/B split + a little UV jitter
	# that decays over ~0.4s (driven from _process), so the face glitches as it lands.
	var jsh := Shader.new()
	jsh.code = """
shader_type canvas_item;
uniform float hit = 0.0;
float rand(vec2 c){ return fract(sin(dot(c, vec2(12.9898,78.233))) * 43758.5453); }
void fragment() {
	float h = clamp(hit, 0.0, 1.0);
	vec2 uv = UV;
	uv.x += (rand(vec2(floor(UV.y * 180.0), floor(TIME * 40.0))) - 0.5) * 0.02 * h;
	float off = 0.014 * h;
	vec4 base = texture(TEXTURE, uv);
	float r = texture(TEXTURE, uv + vec2(off, 0.0)).r;
	float b = texture(TEXTURE, uv - vec2(off, 0.0)).b;
	COLOR = vec4(r, base.g, b, base.a);
}
"""
	_scare_mat = ShaderMaterial.new()
	_scare_mat.shader = jsh
	_scare_mat.set_shader_parameter("hit", 0.0)
	_jumpscare_rect.material = _scare_mat
	jl.add_child(_jumpscare_rect)
	_flash = ColorRect.new()
	UI.full(_flash)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	jl.add_child(_flash)

func _connect_events() -> void:
	Events.jumpscare_started.connect(_on_jumpscare)
	Events.threat_repelled.connect(func(_id): _on_threat_repelled())
	Events.threat_at_door.connect(func(id, side): _on_threat_at_door(id, side))
	Events.threat_left_door.connect(func(_id, side): _refresh_door_sprite(side))
	Events.crowd_changed.connect(func(level):
		_crowd_level = level)
	Events.water_level.connect(_on_water_level_audio)
	Events.via_state_changed.connect(_on_via_state_fx)

## A figure arriving at the door: refresh its sprite, and land a small scare beat
## (jolt + low sting) so the doorway threat has weight instead of a silent pop-in.
func _on_threat_at_door(id: String, side: int) -> void:
	_refresh_door_sprite(side)
	if room:
		room.add_shake(0.32)
	# Pitch the arrival sting by side (left lower, right higher) for a directional read,
	# mirroring _update_proximity_audio's left=0.92 breath. Delay it ~0.2s after the
	# threat's own approach_sfx so it reads as cause (footsteps) then consequence (sting).
	var arr_pitch := 0.92 if side == GameEnums.Side.LEFT else 1.06
	get_tree().create_timer(0.2).timeout.connect(func():
		Audio.play_sting("sting_low", -14.0, arr_pitch))
	# Pulse the threatened side's doorway light so the player gets a directional cue.
	if hud and hud.has_method("flash_side"):
		hud.flash_side(side)
	# First time a given rusher reaches a door this night, name its counter in context
	# (teaching that survives past the Night-1 tutorial).
	if not _first_door.get(id, false):
		_first_door[id] = true
		Events.notify.emit("COUNTER_" + id.to_upper(), [])

## A repelled/pushed-back threat: a soft confirm sting + a small jolt so the player
## reads the success — pressure relieving instead of a silent dissipation.
func _on_threat_repelled() -> void:
	if not _running:
		return
	Audio.play_sfx("item_good", -8.0)
	if room:
		room.add_shake(0.12)

## Ma da's flood, voiced as a body of water that swells from a distant trickle to an
## oppressive slosh as the level rises — so the silent flood mechanic is now felt.
func _on_water_level_audio(level: float) -> void:
	# Raise the office floodwater plane from the same flood fraction (0..1). (AUDIT#13)
	if room and room.has_method("set_water_level"):
		room.set_water_level(level)
	if level > 0.02:
		if not _water_on:
			_water_on = true
			Audio.start_loop("water_loop", -30.0)
		Audio.set_loop_volume("water_loop", lerpf(-30.0, -8.0, clampf(level, 0.0, 1.0)))
		Audio.set_loop_pitch("water_loop", lerpf(0.85, 1.05, clampf(level, 0.0, 1.0)))
	elif _water_on:
		_water_on = false
		Audio.stop_loop("water_loop")

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
	# A continuous sub-bass dread floor under the whole night — felt, not heard. Its
	# volume rises with danger in _update_atmosphere so the drone swell reads as the
	# room tightening, not an on/off switch.
	Audio.start_loop("ambience_sub", -34.0)

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
	# Forbidden-offering: arm the occasional "wrong (mặn) tray" event only on nights with the
	# cô hồn offering economy. It's telegraphed (OFFERING_WRONG) and auto-fixes if you wait.
	if config.threat_levels.has("co_hon"):
		_rich_cd = randf_range(45.0, 90.0)
	# Start with one stick of incense (nhang) in hand so the player always has the
	# calm tool available and learns what it does.
	if item_held == null:
		var nhang := ItemRegistry.get_def("nhang")
		if nhang:
			acquire_item(nhang)
	_apply_mods()
	# Night 1 owns the screen centre with its hands-on tutorial banner, so skip the
	# (also-centred) title card there — they'd otherwise stack for the card's ~3s.
	if not Game.is_custom and not OS.has_environment("NW_SKIP_TAPE") and Game.current_night != 1:
		_show_title_card()
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
	# Remind the player the investigation exists (a few seconds in, after the begin toast)
	# until it's complete — so the good ending is a goal they can pursue, not a secret.
	if not Game.is_custom and Game.current_night >= 2 and not Save.investigation_complete():
		get_tree().create_timer(5.0).timeout.connect(func():
			if _running:
				Events.notify.emit("INVEST_GOAL", []))

# --- per-night flavor modifiers --------------------------------------------
func _apply_mods() -> void:
	var m: Array = config.mods if config else []
	_mod_blackout = m.has("blackout")
	_mod_fog = m.has("fog")
	_mod_wisp = m.has("wisp_storm")
	if _mod_fog and monitor and monitor.has_method("set_fog_level"):
		monitor.set_fog_level(0.22)   # the cameras run heavy with static tonight
	if _mod_blackout:
		_blk_cd = randf_range(BLACKOUT_GAP.x, BLACKOUT_GAP.y)

## Rolling-blackout windows: periodically the grid sags, draining power faster and
## rattling the room, until you ride it out.
func _update_mods(delta: float) -> void:
	if not _mod_blackout or not _powered:
		return
	if _blk_t > 0.0:
		_blk_t -= delta
		return
	_blk_cd -= delta
	if _blk_cd <= 0.0:
		_blk_cd = randf_range(BLACKOUT_GAP.x, BLACKOUT_GAP.y)
		_blk_t = randf_range(BLACKOUT_LEN.x, BLACKOUT_LEN.y)
		Audio.play_sfx("power_down", -12.0)
		if room:
			room.add_shake(0.45)
		Events.notify.emit("MOD_BLACKOUT", [])

## A brief title card (night number + flavor name) at the start of each story night.
func _show_title_card() -> void:
	if config == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 45
	add_child(layer)
	var box := UI.vbox(6)
	UI.place(box, 0.5, 0.5, 0.5, 0.5, -380, -70, 380, 70)
	layer.add_child(box)
	box.add_child(UI.text_label(tr("NIGHT_LABEL").format([str(Game.current_night)]), 22, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(UI.label(config.title_key, 52, Color(0.93, 0.88, 0.78), HORIZONTAL_ALIGNMENT_CENTER))
	# backlog#26: Quỷ Môn Quan / Tháng Cô Hồn framing — the night is one hungry-ghost-month
	# vigil, dated under the title card.
	box.add_child(UI.label("DATE_STAMP", 18, Color(0.7, 0.66, 0.52), HORIZONTAL_ALIGNMENT_CENTER))
	box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(1.7)
	tw.tween_property(box, "modulate:a", 0.0, 0.7)
	tw.tween_callback(layer.queue_free)

# --- Night-1 hands-on tutorial ---------------------------------------------
const TUT_STEPS := ["TUT_LOOK", "TUT_INCENSE", "TUT_BELL", "TUT_DOOR", "TUT_CAM"]

func _begin_tutorial() -> void:
	_tut_step = 0
	_tut_incense = false
	_tut_bell = false
	_tut_look_t = 0.0
	director.set_paused(true)
	hud.set_tutorial_prompt(TUT_STEPS[0], 0, TUT_STEPS.size())

## Advance the lesson when the current step's action is performed. The rest of the
## sim is frozen (see _process) so nothing can hurt the player mid-lesson. The prompt
## is a persistent banner (hud.set_tutorial_prompt) naming the exact key, not a toast.
func _check_tutorial() -> void:
	var done := false
	match _tut_step:
		0:
			# Require a SUSTAINED look (~0.4s of panning), not a one-frame mouse twitch on
			# startup that silently skips the lesson. (AUDIT#26)
			if get_pan_speed() > 0.5:
				_tut_look_t += get_process_delta_time()
			done = _tut_look_t > 0.4
		1: done = _tut_incense                     # press R to light incense
		2: done = _tut_bell                        # press B to ring the bell
		3: done = room.is_door_closed(GameEnums.Side.LEFT) or room.is_door_closed(GameEnums.Side.RIGHT)
		4: done = monitor_open                      # press C to raise the cameras
	if not done:
		return
	_tut_step += 1
	if _tut_step >= TUT_STEPS.size():
		_tut_step = -1
		hud.set_tutorial_prompt("")
		Events.notify.emit("TUT_DONE", [])
		_engage_night()
	else:
		hud.set_tutorial_prompt(TUT_STEPS[_tut_step], _tut_step, TUT_STEPS.size())

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
	Audio.start_loop("incense_bed", -28.0)   # subliminal warmth you can feel slip away
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
		if _scare_mat:
			_scare_mat.set_shader_parameter("hit", k)   # glitch decays with the jitter
		if _jump_jitter_t <= 0.0:
			_jumpscare_rect.position = Vector2.ZERO
			if _scare_mat:
				_scare_mat.set_shader_parameter("hit", 0.0)
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
	# Resolve who is at each door ONCE this frame, then thread it through the readers
	# below instead of each (vía / atmosphere / door-sprite) re-scanning the threat list
	# — ~6 scans/frame collapse to 2. Stable for the frame: the director (a child) ticks
	# AFTER this parent _process, per the documented parent-before-child order.
	var loom_l := director.threat_at_door(GameEnums.Side.LEFT)
	var loom_r := director.threat_at_door(GameEnums.Side.RIGHT)
	_update_via(delta, loom_l != null or loom_r != null)
	_update_timers(delta)
	# Panic/agitation: fast panning raises it (rapid cam-switching does too, in
	# on_camera_changed); it decays over time. Drives Ma trơi.
	# A wisp-storm night makes agitation build faster and fade slower (Ma trơi is wild).
	var agit_gain := 2.5 if _mod_wisp else 2.0
	var agit_decay := 0.8 if _mod_wisp else 1.0
	if room.get_pan_speed() > 0.7:
		_agitation = minf(1.0, _agitation + delta * agit_gain)
	# Decays a bit quicker than it builds so that simply STOPPING (not panning, not
	# flipping channels) reliably calms Ma trơi down — "don't run" is always an out.
	_agitation = maxf(0.0, _agitation - delta * agit_decay)
	_update_mods(delta)
	# Look-pan only during free play — not on the monitor or behind a modal overlay.
	room.set_look_enabled(not monitor_open and not shop.visible and not pause.visible and not cassette.visible)
	director.night_progress = night_progress()
	director.broadcast_pan(room.get_pan_speed() > 0.7)
	# Re-broadcast the watched camera every frame WHILE THE MONITOR IS OPEN so a threat
	# that wanders under a held view (e.g. Oan hồn) is correctly seen/unseen. When closed,
	# _set_monitor already cleared every _viewing flag once via broadcast_view("") on the
	# closing edge (L909), so skipping the per-frame all-threats loop here is safe. (AUDIT#6)
	if monitor_open:
		director.broadcast_view(current_cam)
	if monitor_open:
		room.set_desk_threat(_desk_threat_tex())   # mirror the threat onto the desk CRT
	_update_altar(delta)
	_refresh_door_sprite(GameEnums.Side.LEFT, loom_l)
	_refresh_door_sprite(GameEnums.Side.RIGHT, loom_r)
	_update_crowd_overlay(delta)
	_update_atmosphere(loom_l, loom_r)

## Drives the room's danger grade and the tension drone from how close to losing you
## are: low vía / low hương / a blackout sour the colour; a rusher at the door or a
## critical vía fades a low drone in under everything.
func _update_atmosphere(loom_l, loom_r) -> void:
	var via_danger := 1.0 - clampf(via / via_max, 0.0, 1.0)
	var huong_danger := 1.0 - clampf(huong / huong_max, 0.0, 1.0)
	var d := maxf(via_danger * 1.1, huong_danger * 0.6)
	if not _powered:
		d = maxf(d, 0.85)
	var dread := clampf(d, 0.0, 1.0)
	if room:
		room.set_dread(dread)
	if _post_mat:
		_post_mat.set_shader_parameter("strength", dread)
	# The grain pass keeps a faint always-on floor, so hide the whole layer when the office
	# is safe (dread ~0) or fully occluded by the open monitor — no full-screen pass for
	# nothing. It re-shows the instant dread climbs again. (AUDIT#12)
	if _post_rect:
		_post_rect.visible = dread > 0.001 and not monitor_open
	# The sub floor breathes up with danger (subliminal calm -> oppressive at the edge).
	Audio.set_loop_volume("ambience_sub", lerpf(-34.0, -12.0, dread))
	# Heartbeat swells with danger from SHAKEN onward AND speeds up — a constant-tempo
	# pulse is a metronome you tune out, an accelerating one makes the late game frantic.
	if via_state == GameEnums.ViaState.NORMAL:
		if _hb_on:
			_hb_on = false
			Audio.stop_loop("heartbeat")
	else:
		var frac := clampf(via / via_max, 0.0, 1.0)
		var sev := clampf((0.4 - frac) / 0.4, 0.0, 1.0)   # 0 at SHAKEN edge -> 1 near death
		var vol := lerpf(-20.0, -3.0, sev)
		if not _hb_on:
			_hb_on = true
			Audio.start_loop("heartbeat", vol)
		else:
			Audio.set_loop_volume("heartbeat", vol)
		Audio.set_loop_pitch("heartbeat", lerpf(0.9, 1.5, sev))
	var left_loom: bool = loom_l != null
	var right_loom: bool = loom_r != null
	var looming := left_loom or right_loom
	var want_drone := looming or via_state == GameEnums.ViaState.CRITICAL
	if want_drone and not _drone_on:
		_drone_on = true
		Audio.start_loop("drone_tension", -19.0)
	elif not want_drone and _drone_on:
		_drone_on = false
		Audio.stop_loop("drone_tension")
	_update_proximity_audio(left_loom, right_loom)

## The far side of the door, voiced: a wet breath when something looms (pitched toward
## the side it's on), and a low metal strain when it's pressing a CLOSED shutter. These
## make holding a door feel physically occupied instead of silent after the arrival sting.
func _update_proximity_audio(left_loom: bool, right_loom: bool) -> void:
	var loom := left_loom or right_loom
	if loom:
		var pitch := 0.92 if (left_loom and not right_loom) else 1.0
		if not _breath_on:
			_breath_on = true
			Audio.start_loop("breathing", -18.0)
		Audio.set_loop_pitch("breathing", pitch)
	elif _breath_on:
		_breath_on = false
		Audio.stop_loop("breathing")
	var pressed := false
	if room:
		pressed = (left_loom and room.is_door_closed(GameEnums.Side.LEFT)) \
			or (right_loom and room.is_door_closed(GameEnums.Side.RIGHT))
	if pressed and not _strain_on:
		_strain_on = true
		Audio.start_loop("shutter_strain", -19.0)
	elif not pressed and _strain_on:
		_strain_on = false
		Audio.stop_loop("shutter_strain")

func _advance_clock(delta: float) -> void:
	var rate := 60.0 / maxf(config.seconds_per_hour, 1.0)   # game-minutes per real second
	game_minutes += delta * rate
	var m := int(game_minutes)
	if m != _last_minute:
		_last_minute = m
		Events.clock_advanced.emit(m)
	# Fire every hour actually crossed so a long frame can never skip the chime
	# or, critically, the 06:00 win (which would softlock the night).
	var h := int(game_minutes / 60.0)
	while _last_hour < h:
		_last_hour += 1
		Events.hour_reached.emit(_last_hour)
		if _last_hour > 0 and _last_hour < 6:
			Audio.play_sfx("clock_chime", -10.0)
			_earn_coins(8)   # vàng mã for each hour you survive
		# backlog#27: canh ba — the 3 AM witching hour. Fire once on the cross to 3, and nudge
		# the dread/ambience up a touch (a brief sub-bass swell) so the hour is felt, not just told.
		if _last_hour == 3:
			Audio.play_sting("sting_low", -14.0, 0.85)
			if room:
				room.add_shake(0.18)
		# AUDIT#22: rarely, on a late night past ~3AM, let the eerie đồng-dao motif drift in
		# on an hour-cross. Probability scales with night_progress() so it stays sparse (at
		# most ~1x/night). Routed via play_sting so it goes to VERB + honours the scare tier.
		if config.night_index >= 3 and _last_hour >= 3 and _last_hour < 6:
			if randf() < 0.18 * night_progress():
				Audio.play_sting("dong_dao", -10.0)
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
	if _mod_blackout and _blk_t > 0.0:
		drain += 0.5   # the grid sags during a blackout window
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
	# Doors are forced open now, so the door-pressure loops no longer make sense — stop
	# them proactively instead of waiting a frame for _update_proximity_audio to catch up.
	_strain_on = false
	Audio.stop_loop("shutter_strain")
	_breath_on = false
	Audio.stop_loop("breathing")
	if monitor_open:
		_set_monitor(false)
	Audio.play_sfx("power_down", -2.0)
	if room:
		room.add_shake(0.6)
	Events.power_depleted.emit()
	Events.notify.emit("POWER_OUT", [])

func _update_via(delta: float, looming: bool) -> void:
	if _via_drain_cd > 0.0:
		_via_drain_cd = maxf(0.0, _via_drain_cd - delta)
	# Regen only when nothing looms AND no drain happened very recently, so active
	# meter pressure (cô hồn / ma da / oan hồn) is a genuine net loss, not cancelled.
	if not looming and _via_drain_cd <= 0.0:
		var regen := 1.0 + night_progress() * 1.8
		via = minf(via_max, via + regen * delta)
		Events.via_changed.emit(via, via_max)
	# Blackout bleed routes through the CONTINUOUS channel (add_via_drain) so vía regen
	# can still fight it. The old add_via() re-armed the 0.7s regen freeze every frame —
	# stalling recovery for 0.7s after power returned — and was taint-amplified; neither
	# suits a slow blackout pressure (this mirrors the guttered-altar bleed).
	if not _powered:
		add_via_drain(-2.0 * delta)
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
		# Heartbeat is ramped continuously in _update_atmosphere (not snapped on here).

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
	for k in _tag_cds:
		if _tag_cds[k] > 0.0:
			_tag_cds[k] = maxf(0.0, _tag_cds[k] - delta)
	if _hex_t > 0.0:
		_hex_t = maxf(0.0, _hex_t - delta)
	_update_unease(delta)
	_tick_offering_events(delta)

## Creeping-dread pokes: in CALM windows only (nothing looming, healthy vía + hương) fire ONE
## cheap diegetic false-alarm every ~25-50s — a distant footstep, a forced ceiling stutter, or
## a knock with no threat. Reuses existing audio/props; never adds real pressure. The window
## tightens as the night wears on. (backlog#24)
func _update_unease(delta: float) -> void:
	_unease_cd -= delta
	if _unease_cd > 0.0:
		return
	# Re-arm tighter as the night progresses (25-50s early -> ~15-30s late).
	var prog := night_progress()
	_unease_cd = randf_range(25.0, 50.0) * (1.0 - 0.4 * prog)
	# Only when truly calm: no rusher at either door, and both meters healthy.
	var calm := director.threat_at_door(GameEnums.Side.LEFT) == null \
		and director.threat_at_door(GameEnums.Side.RIGHT) == null \
		and via >= via_max * 0.6 and huong >= huong_max * 0.5 and altar_lit
	if not calm:
		return
	match randi() % 4:
		0:
			Audio.play_sfx("footstep_wood", -18.0)   # distant step in the dark
		1:
			if room and room.has_method("poke_stutter"):
				room.poke_stutter()                   # the lights hiccup on their own
		2:
			Audio.play_sfx("knock", -16.0)           # a knock with nothing behind it
		3:
			# backlog#36: a rare, respectful after-midnight kiêng-kỵ (taboo) surfaced as desk-whisper
			# flavor — NOT a gameplay trap. Only fires in calm windows, never punishes. A soft murmur
			# + one of a small pool of genuine night taboos.
			var taboos := ["TABOO_NO_ANSWER", "TABOO_NO_WHISTLE", "TABOO_NO_LAUNDRY", "TABOO_NO_MIRROR"]
			Audio.play_sfx("whisper", -20.0)
			Events.notify.emit(taboos[randi() % taboos.size()], [])

## Cô hồn smother: blind the office (and especially the camera feed) as the crowd
## swells past ~55%. Hidden behind any modal so it can't trap the player off-screen.
func _update_crowd_overlay(delta: float) -> void:
	if _crowd_overlay == null:
		return
	var target := 0.0
	var press := 0.0
	if not (shop.visible or cassette.visible or pause.visible):
		press = clampf((_crowd_level - 0.55) / 0.45, 0.0, 1.0)
		# Pressing harder while you're trying to watch cameras — true information denial.
		target = press * (0.78 if monitor_open else 0.6)
	_crowd_overlay.modulate.a = move_toward(_crowd_overlay.modulate.a, target, delta * 1.5)
	# A subtle pulsing scale keyed off the press fraction makes the wall of faces seem to
	# surge and breathe in toward you as the crowd swells, rather than sit as a flat sheet.
	_crowd_pulse_t += delta * 4.0
	var pulse := 1.0 + 0.02 * press * sin(_crowd_pulse_t)
	_crowd_overlay.pivot_offset = _crowd_overlay.size * 0.5
	_crowd_overlay.scale = Vector2(pulse, pulse)

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
		if _tut_step >= 0:
			return
		Events.office_action.emit("close_drain")

# --- requests from UI / input ----------------------------------------------
func request_toggle_door(side: int) -> void:
	if not _powered or not _running:
		return
	if _hex_t > 0.0:
		return
	var closed: bool = not room.is_door_closed(side)
	room.set_door(side, closed)
	director.broadcast_door(side, closed)

func request_toggle_light(side: int) -> void:
	if not _powered or not _running:
		return
	if _hex_t > 0.0:
		return
	var on: bool = not room.is_light_on(side)
	room.set_light(side, on)
	director.broadcast_light(side, on)
	_refresh_door_sprite(side)

## Ma trơi lock-on: the wisp's panic jinx flails your doors/lights open and jams them
## for a moment, leaving you exposed to whatever is approaching. Punishes running.
func hex_controls(d: float) -> void:
	if not _running:
		return
	# Runs even at zero power (doors already open in a blackout): keeps the kill-pause
	# guard + the CONTROLS_HEXED cue consistent so the surge never lands silently.
	_hex_t = maxf(_hex_t, d)
	room.set_door(GameEnums.Side.LEFT, false)
	room.set_door(GameEnums.Side.RIGHT, false)
	director.broadcast_door(GameEnums.Side.LEFT, false)
	director.broadcast_door(GameEnums.Side.RIGHT, false)
	if room:
		room.add_shake(0.5)
	Audio.play_sfx("power_down", -10.0)
	Events.notify.emit("CONTROLS_HEXED", [])

## True while Ma trơi's lock-on jinx has the controls jammed. Threats read this and
## pause their kill timer so the hex can never be a death the player couldn't prevent.
func is_hexed() -> bool:
	return _hex_t > 0.0

func request_toggle_monitor() -> void:
	if not _running or shop.visible or cassette.visible:
		return
	_set_monitor(not monitor_open)

func _set_monitor(open: bool) -> void:
	monitor_open = open
	room.set_look_enabled(not open)
	# Kill any in-flight raise/lower tween so a quick close-then-open can't let the close
	# fade's deferred hide fire after the panel has already been reopened (look-lock bug).
	if _monitor_tw and _monitor_tw.is_valid():
		_monitor_tw.kill()
	if open:
		monitor.visible = true
		monitor.modulate.a = 0.0
		_monitor_tw = create_tween()
		_monitor_tw.tween_property(monitor, "modulate:a", 1.0, 0.12)
		Audio.play_sfx("camera_up", -6.0)
		Audio.start_loop("static_loop", -22.0)
		monitor.show_feed(current_cam)
		director.broadcast_view(current_cam)
		room.set_desk_mirror(current_cam)   # desk CRT mirrors what you're watching
	else:
		Audio.play_sfx("camera_down", -6.0)
		# Fade the panel out to match the raise, then hide it on completion. The next open
		# resets modulate.a to 0, so leaving a=0 after a faded close is fine. The callback
		# re-checks monitor_open so a reopen mid-fade is never stomped invisible.
		_monitor_tw = create_tween()
		_monitor_tw.tween_property(monitor, "modulate:a", 0.0, 0.10)
		_monitor_tw.tween_callback(func(): if not monitor_open: monitor.visible = false)
		Audio.stop_loop("static_loop")
		director.broadcast_view("")
		room.set_desk_idle()                # back to the idle slideshow
	Events.cameras_toggled.emit(open)

func on_camera_changed(cam_id: String) -> void:
	current_cam = cam_id
	# Only rapid channel-flipping reads as panic: gate the bump on recency so a paced scan
	# (>1.2s between switches) adds little/nothing, while a frantic flip still spikes it.
	var now := Time.get_ticks_msec()
	if now - _last_cam_switch_ms <= 1200:
		_agitation = minf(1.0, _agitation + 0.2)
	_last_cam_switch_ms = now
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
	if not _running or _tut_step >= 0:
		return
	# A giật-cô-hồn scramble is live: the offering key now GUARDS the tray from the spirits.
	if _scramble_t > 0.0:
		_scramble_guard()
		return
	if offerings <= 0:
		Events.notify.emit("OFFERING_NONE", [])
		return
	# Forbidden offering: the rookie grabbed the mặn (lavish) tray — the souls' needle-thin
	# throats refuse it. A gentle, telegraphed fail (it was flagged by OFFERING_WRONG): the
	# tray is spent but nothing is appeased. Teaches that offerings must be humble.
	if _rich_tray:
		offerings -= 1
		_rich_tray = false
		_rich_cd = randf_range(45.0, 90.0)
		Audio.play_sfx("item_bad", -6.0)
		Events.notify.emit("OFFERING_WRONG", [])
		return
	offerings -= 1
	Events.offering_placed.emit(MapGraph.GATE)
	director.broadcast_offering(MapGraph.GATE)
	add_via(14.0)
	Save.record_offering()
	Audio.play_sfx("offering_bell", -4.0)
	# backlog#30: the FIRST offering of the night teaches the real etiquette — scatter the
	# muối gạo OUTWARD at the gate so the souls take their share but don't follow inside;
	# later offerings cycle authentic confirm lines naming the humble items (cháo/muối gạo/bánh kẹo).
	_offering_count += 1
	if _offering_count == 1:
		Events.notify.emit("OFFERING_FIRST", [])
	else:
		var done_keys := ["OFFERING_DONE", "OFFERING_DONE_2", "OFFERING_DONE_3"]
		Events.notify.emit(done_keys[(_offering_count - 2) % done_keys.size()], [])
	_maybe_start_scramble()

## Giật cô hồn: after a successful offering, mischievous child-spirits may scramble for the
## tray. Letting them take it (do nothing) brings lộc — sharing is fortune; grabbing it back
## (press the offering key) keeps the tray but slights the souls. A risk/reward beat tied to
## the cô hồn economy. (v2 feature — feel/odds want playtest tuning.)
func _maybe_start_scramble() -> void:
	if _scramble_t > 0.0 or director.get_threat("co_hon") == null:
		return
	if randf() < 0.35:
		_scramble_t = 4.0
		Audio.play_sfx("whisper", -8.0)
		Events.notify.emit("GIAT_PROMPT", [])

func _scramble_guard() -> void:
	_scramble_t = 0.0
	var ch := director.get_threat("co_hon")
	if ch:
		ch.crowd = clampf(ch.crowd + 18.0, 0.0, 100.0)   # slighted souls press back in
	Audio.play_sfx("item_bad", -8.0)
	Events.notify.emit("GIAT_GUARD", [])

func _scramble_snatch() -> void:
	_scramble_t = 0.0
	add_via(6.0)          # lộc: sharing brings a little calm
	_earn_coins(2)
	Audio.play_sfx("coin_chime", -12.0)
	Events.notify.emit("GIAT_SNATCH", [])

## Tick the giật-cô-hồn window and the forbidden-offering "wrong tray" timer (both tied to
## the cô hồn offering economy). Called once per frame from _update_timers.
func _tick_offering_events(delta: float) -> void:
	if _scramble_t > 0.0:
		_scramble_t = maxf(0.0, _scramble_t - delta)
		if _scramble_t == 0.0:
			_scramble_snatch()
	if _rich_cd > 0.0:
		_rich_cd = maxf(0.0, _rich_cd - delta)
		if _rich_cd == 0.0:
			_rich_tray = true
			_rich_expire = 12.0
			Audio.play_sfx("item_bad", -10.0)
			Events.notify.emit("OFFERING_WRONG", [])
	elif _rich_tray:
		_rich_expire = maxf(0.0, _rich_expire - delta)
		if _rich_expire == 0.0:
			_rich_tray = false   # the rookie quietly swaps in a humble tray
			_rich_cd = randf_range(45.0, 90.0)

func request_use_item() -> void:
	if item_held == null or not _running or _tut_step >= 0:
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
		# Restore exactly: re-asserts Master/Music/SFX/Verb from Settings and clears any duck.
		Audio.apply_volumes()
	else:
		pause.open()
		get_tree().paused = true
		# Duck the SFX bus (where the heartbeat/drone/breathing/water/static loops live) so the
		# drone bed drops behind the menu. Reversible — resume calls Audio.apply_volumes().
		var sfx_idx := AudioServer.get_bus_index(Audio.SFX_BUS)
		if sfx_idx != -1:
			AudioServer.set_bus_volume_db(sfx_idx, -60.0)

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
func _refresh_door_sprite(side: int, t = false) -> void:
	if room == null:
		return
	if typeof(t) == TYPE_BOOL:   # sentinel: caller didn't supply it — look it up
		t = director.threat_at_door(side)
	if t:
		# Pass the threat's accent so the doorway rim light takes its cold/warm cast. (AUDIT#14)
		room.refresh_threat_visibility(side, true, t.current_texture(), true, t.accent_color)
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
	# Even a failed night still pays a little vàng mã for the hours you held — so a
	# loss feeds the shrine meta instead of being pure wasted time.
	if _last_hour > 0:
		_earn_coins(_last_hour * 3)
	# Anti-farm: do NOT commit best on death. Raising the bar only on a WIN keeps a
	# stuck player from grinding deaths up to an unbeatable threshold (see _earn_coins).
	Events.game_over.emit(cause)
	# Scariness scales with WHO caught you and how late it is: a Night-1 ông kẹ grab and a
	# Night-6 oan hồn grab should not feel identical.
	var t := director.get_threat(cause)
	var fear: float = float(t.fear_factor) if t else 3.0
	var prog := night_progress()
	var intensity: float = clampf(0.30 + fear * 0.11 + prog * 0.34, 0.0, 1.0)
	var is_oan: bool = cause == "oan_hon"
	# REDUCED scare tier is gentler than FULL: softer shake/strobe and no position jitter.
	var reduced: bool = Settings.scare_intensity == Settings.Scare.REDUCED

	# --- 1) ANTICIPATION — the held breath. The whole mix ducks out, the office snaps
	# dark, and a low sub swells for a beat where you KNOW it is coming. ----------------
	Audio.duck(26.0, 0.04, 1.2, 0.7)
	_stop_tension_loops()
	Audio.stop_music(0.05)
	if room:
		room.set_dread(1.0)
		room.set_powered(false)   # blackout for the beat
		if Settings.allow_jumpscares():
			room.add_shake(0.16)
	_flash.color = Color(0, 0, 0, 0)
	Audio.play_sting("pre_scare", -3.0, lerpf(1.06, 0.8, intensity))
	var pre := 0.32 + intensity * 0.22 + (0.26 if is_oan else 0.0)
	await get_tree().create_timer(pre).timeout
	if not is_inside_tree():
		return

	# --- 2) THE HIT ---------------------------------------------------------------------
	var meta := ThreatRegistry.info(cause)
	var scare_path: String = meta.get("scare", "") if not meta.is_empty() else ""
	var has_image: bool = Settings.allow_jumpscares() and scare_path != "" and ResourceLoader.exists(scare_path)
	if has_image:
		_jumpscare_rect.texture = load(scare_path)
		_jumpscare_rect.pivot_offset = _jumpscare_rect.size * 0.5
		var pop := 1.18 if is_oan else 1.5
		_jumpscare_rect.scale = Vector2(pop, pop)
		_jumpscare_rect.modulate = Color(1, 1, 1, 1)
		_jumpscare_rect.visible = true
		if _scare_mat:
			_scare_mat.set_shader_parameter("hit", 1.0)
		var ts := create_tween()
		ts.tween_property(_jumpscare_rect, "scale", Vector2.ONE, 0.7 if is_oan else 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		# REDUCED tier skips the screen-position jitter entirely (FULL keeps it).
		if not reduced:
			_jump_jitter_t = (0.28 if is_oan else 0.5) * (0.7 + intensity)
		# REDUCED uses the soft/low-intensity strobe variant (as Oan hồn already does).
		_strobe_flash(is_oan or reduced)
		if room:
			# REDUCED halves the jumpscare shake; FULL is unchanged.
			room.add_shake(clampf(0.85 + intensity * 0.35, 0.0, 1.2) * (0.6 if is_oan else 1.0) * (0.5 if reduced else 1.0))
		Audio.play_jumpscare(lerpf(1.0, 0.82, intensity))
	else:
		# accessibility / non-lethal cause: a soft red wash + a breath sting, no jump image.
		Audio.play_sting("sting_breath", -5.0, 1.0)
		# Scares OFF must produce no shake and no flash — gate the red wash + jolt.
		if Settings.allow_jumpscares():
			_flash.color = Color(0.35, 0.02, 0.02, 0.55)
			var tfade := create_tween()
			tfade.tween_property(_flash, "color:a", 0.0, 0.9)
			if room:
				room.add_shake(0.4)

	# --- 3) LINGER — hold the burned-in face in dead silence, then dissolve to black. ---
	await get_tree().create_timer(0.9 + intensity * 0.5).timeout
	if not is_inside_tree():
		return
	if has_image and _jumpscare_rect.visible:
		var td := create_tween()
		td.tween_property(_jumpscare_rect, "modulate:a", 0.0, 0.5)
	await get_tree().create_timer(0.6).timeout
	Save.record_death(cause)
	Router.to_game_over(cause)

## Multi-step flash on the grab: a hard white pop, a dark dip, a softer second pop, out —
## reads as a strobing camera shock, not a single fade. Oan hồn gets a gentler version.
func _strobe_flash(soft: bool) -> void:
	var peak := 0.55 if soft else 0.92
	_flash.color = Color(1, 1, 1, peak)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.15, 0.06)
	tw.tween_property(_flash, "color:a", peak * 0.7, 0.05)
	tw.tween_property(_flash, "color:a", 0.0, 0.4)

func _win() -> void:
	if _ending:
		return
	_ending = true
	_running = false
	director.set_paused(true)
	_stop_tension_loops()   # heartbeat, drone, sub, breathing, strain, water, incense...
	if room:
		room.set_dread(0.0)
	Audio.stop_music(0.2)   # let the win/ending screen start its own ambience cleanly
	# Dawn relief: the rooster, a soft temple bell, and a warm swell — an exhale after
	# the night, with the new reverb tail letting it breathe.
	Audio.play_sfx("rooster", -3.0, 1.0, Audio.VERB_BUS)
	# Delay the temple bell a beat so it reads as "cockcrow, then bell", not a single smear.
	get_tree().create_timer(0.35).timeout.connect(func():
		Audio.play_sfx("offering_bell", -10.0, 1.0, Audio.VERB_BUS))
	_earn_coins(15)   # survival bonus toward shrine upgrades
	_commit_best()
	Events.night_survived.emit()
	Game.notify_night_survived()
	# Dawn beat: a soft warm-gold wash that fades, and the bruised vignette settling to a
	# clean warm white — relief reads visually before we route to the win screen.
	if _flash:
		_flash.color = Color(1.0, 0.86, 0.55, 0.0)
		var tg := create_tween()
		tg.tween_property(_flash, "color:a", 0.4, 0.5)
		tg.tween_property(_flash, "color:a", 0.0, 0.7)
	if _vignette:
		var tv := create_tween()
		tv.tween_property(_vignette, "modulate", Color(1.0, 0.97, 0.9, 1.0), 0.7)
	await get_tree().create_timer(0.9).timeout
	# Clearing the final story night resolves the campaign with a proper ending
	# (siêu thoát if the investigation is complete, otherwise the survive epilogue).
	if not Game.is_custom and Game.current_night >= Game.MAX_NIGHTS:
		Router.to_ending()
	else:
		Router.to_win()

## Stop every sustained loop and clear the loop-state flags — the single source of
## truth for the death/win audio teardown (the documented loop-cleanup invariant), so
## the two end states can't silently drift apart when a new loop is added later.
func _stop_tension_loops() -> void:
	Audio.stop_all_loops()
	_drone_on = false
	_hb_on = false
	_breath_on = false
	_strain_on = false
	_water_on = false

# --- public API used by threats & items ------------------------------------
func is_door_closed(side: int) -> bool:
	return room.is_door_closed(side)

func is_light_on(side: int) -> bool:
	return room.is_light_on(side)

func get_pan_speed() -> float:
	return room.get_pan_speed()

func is_monitor_open() -> bool:
	return monitor_open

func is_running() -> bool:
	return _running

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
	var hit := amount * (1.0 - clampf(startle_resist, 0.0, 0.8))
	add_via(hit)
	# A meaningful startle burst should be felt: a jolt (gated on jumpscares) + a breath
	# sting scaled to the size of the hit, so a wisp's startle lands with weight.
	if hit <= -6.0:
		if Settings.allow_jumpscares() and room:
			room.add_shake(0.25)
		var mag := clampf(absf(hit) / 18.0, 0.0, 1.0)
		Audio.play_sting("sting_breath", lerpf(-12.0, -3.0, mag), 1.0)

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
	# Cold-draft telegraph: a warning beat fires first (wind swell + the altar's candles
	# guttering harder), THEN the snuff lands — so the player gets a ~1-1.5s window to read
	# it. The altar only WARNS here; it is never the monster (binding rule). (backlog#22)
	if _draft_warn_t > 0.0:
		_draft_warn_t = maxf(0.0, _draft_warn_t - delta)
		if _draft_warn_t == 0.0 and altar_lit:
			_gutter_candles(true)   # gust already played at the warning beat
	# Cold-draft event: a gust snuffs the candles. Likelier (and meaner) late at night.
	_draft_cd -= delta
	if _draft_cd <= 0.0:
		_draft_cd = randf_range(32.0, 62.0) * (1.0 - 0.35 * night_progress())
		if altar_lit and _draft_warn_t <= 0.0 and randf() < 0.45 + 0.35 * night_progress():
			# Telegraph, don't snuff yet: a low wind swell + the candle flicker spikes for the
			# warning window (candle_gust SFX already leads with an inhaled breath).
			_draft_warn_t = randf_range(1.0, 1.5)
			Audio.play_sfx("candle_gust", -3.0)
			if room and room.has_method("warn_draft"):
				room.warn_draft(_draft_warn_t)
	if altar_lit:
		huong = maxf(0.0, huong - _huong_decay * delta)
		if huong <= 0.0:
			if _auto_relight:
				_auto_relight = false
				_light_incense(true)
			else:
				_gutter_candles()
	# When the altar is dark — or the incense is nearly out — the spirits press in.
	# Routed through add_via_drain so vía regen can still fight it (no hard lockout).
	# A guttered altar bites HARD now: incense is a high-stakes resource you can't ignore.
	if not altar_lit:
		add_via_drain(-5.5 * delta)
	elif huong <= 20.0:
		add_via_drain(-2.6 * delta)
	if room:
		room.set_huong(huong / huong_max)
		room.set_altar_lit(altar_lit)
	Events.huong_changed.emit(huong / huong_max)
	if _incense_cd > 0.0:
		_incense_cd = maxf(0.0, _incense_cd - delta)
	if _bell_cd > 0.0:
		_bell_cd = maxf(0.0, _bell_cd - delta)

func _gutter_candles(skip_gust: bool = false) -> void:
	if not altar_lit:
		return
	altar_lit = false
	huong = 0.0
	# Telegraphed snuffs already played candle_gust at the warning beat — don't double it. (backlog#22)
	if not skip_gust:
		Audio.play_sfx("candle_gust", -3.0)
	Audio.play_sting("sting_breath", -10.0, 1.0)
	Audio.stop_loop("incense_bed")   # the room goes acoustically cold
	if room:
		room.add_shake(0.5)
	Events.altar_lit_changed.emit(false)
	Events.huong_changed.emit(0.0)
	Events.notify.emit("ALTAR_DRAFT", [])

func request_light_incense() -> void:
	if not _running or _incense_cd > 0.0:
		return
	if _nhang <= 0:
		Audio.play_sfx("sting_low", -18.0)
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
		huong = minf(huong_max, huong + 70.0)
		_incense_cd = 4.0
	if room:
		room.set_huong(huong / huong_max)
		room.set_altar_lit(true)
	Audio.start_loop("incense_bed", -28.0)   # the altar warms back up
	Events.altar_lit_changed.emit(true)
	Events.huong_changed.emit(huong / huong_max)
	if not silent:
		Audio.play_sfx("incense_whoosh", -3.0)
		# backlog#31: a RARE dread beat, gated on a near-failure state (vía shaken/critical or the
		# incense already burning low) — the burner seems to hold a FOURTH stick (tứ→tử, the
		# four/death taboo). Audio-only cue; the altar only WARNS, it is never the monster.
		var near_fail := via_state != GameEnums.ViaState.NORMAL or huong <= 25.0
		if near_fail and randf() < 0.08:
			Audio.play_sting("sting_low", -13.0, 0.9)

## Replenish the incense bundle (the held "nhang" item is a fresh handful of sticks).
func add_nhang(n: int) -> void:
	_nhang += n
	Events.incense_changed.emit(_nhang)

func request_ring_bell() -> void:
	if not _running or _bell_cd > 0.0:
		return
	_tut_bell = true
	_bell_cd = _bell_cd_max
	Audio.play_sfx("offering_bell", -2.0)
	# The bell now does ONE job — shove the nearest rusher back from the door — so it's
	# a positioning tool, not a second free altar. (Meter spirits are the incense's job.)
	var pushed := director.setback_nearest()
	add_via(6.0)
	# Make the bell's push-back visible: a small jolt + a brief reveal of the map.
	if room:
		room.add_shake(0.12)
	start_reveal(1.5)
	# When there is nothing to set back (only meter spirits, or the risen corpse — a
	# CREEPER that is door-only), say so, instead of a silent no-op that reads as broken. (AUDIT#36)
	if not pushed:
		Events.notify.emit("BELL_NO_TARGET", [])

## Combined threat-aggression multiplier (read by the meter threats each frame):
## tending the incense suppresses them; a guttered altar or the bánh-lạ curse
## whips them up. This is what makes the altar your primary, active defense.
func meter_mult() -> float:
	var m := _aggro_mult
	if not altar_lit:
		m *= 1.7
	elif huong >= 60.0:
		m *= (0.4 if _bright_altar else 0.5)
	elif huong <= 25.0:
		m *= 1.5
	return m

# --- phone ------------------------------------------------------------------
func request_answer_phone() -> void:
	if not _running or _tut_step >= 0 or phone == null:
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
	# A brief static/brightness spike on the live feed confirms the tag landed.
	if monitor and monitor.has_method("tag_confirm"):
		monitor.tag_confirm()
	Events.anomaly_tagged.emit(threat_id)
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
		# A distinct temple-bell cue for investigation progress (vs the generic item pickup).
		Audio.play_sfx("offering_bell", -8.0)

# --- vía / currency ---------------------------------------------------------
## Continuous meter drain that does NOT freeze vía regen (see _update_via). Slow
## meter pressure is a net bleed you can offset, not an unrecoverable lockout.
func add_via_drain(amount: float) -> void:
	if amount < 0.0:
		amount *= via_drain_mult
	via = clampf(via + amount, 0.0, via_max)
	Events.via_changed.emit(via, via_max)

func _earn_coins(n: int) -> void:
	# No-farming: only the part of this run's gross earnings that exceeds the night's
	# previous best is banked. Replaying a night you've already milked pays nothing new,
	# so careful first clears — not grinding deaths/retries — drive the shrine economy.
	_run_earned += n
	var best := int(Save.night_best_coins.get(_night_key(), 0))
	var creditable: int = clampi(_run_earned - best, 0, n)
	if creditable <= 0:
		return
	coins += creditable
	Save.coins = coins
	Save.save_progress()
	Events.coins_changed.emit(coins)
	# Defer the coin chime a beat so it doesn't smear against the hourly clock_chime
	# (both otherwise land on the same frame); they read as two distinct cues.
	get_tree().create_timer(0.35).timeout.connect(func(): Audio.play_sfx("coin_chime", -16.0))

func _night_key() -> String:
	return "custom" if Game.is_custom else str(Game.current_night)

## Lock in this run's gross earnings as the night's best, so future runs only pay the delta.
func _commit_best() -> void:
	var k := _night_key()
	Save.night_best_coins[k] = maxi(int(Save.night_best_coins.get(k, 0)), _run_earned)
	Save.save_progress()

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
