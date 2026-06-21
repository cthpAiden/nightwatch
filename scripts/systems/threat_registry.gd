class_name ThreatRegistry
## Static metadata for every threat. The director instantiates `script` and applies
## these textures/identity. Bestiary (Hồ Sơ Ma) reads name/desc/tag keys.

const DATA := {
	"ong_ke": {
		"name_key": "THREAT_ONG_KE", "desc_key": "BEST_ONG_KE", "tag_key": "TAG_FOLK_THIN",
		"fear": 3, "accent": Color(0.55, 0.5, 0.62),
		"script": "res://scripts/threats/ong_ke.gd",
		"idle": "res://assets/art/threats/ong_ke_idle.svg",
		"active": "res://assets/art/threats/ong_ke_active.svg",
		"scare": "res://assets/art/jumpscare/ong_ke_scare.svg",
	},
	"ma_da": {
		"name_key": "THREAT_MA_DA", "desc_key": "BEST_MA_DA", "tag_key": "TAG_DOCUMENTED",
		"fear": 5, "accent": Color(0.43, 0.6, 0.65),
		"script": "res://scripts/threats/ma_da.gd",
		"idle": "res://assets/art/threats/ma_da_idle.svg",
		"active": "res://assets/art/threats/ma_da_active.svg",
		"scare": "res://assets/art/jumpscare/ma_da_scare.svg",
	},
	"co_hon": {
		"name_key": "THREAT_CO_HON", "desc_key": "BEST_CO_HON", "tag_key": "TAG_DOCUMENTED",
		"fear": 2, "accent": Color(0.7, 0.66, 0.5),
		"script": "res://scripts/threats/co_hon.gd",
		"idle": "res://assets/art/threats/co_hon_idle.svg",
		"active": "res://assets/art/threats/co_hon_crowd.svg",
		"scare": "",
	},
	"quy_nhap_trang": {
		"name_key": "THREAT_QUY", "desc_key": "BEST_QUY", "tag_key": "TAG_DOCUMENTED",
		"fear": 4, "accent": Color(0.75, 0.75, 0.7),
		"script": "res://scripts/threats/quy_nhap_trang.gd",
		"idle": "res://assets/art/threats/quy_nhap_trang_idle.svg",
		"active": "res://assets/art/threats/quy_nhap_trang_active.svg",
		"scare": "res://assets/art/jumpscare/quy_nhap_trang_scare.svg",
	},
	"ma_troi": {
		"name_key": "THREAT_MA_TROI", "desc_key": "BEST_MA_TROI", "tag_key": "TAG_SHARED",
		"fear": 3, "accent": Color(0.43, 0.7, 0.7),
		"script": "res://scripts/threats/ma_troi.gd",
		"idle": "res://assets/art/threats/ma_troi_idle.svg",
		"active": "res://assets/art/threats/ma_troi_active.svg",
		"scare": "",
	},
	"oan_hon": {
		"name_key": "THREAT_OAN_HON", "desc_key": "BEST_OAN_HON", "tag_key": "TAG_DOCUMENTED",
		"fear": 5, "accent": Color(0.85, 0.86, 0.88),
		"script": "res://scripts/threats/oan_hon.gd",
		"idle": "res://assets/art/threats/oan_hon_idle.svg",
		"active": "res://assets/art/threats/oan_hon_active.svg",
		"scare": "res://assets/art/jumpscare/oan_hon_scare.svg",
	},
	# The counterfeit impostor (never the real grandmother). No script: handled by
	# vendor.gd, not the director. Listed here only for its scare image + bestiary.
	"ba_hang_rong": {
		"name_key": "THREAT_BA_GIA", "desc_key": "BEST_BA_GIA", "tag_key": "TAG_URBAN",
		"fear": 4, "accent": Color(0.8, 0.5, 0.3),
		"script": "",
		"idle": "res://assets/art/threats/vendor_idle.svg",
		"active": "res://assets/art/threats/vendor_hostile.svg",
		"scare": "res://assets/art/threats/vendor_hostile.svg",
	},
}

static func info(id: String) -> Dictionary:
	return DATA.get(id, {})

static func ids() -> Array:
	return DATA.keys()

static func name_key(id: String) -> String:
	return DATA.get(id, {}).get("name_key", id)

static func load_tex(id: String, which: String) -> Texture2D:
	var path: String = DATA.get(id, {}).get(which, "")
	if path != "" and ResourceLoader.exists(path):
		return load(path)
	return null
