extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const ART := preload("res://assets/rooms/migurd_cabin/reference_ep18/bg.png")
const AMBIENCE := preload("res://shaders/title_ambience.gdshader")

var _title_font: SystemFont
var _body_font: SystemFont
var _continue: Button
var _latest := ""
var _picker: PanelContainer
var _picker_slot: Control


func _ready() -> void:
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	_build_art()
	_build_cover()
	_build_picker()
	SaveManager.slots_changed.connect(_refresh)
	_refresh()


func _input(event: InputEvent) -> void:
	if JournalUI.handle_scene_input(event, false):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _picker.visible:
		_hide_picker()
		get_viewport().set_input_as_handled()


func _build_art() -> void:
	var art := TextureRect.new()
	art.texture = ART
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(copy)
	var warmth := ColorRect.new()
	warmth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = AMBIENCE
	warmth.material = material
	add_child(warmth)
	warmth.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _build_cover() -> void:
	var cover := VBoxContainer.new()
	cover.add_theme_constant_override("separation", 9)
	add_child(cover)
	cover.anchor_left = 0.093
	cover.anchor_top = 0.165
	cover.anchor_right = 0.093
	cover.anchor_bottom = 0.165
	cover.offset_right = 572.0

	var title := Kit.create_label("无职转生", 108, Kit.INK, _title_font)
	cover.add_child(title)
	cover.add_child(Kit.create_label("属于你自己的人生", 40, Color("#6c6150"), _title_font))
	var line_texture := GradientTexture2D.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.31, 1.0])
	gradient.colors = PackedColorArray([Color("#B88A4B15"), Color("#986B33"), Color("#AD7D3E00")])
	line_texture.gradient = gradient
	line_texture.width = 520
	line_texture.height = 2
	var divider := TextureRect.new()
	divider.texture = line_texture
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(divider)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 12)
	menu.custom_minimum_size.x = 384.0
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cover.add_child(menu)
	var gap := Control.new()
	gap.custom_minimum_size.y = 36.0
	menu.add_child(gap)
	_continue = _button("继续旅程", "primary", _continue_journey)
	menu.add_child(_continue)
	menu.add_child(_button("开启新的人生", "primary", _show_picker))
	menu.add_child(_button("读取手账", "secondary", JournalUI.open_title_saves))
	menu.add_child(_button("离开", "subtle", get_tree().quit))


func _build_picker() -> void:
	_picker_slot = Control.new()
	_picker_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picker_slot)
	_picker_slot.anchor_left = 0.58
	_picker_slot.anchor_top = 0.245
	_picker_slot.anchor_right = 0.935
	_picker_slot.anchor_bottom = 0.695
	_picker = Kit.create_folio_panel(Kit.PAPER, 26, 23, 13)
	_picker_slot.add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	_picker.add_child(page)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("选择旅程的主角", _title_font, 24, Kit.BLUE)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(ribbon)
	heading.add_child(_button("合上", "secondary", _hide_picker))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	Kit.style_scrollbar(scroll.get_v_scroll_bar())
	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 10)
	scroll.add_child(cards)
	for id: String in WorldBlackboard.catalog.presets:
		var preset: Dictionary = WorldBlackboard.catalog.presets[id]
		var locked := bool(preset.get("locked", false))
		var card := Kit.create_folio_panel(Kit.PAPER_DEEP, 15, 12, 0)
		cards.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(words)
		words.add_child(Kit.create_label(str(preset.get("label", id)), 27, Kit.INK, _title_font))
		var subtitle := Kit.create_label(str(preset.get("subtitle", "")), 18, Kit.MUTED, _body_font)
		subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(subtitle)
		var start := _button("尚未开放" if locked else "启程", "secondary" if locked else "primary", _start.bind(id))
		start.custom_minimum_size.x = 110.0
		start.disabled = locked
		row.add_child(start)
	_picker.hide()


func _refresh() -> void:
	_latest = SaveManager.latest_slot()
	_continue.visible = not _latest.is_empty()


func _continue_journey() -> void:
	SaveManager.load_slot(_latest)


func _show_picker() -> void:
	_picker.show()
	Motion.slide_drawer_in(_picker, 110.0)


func _hide_picker() -> void:
	_picker.hide()
	Motion.cancel(_picker, ^"position:x")
	_picker.position.x = 0.0


func _start(id: String) -> void:
	SaveManager.new_game(id)


func _button(text: String, variant: String, action: Callable) -> Button:
	var button := Kit.create_tactile_button(text, variant, _title_font, 25)
	button.custom_minimum_size.y = 54
	button.pressed.connect(action)
	return button
