extends Node
## Scene transitions with a fade overlay + a global brightness layer (autoload "Router").

const MAIN_MENU := "res://scenes/screens/MainMenu.tscn"
const NIGHT := "res://scenes/Night.tscn"
const WIN := "res://scenes/screens/WinScreen.tscn"
const GAME_OVER := "res://scenes/screens/GameOver.tscn"
const INTRO := "res://scenes/screens/Intro.tscn"
const ENDING := "res://scenes/screens/EndingScreen.tscn"
const CREDITS := "res://scenes/screens/CreditsScreen.tscn"

var _layer: CanvasLayer
var _fade: ColorRect
var _brightness: ColorRect
var _busy := false
var _pending: Array = []   # [path, fade_time] requested while a transition was running

func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 128
	add_child(_layer)

	_brightness = ColorRect.new()
	_brightness.color = Color(0, 0, 0, 0)
	_brightness.set_anchors_preset(Control.PRESET_FULL_RECT)
	_brightness.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_brightness)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fade)

	Events.settings_changed.connect(_apply_brightness)
	_apply_brightness()

func _apply_brightness() -> void:
	# Slider 0.5..1.5. Below 1.0 darkens via a black overlay; 1.0+ is "normal"
	# (a horror game leans dark, so we don't force-brighten the scene).
	var b := Settings.brightness
	var a := clampf(1.0 - b, 0.0, 0.6) if b < 1.0 else 0.0
	_brightness.color = Color(0, 0, 0, a)

func change_scene(path: String, fade_time: float = 0.5) -> void:
	if _busy:
		# Don't drop a transition requested mid-fade (e.g. a death that resolves while
		# a win fade is running) — remember the latest target and run it next.
		_pending = [path, fade_time]
		return
	_busy = true
	# Sustained loops (heartbeat / tension drone / camera static) live on the Audio
	# autoload, so they'd otherwise bleed across a scene change (dying with cameras up,
	# quitting from the pause menu, etc.). Kill them on every transition. Music is left
	# alone — each destination screen manages its own ambience.
	Audio.stop_all_loops()
	await fade_out(fade_time)
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Failed to change scene to %s (err %d)" % [path, err])
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in(fade_time)
	_busy = false
	if not _pending.is_empty():
		var nxt: Array = _pending
		_pending = []
		change_scene(nxt[0], nxt[1])

func fade_out(t: float = 0.5) -> void:
	_fade.color.a = 0.0
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, max(0.01, t))
	await tw.finished

func fade_in(t: float = 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 0.0, max(0.01, t))
	await tw.finished

func flash_black(hold: float = 0.05) -> void:
	_fade.color.a = 1.0
	var tw := create_tween()
	tw.tween_interval(hold)
	tw.tween_property(_fade, "color:a", 0.0, 0.4)

func to_main_menu() -> void:
	change_scene(MAIN_MENU)

func to_intro() -> void:
	change_scene(INTRO, 0.8)

func to_night() -> void:
	change_scene(NIGHT, 1.0)

func to_win() -> void:
	change_scene(WIN, 1.5)

func to_ending() -> void:
	change_scene(ENDING, 1.8)

func to_credits() -> void:
	change_scene(CREDITS, 1.0)

func to_game_over(cause: String = "") -> void:
	Game.last_cause = cause
	change_scene(GAME_OVER, 0.25)
