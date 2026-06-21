class_name GameEnums
## Shared enums used across the whole game. Registered globally via class_name,
## so any script can reference e.g. GameEnums.Side.LEFT without an autoload.

enum Side { LEFT, RIGHT }

## Spirit / sanity state derived from the "via" meter.
enum ViaState { NORMAL, SHAKEN, CRITICAL }

## Bà bán hàng rong dual-state lifecycle.
enum VendorState { IDLE, SHOP, HOSTILE, LEAVING }

enum Difficulty { EASY, NORMAL, HARD, NIGHTMARE }

## Whether an item helps or curses the player (hidden from them).
enum ItemKind { HELPFUL, CURSED, NEUTRAL }

## Generic lifecycle a threat moves through during a night.
enum ThreatPhase { DORMANT, ACTIVE, APPROACHING, AT_DOOR, ATTACKING, REPELLED }

const SIDE_ID := { Side.LEFT: "left", Side.RIGHT: "right" }

static func side_to_string(side: int) -> String:
	return SIDE_ID.get(side, "left")
