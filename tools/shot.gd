extends Node
## Dev-only screenshot harness. Loads a scene, waits, saves a PNG, quits.
## Run: godot --path . res://tools/Shot.tscn  (with NW_SHOT_SCENE / NW_SHOT_OUT env)

func _ready() -> void:
	var scene_path := OS.get_environment("NW_SHOT_SCENE")
	var out_path := OS.get_environment("NW_SHOT_OUT")
	if scene_path == "" or out_path == "":
		get_tree().quit()
		return
	var inst = load(scene_path).instantiate()
	get_tree().root.add_child.call_deferred(inst)
	await get_tree().create_timer(1.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_path)
	await get_tree().process_frame
	get_tree().quit()
