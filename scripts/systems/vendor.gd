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
	if not _started or not _c._running:
		return
	match state:
		GameEnums.VendorState.IDLE:
			_timer -= delta
			if _timer <= 0.0:
				_appear()
		GameEnums.VendorState.SHOP:
			if _c.shop and _c.shop.visible:
				return   # freeze the window while the player is browsing
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
	Audio.play_sfx("vendor_bell", -6.0, 0.55 if counterfeit else 1.0)
	if counterfeit:
		Audio.play_sfx("whisper", -12.0)
	Events.vendor_state_changed.emit(state)
	Events.notify.emit("VENDOR_FAKE_TELL" if counterfeit else "SHOP_PROMPT", [])

func on_bought(def: ItemDef) -> void:
	if state != GameEnums.VendorState.SHOP:
		return   # window already closed/turned hostile; no late purchase
	_c.acquire_item(def)
	_leave()

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
	Audio.play_sfx("stinger", -4.0)
	Events.vendor_state_changed.emit(state)
	Events.notify.emit("VENDOR_HOSTILE", [])

func _repelled() -> void:
	Audio.play_sfx("door_slam", -6.0)
	Events.notify.emit("VENDOR_LEFT", [])
	_reset_idle()

func _attack() -> void:
	Events.jumpscare_started.emit("ba_hang_rong")
