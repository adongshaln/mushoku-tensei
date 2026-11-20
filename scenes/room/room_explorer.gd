extends Control

const Prop := preload("res://scenes/room/interactive_prop.gd")
const PlaceholderArt := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const ROOM_PATH := "res://data/rooms/migurd_cabin.json"
const DIALOGUE_SCENE := "res://scenes/dialogue/dialogue_view.tscn"
const COMBAT_SCENE := "res://scenes/combat/combat_view.tscn"
const MAP_SCENE := "res://scenes/world_map/world_atlas_view.tscn"
const ROOM_ART_OVERRIDE := "res://assets/rooms/migurd_cabin/bg.png"
const SIDE_MARGIN := 44.0
const DRAWER_WIDTH := 458.0
const LIGHT := [Color.WHITE, Color("#ffe8c8"), Color("#e7b185"), Color("#8a9ac1")]
const SLOT_ICONS := ["morning", "afternoon", "evening", "night"]
const SLOT_TONES := [Color("#e8b465"), Color("#f0d9a0"), Color("#e0906a"), Color("#9fc3dd")]

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

var _stage: Control
var _background: TextureRect
var _date: Label
var _slot_icon: Kit.MicroIcon
var _name_label: Label
var _wil_label: Label
var _hp_meter: ProgressBar
var _mp_meter: ProgressBar
var _hp_text: Label
var _mp_text: Label
var _buff_row: HBoxContainer
var _bag_group: HBoxContainer
var _bag_text: Label
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
	var menu := JournalUI.make_toolbar(_title_font)
	add_child(menu)
	menu.position = Vector2(SIDE_MARGIN, 153.0)
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
		if child is CanvasItem and child != _stage:
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
	theme.default_font_size = 23


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
	_background.modulate = LIGHT[int(WorldBlackboard.get_world_time()["slot"])]

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

	_nameplate = Kit.create_folio_panel(Kit.PAPER, 14, 5, 2)
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nameplate_text = Kit.create_label("", 22, Kit.INK, _title_font)
	_nameplate.add_child(_nameplate_text)
	_stage.add_child(_nameplate)
	_nameplate.hide()


func _build_header() -> void:
	var location := Kit.create_folio_panel(Kit.PAPER, 23, 14, 5)
	location.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(location)
	location.position = Vector2(SIDE_MARGIN, 36.0)
	var location_text := VBoxContainer.new()
	location_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_text.add_theme_constant_override("separation", 5)
	location.add_child(location_text)
	_add_text(location_text, "%s  ·  %s" % [_room.get("area", ""), _room.get("name", "")], 30, Kit.INK, _title_font)
	var date_row := HBoxContainer.new()
	date_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_row.add_theme_constant_override("separation", 9)
	location_text.add_child(date_row)
	_slot_icon = Kit.create_micro_icon("morning", 22.0, SLOT_TONES[0])
	date_row.add_child(_slot_icon)
	_date = _add_text(date_row, "", 21, Kit.MUTED)

	var status := Kit.create_folio_panel(Kit.WASH, 20, 14, 5)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	status.offset_right = -SIDE_MARGIN
	status.offset_left = -SIDE_MARGIN - 606.0
	status.offset_top = 36.0
	var status_text := VBoxContainer.new()
	status_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_text.add_theme_constant_override("separation", 8)
	status.add_child(status_text)

	var identity := HBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 12)
	status_text.add_child(identity)
	_name_label = _add_text(identity, "", 25, Kit.PAPER, _title_font)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var wil_badge := Kit.create_badge("", Kit.BLUE, _title_font, 19)
	identity.add_child(wil_badge)
	_wil_label = wil_badge.get_child(0) as Label

	var meters := HBoxContainer.new()
	meters.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meters.add_theme_constant_override("separation", 18)
	status_text.add_child(meters)
	var hp_group := HBoxContainer.new()
	hp_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_group.add_theme_constant_override("separation", 8)
	hp_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(hp_group)
	hp_group.add_child(Kit.create_micro_icon("hp", 19.0, Color("#e08a76")))
	_hp_meter = Kit.create_meter(Kit.VERMILLION, Color("#5a4436"))
	_hp_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_group.add_child(_hp_meter)
	_hp_text = _add_text(hp_group, "", 19, Kit.PAPER)
	var mp_group := HBoxContainer.new()
	mp_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_group.add_theme_constant_override("separation", 8)
	mp_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_child(mp_group)
	mp_group.add_child(Kit.create_micro_icon("drop", 19.0, Color("#8fc0dc")))
	_mp_meter = Kit.create_meter(Kit.BLUE, Color("#5a4436"))
	_mp_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mp_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mp_group.add_child(_mp_meter)
	_mp_text = _add_text(mp_group, "", 19, Kit.PAPER)

	var tray := HBoxContainer.new()
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_theme_constant_override("separation", 10)
	status_text.add_child(tray)
	_buff_row = HBoxContainer.new()
	_buff_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_row.add_theme_constant_override("separation", 8)
	_buff_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tray.add_child(_buff_row)
	_bag_group = HBoxContainer.new()
	_bag_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bag_group.add_theme_constant_override("separation", 7)
	tray.add_child(_bag_group)
	_bag_group.add_child(Kit.create_micro_icon("bag", 19.0, Color("#d9b36a")))
	_bag_text = _add_text(_bag_group, "", 19, Color("#ead5b7"))
	_story_status = _add_text(status_text, "", 19, Kit.PAPER)
	_story_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_drawer() -> void:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	slot.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	slot.offset_left = -SIDE_MARGIN - DRAWER_WIDTH
	slot.offset_right = -SIDE_MARGIN
	slot.offset_top = 215.0
	slot.offset_bottom = -140.0

	_drawer = Kit.create_folio_panel(Kit.PAPER, 30, 22, 9)
	slot.add_child(_drawer)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.resized.connect(_fit_drawer)
	_drawer.minimum_size_changed.connect(_fit_drawer, CONNECT_DEFERRED)

	var page := VBoxContainer.new()
	_drawer_page = page
	page.mouse_filter = Control.MOUSE_FILTER_PASS
	page.add_theme_constant_override("separation", 17)
	_drawer.add_child(page)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("诺缇雅的手账", _title_font, 24, Kit.AMBER)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(ribbon)
	var close_button := Kit.create_tactile_button("合上", "subtle", _title_font, 22)
	close_button.custom_minimum_size = Vector2(89, 53)
	close_button.pressed.connect(_close_drawer)
	heading.add_child(close_button)

	_add_rule(page)
	_entry_label = _add_text(page, "", 19, Kit.BLUE)
	_entry_name = _add_text(page, "", 42, Kit.INK, _title_font)
	_entry_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var portrait := PanelContainer.new()
	portrait.add_theme_stylebox_override("panel", Kit.style(Kit.PAPER_DEEP, 5, 5, 0))
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(portrait)
	_entry_image = TextureRect.new()
	_entry_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entry_image.custom_minimum_size = Vector2(0, 183)
	_entry_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_entry_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.add_child(_entry_image)
	var marks := Kit.CornerMarks.new()
	marks.setup(Kit.AMBER)
	portrait.add_child(marks)

	_entry_description = _add_text(page, "", 25, Kit.INK, _title_font)
	_entry_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry_description.add_theme_constant_override("line_spacing", 9)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(spacer)
	_add_rule(page)
	_entry_effect = _add_text(page, "", 20, Kit.BLUE)
	_entry_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_action = Kit.create_tactile_button("", "primary", _title_font, 25)
	_action.custom_minimum_size.y = 68
	_action.pressed.connect(_perform_action)
	page.add_child(_action)
	_combat_entries = VBoxContainer.new()
	_combat_entries.add_theme_constant_override("separation", 10)
	page.add_child(_combat_entries)
	_combat_entries.hide()
	_drawer_map_button = Kit.create_tactile_button("展开世界舆图", "primary", _title_font, 22)
	_drawer_map_button.custom_minimum_size.y = 61
	_drawer_map_button.pressed.connect(_open_map)
	page.add_child(_drawer_map_button)
	_drawer_map_button.hide()
	_fit_drawer()
	_drawer.hide()


func _build_feedback() -> void:
	var map_button := Kit.create_tactile_button("展开世界舆图", "primary", _title_font, 24)
	map_button.custom_minimum_size = Vector2(260, 65)
	add_child(map_button)
	map_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	map_button.offset_left = -SIDE_MARGIN - 236.0 - 12.0 - 260.0
	map_button.offset_right = -SIDE_MARGIN - 236.0 - 12.0
	map_button.offset_top = -100.0
	map_button.offset_bottom = -35.0
	map_button.pressed.connect(_open_map)
	_sense = Kit.create_tactile_button("感知高亮    Tab", "accent", _title_font, 24)
	_sense.toggle_mode = true
	_sense.custom_minimum_size = Vector2(236, 65)
	add_child(_sense)
	_sense.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_sense.offset_left = -SIDE_MARGIN - 236.0
	_sense.offset_right = -SIDE_MARGIN
	_sense.offset_top = -100.0
	_sense.offset_bottom = -35.0
	_sense.toggled.connect(_set_sense)

	_toast_panel = Kit.create_folio_panel(Kit.WASH, 24, 13, 5)
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_panel)
	_toast_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_toast_panel.offset_left = SIDE_MARGIN
	_toast_panel.offset_top = -110.0
	_toast_panel.offset_right = 1050.0
	_toast_panel.offset_bottom = -35.0
	_toast_text = Kit.create_label("", 23, Kit.PAPER, _title_font)
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
		if _over_controls(event.position):
			_set_hovered(null)
		else:
			_set_hovered(_prop_at(event.position))
		_motion_target = (event.position / size - Vector2(0.5, 0.5)) * 9.0


func _unhandled_input(event: InputEvent) -> void:
	if JournalUI.is_open() or SceneTransition.is_busy():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_activate_at(event.position)


func _over_controls(point: Vector2) -> bool:
	return _sense.get_global_rect().has_point(point) or (
		_drawer.visible and _drawer.get_global_rect().has_point(point)
	)


func _prop_at(viewport_point: Vector2) -> Prop:
	var stage_point: Vector2 = _stage.get_global_transform_with_canvas().affine_inverse() * viewport_point
	for prop: Prop in _props:
		if prop.contains(stage_point):
			return prop
	return null


func _activate_at(point: Vector2) -> void:
	if _over_controls(point):
		return
	var picked := _prop_at(point)
	if picked != null:
		_open_drawer(picked)
		get_viewport().set_input_as_handled()
	elif _selected != null:
		_close_drawer()


func _set_hovered(prop: Prop) -> void:
	if _hovered == prop:
		return
	_hovered = prop
	if prop != null:
		AudioManager.play_sfx("ui_hover")
	_refresh_highlights()


func _set_sense(enabled: bool) -> void:
	_sense_enabled = enabled
	_refresh_highlights()


func _refresh_highlights() -> void:
	for prop: Prop in _props:
		var state := 1 if _sense_enabled else 0
		if prop == _selected or prop == _hovered:
			state = 2
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
	var preview_aspect := (DRAWER_WIDTH - 70.0) / _entry_image.custom_minimum_size.y
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
	_entry_image.custom_minimum_size.y = 127 if _combat_entries.visible else 183
	_drawer_page.add_theme_constant_override("separation", 10 if _combat_entries.visible else 17)
	for entry: Dictionary in entries:
		var button := Kit.create_tactile_button(str(entry["label"]), "secondary", _title_font, 22)
		button.custom_minimum_size.y = 61
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
	_date.text = WorldBlackboard.date_text()
	var slot := int(WorldBlackboard.get_world_time()["slot"])
	_slot_icon.setup(SLOT_ICONS[slot], 22.0, SLOT_TONES[slot])
	_slot_icon.queue_redraw()
	var protagonist := WorldBlackboard.get_protagonist()
	var hp: Dictionary = protagonist.get("hp", {})
	var mp: Dictionary = protagonist.get("mp", {})
	var will := WorldBlackboard.get_check_breakdown("WIL")
	_name_label.text = str(protagonist.get("name", ""))
	_wil_label.text = "意志 %d · 检定 %+d" % [int(will["effective_stat"]), int(will["total_mod"])]
	_hp_meter.max_value = maxi(1, int(hp.get("max", 1)))
	_hp_meter.value = int(hp.get("current", 0))
	_mp_meter.max_value = maxi(1, int(mp.get("max", 1)))
	_mp_meter.value = int(mp.get("current", 0))
	_hp_text.text = "%d/%d" % [int(hp.get("current", 0)), int(hp.get("max", 0))]
	_mp_text.text = "%d/%d" % [int(mp.get("current", 0)), int(mp.get("max", 0))]
	var buffs := WorldBlackboard.get_buff_names()
	for bonus: Dictionary in will["bonus_list"]:
		var index := buffs.find(str(bonus["name"]))
		if index >= 0:
			buffs[index] = "%+d %s" % [int(bonus["value"]), str(bonus["name"])]
	if buffs != _last_buffs:
		_last_buffs = buffs.duplicate()
		for child: Node in _buff_row.get_children():
			_buff_row.remove_child(child)
			child.queue_free()
		for buff_name: String in buffs:
			var tone := Kit.AMBER if buff_name.begins_with("+") or buff_name.begins_with("-") else Kit.GREEN
			if buff_name == WorldBlackboard.TRAVEL_FATIGUE_NAME:
				tone = Kit.VERMILLION
			var badge := Kit.create_badge(buff_name, tone, _title_font, 18)
			_buff_row.add_child(badge)
			Motion.pop_badge(badge, 0.44)
	var count := WorldBlackboard.get_inventory_count()
	_bag_text.text = "行囊 %d" % count
	if count != _bag_count:
		_bag_count = count
		Motion.pop_badge(_bag_group, 0.4)
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
	_story_status.text = "    /    ".join(updates)
	_story_status.visible = not updates.is_empty()


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
	var ambient: Color = LIGHT[int(WorldBlackboard.get_world_time()["slot"])]
	if _light_tween != null:
		_light_tween.kill()
	_light_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_light_tween.tween_property(_background, "modulate", ambient, 0.68)
	_light_tween.tween_property(_entry_image, "modulate", ambient, 0.68)


func _label(text: String, type_size: int, color: Color, font: Font = null) -> Label:
	return Kit.create_label(text, type_size, color, font)


func _add_text(parent: Control, text: String, type_size: int, color: Color, font: Font = null) -> Label:
	var label := _label(text, type_size, color, font)
	parent.add_child(label)
	return label


func _add_rule(parent: Control) -> void:
	var rule := ColorRect.new()
	rule.color = Color("#b59c7c")
	rule.custom_minimum_size.y = 1.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)


