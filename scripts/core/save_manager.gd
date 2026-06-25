extends Node
## Persistent progress (autoload "Save"): unlocked nights, clears, bestiary, tapes, stats.
## Stored in user://progress.cfg. Pure data — no gameplay logic here.
##
## Writes are atomic (.tmp + rename, keeping a .bak) and a corrupt file is preserved
## rather than overwritten, so a partial write or bad file can never silently wipe a
## player's whole campaign. A save_version field guards future schema migrations.

const PATH := "user://progress.cfg"
const SAVE_VERSION := 1
## The three Oan hồn investigation clues. Gather all three before clearing Night 6
## to unlock the "siêu thoát" good ending.
const CLUE_IDS := ["clue_name", "clue_drawing", "clue_photo"]

var highest_unlocked: int = 1                 # nights 1..N
var nights_cleared: Dictionary = {}           # night(int) -> true
var bestiary_seen: Dictionary = {}            # threat_id(String) -> true
var tapes_unlocked: Dictionary = {}           # night(int) -> true
var custom_night_beaten: bool = false
var coins: int = 0                            # vàng mã: shop + shrine-upgrade currency
var upgrades: Dictionary = {}                 # upgrade_id(String) -> true (purchased)
var clues: Dictionary = {}                    # clue_id(String) -> true (Oan hồn investigation)
var endings_seen: Dictionary = {}             # ending_id(String) -> true
var night_best_coins: Dictionary = {}         # night key -> best gross coins earned (anti-farm)
var stats: Dictionary = {
	"deaths": 0,
	"deaths_by": {},                          # threat_id -> count
	"nights_won": 0,
	"power_outages": 0,
	"offerings_made": 0,
}

func _ready() -> void:
	load_progress()

func load_progress() -> void:
	var cfg := ConfigFile.new()
	var recovered := false
	var err := cfg.load(PATH)
	if err != OK:
		# Try a backup from the last good atomic write before giving up.
		var bak := PATH + ".bak"
		if FileAccess.file_exists(bak) and cfg.load(bak) == OK:
			recovered = true   # recovered from backup; rewrite a healthy cfg below
		elif FileAccess.file_exists(PATH):
			# The file exists but is unreadable/corrupt. Copy it aside to a non-rotating
			# name (a later save rotates .bak, so that alone wouldn't preserve it), then
			# run on in-memory defaults so the bad file can still be inspected/recovered.
			var da := DirAccess.open("user://")
			if da and not da.file_exists(PATH.get_file() + ".corrupt"):
				da.copy(PATH, PATH + ".corrupt")
			push_warning("progress.cfg is corrupt; copied to progress.cfg.corrupt, running on defaults.")
			tapes_unlocked[1] = true
			return
		else:
			# Genuine first run: seed defaults and write them.
			tapes_unlocked[1] = true
			save_progress()
			return
	var ver := int(cfg.get_value("meta", "version", 0))
	highest_unlocked = cfg.get_value("progress", "highest_unlocked", 1)
	nights_cleared = cfg.get_value("progress", "nights_cleared", {})
	bestiary_seen = cfg.get_value("progress", "bestiary_seen", {})
	tapes_unlocked = cfg.get_value("progress", "tapes_unlocked", {1: true})
	custom_night_beaten = cfg.get_value("progress", "custom_night_beaten", false)
	coins = cfg.get_value("progress", "coins", 0)
	upgrades = cfg.get_value("progress", "upgrades", {})
	clues = cfg.get_value("progress", "clues", {})
	endings_seen = cfg.get_value("progress", "endings_seen", {})
	night_best_coins = cfg.get_value("progress", "night_best_coins", {})
	stats = cfg.get_value("stats", "data", stats)
	_migrate(ver)
	# Recovered from .bak: immediately rewrite a healthy progress.cfg, otherwise the next
	# routine save would rotate the still-corrupt cfg over our only good backup. But never
	# re-persist a backup from a NEWER build — that would downgrade it (the forward-version
	# guard in _migrate already refused to touch it).
	if recovered and ver <= SAVE_VERSION:
		save_progress()

## Forward-migration hook. Bump SAVE_VERSION and add a branch per schema change.
func _migrate(from_version: int) -> void:
	if from_version > SAVE_VERSION:
		# Save came from a newer build; don't run old migrations or rewrite it and risk
		# downgrading fields this build doesn't understand.
		push_warning("progress.cfg is from a newer version (%d > %d); not overwriting." % [from_version, SAVE_VERSION])
		return
	if from_version < SAVE_VERSION:
		# v0 (pre-versioning) -> v1: new fields default to empty; nothing to convert.
		save_progress()

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	cfg.set_value("progress", "highest_unlocked", highest_unlocked)
	cfg.set_value("progress", "nights_cleared", nights_cleared)
	cfg.set_value("progress", "bestiary_seen", bestiary_seen)
	cfg.set_value("progress", "tapes_unlocked", tapes_unlocked)
	cfg.set_value("progress", "custom_night_beaten", custom_night_beaten)
	cfg.set_value("progress", "coins", coins)
	cfg.set_value("progress", "upgrades", upgrades)
	cfg.set_value("progress", "clues", clues)
	cfg.set_value("progress", "endings_seen", endings_seen)
	cfg.set_value("progress", "night_best_coins", night_best_coins)
	cfg.set_value("stats", "data", stats)
	_atomic_write(cfg)

## Write to a temp file, then swap it into place keeping a .bak of the last good
## file. A crash mid-write leaves either the old file, the .bak, or the .tmp intact —
## never a half-written progress.cfg.
func _atomic_write(cfg: ConfigFile) -> void:
	var tmp := PATH + ".tmp"
	if cfg.save(tmp) != OK:
		cfg.save(PATH)   # best effort if the temp write itself failed
		return
	var da := DirAccess.open("user://")
	if da == null:
		cfg.save(PATH)
		return
	var base := PATH.get_file()         # progress.cfg
	var tmpf := tmp.get_file()          # progress.cfg.tmp
	var bakf := base + ".bak"
	if da.file_exists(base):
		if da.file_exists(bakf):
			da.remove(bakf)
		da.rename(base, bakf)
	da.rename(tmpf, base)

func is_night_unlocked(n: int) -> bool:
	return n <= highest_unlocked

func unlock_night(n: int) -> void:
	if n > highest_unlocked:
		highest_unlocked = n
	tapes_unlocked[n] = true
	save_progress()

func mark_night_cleared(n: int) -> void:
	# Only count the win the first time this night is cleared; replays of an
	# already-cleared night must not inflate nights_won.
	var first := not nights_cleared.has(n)
	nights_cleared[n] = true
	if first:
		stats["nights_won"] = int(stats.get("nights_won", 0)) + 1
	save_progress()

func see_threat(threat_id: String) -> void:
	if not bestiary_seen.has(threat_id):
		bestiary_seen[threat_id] = true
		save_progress()

# --- Oan hồn investigation --------------------------------------------------
func find_clue(clue_id: String) -> bool:
	if clues.has(clue_id):
		return false
	clues[clue_id] = true
	save_progress()
	return true

func has_clue(clue_id: String) -> bool:
	return clues.get(clue_id, false)

func clue_count() -> int:
	var n := 0
	for c in CLUE_IDS:
		if clues.get(c, false):
			n += 1
	return n

func investigation_complete() -> bool:
	for c in CLUE_IDS:
		if not clues.get(c, false):
			return false
	return true

func mark_ending_seen(ending_id: String) -> void:
	if not endings_seen.has(ending_id):
		endings_seen[ending_id] = true
		save_progress()

func has_ending(ending_id: String) -> bool:
	return endings_seen.get(ending_id, false)

func record_death(cause_id: String) -> void:
	stats["deaths"] = int(stats.get("deaths", 0)) + 1
	var by: Dictionary = stats.get("deaths_by", {})
	by[cause_id] = int(by.get(cause_id, 0)) + 1
	stats["deaths_by"] = by
	save_progress()

func record_power_outage() -> void:
	stats["power_outages"] = int(stats.get("power_outages", 0)) + 1
	save_progress()

func record_offering() -> void:
	stats["offerings_made"] = int(stats.get("offerings_made", 0)) + 1
	save_progress()

func has_upgrade(id: String) -> bool:
	return upgrades.get(id, false)

## Buy a shrine upgrade if affordable and not already owned. Returns true on success.
func purchase_upgrade(id: String, cost: int) -> bool:
	if has_upgrade(id) or coins < cost:
		return false
	coins -= cost
	upgrades[id] = true
	save_progress()
	return true

func reset_all() -> void:
	highest_unlocked = 1
	nights_cleared = {}
	bestiary_seen = {}
	tapes_unlocked = {1: true}
	custom_night_beaten = false
	coins = 0
	upgrades = {}
	clues = {}
	endings_seen = {}
	night_best_coins = {}
	stats = {"deaths": 0, "deaths_by": {}, "nights_won": 0, "power_outages": 0, "offerings_made": 0}
	save_progress()
