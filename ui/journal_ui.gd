extends Node

const Kit := preload("res://ui/ui_theme_kit.gd")
const CharacterOverlay := preload("res://ui/character_journal_overlay.gd")
const SaveOverlay := preload("res://ui/save_load_overlay.gd")
const SettingsOverlayScene := preload("res://scenes/ui/settings/settings_overlay.tscn")

var character: CharacterOverlay
var saves: SaveOverlay
var settings: CanvasLayer


func _ready() -> void:
	character = CharacterOverlay.new()
	add_child(character)
	saves = SaveOverlay.new()
	add_child(saves)
	settings = SettingsOverlayScene.instantiate() as CanvasLayer
	add_child(settings)
	var settings_mgr := get_node_or_null("/root/SettingsManager")
	var bus_mgr := get_node_or_null("/root/AudioBusManager")
	if settings != null and settings.has_method("configure"):
		settings.call("configure", settings_mgr, bus_mgr)


func make_toolbar(font: Font) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	for entry: Array in [
		["book", "手账", open_character],
		["quill", "存/读档", open_save],
		["gear", "", open_settings],
		["door", "标题", return_title]
	]:
		var button := Kit.create_icon_button(str(entry[0]), str(entry[1]), "dark_brass", font, 18, Kit.BRASS)
		button.custom_minimum_size.y = 48.0
		if str(entry[0]) == "gear":
			button.tooltip_text = "系统设置"
		button.pressed.connect(entry[2])
		bar.add_child(button)
	return bar


func open_character() -> void:
	if SaveManager.can_save() and not is_open():
		character.open_section("overview")


func open_diary() -> void:
	if SaveManager.can_save() and not is_open():
		character.open_section("diary")


func open_codex(entry_id: String = "") -> void:
	if SaveManager.can_save() and not is_open():
		character.open_section("codex", entry_id)


func get_unread_codex_count() -> int:
	if has_node("/root/JournalManager"):
		return int(get_node("/root/JournalManager").call("get_unread_codex_count"))
	return 0


func open_save() -> void:
	if SaveManager.can_save() and not is_open():
		saves.open(true)


func open_title_saves() -> void:
	if not SceneTransition.is_busy() and not is_open():
		saves.open(false)


func return_title() -> void:
	if SaveManager.can_save() and not is_open():
		SceneTransition.change_to(SaveManager.TITLE)


func open_settings(initial_tab: String = "") -> void:
	if settings == null or SceneTransition.is_busy() or is_settings_open():
		return
	var settings_mgr := get_node_or_null("/root/SettingsManager")
	var bus_mgr := get_node_or_null("/root/AudioBusManager")
	if settings.has_method("configure"):
		settings.call("configure", settings_mgr, bus_mgr)
	if settings.has_method("open"):
		settings.call("open", initial_tab)


func close_settings(animated: bool = true) -> void:
	if is_settings_open() and settings.has_method("close"):
		settings.call("close", animated)


func is_settings_open() -> bool:
	return settings != null and settings.has_method("is_open") and bool(settings.call("is_open"))


func is_open() -> bool:
	return character.is_open() or saves.is_open() or is_settings_open()


func handle_scene_input(event: InputEvent, allow_shortcuts: bool = true) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_open():
			if is_settings_open():
				close_settings(true)
			elif saves.is_open():
				saves.close()
			else:
				character.close()
			get_viewport().set_input_as_handled()
			return true
		if allow_shortcuts and event.keycode in [KEY_C, KEY_I] and not saves.is_open() and not is_settings_open():
			if character.is_open():
				character.close()
			else:
				open_character()
			if SaveManager.can_save():
				get_viewport().set_input_as_handled()
				return true
	return is_open()
