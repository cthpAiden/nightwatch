class_name Lore
## The previous guard (bác Tư) cassette tapes — one per night. Each entry is a list
## of string keys (see localization/strings.csv). Tutorial + lore + slow-burn arc.

const TAPES := {
	1: ["TAPE_N1_L1", "TAPE_N1_L2", "TAPE_N1_L3"],
	2: ["TAPE_N2_L1", "TAPE_N2_L2", "TAPE_N2_L3"],
	3: ["TAPE_N3_L1", "TAPE_N3_L2", "TAPE_N3_L3"],
	4: ["TAPE_N4_L1", "TAPE_N4_L2", "TAPE_N4_L3"],
	5: ["TAPE_N5_L1", "TAPE_N5_L2", "TAPE_N5_L3"],
	6: ["TAPE_N6_L1", "TAPE_N6_L2", "TAPE_N6_L3"],
}

static func tape_keys(night: int) -> Array:
	return TAPES.get(night, [])

## Live phone calls from bác Tư during a night — short hints + slow-burn story,
## delivered one per pick-up (see PhoneSystem). Keys live in localization/strings.csv.
const PHONE := {
	1: ["PHONE_N1_L1", "PHONE_N1_L2", "PHONE_N1_L3"],
	2: ["PHONE_N2_L1", "PHONE_N2_L2", "PHONE_N2_L3"],
	3: ["PHONE_N3_L1", "PHONE_N3_L2", "PHONE_N3_L3"],
	4: ["PHONE_N4_L1", "PHONE_N4_L2", "PHONE_N4_L3"],
	5: ["PHONE_N5_L1", "PHONE_N5_L2", "PHONE_N5_L3"],
	6: ["PHONE_N6_L1", "PHONE_N6_L2", "PHONE_N6_L3"],
}

static func phone_lines(night: int) -> Array:
	return PHONE.get(night, PHONE.get(1, []))
