extends CanvasLayer
## Toggleable performance readout (F3). Hidden by default; never shown unless the
## player asks for it, so it costs nothing in normal play. Reads engine Performance
## monitors so the graphics/FPS work can be verified against real numbers instead of
## guesswork. Lives on its own high layer so it draws above the HUD, monitor and
## even the jumpscare.

const TOGGLE_KEY := KEY_F3

var _label: Label
var _accum := 0.0        # throttles the text rebuild to ~5 Hz (the numbers are noisy per-frame)

func _ready() -> void:
	layer = 100
	_label = UI.text_label("", 16, Color(0.6, 1.0, 0.6))
	UI.place(_label, 0.0, 0.0, 0.0, 0.0, 10.0, 8.0, 360.0, 200.0)
	# A faint dark plate behind the text so it stays legible over bright feeds.
	var plate := UI.color_rect(Color(0, 0, 0, 0.45))
	UI.place(plate, 0.0, 0.0, 0.0, 0.0, 4.0, 4.0, 250.0, 128.0)
	add_child(plate)
	add_child(_label)
	visible = false

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		visible = not visible

func _process(delta: float) -> void:
	if not visible:
		return
	_accum += delta
	if _accum < 0.2:
		return
	_accum = 0.0
	var fps := Engine.get_frames_per_second()
	var proc_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var objs := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var q: String = ["Low", "Medium", "High"][Settings.graphics_quality] if "graphics_quality" in Settings else "?"
	_label.text = "FPS %d  (%.1f ms cpu / %.1f ms phys)\nDraws %d   Prims %d\nVRAM %.0f MB   Nodes %d\nPreset: %s" % [
		fps, proc_ms, phys_ms, draws, prims, vram, objs, q]
