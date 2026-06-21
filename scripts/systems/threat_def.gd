class_name ThreatDef
extends Resource
## Static identity of a threat. The actual AI lives in the threat's scene/script.

@export var id: String = ""
@export var name_key: String = ""
@export var bestiary_key: String = ""
@export var scene: PackedScene
@export var spawn_location: String = ""
@export var fear_factor: int = 3
@export var accent_color: Color = Color(0.8, 0.2, 0.2)
