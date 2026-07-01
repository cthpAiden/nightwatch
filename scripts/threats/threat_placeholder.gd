extends Node3D
## Temporary stand-in 3D threat figure until real art lands: a shrouded humanoid blockout
## tinted by `tint` and faintly self-lit so it reads on the dark camera feeds. Its origin
## sits at mid-height (~0.85 above the feet) to match the real GLB threats (ong_ke/ma_da),
## so CameraSystem and GuardRoom place, scale and face it exactly the same way.

@export var tint := Color(0.8, 0.8, 0.82)

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.85
	mat.emission_enabled = true          # a little self-lit so it doesn't vanish in the dark
	mat.emission = tint
	mat.emission_energy_multiplier = 0.35
	# Shroud/robe: a tapered column from the feet up to the shoulders.
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.16
	bm.bottom_radius = 0.34
	bm.height = 1.5
	bm.material = mat
	body.mesh = bm
	body.position = Vector3(0, -0.1, 0)   # spans ~-0.85 (feet) .. 0.65 (shoulders)
	add_child(body)
	# Head.
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.30
	hm.material = mat
	head.mesh = hm
	head.position = Vector3(0, 0.74, 0)
	add_child(head)
