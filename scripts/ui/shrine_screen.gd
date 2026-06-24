extends Control
## Between-nights shrine: spend vàng mã (coins, earned by surviving) on permanent
## upgrades to your altar and tools. Reachable from the menu, night select, and the
## dawn (win) screen. Purchases persist in Save and are applied by NightController.

var _grid: GridContainer
var _coins_lbl: Label

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	var dim := UI.color_rect(Color(0, 0, 0, 0.4))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -440, -300, 440, 320)
	add_child(vb)
	vb.add_child(UI.label("SHRINE_TITLE", 40, Color(0.95, 0.82, 0.45), HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(UI.label("SHRINE_SUB", 17, UI.COL_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_coins_lbl = UI.text_label("", 22, Color(1.0, 0.85, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(_coins_lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(852, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	var back := UI.button("SET_BACK", 220, 46)
	back.pressed.connect(func(): Router.to_main_menu())
	vb.add_child(back)

	_rebuild()
	Audio.play_music("ambience_night")

func _rebuild() -> void:
	_coins_lbl.text = "%s: %d" % [tr("HUD_COINS"), Save.coins]
	for c in _grid.get_children():
		c.queue_free()
	for up in ShrineUpgrades.CATALOG:
		_grid.add_child(_make_card(up))

func _make_card(up: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(410, 116)
	var vb := UI.vbox(4)
	card.add_child(vb)
	vb.add_child(UI.label(up.name, 20, UI.COL_TEXT))
	var desc := UI.label(up.desc, 14, UI.COL_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(386, 40)
	vb.add_child(desc)
	var owned: bool = Save.has_upgrade(up.id)
	if owned:
		vb.add_child(UI.label("SHRINE_OWNED", 16, Color(0.5, 0.85, 0.55)))
	else:
		var buy := UI.button("", 386, 36)
		buy.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		buy.text = "%s — %d %s" % [tr("SHRINE_BUY"), int(up.cost), tr("HUD_COINS")]
		buy.disabled = Save.coins < int(up.cost)
		buy.pressed.connect(func(): _buy(up))
		vb.add_child(buy)
	return card

func _buy(up: Dictionary) -> void:
	if Save.purchase_upgrade(up.id, int(up.cost)):
		Audio.play_sfx("ui_confirm", -4.0)
		Events.coins_changed.emit(Save.coins)
		_rebuild()
	else:
		Audio.play_sfx("ui_back", -4.0)
