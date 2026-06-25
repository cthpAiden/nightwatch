extends Node
## Headless integrity sweep for Bảo Vệ Đêm. Boots every screen scene and every story
## night (plus a custom night), then validates registries, on-disk assets, and that
## localization keys resolve. Prints PASS/FAIL per check; exit code 1 on any failure.
##   godot --headless --path . res://tools/IntegrityCheck.tscn
## Do NOT set NW_NIGHT — the night sweep sets Game.current_night itself. The player's real
## save is snapshotted up front and restored at the end, so progress is never mutated.

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
	# Snapshot the player's real save; everything below runs sandboxed and restores it.
	var snap := {
		"hu": Save.highest_unlocked, "nc": Save.nights_cleared.duplicate(true),
		"bs": Save.bestiary_seen.duplicate(true), "tu": Save.tapes_unlocked.duplicate(true),
		"cb": Save.custom_night_beaten, "coins": Save.coins, "up": Save.upgrades.duplicate(true),
		"cl": Save.clues.duplicate(true), "es": Save.endings_seen.duplicate(true),
		"nbc": Save.night_best_coins.duplicate(true), "st": Save.stats.duplicate(true),
	}

	await _scene_sweep()
	await _night_sweep()
	_registries()
	_assets()
	_localization()

	# Restore the real save exactly.
	Save.highest_unlocked = snap.hu
	Save.nights_cleared = snap.nc
	Save.bestiary_seen = snap.bs
	Save.tapes_unlocked = snap.tu
	Save.custom_night_beaten = snap.cb
	Save.coins = snap.coins
	Save.upgrades = snap.up
	Save.clues = snap.cl
	Save.endings_seen = snap.es
	Save.night_best_coins = snap.nbc
	Save.stats = snap.st
	Save.save_progress()

	print("\n==== INTEGRITY: %d passed, %d failed ====" % [passed, failed])
	if failed > 0:
		print("FAILURES:")
		for f in fails:
			print("   - " + f)
	get_tree().quit(1 if failed > 0 else 0)

func _scene_sweep() -> void:
	print("\n--- SCENE BOOT (every screen builds without error) ---")
	var scenes := [
		"res://scenes/screens/MainMenu.tscn", "res://scenes/screens/Intro.tscn",
		"res://scenes/screens/NightSelect.tscn", "res://scenes/screens/SettingsMenu.tscn",
		"res://scenes/screens/ShrineScreen.tscn", "res://scenes/screens/ExtrasScreen.tscn",
		"res://scenes/screens/BestiaryScreen.tscn", "res://scenes/screens/TapeArchiveScreen.tscn",
		"res://scenes/screens/StatsScreen.tscn", "res://scenes/screens/CustomNightScreen.tscn",
		"res://scenes/screens/CreditsScreen.tscn", "res://scenes/screens/WinScreen.tscn",
		"res://scenes/screens/GameOver.tscn", "res://scenes/screens/EndingScreen.tscn",
	]
	for path in scenes:
		var ps: PackedScene = load(path)
		var ok := ps != null
		var inst: Node = null
		if ok:
			inst = ps.instantiate()
			add_child(inst)
			await _frames(4)
			ok = is_instance_valid(inst) and inst.get_child_count() > 0
		check("boots: " + path.get_file(), ok)
		if is_instance_valid(inst):
			inst.queue_free()
		await _frames(1)
		Audio.stop_all_loops()

func _night_sweep() -> void:
	print("\n--- NIGHT BOOT (each story night + a custom night runs) ---")
	var expect := {1: 1, 2: 2, 3: 3, 4: 4, 5: 5, 6: 6}
	var ns: PackedScene = load("res://scenes/Night.tscn")
	for n in range(1, 7):
		Game.is_custom = false
		Game.active_config = null
		Game.current_night = n
		var night = ns.instantiate()
		add_child(night)
		await _frames(45)
		if not night._running and night.has_method("_begin_night"):
			night._begin_night()
			await _frames(2)
		var run_ok: bool = night._running and not night._ending
		var cnt_ok: bool = night.director != null and night.director.threats.size() == expect[n]
		check("night %d boots and runs" % n, run_ok)
		check("night %d spawns %d threat(s)" % [n, expect[n]], cnt_ok)
		night.queue_free()
		await _frames(2)
		Audio.stop_all_loops()
	# A custom night must also build and run.
	Game.start_custom_night({"ong_ke": 10, "oan_hon": 8})
	var cn = ns.instantiate()
	add_child(cn)
	await _frames(45)
	if not cn._running and cn.has_method("_begin_night"):
		cn._begin_night()
		await _frames(2)
	check("custom night boots and runs", cn._running and not cn._ending)
	check("custom night is flagged custom", Game.is_custom)
	cn.queue_free()
	await _frames(2)
	Audio.stop_all_loops()

func _registries() -> void:
	print("\n--- REGISTRIES ---")
	var ids := ["ong_ke", "ma_da", "co_hon", "quy_nhap_trang", "ma_troi", "oan_hon"]
	var threats_ok := true
	for id in ids:
		if ThreatRegistry.info(id).is_empty():
			threats_ok = false
	check("ThreatRegistry has all 6 threats", threats_ok)
	check("ItemRegistry has >= 14 items", ItemRegistry.all().size() >= 14)
	check("MapGraph has 10 cameras", MapGraph.CAMERAS.size() == 10)
	check("MapGraph mirror is symmetric",
		MapGraph.mirror(MapGraph.LEFT_HALL) == MapGraph.RIGHT_HALL
		and MapGraph.mirror(MapGraph.CANTEEN) == MapGraph.GYM)
	var lore_ok := true
	for n in range(1, 7):
		if Lore.tape_keys(n).is_empty() or Lore.phone_lines(n).is_empty():
			lore_ok = false
	check("Lore has tape + phone lines for nights 1-6", lore_ok)

func _assets() -> void:
	print("\n--- ASSETS ON DISK ---")
	var cams_ok := true
	for c in MapGraph.CAMERAS:
		if not FileAccess.file_exists("res://assets/art/cameras/cam_%s.svg" % c):
			cams_ok = false
	check("all 10 camera feed SVGs exist", cams_ok)
	var crit := [
		"res://assets/art/screens/ending_sieuthoat.svg",
		"res://assets/art/screens/ending_survive.svg",
		"res://assets/art/intro/intro_bg.svg",
		"res://assets/art/ui/vignette.svg",
		"res://assets/art/ui/icon_app.svg",
		"res://assets/audio/jumpscare/jumpscare.wav",
	]
	var crit_ok := true
	for p in crit:
		if not FileAccess.file_exists(p):
			crit_ok = false
			print("    missing: " + p)
	check("critical screen/audio assets exist", crit_ok)

func _localization() -> void:
	print("\n--- LOCALIZATION KEYS RESOLVE ---")
	var keys := [
		"GAME_TITLE", "MENU_NEW_GAME", "HUD_NIGHT", "NIGHT_TITLE_1", "NIGHT_TITLE_6",
		"TAPE_N1_L1", "PHONE_N1_L1", "ENDING_GOOD_L1", "ENDING_SURV_L1", "WIN_SIEU_TITLE",
		"BEST_ONG_KE", "COUNTER_ONG_KE", "SHOP_PROMPT", "MADA_LURE",
	]
	var ok := true
	for k in keys:
		var v := tr(k)
		if v == k or v.strip_edges() == "":
			ok = false
			print("    unresolved: " + k)
	check("sample localization keys resolve", ok)
