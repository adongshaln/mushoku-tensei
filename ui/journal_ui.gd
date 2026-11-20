extends Node

const Kit := preload("res://ui/ui_theme_kit.gd")
const CharacterOverlay := preload("res://ui/character_journal_overlay.gd")
const SaveOverlay := preload("res://ui/save_load_overlay.gd")

var character: CharacterOverlay
var saves: SaveOverlay


func _ready() -> void:
	character = CharacterOverlay.new()
	add_child(character)
	saves = SaveOverlay.new()
	add_child(saves)


func make_toolbar(font: Font) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	for entry: Array in [["手账", open_character], ["存档", open_save], ["返回标题页", return_title]]:
		var button := Kit.create_tactile_button(str(entry[0]), "secondary", font, 20)
		button.custom_minimum_size = Vector2(94.0, 49.0)
		button.pressed.connect(entry[1])
		bar.add_child(button)
	return bar


func open_character() -> void:
	if SaveManager.can_save() and not is_open():
		character.open()


func open_save() -> void:
	if SaveManager.can_save() and not is_open():
		saves.open(true)


func open_title_saves() -> void:
	if not SceneTransition.is_busy() and not is_open():
		saves.open(false)


func return_title() -> void:
	if SaveManager.can_save() and not is_open():
		SceneTransition.change_to(SaveManager.TITLE)


func is_open() -> bool:
	return character.is_open() or saves.is_open()


func handle_scene_input(event: InputEvent, allow_shortcuts: bool = true) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and is_open():
			if saves.is_open():
				saves.close()
			else:
				character.close()
			get_viewport().set_input_as_handled()
			return true
		if allow_shortcuts and event.keycode in [KEY_C, KEY_I] and not saves.is_open():
			if character.is_open():
				character.close()
			else:
				open_character()
			if SaveManager.can_save():
				get_viewport().set_input_as_handled()
				return true
	return is_open()
