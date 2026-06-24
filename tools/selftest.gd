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
	check("closed door repels ong_ke", not og.is_at_door())
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
		md.flood = 30.0
		md._lure_active = true
		Events.intercom_answered.emit()
		check("ma_da: answering raises flood", md.flood > 30.0)
		md.flood = 50.0
		Events.office_action.emit("close_drain")
		check("ma_da: close_drain lowers flood", md.flood < 50.0)
		md.flood = 50.0
		md.on_calm()
		check("ma_da: incense lowers flood", md.flood < 50.0)
		md.flood = 50.0
		md.on_offering("")
		check("ma_da: offering lowers flood", md.flood < 50.0)

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

	print("\n--- MA TROI (non-lethal surge) ---")
	var mt = d.get_threat("ma_troi")
	if mt:
		c._agitation = 0.9
		mt.lock = 99.0
		var vbefore: float = c.via
		mt.process_ai(0.2, 0.5)
		check("ma_troi: surge resets lock (not a kill)", mt.lock <= 60.0 and mt._active)
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
	# Meter threat: a ward must actually break the meter's hold, not just dent it.
	var md2 = d.get_threat("ma_da")
	if md2:
		md2.flood = 100.0
		md2._active = false
		c.ward_tokens = 1
		c._ending = false
		c._on_jumpscare("ma_da")
		check("ward fully breaks ma_da flood", md2.flood <= 25.0)
		check("ward revives ma_da (not stuck dead)", md2._active)

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

	print("\n--- PHONE ---")
	var ph = c.phone
	ph.begin()
	ph._start_real()
	check("real phone call rings", ph.is_ringing() and not ph.is_fake())
	c.via = 50.0
	ph.answer()
	check("answering real call stops the ring", not ph.is_ringing())
	ph._on_water_lure(true)
	check("ma da lure rings a FAKE call", ph.is_ringing() and ph.is_fake())
	var md3 = d.get_threat("ma_da")
	if md3:
		md3.flood = 30.0
		md3._lure_active = true
		ph.answer()
		check("answering the fake ring spikes flood", md3.flood > 30.0)

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
	var c0: int = c.coins
	c._earn_coins(5)
	check("earning coins adds + persists", c.coins == c0 + 5 and Save.coins == c.coins)
	check("cannot overspend coins", not c.try_spend_coins(c.coins + 100))
	check("spending deducts coins", c.try_spend_coins(3) and c.coins == c0 + 2)
	Save.coins = 100
	check("buy shrine upgrade persists", Save.purchase_upgrade("sturdy_doors", 34) and Save.has_upgrade("sturdy_doors"))
	check("cannot rebuy an owned upgrade", not Save.purchase_upgrade("sturdy_doors", 34))
	Save.upgrades.erase("sturdy_doors")   # don't pollute the real save with a test buy
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
