extends Camera3D
## Aims the CCTV at a fixed point in _ready so the corner mount always frames the
## room correctly — avoids hand-authoring a look-at basis in the .tscn.

@export var target := Vector3(0.0, 1.3, 2.0)

func _ready() -> void:
	look_at(target, Vector3.UP)
