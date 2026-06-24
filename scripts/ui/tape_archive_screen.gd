extends Control
## Kho Băng — re-listen to bác Tư's cassette tapes. The tapes ARE the story, and they
## play only once at night start (skippable), so this gives them a permanent home.

var _text: Label
var _title: Label

func _ready() -> void:
	UI.full(self)
	add_child(UI.backdrop("menu"))
	var dim := UI.color_rect(Color(0, 0, 0, 0.45))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -440, -290, 440, 310)
	add_child(vb)
	vb.add_child(UI.label("TAPE_ARCHIVE_TITLE", 40, Color(0.9, 0.86, 0.8), HORIZONTAL_ALIGNMENT_CENTER))

	var row := UI.hbox(18)
	vb.add_child(row)

	# Left: a column of night buttons (locked until that night's tape is unlocked).
	var list := UI.vbox(8)
	list.custom_minimum_size = Vector2(220, 380)
	row.add_child(list)
	for n in range(1, Game.MAX_NIGHTS + 1):
		var unlocked: bool = Save.tapes_unlocked.get(n, false)
		var b := UI.button("", 220, 46)
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.text = tr("TAPE_NIGHT_LABEL") % n if unlocked else "%s — %s" % [tr("TAPE_NIGHT_LABEL") % n, tr("TAPE_LOCKED")]
		b.disabled = not unlocked
		var night := n
		b.pressed.connect(func(): _show(night))
		list.add_child(b)

	# Right: the selected tape's transcript.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(580, 380)
	row.add_child(panel)
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 18)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(pad)
	var tcol := UI.vbox(12)
	pad.add_child(tcol)
	_title = UI.text_label("", 22, Color(0.95, 0.8, 0.4), HORIZONTAL_ALIGNMENT_LEFT)
	tcol.add_child(_title)
	_text = UI.text_label(tr("TAPE_PICK"), 18, UI.COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(540, 0)
	tcol.add_child(_text)

	var back := UI.button("SET_BACK", 220, 46)
	back.pressed.connect(func(): Router.change_scene("res://scenes/screens/ExtrasScreen.tscn"))
	vb.add_child(back)
	Audio.play_music("ambience_night")

func _show(night: int) -> void:
	Audio.play_sfx("ui_click", -6.0)
	_title.text = tr("TAPE_NIGHT_LABEL") % night
	var lines: Array = Lore.tape_keys(night)
	var body := ""
	for k in lines:
		body += tr(k) + "\n\n"
	_text.text = body.strip_edges()
