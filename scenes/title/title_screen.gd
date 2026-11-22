extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const KitArt := preload("res://core/placeholder_art_factory.gd")
const ART := preload("res://assets/rooms/migurd_cabin/reference_ep18/bg.png")
const AMBIENCE := preload("res://shaders/title_ambience.gdshader")

var _title_font: SystemFont
var _body_font: SystemFont
var _art: TextureRect
var _watermark: Kit.AstralWatermark
var _cover: VBoxContainer
var _menu_entries: Array[Control] = []
var _continue_btn: Button
var _continue_sub: Label
var _latest := ""
var _picker: PanelContainer
var _picker_slot: Control
var _clock := 0.0
var _parallax := Vector2.ZERO
var _parallax_target := Vector2.ZERO


func _ready() -> void:
	clip_contents = true
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	_build_art()
	_build_cover()
	_build_picker()
	SaveManager.slots_changed.connect(_refresh)
	_refresh()
	_animate_entrance()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_cover, _picker_slot, _watermark]


func _process(delta: float) -> void:
	_clock += delta
	_parallax = _parallax.lerp(_parallax_target, 1.0 - exp(-delta * 5.0))
	if _art != null:
		var breath := 1.042 + sin(_clock * 0.34) * 0.015
		_art.scale = Vector2(breath, breath)
		_art.position = _parallax


func _input(event: InputEvent) -> void:
	if JournalUI.handle_scene_input(event, false):
		return
	if event is InputEventMouseMotion and size.x > 0.0 and size.y > 0.0:
		var rel: Vector2 = (event.position / size - Vector2(0.5, 0.5)) * 2.0
		_parallax_target = Vector2(-rel.x * 16.0, -rel.y * 9.0)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and _picker.visible:
		_hide_picker()
		get_viewport().set_input_as_handled()


func _build_art() -> void:
	_art = TextureRect.new()
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.pivot_offset_ratio = Vector2(0.58, 0.52)
	add_child(_art)
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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

	_watermark = Kit.AstralWatermark.new()
	_watermark.setup(Kit.BRASS)
	add_child(_watermark)
	_watermark.anchor_left = 0.02
	_watermark.anchor_top = 0.06
	_watermark.anchor_right = 0.02
	_watermark.anchor_bottom = 0.06
	_watermark.offset_right = 460.0
	_watermark.offset_bottom = 460.0


func _build_cover() -> void:
	_cover = VBoxContainer.new()
	_cover.add_theme_constant_override("separation", 6)
	add_child(_cover)
	_cover.anchor_left = 0.075
	_cover.anchor_top = 0.14
	_cover.anchor_right = 0.075
	_cover.anchor_bottom = 0.14
	_cover.offset_right = 580.0

	var kicker_row := HBoxContainer.new()
	kicker_row.add_theme_constant_override("separation", 10)
	_cover.add_child(kicker_row)
	var star_l := Kit.create_micro_icon("star", 14.0, Kit.BRASS)
	star_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	kicker_row.add_child(star_l)
	var kicker := Kit.create_label("甲龙历 418 年  ·  六面世界手账", 19, Kit.BRASS, _title_font)
	kicker.add_theme_color_override("font_shadow_color", Color("#0c0805cc"))
	kicker.add_theme_constant_override("shadow_offset_y", 2)
	kicker_row.add_child(kicker)

	var title := Kit.create_label("无职转生", 110, Kit.IVORY, _title_font)
	title.add_theme_color_override("font_shadow_color", Color("#120a05e0"))
	title.add_theme_constant_override("shadow_offset_y", 5)
	title.add_theme_constant_override("shadow_outline_size", 10)
	_cover.add_child(title)

	var subtitle := Kit.create_label("～属于你自己的人生～", 36, Color("#e4d2b4"), _title_font)
	subtitle.add_theme_color_override("font_shadow_color", Color("#120a05cc"))
	subtitle.add_theme_constant_override("shadow_offset_y", 3)
	_cover.add_child(subtitle)

	var divider := Kit.create_gold_divider(492.0, true, 18.0)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cover.add_child(divider)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu.custom_minimum_size.x = 486.0
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_cover.add_child(menu)

	var gap := Control.new()
	gap.custom_minimum_size.y = 22.0
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(gap)

	_continue_btn = _build_continue_button()
	menu.add_child(_continue_btn)
	_menu_entries.append(_continue_btn)

	var new_btn := _calligraphy_entry("开启新的人生", "翻开主角卷轴 · 踏上六面世界", "compass", _show_picker)
	menu.add_child(new_btn)
	_menu_entries.append(new_btn)

	var load_btn := _calligraphy_entry("读取手账", "翻阅已封存的旅途旧章", "book", JournalUI.open_title_saves)
	menu.add_child(load_btn)
	_menu_entries.append(load_btn)

	var settings_btn := _calligraphy_entry("系统设置", "画质档位 · 五轨音量与阅读流速", "gear", _open_settings)
	menu.add_child(settings_btn)
	_menu_entries.append(settings_btn)

	var quit_btn := _calligraphy_entry("离开", "合上手账 · 暂别此世", "door", get_tree().quit)
	menu.add_child(quit_btn)
	_menu_entries.append(quit_btn)


func _open_settings() -> void:
	open_settings("")


func open_settings(initial_tab: String = "") -> void:
	if _picker != null and _picker.visible:
		_hide_picker()
	JournalUI.open_settings(initial_tab)


func close_settings(animated: bool = true) -> void:
	JournalUI.close_settings(animated)


func is_settings_open() -> bool:
	return JournalUI.is_settings_open()


func _build_continue_button() -> Button:
	var btn := Kit.create_tactile_button("", "dark_brass", _title_font, 26, 1.025, 0.97)
	btn.custom_minimum_size = Vector2(486.0, 90.0)
	btn.pressed.connect(_continue_journey)

	# Warm burnished gold accent bar on the left edge.
	var accent_bar := ColorRect.new()
	accent_bar.color = Kit.BRASS
	accent_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(accent_bar)
	accent_bar.anchor_top = 0.14
	accent_bar.anchor_bottom = 0.86
	accent_bar.offset_left = 4.0
	accent_bar.offset_right = 8.0

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	btn.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var seal := Kit.WaxSeal.new()
	seal.setup(Kit.WAX_GOLD, "star", 46.0)
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seal)

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 4)
	row.add_child(stack)

	var head := Kit.create_label("继续旅程", 27, Color("#fff3d8"), _title_font)
	stack.add_child(head)
	_continue_sub = Kit.create_label("", 15, Kit.BRASS, _body_font)
	_continue_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stack.add_child(_continue_sub)
	return btn


func _calligraphy_entry(label_text: String, sub_text: String, icon_kind: String, action: Callable) -> Button:
	var btn := Kit.create_tactile_button("", "ghost_gold", _title_font, 26)
	btn.custom_minimum_size = Vector2(486.0, 68.0)
	btn.pressed.connect(action)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	btn.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)

	var icon := Kit.create_micro_icon(icon_kind, 24.0, Kit.BRASS)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 1)
	row.add_child(words)

	var title_lbl := Kit.create_label(label_text, 26, Kit.IVORY, _title_font)
	title_lbl.add_theme_color_override("font_shadow_color", Color("#120a05cc"))
	title_lbl.add_theme_constant_override("shadow_offset_y", 2)
	words.add_child(title_lbl)
	var sub_lbl := Kit.create_label(sub_text, 15, Color("#c7b59a"), _body_font)
	words.add_child(sub_lbl)

	var pointer := Kit.create_micro_icon("star", 16.0, Kit.BRASS)
	pointer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pointer.modulate.a = 0.0
	row.add_child(pointer)

	btn.mouse_entered.connect(func() -> void:
		Motion.fade_alpha(pointer, 1.0, 0.16)
		title_lbl.add_theme_color_override("font_color", Color("#fff6e0")))
	btn.mouse_exited.connect(func() -> void:
		Motion.fade_alpha(pointer, 0.0, 0.18)
		title_lbl.add_theme_color_override("font_color", Kit.IVORY))
	return btn


func _build_picker() -> void:
	_picker_slot = Control.new()
	_picker_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picker_slot)
	_picker_slot.anchor_left = 0.48
	_picker_slot.anchor_top = 0.115
	_picker_slot.anchor_right = 0.955
	_picker_slot.anchor_bottom = 0.885

	var book := Kit.create_grimoire_book(Vector2(860.0, 780.0), 0.5, false)
	_picker = book["binding"] as PanelContainer
	var spread := book["spread"] as PanelContainer
	_picker_slot.add_child(_picker)
	_picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	spread.add_child(page)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("主角卷轴选择", _title_font, 26, Kit.WAX_GOLD)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(ribbon)
	var close_btn := Kit.create_icon_button("close", "合上", "dark_brass", _title_font, 18, Kit.BRASS)
	close_btn.custom_minimum_size = Vector2(106.0, 46.0)
	close_btn.pressed.connect(_hide_picker)
	heading.add_child(close_btn)

	page.add_child(Kit.create_gold_divider(0.0, true, 10.0))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	Kit.style_scrollbar(scroll.get_v_scroll_bar())

	var cards := VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 14)
	scroll.add_child(cards)

	for id: String in WorldBlackboard.catalog.presets:
		var preset: Dictionary = WorldBlackboard.catalog.presets[id]
		cards.add_child(_build_preset_card(id, preset))
	_picker.hide()


func _build_preset_card(id: String, preset: Dictionary) -> PanelContainer:
	var locked := bool(preset.get("locked", false))
	var card := Kit.create_folio_panel(Color("#eee3d0") if locked else Kit.PAPER_DEEP, 18, 16, 2 if locked else 5)
	if locked:
		card.modulate.a = 0.78
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	card.add_child(row)

	var thumb_frame := Kit.create_folio_panel(Color("#dfd0b6") if not locked else Color("#d9ccb6"), 5, 5, 1)
	thumb_frame.custom_minimum_size = Vector2(104.0, 134.0)
	thumb_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(thumb_frame)
	var thumb_stage := Control.new()
	thumb_stage.custom_minimum_size = Vector2(92.0, 122.0)
	thumb_frame.add_child(thumb_stage)
	var portrait_tex: Texture2D = null
	if not locked:
		var prof: Dictionary = preset.get("character", {}).get("profile", {})
		var path := str(prof.get("portrait", ""))
		if not path.is_empty():
			portrait_tex = KitArt.load_texture(path)
			var framing: Array = prof.get("portrait_crop", [])
			if portrait_tex != null and framing.size() == 4:
				var dims := portrait_tex.get_size()
				var crop := AtlasTexture.new()
				crop.atlas = portrait_tex
				crop.region = Rect2(Vector2(float(framing[0]), float(framing[1])) * dims,
					Vector2(float(framing[2]), float(framing[3])) * dims).intersection(Rect2(Vector2.ZERO, dims))
				portrait_tex = crop
	if portrait_tex != null:
		var img := TextureRect.new()
		img.texture = portrait_tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		thumb_stage.add_child(img)
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var marks := Kit.CornerMarks.new()
		marks.setup(Kit.WAX_GOLD, 3.0, 10.0)
		thumb_stage.add_child(marks)
		marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var lock_center := CenterContainer.new()
		thumb_stage.add_child(lock_center)
		lock_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var seal := Kit.WaxSeal.new()
		seal.setup(Color("#6b5c4e"), "lock", 52.0)
		lock_center.add_child(seal)

	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 5)
	row.add_child(words)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	words.add_child(title_row)
	title_row.add_child(Kit.create_label(str(preset.get("label", id)), 28, Kit.INK, _title_font))
	var tag_text := str(preset.get("tag", ""))
	if not tag_text.is_empty():
		title_row.add_child(Kit.create_status_badge(tag_text, not locked, _body_font, 14))

	var subtitle := Kit.create_label(str(preset.get("subtitle", "")), 18, Kit.SAPPHIRE if not locked else Kit.MUTED, _body_font)
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(subtitle)

	var summary_text := str(preset.get("summary", ""))
	if not summary_text.is_empty():
		var summary := Kit.create_label(summary_text, 16, Kit.MUTED, _body_font)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(summary)

	var start := Kit.create_icon_button("lock" if locked else "compass", "尚未启封" if locked else "启程", "subtle" if locked else "primary", _title_font, 19, Kit.MUTED if locked else Kit.BRASS)
	start.custom_minimum_size = Vector2(128.0, 52.0)
	start.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	start.disabled = locked
	start.pressed.connect(_start.bind(id))
	row.add_child(start)
	return card


func _animate_entrance() -> void:
	Motion.fade_in(_cover, 0.36)
	var delay := 0.05
	for entry: Control in _menu_entries:
		if not entry.visible:
			continue
		entry.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_interval(delay)
		tween.tween_callback(func() -> void:
			Motion.fade_in(entry, 0.28)
			Motion.spring(entry, ^"position:x", -30.0, 0.0, 0.38, 9.0, 7.0))
		delay += 0.07


func _refresh() -> void:
	_latest = SaveManager.get_latest_slot_id()
	var has_save := not _latest.is_empty()
	_continue_btn.visible = has_save
	if has_save:
		var info := SaveManager.slot_info(_latest)
		var compact_date := str(info.get("date_text", "")).replace("   ", " ")
		_continue_sub.text = "%s · %s · %s" % [
			str(info.get("character_name", "旅人")),
			compact_date,
			str(info.get("location_name", ""))
		]


func _continue_journey() -> void:
	if not _latest.is_empty():
		SaveManager.load_slot(_latest)


func _show_picker() -> void:
	if _picker.visible:
		return
	_picker.show()
	Motion.slide_drawer_in(_picker, 120.0)
	AudioManager.play_sfx("page_flip")


func _hide_picker() -> void:
	_picker.hide()
	Motion.cancel(_picker, ^"position:x")
	_picker.position.x = 0.0


func _start(id: String) -> void:
	SaveManager.new_game(id)
