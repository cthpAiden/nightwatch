extends Camera3D
## Aims the CCTV at a fixed point in _ready so the corner mount always frames the
## room correctly — avoids hand-authoring a look-at basis in the .tscn.

@export var target := Vector3(0.0, 1.3, 2.0)
## Optional floor point where a roaming threat's 3D figure stands on this feed. Left unset
## (INF) → CameraSystem falls back to the camera's aim point. Set it to keep the figure on
## open floor when the camera happens to aim through props (e.g. behind the restroom stalls).
@export var figure_spot := Vector3(INF, INF, INF)

func _ready() -> void:
	look_at(target, Vector3.UP)
