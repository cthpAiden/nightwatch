extends Node
## Persistent progress (autoload "Save"): unlocked nights, clears, bestiary, tapes, stats.
## Stored in user://progress.cfg. Pure data — no gameplay logic here.

const PATH := "user://progress.cfg"

var highest_unlocked: int = 1                 # nights 1..N
var nights_cleared: Dictionary = {}           # night(int) -> true
var bestiary_seen: Dictionary = {}            # threat_id(String) -> true
var tapes_unlocked: Dictionary = {}           # night(int) -> true
var custom_night_beaten: bool = false
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
	if cfg.load(PATH) != OK:
		# First tape is always available so the player gets the intro briefing.
		tapes_unlocked[1] = true
		save_progress()
		return
	highest_unlocked = cfg.get_value("progress", "highest_unlocked", 1)
	nights_cleared = cfg.get_value("progress", "nights_cleared", {})
	bestiary_seen = cfg.get_value("progress", "bestiary_seen", {})
	tapes_unlocked = cfg.get_value("progress", "tapes_unlocked", {1: true})
	custom_night_beaten = cfg.get_value("progress", "custom_night_beaten", false)
	stats = cfg.get_value("stats", "data", stats)

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "highest_unlocked", highest_unlocked)
	cfg.set_value("progress", "nights_cleared", nights_cleared)
	cfg.set_value("progress", "bestiary_seen", bestiary_seen)
	cfg.set_value("progress", "tapes_unlocked", tapes_unlocked)
	cfg.set_value("progress", "custom_night_beaten", custom_night_beaten)
	cfg.set_value("stats", "data", stats)
	cfg.save(PATH)

func is_night_unlocked(n: int) -> bool:
	return n <= highest_unlocked

func unlock_night(n: int) -> void:
	if n > highest_unlocked:
		highest_unlocked = n
	tapes_unlocked[n] = true
	save_progress()

func mark_night_cleared(n: int) -> void:
	nights_cleared[n] = true
	stats["nights_won"] = int(stats.get("nights_won", 0)) + 1
	save_progress()

func see_threat(threat_id: String) -> void:
	if not bestiary_seen.has(threat_id):
		bestiary_seen[threat_id] = true
		save_progress()

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

func reset_all() -> void:
	highest_unlocked = 1
	nights_cleared = {}
	bestiary_seen = {}
	tapes_unlocked = {1: true}
	custom_night_beaten = false
	stats = {"deaths": 0, "deaths_by": {}, "nights_won": 0, "power_outages": 0, "offerings_made": 0}
	save_progress()
