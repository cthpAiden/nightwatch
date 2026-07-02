extends Node
## Persistent player settings (autoload "Settings").
## Stores audio, display, accessibility and difficulty options in user://settings.cfg.
## Other systems read these values and listen to Events.settings_changed to react.

const PATH := "user://settings.cfg"
const SETTINGS_VERSION := 1
const MIN_WINDOW_SIZE := Vector2i(960, 540)

# Accessibility: how intense scares are allowed to be.
enum Scare { FULL, REDUCED, OFF }

var language: String = "vi"
var master_volume: float = 0.45     # 0..1 linear (default halved from 0.9)
var music_volume: float = 0.8
var sfx_volume: float = 1.0
var fullscreen: bool = false
var brightness: float = 1.0         # 0.5 .. 1.5 multiplier
var graphics_quality: int = 1       # 0=Low, 1=Medium, 2=High (see Graphics autoload)
var sdfgi_enabled: bool = false     # optional real-time GI, honoured only on High
var scare_intensity: int = Scare.FULL
var difficulty: int = GameEnums.Difficulty.NORMAL
var first_run: bool = true

func _ready() -> void:
	load_settings()
	_apply_window()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		# No file yet (first ever run): pick a preset from the GPU, then write defaults.
		graphics_quality = _detect_default_quality()
		save_settings()
		return
	language = cfg.get_value("general", "language", language)
	first_run = cfg.get_value("general", "first_run", first_run)
	difficulty = cfg.get_value("general", "difficulty", difficulty)
	master_volume = cfg.get_value("audio", "master", master_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	fullscreen = cfg.get_value("display", "fullscreen", fullscreen)
	brightness = cfg.get_value("display", "brightness", brightness)
	graphics_quality = cfg.get_value("display", "graphics_quality", _detect_default_quality())
	sdfgi_enabled = cfg.get_value("display", "sdfgi_enabled", sdfgi_enabled)
	scare_intensity = cfg.get_value("accessibility", "scare_intensity", scare_intensity)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SETTINGS_VERSION)
	cfg.set_value("general", "language", language)
	cfg.set_value("general", "first_run", first_run)
	cfg.set_value("general", "difficulty", difficulty)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "brightness", brightness)
	cfg.set_value("display", "graphics_quality", graphics_quality)
	cfg.set_value("display", "sdfgi_enabled", sdfgi_enabled)
	cfg.set_value("accessibility", "scare_intensity", scare_intensity)
	cfg.save(PATH)

## Generic setter used by the options menu. Saves and notifies listeners.
func apply(changes: Dictionary) -> void:
	for key in changes:
		match key:
			"language": language = changes[key]
			"master_volume": master_volume = clampf(changes[key], 0.0, 1.0)
			"music_volume": music_volume = clampf(changes[key], 0.0, 1.0)
			"sfx_volume": sfx_volume = clampf(changes[key], 0.0, 1.0)
			"fullscreen": fullscreen = changes[key]
			"brightness": brightness = clampf(changes[key], 0.5, 1.5)
			"graphics_quality": graphics_quality = clampi(changes[key], 0, 2)
			"sdfgi_enabled": sdfgi_enabled = changes[key]
			"scare_intensity": scare_intensity = changes[key]
			"difficulty": difficulty = changes[key]
			"first_run": first_run = changes[key]
	save_settings()
	_apply_window()
	Events.settings_changed.emit()

func _apply_window() -> void:
	DisplayServer.window_set_min_size(MIN_WINDOW_SIZE)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)

## Best-effort first-run preset from the GPU name. Integrated Intel/AMD parts (and any
## headless/empty adapter) fall to Low, the safe floor; anything else starts at Medium.
## Always overridable in Settings — this only picks the initial value.
func _detect_default_quality() -> int:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	if adapter == "":
		return 1
	# "Intel Arc" is discrete; every other Intel iGPU and the AMD "Radeon Graphics"
	# APU line are integrated and want the Low floor.
	var integrated := (adapter.contains("intel") and not adapter.contains("arc")) \
		or adapter.contains("uhd graphics") or adapter.contains("hd graphics") \
		or adapter.contains("iris") or adapter.contains("radeon(tm) graphics") \
		or adapter.contains("amd radeon graphics")
	return 0 if integrated else 1

func allow_jumpscares() -> bool:
	return scare_intensity != Scare.OFF

func scare_volume_scale() -> float:
	match scare_intensity:
		Scare.REDUCED: return 0.55
		Scare.OFF: return 0.0
		_: return 1.0
