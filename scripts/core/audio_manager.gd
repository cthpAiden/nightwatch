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
	"candle_gust", "phone_ring", "phone_ring_warp", "drone_tension", "coin_chime",
	# horror pass: anticipation, per-threat approaches, water, stinger family, loops
	"pre_scare", "ambience_sub", "approach_drag", "approach_heavy", "approach_soft",
	"water_loop", "water_call", "sting_low", "sting_rise", "sting_metal", "sting_breath",
	"shutter_strain", "incense_bed",
]
const MUSIC_NAMES := ["ambience_night", "ambience_dread"]
# NOTE: "whisper" is intentionally NOT here. It is played as a one-shot lure
# (ma_da / counterfeit vendor); if its WAV had loop_mode set it would play
# forever in the SFX pool — that was the "windy/sawing" bug.
# NOTE: "fluorescent_hum" is loaded (still in SFX_NAMES) but currently unused —
# it is never started, so it is intentionally left out of LOOPING.
const LOOPING := ["static_loop", "heartbeat", "breathing",
	"ambience_night", "ambience_dread", "drone_tension",
	"ambience_sub", "water_loop", "shutter_strain", "incense_bed"]

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const VERB_BUS := "Verb"   # wet send for scares/stingers so they bloom + survive a duck()
const POOL_SIZE := 16

var _streams: Dictionary = {}                 # name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}                    # name -> AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _duck_tweens: Dictionary = {}              # bus name -> active duck Tween (overlap guard)

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
	for b in [MUSIC_BUS, SFX_BUS, VERB_BUS]:
		if AudioServer.get_bus_index(b) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# Verb: a dim, dark room tail. Scares/stingers route here so they sound spatial
	# and — crucially — are NOT touched by duck() (which only drops Music + dry SFX),
	# so the hit punches through a momentarily-silenced mix.
	var vi := AudioServer.get_bus_index(VERB_BUS)
	if vi != -1 and AudioServer.get_bus_effect_count(vi) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.78
		rv.damping = 0.45
		rv.wet = 0.32
		rv.dry = 0.92
		rv.predelay_msec = 28.0
		rv.spread = 0.7
		AudioServer.add_bus_effect(vi, rv)
	# Master glue: a gentle compressor tames the procedural peaks, a limiter stops the
	# jumpscare from hard-clipping. Keeps the mix cohesive without obvious pumping.
	var mi := AudioServer.get_bus_index("Master")
	if mi != -1 and AudioServer.get_bus_effect_count(mi) == 0:
		var comp := AudioEffectCompressor.new()
		# Eased from -14/3.5 to -10/2.5: the source WAVs are already peak-0.9 normalised and
		# soft-clipped, so the old hot, high-ratio comp pumped the bed and stacked saturation
		# under the limiter. Gentler glue, less audible pumping.
		comp.threshold = -10.0
		comp.ratio = 2.5
		comp.attack_us = 18000.0
		comp.release_ms = 240.0
		comp.gain = 1.0
		AudioServer.add_bus_effect(mi, comp)
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.6
		# soft_clip_db 2.0 -> 0.3: AudioEffectLimiter's soft-clip saturates BELOW the ceiling,
		# so 2 dB of it coloured every loud hit (jumpscare) on top of the source soft-clip —
		# audible grit. Drop it so the limiter is a clean brickwall catch, not a saturator.
		lim.soft_clip_db = 0.3
		AudioServer.add_bus_effect(mi, lim)

func apply_volumes() -> void:
	_set_bus("Master", Settings.master_volume)
	_set_bus(MUSIC_BUS, Settings.music_volume)
	_set_bus(SFX_BUS, Settings.sfx_volume)
	# Wet send tracks the SFX slider but sits ~3 dB under the dry bus (×0.708) so a scare's
	# reverb tail doesn't tower over the (ducked) dry mix during a death duck().
	_set_bus(VERB_BUS, Settings.sfx_volume * 0.708)

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
func play_sfx(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = SFX_BUS) -> AudioStreamPlayer:
	var s: AudioStream = _streams.get(sound_name)
	if s == null:
		return null
	var p := _free_player()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = bus
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

func play_jumpscare(pitch: float = 1.0) -> void:
	var scale := Settings.scare_volume_scale()
	if scale <= 0.0:
		return
	play_sfx("jumpscare", linear_to_db(scale), pitch, VERB_BUS)

## Play a scare-grade sting (pre-scare swell, death/startle/approach stings). Routes to
## VERB (so it blooms + survives a duck) AND honours the accessibility tier: REDUCED
## attenuates it, OFF keeps only a soft floor so the cue still lands (OFF removes the jump
## IMAGE + shake/flash, never the audio confirmation). FULL is unchanged (0 dB offset).
func play_sting(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
	var mult := maxf(Settings.scare_volume_scale(), 0.4)
	return play_sfx(sound_name, volume_db + linear_to_db(mult), pitch, VERB_BUS)

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

## Live-pitch a sustained loop (e.g. ramp the heartbeat faster as danger climbs).
func set_loop_pitch(sound_name: String, pitch: float) -> void:
	var p: AudioStreamPlayer = _loops.get(sound_name)
	if p:
		p.pitch_scale = maxf(0.01, pitch)

## Sidechain duck: drop Music + dry SFX for a held beat, then recover. Sounds routed
## to the Verb bus (jumpscare, key stingers) are untouched, so they punch through the
## sudden quiet — the "the mix drops out a beat before the hit" scare move.
func duck(amount_db: float = 16.0, attack: float = 0.05, hold: float = 0.22, release: float = 0.5) -> void:
	for bus in [MUSIC_BUS, SFX_BUS]:
		var idx := AudioServer.get_bus_index(bus)
		if idx == -1 or AudioServer.is_bus_mute(idx):
			continue
		# Restore TARGET is the slider volume, not the live (maybe already-ducked) level,
		# and any in-flight duck on this bus is killed first — so overlapping ducks (e.g.
		# a ma da lure rolling into a death) can't ratchet the bus down and never recover.
		var setting: float = Settings.music_volume if bus == MUSIC_BUS else Settings.sfx_volume
		var base := linear_to_db(setting)
		var low := base - amount_db
		var prev: Tween = _duck_tweens.get(bus)
		if prev and prev.is_valid():
			prev.kill()
		var tw := create_tween()
		tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(idx, v), base, low, attack)
		tw.tween_interval(hold)
		tw.tween_method(func(v: float): AudioServer.set_bus_volume_db(idx, v), low, base, release)
		_duck_tweens[bus] = tw

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
