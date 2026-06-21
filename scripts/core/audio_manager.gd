extends Node
## Audio playback (autoload "Audio").
## Buses Master / Music / SFX are created at runtime so no .tres is required.
## One-shots use a pool; music and sustained loops use dedicated players.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const JUMP_DIR := "res://assets/audio/jumpscare/"

const SFX_NAMES := [
	"ui_click", "ui_hover", "ui_back", "ui_confirm", "clock_tick", "clock_chime",
	"door_slam", "door_creak", "light_switch", "fluorescent_hum", "camera_switch",
	"static_loop", "camera_up", "camera_down", "heartbeat", "breathing", "whisper",
	"stinger", "power_down", "low_power_beep", "offering_bell", "incense_whoosh",
	"item_good", "item_bad", "footstep_wood", "knock", "rooster", "vendor_bell",
]
const MUSIC_NAMES := ["ambience_night", "ambience_dread"]
const LOOPING := ["fluorescent_hum", "static_loop", "heartbeat", "breathing",
	"ambience_night", "ambience_dread", "whisper"]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const POOL_SIZE := 16

var _streams: Dictionary = {}                 # name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}                    # name -> AudioStreamPlayer
var _music_player: AudioStreamPlayer

func _ready() -> void:
	_ensure_buses()
	_load_all()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_pool.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)
	apply_volumes()
	Events.settings_changed.connect(func() -> void: apply_volumes())

# --- bus / volume -----------------------------------------------------------
func _ensure_buses() -> void:
	for b in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(b) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")

func apply_volumes() -> void:
	_set_bus("Master", Settings.master_volume)
	_set_bus(MUSIC_BUS, Settings.music_volume)
	_set_bus(SFX_BUS, Settings.sfx_volume)

func _set_bus(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	if linear <= 0.001:
		AudioServer.set_bus_mute(idx, true)
	else:
		AudioServer.set_bus_mute(idx, false)
		AudioServer.set_bus_volume_db(idx, linear_to_db(linear))

# --- loading ----------------------------------------------------------------
func _load_all() -> void:
	for n in SFX_NAMES:
		_streams[n] = _load_stream(SFX_DIR + n + ".wav", n)
	for n in MUSIC_NAMES:
		_streams[n] = _load_stream(MUSIC_DIR + n + ".wav", n)
	_streams["jumpscare"] = _load_stream(JUMP_DIR + "jumpscare.wav", "jumpscare")

func _load_stream(path: String, sound_name: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		push_warning("Audio missing: " + path)
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV and LOOPING.has(sound_name):
		var w: AudioStreamWAV = s
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = _wav_frames(w)
	return s

func _wav_frames(w: AudioStreamWAV) -> int:
	var bytes_per_sample := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
	var channels := 2 if w.stereo else 1
	var denom := bytes_per_sample * channels
	return w.data.size() / denom if denom > 0 else 0

# --- one-shots --------------------------------------------------------------
func play_sfx(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var s: AudioStream = _streams.get(sound_name)
	if s == null:
		return null
	var p := _free_player()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = SFX_BUS
	p.play()
	return p

func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	# All busy: grow the pool.
	var np := AudioStreamPlayer.new()
	np.bus = SFX_BUS
	add_child(np)
	_pool.append(np)
	return np

func play_jumpscare() -> void:
	var scale := Settings.scare_volume_scale()
	if scale <= 0.0:
		return
	play_sfx("jumpscare", linear_to_db(scale))

# --- sustained loops --------------------------------------------------------
func start_loop(sound_name: String, volume_db: float = 0.0) -> void:
	var s: AudioStream = _streams.get(sound_name)
	if s == null:
		return
	var p: AudioStreamPlayer = _loops.get(sound_name)
	if p == null:
		p = AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_loops[sound_name] = p
	p.stream = s
	p.volume_db = volume_db
	if not p.playing:
		p.play()

func stop_loop(sound_name: String) -> void:
	var p: AudioStreamPlayer = _loops.get(sound_name)
	if p and p.playing:
		p.stop()

func set_loop_volume(sound_name: String, volume_db: float) -> void:
	var p: AudioStreamPlayer = _loops.get(sound_name)
	if p:
		p.volume_db = volume_db

func stop_all_loops() -> void:
	for k in _loops:
		_loops[k].stop()

# --- music ------------------------------------------------------------------
func play_music(sound_name: String, fade: float = 1.5) -> void:
	var s: AudioStream = _streams.get(sound_name)
	if s == null or _music_player.stream == s and _music_player.playing:
		return
	if _music_player.playing and fade > 0.0:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -40.0, fade * 0.5)
		await tw.finished
	_music_player.stream = s
	_music_player.volume_db = -40.0 if fade > 0.0 else 0.0
	_music_player.play()
	if fade > 0.0:
		var tw2 := create_tween()
		tw2.tween_property(_music_player, "volume_db", 0.0, fade)

func stop_music(fade: float = 1.0) -> void:
	if not _music_player.playing:
		return
	if fade > 0.0:
		var tw := create_tween()
		tw.tween_property(_music_player, "volume_db", -40.0, fade)
		await tw.finished
	_music_player.stop()
