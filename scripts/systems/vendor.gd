extends Node
## Bà bán hàng rong. The REAL vendor is dignified and sells reliable goods; she just
## wanders off if ignored. A COUNTERFEIT impostor (the tell: a warped tiếng rao)
## sells cursed goods and, if not refused, turns HOSTILE and rushes the left door —
## close it to drive the impostor off. The real grandmother is never the monster.

var _c
var cfg: NightConfig
var state := GameEnums.VendorState.IDLE
var counterfeit := false
var stock: Array = []

var _timer := 0.0
var _shop_t := 0.0
var _hostile_t := 0.0
var _fake_tell_t := 0.0   # re-emit cadence so the counterfeit tell HOLDS, not flashes once
var _rng := RandomNumberGenerator.new()
var _started := false

func setup(controller, config: NightConfig) -> void:
	_c = controller
	cfg = config
	_rng.randomize()

func begin() -> void:
	if not cfg.vendor_enabled:
		return
	_started = true
	_timer = _rng.randf_range(cfg.vendor_min_interval, cfg.vendor_max_interval) * 0.6

func _process(delta: float) -> void:
	if not _started or _c == null:
		return
	# Use the controller's accessor (guarded) instead of touching _running directly.
	if _c.has_method("is_running") and not _c.is_running():
		return
	match state:
		GameEnums.VendorState.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_appear()
		GameEnums.VendorState.SHOP:
			if _c.shop and _c.shop.visible:
				return   # freeze the window while the player is browsing
			# Hold the counterfeit tell: while the fake window is up, keep re-emitting
			# VENDOR_FAKE_TELL and re-cueing the warped rao so a glance away still catches it.
			if counterfeit:
				_fake_tell_t -= delta
				if _fake_tell_t <= 0.0:
					_fake_tell_t = 3.0
					Audio.play_sfx("vendor_bell", -3.0, 0.5, Audio.VERB_BUS)   # the rao, plainly wrong
					Audio.play_sfx("whisper", -6.0)
					Events.notify.emit("VENDOR_FAKE_TELL", [])
			_shop_t -= delta
			if _shop_t <= 0.0:
				if counterfeit:
					_go_hostile()
				else:
					_leave()
		GameEnums.VendorState.HOSTILE:
			_hostile_t -= delta
			if _c.is_door_closed(GameEnums.Side.LEFT):
				_repelled()
			elif _hostile_t <= 0.0:
				_attack()

func _appear() -> void:
	state = GameEnums.VendorState.SHOP
	counterfeit = cfg.night_index >= 3 and _rng.randf() < (0.28 + 0.04 * cfg.night_index)
	stock = ItemRegistry.random_shop(_rng, 3, counterfeit)
	_shop_t = 30.0
	# Counterfeit: a markedly warped, louder rao (lower pitch, hotter mix) so the tell
	# lands; the real grandmother's bell is clean. Arm the hold re-emit on the next tick.
	if counterfeit:
		Audio.play_sfx("vendor_bell", -3.0, 0.5, Audio.VERB_BUS)
		Audio.play_sfx("whisper", -6.0)
		_fake_tell_t = 3.0
	else:
		Audio.play_sfx("vendor_bell", -6.0, 1.0)
	Events.vendor_state_changed.emit(state)
	Events.notify.emit("VENDOR_FAKE_TELL" if counterfeit else "SHOP_PROMPT", [])

func on_bought(def: ItemDef) -> bool:
	if state != GameEnums.VendorState.SHOP:
		return false   # window already closed/turned hostile; no late purchase
	if not _c.try_spend_coins(def.cost):
		Events.notify.emit("SHOP_NOT_ENOUGH", [])
		return false   # keep the window open so the player can pick something cheaper
	_c.acquire_item(def)
	_leave()
	return true

func _leave() -> void:
	state = GameEnums.VendorState.LEAVING
	Events.vendor_state_changed.emit(state)
	_reset_idle()

func _reset_idle() -> void:
	state = GameEnums.VendorState.IDLE
	_timer = _rng.randf_range(cfg.vendor_min_interval, cfg.vendor_max_interval)
	Events.vendor_state_changed.emit(state)

func _go_hostile() -> void:
	state = GameEnums.VendorState.HOSTILE
	_hostile_t = 12.0
	Audio.play_sting("sting_metal", -4.0, 1.0)   # the mask drops: "that isn't her"
	Events.vendor_state_changed.emit(state)
	Events.notify.emit("VENDOR_HOSTILE", [])

func _repelled() -> void:
	Audio.play_sfx("door_slam", -6.0)
	Events.notify.emit("VENDOR_LEFT", [])
	_reset_idle()

## A ward/charm save (or any forced clear) must send the impostor packing —
## otherwise she stays frozen mid-lunge with her timer already spent and re-fires
## the grab on the very next frame, silently wasting the ward.
func repel_to_idle() -> void:
	# Include LEAVING: _attack() now self-disables to LEAVING before emitting the grab,
	# so a same-frame ward save reaches us already in LEAVING — still send her home.
	if state == GameEnums.VendorState.HOSTILE or state == GameEnums.VendorState.SHOP or state == GameEnums.VendorState.LEAVING:
		_reset_idle()

func _attack() -> void:
	# Self-disable so the HOSTILE branch can't re-emit the grab every frame (mirrors
	# ThreatBase._kill()). The ward path (repel_to_idle) still resets her independently.
	if state != GameEnums.VendorState.HOSTILE:
		return
	state = GameEnums.VendorState.LEAVING
	Events.jumpscare_started.emit("ba_hang_rong")
