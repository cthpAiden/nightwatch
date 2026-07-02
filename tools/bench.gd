extends Node
## FPS benchmark harness (real renderer, NOT headless — needs a GPU to be meaningful).
## Loads a live night, forces a graphics preset, uncaps the framerate + vsync so the
## number reflects the GPU ceiling (not the 144 cap), samples average frame time over a
## fixed window, prints one BENCH line and quits. Run per preset to compare before/after:
##   NW_BENCH_Q=0 <godot> --path . res://tools/Bench.tscn   (0=Low 1=Medium 2=High)
## Optional NW_BENCH_CAM=1 raises the camera monitor (measures the CCTV feed path instead
## of the desk-CRT path).

const WARMUP := 120        # frames to discard while shaders compile / the night settles
const SAMPLE := 240        # frames averaged for the reported number

func _ready() -> void:
	var q := int(OS.get_environment("NW_BENCH_Q")) if OS.has_environment("NW_BENCH_Q") else 1
	Settings.graphics_quality = clampi(q, 0, 2)
	# Uncap so we measure the real GPU ceiling, not the 144 cap / vsync.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var night: Node = load("res://scenes/Night.tscn").instantiate()
	add_child(night)
	await _frames(40)
	if night.has_method("_begin_night") and "_running" in night and not night._running:
		night._begin_night()
	await _frames(4)
	if OS.has_environment("NW_BENCH_CAM") and night.has_method("_set_monitor"):
		night._set_monitor(true)
	Engine.max_fps = 0   # re-assert in case the night touched it

	await _frames(WARMUP)
	var acc := 0.0
	for i in SAMPLE:
		acc += get_process_delta_time()
		await get_tree().process_frame
	var avg_ms := (acc / float(SAMPLE)) * 1000.0
	var fps := 1000.0 / avg_ms if avg_ms > 0.0 else 0.0
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var vram := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var preset: String = ["Low", "Medium", "High"][Settings.graphics_quality]
	print("BENCH q=%d(%s) cam=%s :: avg %.3f ms  = %.0f FPS  | draws %d  prims %d  vram %.0f MB" % [
		Settings.graphics_quality, preset,
		"1" if OS.has_environment("NW_BENCH_CAM") else "0",
		avg_ms, fps, draws, prims, vram])
	get_tree().quit(0)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
