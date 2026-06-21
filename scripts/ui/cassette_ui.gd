extends Control
## Plays the previous guard's cassette at the start of a night: lines one at a time,
## then emits `closed` so the night can begin. Skippable.

signal closed

var _c
var _keys: Array = []
var _index := 0
var _line: Label
var _next_btn: Button
var _root: Control

func setup(controller) -> void:
	_c = controller
	UI.full(self)
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_tape(night: int) -> void:
	_keys = Lore.tape_keys(night)
	_index = 0
	if _root:
		_root.queue_free()
	var dim := UI.color_rect(Color(0, 0, 0, 0.8))
	UI.full(dim)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = dim

	var panel := PanelContainer.new()
	UI.place(panel, 0.5, 0.5, 0.5, 0.5, -380, -180, 380, 180)
	dim.add_child(panel)
	var vb := UI.vbox(16)
	panel.add_child(vb)
	var head := UI.hbox(10)
	head.add_child(UI.texture_rect("res://assets/art/ui/btn_item.svg", TextureRect.STRETCH_KEEP_ASPECT))
	head.get_child(0).custom_minimum_size = Vector2(40, 40)
	var title := UI.text_label("%s — %s" % [tr("TAPE_TITLE"), tr("TAPE_NIGHT").format([str(night)])], 24, Color(0.9, 0.8, 0.55))
	head.add_child(title)
	vb.add_child(head)
	vb.add_child(UI.label("TAPE_FROM", 15, UI.COL_DIM))

	_line = UI.text_label("", 21, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_line.custom_minimum_size = Vector2(700, 120)
	vb.add_child(_line)

	var row := UI.hbox(12)
	var skip := UI.button("BTN_SKIP", 160, 44)
	skip.pressed.connect(_finish)
	_next_btn = UI.button("BTN_CONTINUE", 200, 44)
	_next_btn.pressed.connect(_advance)
	row.add_child(skip)
	row.add_child(_next_btn)
	vb.add_child(row)

	visible = true
	Audio.start_loop("static_loop", -26.0)
	_show_line()

func _show_line() -> void:
	if _index < _keys.size():
		_line.text = tr(_keys[_index])
		Audio.play_sfx("ui_hover", -14.0)
		_next_btn.text = "BTN_START" if _index == _keys.size() - 1 else "BTN_CONTINUE"

func _advance() -> void:
	_index += 1
	if _index >= _keys.size():
		_finish()
	else:
		_show_line()

func _finish() -> void:
	Audio.stop_loop("static_loop")
	if _root:
		_root.queue_free()
		_root = null
	visible = false
	closed.emit()
