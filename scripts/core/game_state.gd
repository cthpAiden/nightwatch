extends Node
## Persistent run/session state (autoload "Game"). Decides what night to play and
## hands a NightConfig to the Night scene. Night-specific runtime state lives in
## NightController, not here.

const MAX_NIGHTS := 6
const CUSTOM_NIGHT_INDEX := 7

var current_night: int = 1
var is_custom: bool = false
var custom_levels: Dictionary = {}
var difficulty: int = GameEnums.Difficulty.NORMAL
var last_cause: String = ""
var rng := RandomNumberGenerator.new()
var active_config: NightConfig

## Story table — mirrors DESIGN.md §7. Threats are introduced one at a time so each
## distinct mechanic is learned before stacking. IDs match scripts/threats + data.
## Tuned for "approachable, then ramps hard". Difficulty scales these at runtime.
## "spd" = real seconds per in-game hour (×6 hours = night length). Tuned a bit
## quicker than before so a night moves at a livelier pace.
const STORY := {
	1: {"levels": {"ong_ke": 2}, "vendor": false, "spd": 68.0},
	2: {"levels": {"ong_ke": 3, "ma_da": 2}, "vendor": true, "spd": 66.0},
	3: {"levels": {"ong_ke": 4, "ma_da": 3, "co_hon": 3}, "vendor": true, "spd": 64.0},
	4: {"levels": {"ong_ke": 5, "ma_da": 4, "co_hon": 4, "quy_nhap_trang": 3}, "vendor": true, "spd": 62.0},
	5: {"levels": {"ong_ke": 6, "ma_da": 5, "co_hon": 5, "quy_nhap_trang": 4, "ma_troi": 4}, "vendor": true, "spd": 60.0},
	6: {"levels": {"ong_ke": 7, "ma_da": 6, "co_hon": 6, "quy_nhap_trang": 6, "ma_troi": 6, "oan_hon": 8}, "vendor": true, "spd": 58.0},
}

func _ready() -> void:
	rng.randomize()
	difficulty = Settings.difficulty

func start_story_night(n: int) -> void:
	current_night = clampi(n, 1, MAX_NIGHTS)
	is_custom = false
	difficulty = Settings.difficulty
	active_config = get_night_config(current_night)
	last_cause = ""
	Router.to_night()

func start_custom_night(levels: Dictionary) -> void:
	is_custom = true
	custom_levels = levels.duplicate(true)
	current_night = CUSTOM_NIGHT_INDEX
	difficulty = GameEnums.Difficulty.NIGHTMARE
	active_config = _build_config(CUSTOM_NIGHT_INDEX, levels, true, 75.0)
	last_cause = ""
	Router.to_night()

func get_night_config(n: int) -> NightConfig:
	var path := "res://data/nights/night_%d.tres" % n
	if ResourceLoader.exists(path):
		return load(path)
	var entry: Dictionary = STORY.get(n, STORY[1])
	return _build_config(n, entry["levels"], entry["vendor"], entry.get("spd", 90.0))

func _build_config(n: int, levels: Dictionary, vendor: bool, spd: float) -> NightConfig:
	var cfg := NightConfig.new()
	cfg.night_index = n
	cfg.seconds_per_hour = spd
	cfg.vendor_enabled = vendor
	# Offerings scale with how many appeasement threats are active tonight, so the
	# cô hồn / oan hồn / ma da economy is sustainable (not a one-shot).
	var meter := 0
	for mid in ["co_hon", "ma_da", "oan_hon"]:
		if levels.has(mid):
			meter += 1
	cfg.offerings_start = 0 if meter == 0 else meter + 2
	cfg.has_tape = not is_custom
	# Apply difficulty scaling to AI levels and pacing.
	var lvl_scale := _difficulty_level_scale()
	var scaled := {}
	for id in levels:
		scaled[id] = clampi(int(round(float(levels[id]) * lvl_scale)), 0, 20)
	cfg.threat_levels = scaled
	cfg.seconds_per_hour = spd * _difficulty_speed_scale()
	cfg.ai_ramp = 2.0 + float(n) * 0.3
	return cfg

func _difficulty_level_scale() -> float:
	match difficulty:
		GameEnums.Difficulty.EASY: return 0.7
		GameEnums.Difficulty.HARD: return 1.25
		GameEnums.Difficulty.NIGHTMARE: return 1.6
		_: return 1.0

func _difficulty_speed_scale() -> float:
	# Easy nights last a touch longer (more real time per hour) but threats are slower;
	# nightmare nights are quicker and tenser.
	match difficulty:
		GameEnums.Difficulty.EASY: return 1.1
		GameEnums.Difficulty.HARD: return 0.92
		GameEnums.Difficulty.NIGHTMARE: return 0.85
		_: return 1.0

func notify_night_survived() -> void:
	Save.mark_night_cleared(current_night)
	if is_custom:
		Save.custom_night_beaten = true
		Save.save_progress()
	elif current_night < MAX_NIGHTS:
		Save.unlock_night(current_night + 1)

func has_next_night() -> bool:
	return not is_custom and current_night < MAX_NIGHTS

func go_next_night() -> void:
	if has_next_night():
		start_story_night(current_night + 1)
	else:
		Router.to_main_menu()
