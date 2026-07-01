extends Node
## Dev-only headless self-test. Boots a Night and drives the gameplay systems
## through every scenario, asserting outcomes. Run:
##   NW_SKIP_TAPE=1 NW_NIGHT=6 godot --headless --path . res://tools/SelfTest.tscn
## Prints PASS/FAIL per check and a summary, then quits. It deliberately avoids
## triggering the real game-over / win (those change scene and would kill it).

var passed := 0
var failed := 0
var fails: Array = []

func check(name: String, cond: bool) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		fails.append(name)
	print(("  PASS  " if cond else "  FAIL  ") + name)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	await _frames(2)
	var night = load("res://scenes/Night.tscn").instantiate()
	add_child(night)
	await _frames(40)                 # let _ready build + _begin_night run
	if not night._running and night.has_method("_begin_night"):
		night._begin_night()
		await _frames(2)
	await _run(night)
	print("\n==== SELFTEST: %d passed, %d failed ====" % [passed, failed])
	if failed > 0:
		print("FAILURES:")
		for f in fails:
			print("   - " + f)
	get_tree().quit(1 if failed > 0 else 0)

func _run(c) -> void:
	var d = c.director
	d.set_paused(true)   # take manual control of threat ticking

	print("\n--- BOOT ---")
	check("running after begin", c._running)
	check("power starts full", c.power >= 99.0)
	check("via starts full", c.via >= c.via_max - 0.5)
	check("incense in hand by default", c.item_held != null and c.item_held.id == "nhang")
	check("offerings start > 0 (night6)", c.offerings > 0)
	check("6 threats spawned (night6)", d.threats.size() == 6)

	print("\n--- DOORS / LIGHTS / MONITOR ---")
	c.request_toggle_door(GameEnums.Side.LEFT)
	check("left door closes", c.is_door_closed(GameEnums.Side.LEFT))
	c.request_toggle_door(GameEnums.Side.LEFT)
	check("left door reopens", not c.is_door_closed(GameEnums.Side.LEFT))
	c.request_toggle_light(GameEnums.Side.RIGHT)
	check("right light on", c.is_light_on(GameEnums.Side.RIGHT))
	c.request_toggle_light(GameEnums.Side.RIGHT)
	check("right light off", not c.is_light_on(GameEnums.Side.RIGHT))
	c.request_toggle_monitor()
	check("monitor opens", c.is_monitor_open())
	c.on_camera_changed(MapGraph.RIGHT_HALL)
	check("camera switch registers", c.current_cam == MapGraph.RIGHT_HALL)
	c.request_toggle_monitor()
	check("monitor closes", not c.is_monitor_open())

	print("\n--- POWER DRAIN ---")
	c.power = 100.0
	var p0: float = c.power
	c.request_toggle_door(GameEnums.Side.LEFT)
	await _frames(20)
	check("power drains while door held", c.power < p0)
	c.request_toggle_door(GameEnums.Side.LEFT)
	c.power = 100.0

	print("\n--- OFFERINGS ---")
	c.offerings = 2
	c.via = 50.0
	c.request_offering()
	check("offering consumed", c.offerings == 1)
	check("offering raised via", c.via > 50.0)

	print("\n--- INCENSE ITEM (calm_zone) ---")
	c.via = 40.0
	c.item_held = ItemRegistry.get_def("nhang")
	c.request_use_item()
	check("item consumed on use", c.item_held == null)
	check("incense raised via", c.via > 40.0)
	check("incense triggered reveal", c.is_revealed())

	print("\n--- EVERY ITEM EFFECT (no crash) ---")
	var all_ok := true
	for def in ItemRegistry.all():
		c.via = 60.0
		c.power = 80.0
		if not c.item_system.apply(def):   # apply() now reports unknown/dead effects
			all_ok = false
	check("all %d item effects applied cleanly" % ItemRegistry.all().size(), all_ok)
	check("ward-granting items added a ward", c.ward_tokens >= 1)
	c.cleanse()

	print("\n--- WARD BLOCKS DEATH ---")
	c.ward_tokens = 1
	c._ending = false
	var og = d.get_threat("ong_ke")
	og._arrive_at_door(GameEnums.Side.LEFT)
	check("ong_ke reaches the door", og.is_at_door())
	og._kill()
	await _frames(2)
	check("ward consumed on grab", c.ward_tokens == 0)
	check("ward block keeps night alive", not c._ending)

	print("\n--- ONG KE COUNTERS ---")
	og.reset_to_spawn()
	og._arrive_at_door(GameEnums.Side.LEFT)
	c.request_toggle_door(GameEnums.Side.LEFT)
	d.broadcast_door(GameEnums.Side.LEFT, true)
	og._process_attack(0.1)
	check("closed door does NOT instantly banish ong_ke (must hold it)", og.is_at_door())
	for i in 50:   # > linger_time: holding the door shut finally makes him give up
		og._process_attack(0.1)
	check("holding the door shut repels ong_ke", not og.is_at_door())
	c.request_toggle_door(GameEnums.Side.LEFT)
	og.reset_to_spawn()
	og._arrive_at_door(GameEnums.Side.LEFT)
	c.room.set_light(GameEnums.Side.LEFT, true)
	for i in 40:
		og._process_attack(0.1)
	check("light+still 'ngoan' repels ong_ke", not og.is_at_door())
	c.room.set_light(GameEnums.Side.LEFT, false)

	print("\n--- MA DA ---")
	var md = d.get_threat("ma_da")
	if md:
		# Ma da now roams the right wing like a normal wanderer; door is the counter.
		check("ma_da is a wanderer", md.movement_model == ThreatBase.MODEL_WANDER)
		check("ma_da is countered by the door", md.counter_door)
		check("ma_da spawns in the restroom", md.spawn_location == MapGraph.RESTROOM)
		# It never strays out of its authored wet-wing zone (no leak to the left wing / office).
		md.reset_to_spawn()
		var in_zone := true
		for _i in 30:
			md._behaviour_move()
			if not md.wander_zone.has(md.current_location):
				in_zone = false
				break
		check("ma_da stays inside its wander zone", in_zone)
		# Holding the right door shut presses it off and sends it back (shared linger logic).
		md.reset_to_spawn()
		md._arrive_at_door(GameEnums.Side.RIGHT)
		c.request_toggle_door(GameEnums.Side.RIGHT)
		d.broadcast_door(GameEnums.Side.RIGHT, true)
		for _i in 50:
			md._process_attack(0.1)
		check("holding the right door shut repels ma_da", not md.is_at_door())
		c.request_toggle_door(GameEnums.Side.RIGHT)

	print("\n--- CO HON ---")
	var ch = d.get_threat("co_hon")
	if ch:
		ch.crowd = 60.0
		ch.on_offering("")
		check("co_hon: offering lowers crowd", ch.crowd < 60.0)
		ch.crowd = 60.0
		ch.on_calm()
		check("co_hon: incense lowers crowd", ch.crowd < 60.0)

	print("\n--- OAN HON ---")
	var oh = d.get_threat("oan_hon")
	if oh:
		oh.agro = 30.0
		oh.on_view(true)
		oh.process_ai(0.5, 0.5)
		check("oan_hon: agro rises while watched", oh.agro > 30.0)
		oh.agro = 50.0
		oh.on_offering("")
		check("oan_hon: offering lowers agro", oh.agro < 50.0)
		# The ignored branch must still net positive even while the altar is lit (mult 0.5),
		# or the paradox collapses to "just never look at her". (balance #31)
		c.altar_lit = true
		c.huong = 100.0
		oh.on_view(false)
		oh.agro = 30.0
		for _i in 10:
			oh.process_ai(0.5, 0.5)
		check("oan_hon: neglect builds grievance even while incensed", oh.agro > 32.0)
		oh.agro = 0.0
		oh.on_view(false)

	print("\n--- MA TROI (non-lethal surge) ---")
	var mt = d.get_threat("ma_troi")
	if mt:
		c._agitation = 0.9
		mt.lock = 99.0
		var vbefore: float = c.via
		mt.process_ai(0.2, 0.5)
		check("ma_troi: surge resets lock below the 40 bleed threshold (not a kill)", mt.lock <= 40.0 and mt._active)
		check("ma_troi: surge costs via", c.via < vbefore)
		check("ma_troi: surge jinxes the controls", c._hex_t > 0.0)
		c._agitation = 0.0
		c._hex_t = 0.0   # clear the lock-on jinx so it doesn't bleed into later sections

	print("\n--- QUY NHAP TRANG (cat) ---")
	var qy = d.get_threat("quy_nhap_trang")
	if qy:
		if c.is_door_closed(GameEnums.Side.RIGHT):
			c.request_toggle_door(GameEnums.Side.RIGHT)
		c.barrier_timer = 0.0
		qy.triggered = false
		qy.mun_progress = 99.0
		qy.process_ai(0.5, 0.5)
		check("quy: cat crossing triggers corpse", qy.triggered)
		check("quy: becomes creeper post-trigger", qy.movement_model == ThreatBase.MODEL_CREEPER)
		qy.triggered = false
		qy.movement_model = ThreatBase.MODEL_PATH
		qy.mun_progress = 50.0
		c.request_toggle_door(GameEnums.Side.RIGHT)   # close -> divert
		d.broadcast_door(GameEnums.Side.RIGHT, true)
		var mp: float = qy.mun_progress
		qy.process_ai(0.5, 0.5)
		check("quy: right door diverts the cat", qy.mun_progress < mp)
		c.request_toggle_door(GameEnums.Side.RIGHT)

	print("\n--- POWER OUT ---")
	c._powered = true
	c.power = 0.05
	c.request_toggle_door(GameEnums.Side.LEFT)   # extra drain so it reaches 0 quickly
	await _frames(20)
	check("reaching 0 power blacks out", not c._powered)
	check("blackout forces doors open", not c.is_door_closed(GameEnums.Side.LEFT))
	c.power = 100.0
	c._powered = true
	c.room.set_powered(true)

	print("\n--- VIA-ZERO DECISION ---")
	c.ward_tokens = 1
	check("try_block_death true with ward", c.try_block_death("x"))
	check("ward consumed by block", c.ward_tokens == 0)
	check("try_block_death false without ward", not c.try_block_death("x"))

	print("\n--- VENDOR SHOP ---")
	var ve = c.vendor
	ve.state = GameEnums.VendorState.SHOP
	ve.counterfeit = false
	ve.stock = ItemRegistry.random_shop(ve._rng, 3, false)
	c.item_held = null
	c.coins = 10   # shop items now cost vàng mã, so the buyer needs a wallet
	c.open_shop()
	await _frames(2)
	check("shop opens at gate", c.shop.visible)
	if not ve.stock.is_empty():
		var price: int = ve.stock[0].cost
		check("bought item deducts its cost", ve.on_bought(ve.stock[0]) and c.coins == 10 - price)
		check("buying acquires the item", c.item_held != null)
		check("vendor leaves after purchase", ve.state == GameEnums.VendorState.IDLE)
	if c.shop.visible:
		c.shop.visible = false

	print("\n--- VENDOR ON CAMERA ---")
	ve.state = GameEnums.VendorState.SHOP
	check("vendor shows on the gate feed while shopping", ve.on_camera() and ve.cam_texture() != null)
	ve.state = GameEnums.VendorState.IDLE
	check("vendor is off-camera when idle", not ve.on_camera())

	print("\n--- GIAT CO HON + FORBIDDEN OFFERING ---")
	c._running = true
	c._rich_tray = false
	c._rich_cd = 0.0
	var ch2 = d.get_threat("co_hon")
	if ch2:
		# Giật cô hồn — GUARD (offering key during the window) slights the souls (crowd rises).
		c._scramble_t = 4.0
		ch2.crowd = 40.0
		c.request_offering()
		check("giật guard slights the souls (crowd rises, window ends)", ch2.crowd > 40.0 and c._scramble_t == 0.0)
		# SNATCH (let the window expire) brings lộc (coins credited).
		var saved_best2: Dictionary = Save.night_best_coins.duplicate(true)
		Save.night_best_coins[c._night_key()] = 0
		c._run_earned = 0
		c._rich_cd = 0.0
		var coins_b: int = c.coins
		c._scramble_t = 0.1
		c._update_timers(0.2)
		check("giật snatch brings lộc (coins credited)", c.coins > coins_b and c._scramble_t == 0.0)
		Save.night_best_coins = saved_best2
		Save.save_progress()
		# Forbidden offering — a rich/mặn tray is refused: the offering is spent, nothing appeased.
		c._scramble_t = 0.0
		c._rich_tray = true
		c.offerings = 2
		ch2.crowd = 50.0
		c.request_offering()
		check("rich (mặn) offering is refused — consumed, no calm applied", c.offerings == 1 and ch2.crowd >= 50.0 and not c._rich_tray)
		c._rich_tray = false
		c._rich_cd = 0.0
	# The new player-facing keys must resolve (i.e. strings.csv was re-imported to the
	# .translation binaries — guards against a silent desync).
	check("new offering/giật strings resolve from the .translation",
		tr("OFFERING_WRONG") != "OFFERING_WRONG" and tr("GIAT_PROMPT") != "GIAT_PROMPT" and tr("GIAT_SNATCH") != "GIAT_SNATCH")

	print("\n--- WARD SAVE EDGE CASES ---")
	# Counterfeit vendor: a ward must send her packing, not leave her frozen to
	# re-fire the grab next frame (regression guard for the vendor ward-block bug).
	ve.state = GameEnums.VendorState.HOSTILE
	ve._hostile_t = -1.0
	c.ward_tokens = 1
	c._ending = false
	c._on_jumpscare("ba_hang_rong")
	check("ward blocks vendor grab (night alive)", not c._ending)
	check("ward sends hostile vendor back to idle", ve.state == GameEnums.VendorState.IDLE)
	# The REAL grab goes through _attack(), which self-disables to LEAVING before emitting;
	# a ward save must still send her home from LEAVING (regression guard).
	ve.state = GameEnums.VendorState.HOSTILE
	c.ward_tokens = 1
	c._ending = false
	ve._attack()   # -> LEAVING, emits jumpscare -> _on_jumpscare -> repel_to_idle
	check("ward resets vendor even via the real _attack/LEAVING path", ve.state == GameEnums.VendorState.IDLE and not c._ending)
	# A ward against ma_da's grab must keep the night alive and revive it (not leave it dead).
	var md2 = d.get_threat("ma_da")
	if md2:
		md2._active = false
		c.ward_tokens = 1
		c._ending = false
		c._on_jumpscare("ma_da")
		check("ward keeps the night alive against ma_da", not c._ending)
		check("ward revives ma_da (not stuck dead)", md2._active)

	print("\n--- MONITOR TOGGLE RACE ---")
	# Close-then-open within the 0.10s lower-fade must not let the stale hide callback
	# blank a reopened panel (look-lock regression guard).
	c._set_monitor(true)
	c._set_monitor(false)   # starts the 0.10s close fade
	c._set_monitor(true)    # reopen — must kill the pending close fade
	await get_tree().create_timer(0.2).timeout
	check("reopening the monitor mid-close keeps it visible", c.monitor.visible and c.monitor_open)
	c._set_monitor(false)
	await get_tree().create_timer(0.2).timeout
	check("a normal close still hides the monitor", not c.monitor.visible and not c.monitor_open)

	print("\n--- ALTAR RITUAL (hương — now a finite nhang resource) ---")
	c.huong = 10.0
	c.altar_lit = true
	c._incense_cd = 0.0
	c._nhang = 3
	c.request_light_incense()
	check("hand-lit incense tops up hương (partial, not full)", c.huong >= 60.0 and c.huong < 100.0)
	check("hand-lit incense keeps altar lit", c.altar_lit)
	check("hand-lit incense burns one nhang", c._nhang == 2)
	# Out of incense: relighting does nothing — the finite stock is the real cost.
	c._nhang = 0
	c._incense_cd = 0.0
	c.huong = 10.0
	c.request_light_incense()
	check("no nhang = no relight", c.huong <= 10.5)
	c._nhang = 0
	c.item_system.apply(ItemRegistry.get_def("nhang"))
	check("held nhang item replenishes the stock", c._nhang >= 3)
	c._gutter_candles()
	check("cold draft guts the altar", not c.altar_lit and c.huong <= 0.1)
	c._light_incense(true)   # free/auto relight restores fully
	check("free relight restores altar fully", c.altar_lit and c.huong >= 99.0)
	c.huong = 100.0
	c.altar_lit = true
	var mult_lit: float = c.meter_mult()
	c.altar_lit = false
	var mult_dark: float = c.meter_mult()
	check("guttered altar raises threat aggression", mult_dark > mult_lit)
	c.altar_lit = true
	c.huong = 100.0
	c._bell_cd = 0.0
	c.via = 50.0
	c.request_ring_bell()
	check("bell raises vía + starts cooldown", c.via > 50.0 and c._bell_cd > 0.0)

	print("\n--- VÍA DRAIN (regen not locked by meter pressure) ---")
	c.via = 50.0
	c._via_drain_cd = 0.0
	c.add_via_drain(-1.0)
	check("add_via_drain lowers vía", c.via < 50.0)
	check("meter drain does NOT freeze regen", c._via_drain_cd <= 0.0)
	c.add_via(-1.0)
	check("burst drain DOES pause regen", c._via_drain_cd > 0.0)
	# Blackout bleed must route through the CONTINUOUS channel (add_via_drain) so vía regen
	# is never frozen for 0.7s after power returns — regression guard for the power-out path.
	# (looming=true isolates the bleed from regen so the assertion is deterministic.)
	c._powered = false
	c.via = 80.0
	c._via_drain_cd = 0.0
	c._update_via(0.1, true)
	check("blackout bleed lowers vía", c.via < 80.0)
	check("blackout bleed does NOT freeze vía regen", c._via_drain_cd <= 0.0)
	c._powered = true
	c.room.set_powered(true)

	print("\n--- AUDIO TEARDOWN ---")
	# Death/win loop cleanup is centralised in one helper so the two end states can't drift.
	c._drone_on = true
	c._hb_on = true
	c._breath_on = true
	c._strain_on = true
	c._stop_tension_loops()
	check("_stop_tension_loops clears every loop-state flag",
		not c._drone_on and not c._hb_on and not c._breath_on and not c._strain_on)
	# play_sting honours the REDUCED accessibility tier (attenuates) and leaves FULL bit-identical.
	var prev_scare: int = Settings.scare_intensity
	Settings.scare_intensity = Settings.Scare.FULL
	var pf = Audio.play_sting("sting_low", -10.0, 1.0)
	check("play_sting is a 0 dB offset on FULL (unchanged)", pf != null and is_equal_approx(pf.volume_db, -10.0))
	Settings.scare_intensity = Settings.Scare.REDUCED
	var pr = Audio.play_sting("sting_low", -10.0, 1.0)
	check("play_sting attenuates a scare sting on REDUCED", pr != null and pr.volume_db < -10.5)
	Settings.scare_intensity = prev_scare
	# Master mix: the limiter is a clean brickwall catch (low soft-clip) and the comp is eased.
	var _mi := AudioServer.get_bus_index("Master")
	var _lim_ok := false
	var _comp_ok := false
	for _ei in AudioServer.get_bus_effect_count(_mi):
		var _fx = AudioServer.get_bus_effect(_mi, _ei)
		if _fx is AudioEffectLimiter:
			_lim_ok = _fx.soft_clip_db <= 0.5
		elif _fx is AudioEffectCompressor:
			_comp_ok = _fx.ratio <= 3.0
	check("master limiter soft-clip is a clean catch (<=0.5 dB)", _lim_ok)
	check("master compressor ratio eased (<=3.0)", _comp_ok)

	print("\n--- PHONE ---")
	var ph = c.phone
	ph.begin()
	ph._start_real()
	check("real phone call rings", ph.is_ringing())
	c.via = 50.0
	ph.answer()
	check("answering real call stops the ring", not ph.is_ringing())
	check("answering a real call grants the boon (vía up)", c.via > 50.0)

	print("\n--- CAMERA ANOMALY TAG ---")
	var ot = d.get_threat("ong_ke")
	ot.reset_to_spawn()
	ot._arrive_at_door(GameEnums.Side.LEFT)
	c._tag_cds.clear()
	c.reveal_timer = 0.0
	c.tag_anomaly("ong_ke")
	check("tagging sets a rusher back", not ot.is_at_door())
	check("tagging briefly reveals the map", c.is_revealed())

	print("\n--- COINS + SHRINE UPGRADES ---")
	# Reset this night's anti-farm best so the basic earn/spend checks are deterministic
	# regardless of any best banked by a prior win/flow-test (restored afterwards).
	var saved_best0: Dictionary = Save.night_best_coins.duplicate(true)
	Save.night_best_coins[c._night_key()] = 0
	c._run_earned = 0
	var c0: int = c.coins
	c._earn_coins(5)
	check("earning coins adds + persists", c.coins == c0 + 5 and Save.coins == c.coins)
	check("cannot overspend coins", not c.try_spend_coins(c.coins + 100))
	check("spending deducts coins", c.try_spend_coins(3) and c.coins == c0 + 2)
	Save.coins = 100
	check("buy shrine upgrade persists", Save.purchase_upgrade("sturdy_doors", 34) and Save.has_upgrade("sturdy_doors"))
	check("cannot rebuy an owned upgrade", not Save.purchase_upgrade("sturdy_doors", 34))
	Save.upgrades.erase("sturdy_doors")   # don't pollute the real save with a test buy
	Save.night_best_coins = saved_best0
	Save.save_progress()

	print("\n--- INVESTIGATION / ENDINGS ---")
	var saved_clues: Dictionary = Save.clues.duplicate(true)
	Save.clues = {}
	check("no clues at start", Save.clue_count() == 0 and not Save.investigation_complete())
	c._running = true
	c.find_clue("clue_name", "CLUE_GOT_NAME")
	check("find_clue records a clue", Save.has_clue("clue_name") and Save.clue_count() == 1)
	c.find_clue("clue_name", "CLUE_GOT_NAME")
	check("find_clue is idempotent", Save.clue_count() == 1)
	Save.find_clue("clue_drawing")
	check("two of three clues = still incomplete", not Save.investigation_complete())
	Save.find_clue("clue_photo")
	check("all three clues complete the investigation", Save.investigation_complete())
	Save.clues = saved_clues   # restore the player's real investigation progress
	Save.save_progress()

	print("\n--- NO-FARM ECONOMY ---")
	var saved_best: Dictionary = Save.night_best_coins.duplicate(true)
	var nkey: String = c._night_key()
	Save.night_best_coins[nkey] = 999   # pretend this night was already milked dry
	c._run_earned = 0
	var farm0: int = c.coins
	c._earn_coins(10)
	check("no coins credited past the night's best", c.coins == farm0)
	Save.night_best_coins[nkey] = 0
	c._run_earned = 0
	farm0 = c.coins
	c._earn_coins(10)
	check("a fresh-best night credits full earnings", c.coins == farm0 + 10)
	Save.night_best_coins = saved_best   # restore real progress
	Save.save_progress()

	print("\n--- SAVE ROBUSTNESS ---")
	# (a) A win is counted once: replaying an already-cleared night must not inflate
	# nights_won. Pure in-memory, restored afterwards.
	var saved_nc: Dictionary = Save.nights_cleared.duplicate(true)
	var saved_stats: Dictionary = Save.stats.duplicate(true)
	Save.nights_cleared = {}
	Save.stats["nights_won"] = 0
	Save.mark_night_cleared(2)
	Save.mark_night_cleared(2)   # replay of an already-cleared night
	check("mark_night_cleared counts a win once", int(Save.stats.get("nights_won", 0)) == 1 and Save.nights_cleared.has(2))
	Save.nights_cleared = saved_nc
	Save.stats = saved_stats
	Save.save_progress()

	# (b) .bak recovery re-heals progress.cfg; (c) a newer save_version is not downgraded.
	# The real save files are sandboxed to *.selftest and restored at the end, so the
	# player's campaign is never touched even if a check fails.
	var pth: String = Save.PATH
	var da2 := DirAccess.open("user://")
	if da2 != null:
		var had_main := da2.file_exists(pth)
		var had_bak := da2.file_exists(pth + ".bak")
		if had_main:
			if da2.file_exists(pth + ".selftest"): da2.remove(pth + ".selftest")
			da2.copy(pth, pth + ".selftest")
		if had_bak:
			if da2.file_exists(pth + ".bak.selftest"): da2.remove(pth + ".bak.selftest")
			da2.copy(pth + ".bak", pth + ".bak.selftest")
		# Known-good backup, deliberately-corrupt main: recovery should read the .bak.
		var good := ConfigFile.new()
		good.set_value("meta", "version", Save.SAVE_VERSION)
		good.set_value("progress", "highest_unlocked", 4)
		good.set_value("progress", "coins", 77)
		good.save(pth + ".bak")
		var fbad := FileAccess.open(pth, FileAccess.WRITE)
		fbad.store_buffer(PackedByteArray([0, 1, 2, 255, 254, 91, 91, 91, 61, 61]))
		fbad.close()
		Save.load_progress()
		check("recovery restores values from .bak", Save.highest_unlocked == 4 and Save.coins == 77)
		var reheal := ConfigFile.new()
		check("recovery re-heals a clean progress.cfg on disk", reheal.load(pth) == OK)
		# Forward-version guard: a save from a newer build must not be silently downgraded.
		var future := ConfigFile.new()
		future.set_value("meta", "version", Save.SAVE_VERSION + 99)
		future.set_value("progress", "highest_unlocked", 5)
		future.save(pth)
		if da2.file_exists(pth + ".bak"): da2.remove(pth + ".bak")   # force a read of main
		Save.load_progress()
		var after := ConfigFile.new()
		after.load(pth)
		check("newer save_version is not downgraded on disk", int(after.get_value("meta", "version", 0)) == Save.SAVE_VERSION + 99)
		# Restore the player's real save exactly.
		if da2.file_exists(pth): da2.remove(pth)
		if da2.file_exists(pth + ".bak"): da2.remove(pth + ".bak")
		if had_main: da2.rename(pth + ".selftest", pth)
		if had_bak: da2.rename(pth + ".bak.selftest", pth + ".bak")
		Save.load_progress()

	print("\n--- MA TROI HEX IS NON-LETHAL ---")
	c._hex_t = 0.0
	if c.is_door_closed(GameEnums.Side.LEFT):   # ensure the door is OPEN so the rusher looms
		c.request_toggle_door(GameEnums.Side.LEFT)
	var hx = d.get_threat("ong_ke")
	hx.reset_to_spawn()
	hx._arrive_at_door(GameEnums.Side.LEFT)
	c._hex_t = 3.0
	hx._process_attack(2.0)   # door is open + hexed: the kill timer must NOT advance
	check("hex pauses the kill timer", hx._attack_accum == 0.0 and hx.is_at_door())
	c._hex_t = 0.0
	hx._process_attack(0.5)   # unhexed: timer resumes (but not enough to kill)
	check("kill timer resumes after the hex clears", hx._attack_accum > 0.0)
	hx.reset_to_spawn()
	c._ending = false

	print("\n--- DIFFICULTY FLOOR ---")
	var prev_diff: int = Game.difficulty
	Game.difficulty = GameEnums.Difficulty.EASY
	var fcfg = Game._build_config(2, {"ong_ke": 1}, false, 60.0)
	check("story EASY floors an introduced threat at a teachable 2 (not 0/1)", int(fcfg.threat_levels.get("ong_ke", 0)) >= 2)
	# Custom nights keep an exact floor of 1 so an authored low slider value isn't bumped. (#37)
	var prev_custom: bool = Game.is_custom
	Game.is_custom = true
	var ccfg = Game._build_config(7, {"ong_ke": 1}, false, 75.0)
	check("custom night honours an authored level of 1 (floor stays 1)", int(ccfg.threat_levels.get("ong_ke", 0)) == 1)
	Game.is_custom = prev_custom
	Game.difficulty = prev_diff

	print("\n--- MAP (10 cameras, two wings, FNAF routes) ---")
	check("10 camera locations", MapGraph.CAMERAS.size() == 10)
	check("left wing mirrors to right", MapGraph.mirror(MapGraph.LEFT_HALL) == MapGraph.RIGHT_HALL and MapGraph.mirror(MapGraph.CANTEEN) == MapGraph.GYM)
	var ogk = d.get_threat("ong_ke")
	check("ong_ke walks a full multi-node wing route", ogk != null and ogk.path.size() >= 5)
	check("a wing route ends at a door", ogk != null and MapGraph.door_side(ogk.path[ogk.path.size() - 1]) != -1)
	var locs_ok := true
	for t in d.threats:
		var loc: String = t.current_location
		if not (MapGraph.is_camera(loc) or loc == MapGraph.OFFICE or MapGraph.door_side(loc) != -1):
			locs_ok = false
			print("    bad location: %s -> %s" % [t.id, loc])
	check("every threat sits on a valid map node", locs_ok)
	check("gate is a long approach from the office", MapGraph.distance(MapGraph.GATE, MapGraph.OFFICE) >= 5)
	check("a deep wing node still routes to the office", MapGraph.distance(MapGraph.LIBRARY, MapGraph.OFFICE) == 3)

	print("\n--- ROSTER INTEGRITY ---")
	var ids := ["ong_ke", "ma_da", "co_hon", "quy_nhap_trang", "ma_troi", "oan_hon"]
	var tex_ok := true
	for id in ids:
		var t = d.get_threat(id)
		if t == null or t.current_texture() == null:
			tex_ok = false
	check("every threat has a current texture", tex_ok)
	check("clock advanced past 0", c.game_minutes > 0.0)
	check("not accidentally ending", not c._ending)
