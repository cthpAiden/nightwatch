class_name NightConfig
extends Resource
## Configuration for one night. Authored as a .tres in data/nights/, or built
## procedurally by Game from its default table when no .tres exists.

@export var night_index: int = 1
@export var title_key: String = "NIGHT_LABEL"

## threat_id -> starting AI level (0..20, FNAF-style). Missing/0 = inactive tonight.
@export var threat_levels: Dictionary = {}
## How much each active threat's AI level climbs from 00:00 to 06:00 (linear).
@export var ai_ramp: float = 2.0

## Pacing: real seconds per in-game hour. 6 hours total (00:00 -> 06:00).
@export var seconds_per_hour: float = 90.0

## Power economy (percent per second). Idle is low enough to survive a full night
## doing nothing; doors/lights/cameras are the real cost (FNAF-style tension).
## Tuned so a careful camera/door user comfortably clears the night, while
## camping the cameras or holding doors all night still drains you out.
@export var power_drain_idle: float = 0.05
@export var power_drain_per_door: float = 1.1
@export var power_drain_camera: float = 0.12
@export var power_drain_per_light: float = 0.55

## Via (spirit/sanity) economy.
@export var via_enabled: bool = true
@export var via_max: float = 100.0

## Vendor (bà hàng rong).
@export var vendor_enabled: bool = false
@export var vendor_min_interval: float = 120.0
@export var vendor_max_interval: float = 190.0

@export var offerings_start: int = 0
@export var has_tape: bool = true

func active_threats() -> Array:
	var out: Array = []
	for id in threat_levels:
		if int(threat_levels[id]) > 0:
			out.append(id)
	return out
