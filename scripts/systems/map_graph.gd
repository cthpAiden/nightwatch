class_name MapGraph
## Static description of the school's camera/location graph. Pure data + helpers.
##
## Layout (symmetric two wings converging on the office, FNAF-style approach):
##
##                         GATE (cam)
##                    /       |        \
##              CANTEEN   COURTYARD    GYM
##                 |      /       \     |
##            CLASSROOM             RESTROOM
##                 |                    |
##             LIBRARY              INFIRMARY
##                 |                    |
##            LEFT_HALL              RIGHT_HALL
##                 |                    |
##            LEFT_DOOR             RIGHT_DOOR
##                    \             /
##                        OFFICE (you)
##
## A path threat steps node-by-node down a wing; it is only "at the door" once it
## reaches LEFT_DOOR / RIGHT_DOOR (the squares adjacent to the office).

const GATE := "gate"
const COURTYARD := "courtyard"
# Left wing
const CANTEEN := "canteen"
const CLASSROOM := "classroom"
const LIBRARY := "library"
const LEFT_HALL := "left_hall"
# Right wing
const GYM := "gym"
const RESTROOM := "restroom"
const INFIRMARY := "infirmary"
const RIGHT_HALL := "right_hall"
# Office approaches (not cameras)
const LEFT_DOOR := "left_door"
const RIGHT_DOOR := "right_door"
const OFFICE := "office"

## Camera-viewable locations, in display order (index+1 == CAM number).
const CAMERAS := [
	GATE, COURTYARD,
	CANTEEN, CLASSROOM, LIBRARY, LEFT_HALL,
	GYM, RESTROOM, INFIRMARY, RIGHT_HALL,
]

const NAME_KEYS := {
	GATE: "CAM1_NAME", COURTYARD: "CAM2_NAME",
	CANTEEN: "CAM3_NAME", CLASSROOM: "CAM4_NAME", LIBRARY: "CAM5_NAME", LEFT_HALL: "CAM6_NAME",
	GYM: "CAM7_NAME", RESTROOM: "CAM8_NAME", INFIRMARY: "CAM9_NAME", RIGHT_HALL: "CAM10_NAME",
}

## Map-panel button positions (in the 420x340 map_panel.svg local space).
const MAP_POS := {
	GATE: Vector2(210, 50), COURTYARD: Vector2(210, 152),
	CANTEEN: Vector2(120, 96), CLASSROOM: Vector2(72, 158), LIBRARY: Vector2(96, 224), LEFT_HALL: Vector2(150, 284),
	GYM: Vector2(300, 96), RESTROOM: Vector2(348, 158), INFIRMARY: Vector2(324, 224), RIGHT_HALL: Vector2(270, 284),
}

const ADJ := {
	GATE: [CANTEEN, GYM, COURTYARD],
	COURTYARD: [GATE, CLASSROOM, RESTROOM],
	# left wing
	CANTEEN: [GATE, CLASSROOM],
	CLASSROOM: [CANTEEN, LIBRARY, COURTYARD],
	LIBRARY: [CLASSROOM, LEFT_HALL],
	LEFT_HALL: [LIBRARY, LEFT_DOOR],
	LEFT_DOOR: [LEFT_HALL, OFFICE],
	# right wing
	GYM: [GATE, RESTROOM],
	RESTROOM: [GYM, INFIRMARY, COURTYARD],
	INFIRMARY: [RESTROOM, RIGHT_HALL],
	RIGHT_HALL: [INFIRMARY, RIGHT_DOOR],
	RIGHT_DOOR: [RIGHT_HALL, OFFICE],
	OFFICE: [],
}

static func neighbors(loc: String) -> Array:
	return ADJ.get(loc, [])

static func is_camera(loc: String) -> bool:
	return CAMERAS.has(loc)

static func door_side(loc: String) -> int:
	if loc == LEFT_DOOR:
		return GameEnums.Side.LEFT
	if loc == RIGHT_DOOR:
		return GameEnums.Side.RIGHT
	return -1

static func side_door(side: int) -> String:
	return LEFT_DOOR if side == GameEnums.Side.LEFT else RIGHT_DOOR

## Left/right mirror so a PATH threat can approach from either wing on the symmetric
## map. Locations with no mirror (gate, courtyard, office) map to themselves.
const MIRROR := {
	CANTEEN: GYM, GYM: CANTEEN,
	CLASSROOM: RESTROOM, RESTROOM: CLASSROOM,
	LIBRARY: INFIRMARY, INFIRMARY: LIBRARY,
	LEFT_HALL: RIGHT_HALL, RIGHT_HALL: LEFT_HALL,
	LEFT_DOOR: RIGHT_DOOR, RIGHT_DOOR: LEFT_DOOR,
}

static func mirror(loc: String) -> String:
	return MIRROR.get(loc, loc)

static func name_key(loc: String) -> String:
	return NAME_KEYS.get(loc, "")

## Breadth-first graph distance, used by "reset the nearest threat" item.
static func distance(from: String, to: String) -> int:
	if from == to:
		return 0
	var visited := {from: true}
	var queue := [[from, 0]]
	while not queue.is_empty():
		var cur: Array = queue.pop_front()
		for nb in neighbors(cur[0]):
			if nb == to:
				return cur[1] + 1
			if not visited.has(nb):
				visited[nb] = true
				queue.append([nb, cur[1] + 1])
	return 9999
