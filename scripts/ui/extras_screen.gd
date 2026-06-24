extends Control
## Extras hub: Bestiary (Hồ Sơ Ma), Tape Archive, Statistics, Credits. Reached from
## the main menu. Exposes content the campaign already authored but never surfaced.

func _ready() -> void:
	UI.full(self)
	var bg := UI.texture_rect("res://assets/art/intro/title_bg.svg", TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	UI.full(bg)
	add_child(bg)
	var dim := UI.color_rect(Color(0, 0, 0, 0.6))
	UI.full(dim)
	add_child(dim)

	var vb := UI.vbox(12)
	UI.place(vb, 0.5, 0.5, 0.5, 0.5, -170, -210, 170, 230)
	add_child(vb)
	vb.add_child(UI.label("EXTRAS_TITLE", 44, Color(0.93, 0.9, 0.82), HORIZONTAL_ALIGNMENT_CENTER))
	_add(vb, "EXTRAS_BESTIARY", "res://scenes/screens/BestiaryScreen.tscn")
	_add(vb, "EXTRAS_TAPES", "res://scenes/screens/TapeArchiveScreen.tscn")
	_add(vb, "EXTRAS_STATS", "res://scenes/screens/StatsScreen.tscn")
	_add(vb, "MENU_CREDITS", "res://scenes/screens/CreditsScreen.tscn")
	var back := UI.button("SET_BACK", 320, 48)
	back.pressed.connect(func(): Router.to_main_menu())
	vb.add_child(back)
	Audio.play_music("ambience_night")

func _add(vb: VBoxContainer, key: String, path: String) -> void:
	var b := UI.button(key, 320, 50)
	b.pressed.connect(func():
		Audio.play_sfx("ui_click", -6.0)
		Router.change_scene(path))
	vb.add_child(b)
