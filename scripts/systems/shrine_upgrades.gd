class_name ShrineUpgrades
## Static catalog of permanent shrine upgrades bought with vàng mã (coins) between
## nights. NightController reads Save.upgrades at the start of each night and applies
## the matching effect (see _apply_shrine_upgrades). One-time purchases.

const CATALOG := [
	{"id": "more_offerings", "name": "UPG_MORE_OFFERINGS_NAME", "desc": "UPG_MORE_OFFERINGS_DESC", "cost": 18},
	{"id": "fast_bell", "name": "UPG_FAST_BELL_NAME", "desc": "UPG_FAST_BELL_DESC", "cost": 16},
	{"id": "incense_slow", "name": "UPG_INCENSE_SLOW_NAME", "desc": "UPG_INCENSE_SLOW_DESC", "cost": 20},
	{"id": "sturdy_doors", "name": "UPG_STURDY_DOORS_NAME", "desc": "UPG_STURDY_DOORS_DESC", "cost": 22},
	{"id": "auto_relight", "name": "UPG_AUTO_RELIGHT_NAME", "desc": "UPG_AUTO_RELIGHT_DESC", "cost": 30},
	{"id": "bright_altar", "name": "UPG_BRIGHT_ALTAR_NAME", "desc": "UPG_BRIGHT_ALTAR_DESC", "cost": 22},
	{"id": "extra_ward", "name": "UPG_EXTRA_WARD_NAME", "desc": "UPG_EXTRA_WARD_DESC", "cost": 26},
]
