extends Control
## The vendor's shop. Shows 3 items (effects hidden — the player learns by using).
## A pick calls the supplied callback with the chosen ItemDef.

var _c
var _on_pick: Callable
var _root: Control

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	process_mode = Node.PROCESS_MODE_ALWAYS

func open(stock: Array, counterfeit: bool, on_pick: Callable) -> void:
	_on_pick = on_pick
	if _root:
		_root.queue_free()
	var dim := UI.color_rect(Color(0, 0, 0, 0.6))
	UI.full(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = dim

	var portrait := UI.texture_rect(
		"res://assets/art/threats/%s" % ("vendor_hostile.svg" if counterfeit else "vendor_shop.svg"),
		TextureRect.STRETCH_KEEP_ASPECT)
	UI.place(portrait, 0, 0.5, 0, 0.5, 60, -260, 320, 260)
	dim.add_child(portrait)

	var panel := PanelContainer.new()
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -360, -220, 460, 240)
	dim.add_child(panel)
	var vb := UI.vbox(14)
	panel.add_child(vb)
	vb.add_child(UI.label("SHOP_TITLE", 28, Color(0.95, 0.8, 0.5)))
	vb.add_child(UI.label("SHOP_PICK_ONE", 18, UI.COL_DIM))
	var row := UI.hbox(14)
	vb.add_child(row)
	for def in stock:
		row.add_child(_make_card(def))
	var cancel := UI.button("SHOP_LEAVE", 200, 44)
	cancel.pressed.connect(close)
	vb.add_child(cancel)

	visible = true

func _make_card(def: ItemDef) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 230)
	var vb := UI.vbox(8)
	card.add_child(vb)
	var icon := UI.texture_rect(def.icon_path, TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	icon.custom_minimum_size = Vector2(64, 64)
	vb.add_child(icon)
	vb.add_child(UI.label(def.name_key, 20, UI.COL_TEXT))
	var flavor := UI.label(def.flavor_key, 15, UI.COL_DIM)
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD
	flavor.custom_minimum_size = Vector2(196, 90)
	vb.add_child(flavor)
	var take := UI.button("SHOP_TAKE", 196, 40)
	take.pressed.connect(func(): _pick(def))
	vb.add_child(take)
	return card

func _pick(def: ItemDef) -> void:
	Audio.play_sfx("ui_confirm", -4.0)
	if _on_pick.is_valid():
		_on_pick.call(def)
	close()

func close() -> void:
	if _root:
		_root.queue_free()
		_root = null
	visible = false
