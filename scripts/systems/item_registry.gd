class_name ItemRegistry
## All shop items (DESIGN.md §5). HARD RULE: sacred Tier-A items are NEVER cursed.
## Curse risk lives only in Tier B (profane/counterfeit). `kind` is hidden in the UI.

# id, name_key, flavor_key, kind, effect_id, duration, magnitude, icon
const TIER_A := [
	["nhang", "ITEM_NHANG", "ITEM_NHANG_F", GameEnums.ItemKind.HELPFUL, "calm_zone", 30.0, 22.0, "btn_offering"],
	["muoi_gao", "ITEM_MUOI_GAO", "ITEM_MUOI_GAO_F", GameEnums.ItemKind.HELPFUL, "salt_line", 30.0, 1.0, "btn_item"],
	["bua_that", "ITEM_BUA_THAT", "ITEM_BUA_THAT_F", GameEnums.ItemKind.HELPFUL, "ward_save", 0.0, 1.0, "btn_item"],
	["nuoc_phep", "ITEM_NUOC_PHEP", "ITEM_NUOC_PHEP_F", GameEnums.ItemKind.HELPFUL, "cleanse", 0.0, 1.0, "via_icon"],
	["vong_dau_tam", "ITEM_VONG", "ITEM_VONG_F", GameEnums.ItemKind.HELPFUL, "child_ward", 999.0, 0.5, "btn_item"],
	["toi", "ITEM_TOI", "ITEM_TOI_F", GameEnums.ItemKind.HELPFUL, "repel_weak", 0.0, 1.0, "btn_item"],
	["banh_chung", "ITEM_BANH_CHUNG", "ITEM_BANH_CHUNG_F", GameEnums.ItemKind.HELPFUL, "ancestor_favor", 0.0, 1.0, "btn_item"],
	["canh_gai", "ITEM_CANH_GAI", "ITEM_CANH_GAI_F", GameEnums.ItemKind.HELPFUL, "barrier", 90.0, 1.0, "btn_item"],
]
const TIER_B := [
	["banh_la", "ITEM_BANH_LA", "ITEM_BANH_LA_F", GameEnums.ItemKind.CURSED, "speed_curse", 60.0, 2.0, "btn_item"],
	["bua_rom", "ITEM_BUA_ROM", "ITEM_BUA_ROM_F", GameEnums.ItemKind.CURSED, "power_drain", 0.0, 28.0, "btn_item"],
	["tien_roi", "ITEM_TIEN_ROI", "ITEM_TIEN_ROI_F", GameEnums.ItemKind.CURSED, "taint", 45.0, 1.0, "btn_item"],
	["chai_la", "ITEM_CHAI_LA", "ITEM_CHAI_LA_F", GameEnums.ItemKind.NEUTRAL, "mimic", 0.0, 0.0, "via_icon"],
]
const TIER_C := [
	["nuoc_mam", "ITEM_NUOC_MAM", "ITEM_NUOC_MAM_F", GameEnums.ItemKind.NEUTRAL, "odor_cloud", 12.0, 1.0, "btn_item"],
	["den_ong_sao", "ITEM_DEN_SAO", "ITEM_DEN_SAO_F", GameEnums.ItemKind.NEUTRAL, "fragile_light", 20.0, 1.0, "btn_light"],
]

static func _make(row: Array) -> ItemDef:
	var d := ItemDef.new()
	d.id = row[0]
	d.name_key = row[1]
	d.flavor_key = row[2]
	d.kind = row[3]
	d.effect_id = row[4]
	d.duration = row[5]
	d.magnitude = row[6]
	d.icon_path = "res://assets/art/ui/%s.svg" % row[7]
	d.cost = _cost(row[0])
	return d

## Vàng mã price per item. Sacred death-savers cost the most; the Tier-B gamble is
## cheap bait. (Currency is earned by surviving hours; see NightController._earn_coins.)
static func _cost(id: String) -> int:
	match id:
		"bua_that", "banh_chung", "canh_gai":
			return 3
		"nhang", "muoi_gao", "nuoc_phep", "vong_dau_tam", "toi":
			return 2
		"nuoc_mam", "den_ong_sao":
			return 1
		_:
			return 1

static func all() -> Array:
	var out: Array = []
	for t in [TIER_A, TIER_B, TIER_C]:
		for row in t:
			out.append(_make(row))
	return out

static func get_def(id: String) -> ItemDef:
	for t in [TIER_A, TIER_B, TIER_C]:
		for row in t:
			if row[0] == id:
				return _make(row)
	return null

## Build a 3-item shop. Real vendor offers only sacred + mundane (never cursed);
## the counterfeit vendor's pool includes the Tier-B gamble.
static func random_shop(rng: RandomNumberGenerator, count: int, counterfeit: bool) -> Array:
	var pool: Array = []
	for row in TIER_A:
		pool.append(row[0])
	for row in TIER_C:
		pool.append(row[0])
	if counterfeit:
		for row in TIER_B:
			pool.append(row[0])
			pool.append(row[0])  # weight the gamble up for the fake vendor
	pool.shuffle()
	var picked: Array = []
	var seen := {}
	for id in pool:
		if seen.has(id):
			continue
		seen[id] = true
		picked.append(get_def(id))
		if picked.size() >= count:
			break
	return picked
