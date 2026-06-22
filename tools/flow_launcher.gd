extends Node
## Spawns the persistent flow_driver under the root (so it survives the scene
## changes it triggers), then this launcher scene is replaced harmlessly.

func _ready() -> void:
	var drv := Node.new()
	drv.set_script(load("res://tools/flow_driver.gd"))
	get_tree().root.add_child.call_deferred(drv)
