extends Control

const Prop := preload("res://scenes/room/interactive_prop.gd")
const PlaceholderArt := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const CABIN_AMBIENCE := preload("res://shaders/cabin_ambience.gdshader")
const ROOM_PATH := "res://data/rooms/migurd_cabin.json"
const DIALOGUE_SCENE := "res://scenes/dialogue/dialogue_view.tscn"
const COMBAT_SCENE := "res://scenes/combat/combat_view.tscn"
const MAP_SCENE := "res://scenes/world_map/world_atlas_view.tscn"
const ROOM_ART_OVERRIDE := "res://assets/rooms/migurd_cabin/bg.png"
const SIDE_MARGIN := 36.0
const DRAWER_WIDTH := 460.0
const LIGHT := [Color.WHITE, Color("#ffe8c8"), Color("#e7b185"), Color("#8a9ac1")]
const NIGHT_FACTORS := [0.0, 0.0, 0.45, 1.0]
const SLOT_ICONS := ["morning", "afternoon", "evening", "night"]
const SLOT_TONES := [Color("#f0c272"), Color("#f8df9f"), Color("#e5966a"), Color("#9fc7e4")]

var _room: Dictionary
var _props: Array[Prop] = []
var _hovered: Prop
var _selected: Prop
var _sense_enabled := false
var _stage_center := Vector2.ZERO
var _parallax := Vector2.ZERO
var _motion_target := Vector2.ZERO
var _art_missing := false
var _body_font: SystemFont
var _title_font: SystemFont
var _last_buffs: PackedStringArray
var _bag_count := -1
var _portrait_path := ""

var _stage: Control
var _background: TextureRect
var _ambience_rect: ColorRect
var _ambience_mat: ShaderMaterial
var _medallion: Kit.PortraitMedallion
var _date: Label
var _slot_icon: Kit.MicroIcon
var _name_label: Label
var _wil_badge_holder: HBoxContainer
var _hp_meter: ProgressBar
var _mp_meter: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _buff_row: HBoxContainer
var _bag_group: HBoxContainer
var _bag_text: Label
var _story_status_panel: PanelContainer
var _story_status: Label
var _nameplate: PanelContainer
var _nameplate_text: Label
var _sense: Button
var _drawer: PanelContainer
var _entry_label: Label
var _entry_name: Label
var _entry_description: Label
var _entry_image: TextureRect
var _entry_effect: Label
var _action: Button
var _drawer_page: VBoxContainer
var _combat_entries: VBoxContainer
var _drawer_map_button: Button
var _toast_panel: PanelContainer
var _toast_text: Label
var _toast_timer: Timer
var _light_tween: Tween


func _ready() -> void:
	clip_contents = true
	_setup_fonts()
	_room = WorldBlackboard.read_config(ROOM_PATH)
	_build_stage()
	_build_header()
	_build_drawer()
	_build_feedback()
	resized.connect(_fit_stage)
	WorldBlackboard.world_time_changed.connect(_on_time_changed)
	WorldBlackboard.protagonist_changed.connect(_refresh_header)
	WorldBlackboard.buffs_changed.connect(_refresh_header)
	WorldBlackboard.inventory_changed.connect(_refresh_header)
	WorldBlackboard.flags_changed.connect(_refresh_flags)
	_fit_stage()
	_refresh_header()


func get_dice_hud_items() -> Array[CanvasItem]:
	var items: Array[CanvasItem] = []
	for child: Node in get_children():
		if child is CanvasItem and child != _stage and child != _ambience_rect:
			items.append(child)
	for child: Node in _stage.get_children():
		if child is CanvasItem and child != _background:
			items.append(child)
	return items


func _setup_fonts() -> void:
	_body_font = Kit.make_font()
	_title_font = Kit.make_font(true)
	theme = Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 22


func _build_stage() -> void:
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_background = TextureRect.new()
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_SCALE
	_stage.add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_background.texture = PlaceholderArt.load_texture(ROOM_ART_OVERRIDE)
	if _background.texture == null:
		_background.texture = PlaceholderArt.load_texture(str(_room.get("background", "")))
	_art_missing = _background.texture == null
	if _art_missing:
		_background.texture = PlaceholderArt.make_background()
	var cur_slot := int(WorldBlackboard.get_world_time()["slot"])
	_background.modulate = LIGHT[cur_slot]

	for definition: Dictionary in _room.get("hotspots", []):
		var texture := PlaceholderArt.load_texture(str(definition["mask"]))
		var mask: Image
		if texture != null:
			mask = texture.get_image()
		if mask == null or not mask.get_used_rect().has_area():
			var polygon := PackedVector2Array()
			for point: Array in definition["polygon_uv"]:
				polygon.append(Vector2(float(point[0]), float(point[1])))
			mask = PlaceholderArt.make_mask(polygon)
		if not mask.get_used_rect().has_area():
			continue
		var prop := Prop.new()
		prop.configure(definition, mask, float(_room.get("alpha_cutoff", 0.1)), _art_missing)
		_stage.add_child(prop)
		_props.append(prop)
	_props.sort_custom(func(left: Prop, right: Prop) -> bool:
		return int(left.definition.get("hit_priority", 0)) > int(right.definition.get("hit_priority", 0))
	)

	# Atmospheric hearth glow & floating sunlit dust motes over the room illustration.
	_ambience_rect = ColorRect.new()
	_ambience_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ambience_mat = ShaderMaterial.new()
	_ambience_mat.shader = CABIN_AMBIENCE
	_ambience_mat.set_shader_parameter("night_factor", NIGHT_FACTORS[cur_slot])
	_ambience_rect.material = _ambience_mat
	add_child(_ambience_rect)
	_ambience_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Floating smoked-glass hover nameplate with brass star emblem.
	_nameplate = Kit.create_smoked_hud_panel(16, 7, 8)
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var np_row := HBoxContainer.new()
	np_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	np_row.add_theme_constant_override("separation", 7)
	_nameplate.add_child(np_row)
	var np_star := Kit.create_micro_icon("star", 14.0, Kit.BRASS)
	np_star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	np_row.add_child(np_star)
	_nameplate_text = Kit.create_label("", 21, Kit.IVORY, _title_font)
	np_row.add_child(_nameplate_text)
	_stage.add_child(_nameplate)
	_nameplate.hide()


func _build_header() -> void:
	# Unified Top-Left Smoked-Glass Character Medallion + Kalendarium Crest.
	var crest := Kit.create_smoked_hud_panel(16, 12, 10)
	crest.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(crest)
	crest.position = Vector2(SIDE_MARGIN, 28.0)
	crest.custom_minimum_size.x = 640.0

	var root_row := HBoxContainer.new()
	root_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_row.add_theme_constant_override("separation", 14)
	crest.add_child(root_row)

	# Clickable circular portrait medallion -> opens Character Grimoire.
	var medallion_btn := Button.new()
	medallion_btn.flat = true
	medallion_btn.custom_minimum_size = Vector2(74.0, 74.0)
	medallion_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	medallion_btn.tooltip_text = "翻开角色手账 (C)"
	medallion_btn.pressed.connect(JournalUI.open_character)
	AudioManager.bind_ui(medallion_btn)
	Motion.attach_button_feel(medallion_btn, 1.05, 0.94, false)
	root_row.add_child(medallion_btn)
	_medallion = Kit.PortraitMedallion.new()
	_medallion.setup(null, 74.0, Kit.BRASS)
	medallion_btn.add_child(_medallion)
	_medallion.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	root_row.add_child(col)

	# Row 1: Character Name + Room Name + Will Check Badge.
	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_theme_constant_override("separation", 12)
	col.add_child(top_row)
	_name_label = _add_text(top_row, "", 24, Kit.IVORY, _title_font)
	var place_lbl := _add_text(top_row, "%s · %s" % [_room.get("area", ""), _room.get("name", "")], 18, Kit.BRASS, _title_font)
	place_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wil_badge_holder = HBoxContainer.new()
	_wil_badge_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_row.add_child(_wil_badge_holder)

	# Row 2: Compact HP & MP jewelled meters.
	var meters := HBoxContainer.new()
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meters.add_theme_constant_override("separation", 16)
	col.add_child(meters)

	var hp_group := HBoxContainer.new()
	hp_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_group.add_theme_constant_override("separation", 7)
	hp_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(hp_group)
	hp_group.add_child(Kit.create_micro_icon("hp", 17.0, Color("#e48774")))
	_hp_meter = Kit.create_meter(Kit.VERMILLION, Color("#3f2e24"), 10.0)
	_hp_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_group.add_child(_hp_meter)
	_hp_text = _add_text(hp_group, "", 16, Kit.IVORY)

	var mp_group := HBoxContainer.new()
	mp_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_group.add_theme_constant_override("separation", 7)
	mp_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(mp_group)
	mp_group.add_child(Kit.create_micro_icon("drop", 17.0, Color("#88c1e3")))
	_mp_meter = Kit.create_meter(Kit.SAPPHIRE, Color("#3f2e24"), 10.0)
	_mp_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mp_group.add_child(_mp_meter)
	_mp_text = _add_text(mp_group, "", 16, Kit.IVORY)

	# Row 3: Kalendarium time dial + Bag count + Frosted Status Pills.
	var meta_row := HBoxContainer.new()
	meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_theme_constant_override("separation", 12)
	col.add_child(meta_row)

	var date_grp := HBoxContainer.new()
	date_grp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_grp.add_theme_constant_override("separation", 7)
	meta_row.add_child(date_grp)
	_slot_icon = Kit.create_micro_icon("morning", 18.0, SLOT_TONES[0])
	_slot_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	date_grp.add_child(_slot_icon)
	_date = _add_text(date_grp, "", 16, Color("#decab0"))

	_bag_group = HBoxContainer.new()
	_bag_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_group.add_theme_constant_override("separation", 5)
	meta_row.add_child(_bag_group)
	var bag_ic := Kit.create_micro_icon("bag", 16.0, Kit.BRASS)
	bag_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bag_group.add_child(bag_ic)
	_bag_text = _add_text(_bag_group, "", 16, Kit.BRASS)

	_buff_row = HBoxContainer.new()
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_row.add_theme_constant_override("separation", 6)
	_buff_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.add_child(_buff_row)

	# Sleek Top-Right Brass Icon Dock (Journal / Save / Title) + Story Whisper.
	var dock_col := VBoxContainer.new()
	dock_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dock_col.add_theme_constant_override("separation", 8)
	add_child(dock_col)
	dock_col.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	dock_col.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock_col.offset_right = -SIDE_MARGIN
	dock_col.offset_left = -SIDE_MARGIN - 420.0
	dock_col.offset_top = 28.0

	var menu := JournalUI.make_toolbar(_title_font)
	menu.alignment = BoxContainer.ALIGNMENT_END
	dock_col.add_child(menu)

	_story_status_panel = Kit.create_smoked_hud_panel(14, 6, 4)
	_story_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_story_status_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	_story_status = Kit.create_label("", 16, Kit.BRASS, _body_font)
	_story_status_panel.add_child(_story_status)
	dock_col.add_child(_story_status_panel)
	_story_status_panel.hide()


func _build_drawer() -> void:
	# Strictly bounded between top-right dock (y=116) and bottom-right controls (bottom=-114) -> ZERO overlap!
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	slot.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	slot.offset_left = -SIDE_MARGIN - DRAWER_WIDTH
	slot.offset_right = -SIDE_MARGIN
	slot.offset_top = 116.0
	slot.offset_bottom = -114.0

	_drawer = Kit.create_folio_panel(Kit.PAPER, 26, 20, 12)
	slot.add_child(_drawer)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.resized.connect(_fit_drawer)
	_drawer.minimum_size_changed.connect(_fit_drawer, CONNECT_DEFERRED)

	var page := VBoxContainer.new()
	_drawer_page = page
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_theme_constant_override("separation", 13)
	_drawer.add_child(page)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 10)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("诺缇雅的手账", _title_font, 22, Kit.WAX_GOLD)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(ribbon)
	var close_button := Kit.create_icon_button("close", "合上", "dark_brass", _title_font, 17, Kit.BRASS)
	close_button.custom_minimum_size = Vector2(96.0, 44.0)
	close_button.pressed.connect(_close_drawer)
	heading.add_child(close_button)

	_entry_label = _add_text(page, "", 17, Kit.SAPPHIRE)
	_entry_name = _add_text(page, "", 36, Kit.INK, _title_font)
	_entry_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var portrait := Kit.create_folio_panel(Kit.PAPER_DEEP, 5, 5, 2)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(portrait)
	_entry_image = TextureRect.new()
	_entry_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_image.custom_minimum_size = Vector2(0, 168)
	_entry_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_entry_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.add_child(_entry_image)
	var marks := Kit.CornerMarks.new()
	marks.setup(Kit.WAX_GOLD, 6.0, 16.0)
	portrait.add_child(marks)
	marks.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_entry_description = _add_text(page, "", 22, Kit.INK, _title_font)
	_entry_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry_description.add_theme_constant_override("line_spacing", 8)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(spacer)
	page.add_child(Kit.create_gold_divider(0.0, false, 8.0))
	_entry_effect = _add_text(page, "", 18, Kit.SAPPHIRE)
	_entry_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action = Kit.create_tactile_button("", "primary", _title_font, 22)
	_action.custom_minimum_size.y = 58
	_action.pressed.connect(_perform_action)
	page.add_child(_action)
	_combat_entries = VBoxContainer.new()
	_combat_entries.add_theme_constant_override("separation", 8)
	page.add_child(_combat_entries)
	_combat_entries.hide()
	_drawer_map_button = Kit.create_icon_button("compass", "展开世界舆图", "primary", _title_font, 20, Kit.BRASS)
	_drawer_map_button.custom_minimum_size.y = 54
	_drawer_map_button.pressed.connect(_open_map)
	page.add_child(_drawer_map_button)
	_drawer_map_button.hide()
	_fit_drawer()
	_drawer.hide()


func _build_feedback() -> void:
	var bottom_bar := HBoxContainer.new()
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	bottom_bar.add_theme_constant_override("separation", 12)
	add_child(bottom_bar)
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bottom_bar.offset_left = -SIDE_MARGIN - 540.0
	bottom_bar.offset_right = -SIDE_MARGIN
	bottom_bar.offset_top = -88.0
	bottom_bar.offset_bottom = -28.0

	var map_button := Kit.create_icon_button("compass", "展开世界舆图", "primary", _title_font, 21, Kit.BRASS)
	map_button.custom_minimum_size = Vector2(220.0, 56.0)
	map_button.pressed.connect(_open_map)
	bottom_bar.add_child(map_button)

	_sense = Kit.create_icon_button("eye", "感知高亮  Tab", "dark_brass", _title_font, 20, Kit.BRASS)
	_sense.toggle_mode = true
	_sense.custom_minimum_size = Vector2(210.0, 56.0)
	_sense.toggled.connect(_set_sense)
	bottom_bar.add_child(_sense)

	_toast_panel = Kit.create_smoked_hud_panel(22, 12, 8)
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_panel)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_panel.offset_left = SIDE_MARGIN
	_toast_panel.offset_top = -94.0
	_toast_panel.offset_right = 920.0
	_toast_panel.offset_bottom = -28.0
	_toast_text = Kit.create_label("", 20, Kit.IVORY, _title_font)
	_toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_panel.add_child(_toast_text)
	_toast_panel.hide()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_toast_panel.hide)
	add_child(_toast_timer)


func _fit_stage() -> void:
	var art_size := _background.texture.get_size()
	var scale_to_fit := minf(size.x / art_size.x, size.y / art_size.y)
	_stage.size = art_size * scale_to_fit * 1.008
	_stage_center = (size - _stage.size) * 0.5
	_stage.position = _stage_center + _parallax
	for prop: Prop in _props:
		prop.fit_to(_stage.size)
	_place_nameplate()


func _fit_drawer() -> void:
	_drawer.size = _drawer.get_parent_control().size


func _process(delta: float) -> void:
	_parallax = _parallax.lerp(_motion_target, 1.0 - exp(-delta * 9.0))
	_stage.position = _stage_center + _parallax


func _input(event: InputEvent) -> void:
	if JournalUI.handle_scene_input(event) or SceneTransition.is_busy():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_sense.button_pressed = not _sense.button_pressed
			AudioManager.play_sfx("ui_click")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _selected != null:
			_close_drawer()
			get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			_set_hovered(null)
			_motion_target = Vector2.ZERO
			return
		var relative: Vector2 = (event.position / size - Vector2(0.5, 0.5)) * 2.0
		_motion_target = Vector2(-relative.x * 8.0, -relative.y * 5.0)
		if _over_drawer(event.position):
			_set_hovered(null)
		else:
			_set_hovered(_pick_prop(event.position))


func _unhandled_input(event: InputEvent) -> void:
	if JournalUI.is_open() or SceneTransition.is_busy():
		return
	var pressed := false
	var point := Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
		point = event.position
	elif event is InputEventScreenTouch and event.pressed:
		pressed = true
		point = event.position
	if not pressed or _over_drawer(point):
		return
	var picked := _pick_prop(point)
	if picked != null:
		_open_drawer(picked)
		get_viewport().set_input_as_handled()
	elif _selected != null:
		_close_drawer()
		get_viewport().set_input_as_handled()


func _over_drawer(point: Vector2) -> bool:
	return _drawer.visible and _drawer.get_global_rect().has_point(point)


func _pick_prop(point: Vector2) -> Prop:
	var local := point - _stage.position
	for prop: Prop in _props:
		if prop.contains(local):
			return prop
	return null


func _set_hovered(prop: Prop) -> void:
	if _hovered == prop:
		return
	_hovered = prop
	if _hovered != null:
		AudioManager.play_sfx("ui_hover")
	_refresh_highlights()


func _set_sense(enabled: bool) -> void:
	_sense_enabled = enabled
	_refresh_highlights()


func _refresh_highlights() -> void:
	for prop: Prop in _props:
		var state := 0
		if prop == _selected:
			state = 3
		elif prop == _hovered:
			state = 2
		elif _sense_enabled:
			state = 1
		prop.set_highlight(state)
	_place_nameplate()


func _place_nameplate() -> void:
	var prop := _hovered if _hovered != null else _selected
	if prop == null:
		_nameplate.hide()
		return
	_nameplate_text.text = str(prop.definition["title"])
	_nameplate.reset_size()
	var bounds := prop.source_bounds
	var anchor := Vector2(bounds.get_center().x, bounds.position.y) * _stage.size
	_nameplate.position = Vector2(
		clampf(anchor.x - _nameplate.size.x * 0.5, 18.0, _stage.size.x - _nameplate.size.x - 18.0),
		maxf(anchor.y - _nameplate.size.y - 13.0, 146.0)
	)
	_nameplate.show()


func _open_drawer(prop: Prop) -> void:
	var opening := _selected == null
	if _selected != prop:
		AudioManager.play_sfx("page_flip")
	_selected = prop
	var definition := prop.definition
	_entry_label.text = str(definition["label"])
	_entry_name.text = str(definition["title"])
	var seen := bool(definition["once"]) and WorldBlackboard.has_performed(_action_id())
	var progress := _active_progress(definition)
	_entry_description.text = str(definition["result"] if seen else progress.get("description", definition["description"]))
	_build_combat_entries(definition.get("combat_entries", []))
	_drawer_map_button.visible = str(definition["id"]) == "curtain"
	var art_size := _background.texture.get_size()
	var bounds := prop.source_bounds
	var region := Rect2(bounds.position * art_size, bounds.size * art_size).grow(18.0)
	var preview_aspect := (DRAWER_WIDTH - 64.0) / _entry_image.custom_minimum_size.y
	var crop_size := Vector2(
		maxf(region.size.x, region.size.y * preview_aspect),
		maxf(region.size.y, region.size.x / preview_aspect)
	).min(art_size)
	var crop_origin := (region.get_center() - crop_size * 0.5).clamp(Vector2.ZERO, art_size - crop_size)
	var closeup := AtlasTexture.new()
	closeup.atlas = _background.texture
	closeup.region = Rect2(crop_origin, crop_size)
	closeup.filter_clip = true
	_entry_image.texture = closeup
	_entry_image.modulate = _background.modulate
	_refresh_action()
	_refresh_highlights()
	if not _drawer.visible:
		_drawer.show()
		Motion.slide_drawer_in(_drawer, DRAWER_WIDTH + SIDE_MARGIN)
	elif opening:
		Motion.slide_drawer_in(_drawer, _drawer.position.x)
	_fit_drawer()


func _build_combat_entries(entries: Array) -> void:
	for child: Node in _combat_entries.get_children():
		_combat_entries.remove_child(child)
		child.queue_free()
	_combat_entries.visible = not entries.is_empty()
	_entry_image.custom_minimum_size.y = 122 if _combat_entries.visible else 168
	_drawer_page.add_theme_constant_override("separation", 8 if _combat_entries.visible else 13)
	for entry: Dictionary in entries:
		var button := Kit.create_tactile_button(str(entry["label"]), "secondary", _title_font, 20)
		button.custom_minimum_size.y = 56
		button.pressed.connect(_enter_combat.bind(str(entry["preset"])))
		_combat_entries.add_child(button)


func _enter_combat(preset: String) -> void:
	SceneTransition.change_to(COMBAT_SCENE, {"combat_preset": preset, "return_scene": scene_file_path})


func _open_map() -> void:
	AudioManager.play_sfx("map_unfold")
	SceneTransition.change_to(MAP_SCENE, {"return_scene": scene_file_path})


func _close_drawer() -> void:
	_selected = null
	_refresh_highlights()
	Motion.slide_drawer_out(_drawer, DRAWER_WIDTH + SIDE_MARGIN).finished.connect(_drawer.hide)


func _action_id() -> String:
	return "%s/%s" % [_room["id"], _selected.definition["id"]]


func _refresh_action() -> void:
	if _selected == null:
		return
	var definition := _selected.definition
	var done := bool(definition["once"]) and WorldBlackboard.has_performed(_action_id())
	_action.disabled = done
	_action.text = "已完成" if done else str(definition["action"])
	var cost := int(definition["time_cost"])
	if cost > 0:
		_action.text += "  [消耗 %d 时段]" % cost
	_entry_effect.text = str(definition["effect_preview"])
	var effect: Dictionary = definition["effect"]
	if effect["type"] == "counter":
		_entry_effect.text += "    当前 %d" % int(WorldBlackboard.get_flag(effect["id"], 0))


func _perform_action() -> void:
	if _selected == null or SceneTransition.is_busy():
		return
	var definition := _selected.definition
	var effect: Dictionary = definition["effect"]
	if effect["type"] == "dialogue":
		SceneTransition.change_to(DIALOGUE_SCENE, {
			"dialogue_id": effect["id"],
			"return_scene": scene_file_path
		})
		return
	var cost := int(definition["time_cost"])
	if not WorldBlackboard.perform(_action_id(), bool(definition["once"]), effect, cost):
		return
	if str(definition["id"]) == "storage_jar":
		WorldBlackboard.modify_stat("WIL", 1, "通过一段时间的锻炼，诺缇雅的意志提升了")
	_entry_description.text = str(definition["result"])
	var feedback := str(definition["effect_preview"])
	if effect["type"] == "observe":
		feedback = str(definition["result"])
	elif cost > 0:
		feedback += "   ·   已经过 %d 时段" % cost
	_toast_text.text = feedback
	_toast_panel.show()
	Motion.pop_badge(_toast_panel, 0.42)
	_toast_timer.start(3.4)
	_refresh_action()


func _refresh_header() -> void:
	_date.text = WorldBlackboard.date_text().replace("   ", " ")
	var slot := int(WorldBlackboard.get_world_time()["slot"])
	_slot_icon.setup(SLOT_ICONS[slot], 18.0, SLOT_TONES[slot])
	var p_path := str(WorldBlackboard.profile.get("portrait", ""))
	if p_path != _portrait_path:
		_portrait_path = p_path
		_medallion.set_portrait(PlaceholderArt.load_texture(p_path) if not p_path.is_empty() else null)
	var protagonist := WorldBlackboard.get_protagonist()
	var hp: Dictionary = protagonist.get("hp", {})
	var mp: Dictionary = protagonist.get("mp", {})
	var will := WorldBlackboard.get_check_breakdown("WIL")
	_name_label.text = str(protagonist.get("name", ""))
	for child: Node in _wil_badge_holder.get_children():
		_wil_badge_holder.remove_child(child)
		child.queue_free()
	var wil_mod := int(will["total_mod"])
	_wil_badge_holder.add_child(Kit.create_status_badge("意志 %d (%+d)" % [int(will["effective_stat"]), wil_mod], wil_mod >= 0, _title_font, 15))
	_hp_meter.max_value = maxi(1, int(hp.get("max", 1)))
	_hp_meter.value = int(hp.get("current", 0))
	_mp_meter.max_value = maxi(1, int(mp.get("max", 1)))
	_mp_meter.value = int(mp.get("current", 0))
	_hp_text.text = "%d/%d" % [int(hp.get("current", 0)), int(hp.get("max", 0))]
	_mp_text.text = "%d/%d" % [int(mp.get("current", 0)), int(mp.get("max", 0))]

	var statuses := WorldBlackboard.active_statuses()
	var names := PackedStringArray()
	for s: Dictionary in statuses:
		names.append(str(s.get("name", "")))
	if names != _last_buffs:
		_last_buffs = names.duplicate()
		for child: Node in _buff_row.get_children():
			_buff_row.remove_child(child)
			child.queue_free()
		for s: Dictionary in statuses:
			var pol := WorldBlackboard.status_polarity(s)
			var badge := Kit.create_status_badge(str(s.get("name", s.get("id", ""))), pol >= 0, _body_font, 14)
			_buff_row.add_child(badge)
			Motion.pop_badge(badge, 0.40)

	var count := WorldBlackboard.get_inventory_count()
	_bag_text.text = "行囊 %d" % count
	if count != _bag_count:
		_bag_count = count
		Motion.pop_badge(_bag_group, 0.38)
	var updates := PackedStringArray()
	for definition: Dictionary in _room.get("hotspots", []):
		var progress := _active_progress(definition)
		if not progress.is_empty():
			updates.append(str(progress["text"]))
			break
	var combat: Dictionary = _room.get("combat_progress", {})
	if not combat.is_empty():
		var outcome := str(WorldBlackboard.get_flag(str(combat["flag"]), ""))
		if combat["labels"].has(outcome):
			updates.append(str(combat["labels"][outcome]))
	_story_status.text = "  ·  ".join(updates)
	_story_status_panel.visible = not updates.is_empty()


func _refresh_flags() -> void:
	_refresh_action()
	_refresh_header()


func _active_progress(definition: Dictionary) -> Dictionary:
	for progress: Dictionary in definition.get("progress", []):
		if WorldBlackboard.get_flag(str(progress["flag"]), false):
			return progress
	return {}


func _on_time_changed() -> void:
	_refresh_header()
	var slot := int(WorldBlackboard.get_world_time()["slot"])
	var ambient: Color = LIGHT[slot]
	if _light_tween != null:
		_light_tween.kill()
	_light_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(_background, "modulate", ambient, 0.68)
	_light_tween.tween_property(_entry_image, "modulate", ambient, 0.68)
	if _ambience_mat != null:
		_light_tween.tween_method(func(v: float) -> void:
			_ambience_mat.set_shader_parameter("night_factor", v),
			float(_ambience_mat.get_shader_parameter("night_factor")), NIGHT_FACTORS[slot], 0.68)


func _label(text: String, type_size: int, color: Color, font: Font = null) -> Label:
	return Kit.create_label(text, type_size, color, font)


func _add_text(parent: Control, text: String, type_size: int, color: Color, font: Font = null) -> Label:
	var label := _label(text, type_size, color, font)
	parent.add_child(label)
	return label
