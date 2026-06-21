class_name ItemDef
extends Resource
## A shop item. Whether it is HELPFUL or CURSED is hidden from the player —
## they learn through play. effect_id is dispatched by ItemSystem.

@export var id: String = ""
@export var name_key: String = ""
@export var flavor_key: String = ""
@export var kind: int = GameEnums.ItemKind.HELPFUL
@export var effect_id: String = ""
@export var duration: float = 0.0
@export var magnitude: float = 1.0
@export var icon_path: String = ""
