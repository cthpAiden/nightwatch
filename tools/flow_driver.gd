extends Node
## Persistent driver (parented to root, survives change_scene) that verifies the
## real end-of-night transitions. Mode via env NW_FLOW = "death" | "win".
##   NW_FLOW=death NW_SKIP_TAPE=1 NW_NIGHT=2 godot --headless --path . res://tools/FlowTest.tscn
##   NW_FLOW=win   NW_SKIP_TAPE=1 NW_FASTWIN=1 godot --headless --path . res://tools/FlowTest.tscn

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ready() -> void:
	await _frames(2)
	var mode := OS.get_environment("NW_FLOW")
	get_tree().change_scene_to_file("res://scenes/Night.tscn")
	await _frames(40)
	var night = get_tree().current_scene
	if night and not night._running and night.has_method("_begin_night"):
		night._begin_night()
		await _frames(2)
	if mode == "death":
		if night:
			night._caught("ong_ke")
		await _frames(1600)   # _caught has a ~1.3s await before Router fires
		_report("res://scenes/screens/GameOver.tscn", "death -> GameOver")
	else:
		await _frames(3200)
		_report("res://scenes/screens/WinScreen.tscn", "win -> WinScreen")

func _report(expect: String, label: String) -> void:
	var cur = get_tree().current_scene
	var path: String = cur.scene_file_path if cur else "<none>"
	var ok := path == expect
	print(("  PASS  " if ok else "  FAIL  ") + label + "   (now: " + path + ")")
	get_tree().quit(0 if ok else 1)
