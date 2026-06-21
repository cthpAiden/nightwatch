extends Node
## Language handling (autoload "Locale"). Thin wrapper over TranslationServer + Settings.

const SUPPORTED := ["vi", "en"]

func _ready() -> void:
	apply(Settings.language)
	Events.settings_changed.connect(_on_settings_changed)

func apply(locale: String) -> void:
	if not SUPPORTED.has(locale):
		locale = "vi"
	TranslationServer.set_locale(locale)
	Events.locale_changed.emit(locale)

func _on_settings_changed() -> void:
	if TranslationServer.get_locale().substr(0, 2) != Settings.language:
		apply(Settings.language)

func toggle() -> void:
	Settings.apply({"language": ("en" if Settings.language == "vi" else "vi")})

## tr() with positional {0},{1} formatting.
func t(key: String, args: Array = []) -> String:
	var s := tr(key)
	return s if args.is_empty() else s.format(args)

func current() -> String:
	return Settings.language
