class_name MapGraph
## Static description of the school's camera/location graph. Pure data + helpers.

const GATE := "gate"
const LEFT_HALL := "left_hall"
const RIGHT_HALL := "right_hall"
const RESTROOM := "restroom"
const CLASSROOM := "classroom"
const COURTYARD := "courtyard"
const LEFT_DOOR := "left_door"
const RIGHT_DOOR := "right_door"
const OFFICE := "office"

## Camera-viewable locations, in display order.
const CAMERAS := [GATE, LEFT_HALL, RIGHT_HALL, RESTROOM, CLASSROOM, COURTYARD]

const NAME_KEYS := {
	GATE: "CAM1_NAME", LEFT_HALL: "CAM2_NAME", RIGHT_HALL: "CAM3_NAME",
	RESTROOM: "CAM4_NAME", CLASSROOM: "CAM5_NAME", COURTYARD: "CAM6_NAME",
}

## Map-panel button positions (in the 420x340 map_panel.svg local space).
const MAP_POS := {
	GATE: Vector2(210, 61), COURTYARD: Vector2(210, 136), LEFT_HALL: Vector2(105, 135),
	RIGHT_HALL: Vector2(315, 135), CLASSROOM: Vector2(100, 217), RESTROOM: Vector2(320, 217),
}

const ADJ := {
	GATE: [LEFT_HALL, RIGHT_HALL, COURTYARD],
	COURTYARD: [GATE, CLASSROOM, RIGHT_HALL],
	LEFT_HALL: [GATE, CLASSROOM, LEFT_DOOR],
	RIGHT_HALL: [GATE, RESTROOM, RIGHT_DOOR, COURTYARD],
	CLASSROOM: [LEFT_HALL, COURTYARD],
	RESTROOM: [RIGHT_HALL],
	LEFT_DOOR: [LEFT_HALL, OFFICE],
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
