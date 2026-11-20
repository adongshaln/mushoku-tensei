extends Control

const Block := preload("res://scenes/world_map/map_region_block.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Art := preload("res://core/placeholder_art_factory.gd")
const MAP_PATH := "res://data/maps/demon_continent.json"
const ROOM_SCENE := "res://scenes/room/room_explorer.tscn"
const SIDE_MARGIN := 34.0
const DRAWER_WIDTH := 470.0
const LIGHT := [Color.WHITE, Color("#fff2da"), Color("#f0c9a0"), Color("#a8b4d8")]
const SLOT_ICONS := ["morning", "afternoon", "evening", "night"]
const SLOT_TONES := [Color("#e8b465"), Color("#f0d9a0"), Color("#e0906a"), Color("#9fc3dd")]


class RouteCanvas extends Control:
	var segments: Array[Dictionary] = []
	var highlight_key := ""
	var flow := 0.0

	func _draw() -> void:
		for segment: Dictionary in segments:
			var points := _curve(segment)
			var highlighted := str(segment["key"]) == highlight_key
			var base_color := Color("#6b5138", 0.55)
			for i: int in range(0, points.size() - 1, 2):
				draw_line(points[i], points[i + 1], base_color, 3.0, true)
			if highlighted:
				var shift := int(flow * 6.0) % 2
				for i: int in range(shift, points.size() - 1, 2):
					draw_line(points[i], points[i + 1], Color("#c88a3b", 0.95), 4.5, true)

	func _curve(segment: Dictionary) -> PackedVector2Array:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var mid := (a + b) * 0.5
		var perpendicular := (b - a).orthogonal().normalized() * 46.0
		var control := mid + perpendicular
		var points := PackedVector2Array()
		for i: int in 26:
			var t := float(i) / 25.0
			points.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
		return points

	func midpoint(segment: Dictionary) -> Vector2:
		var a: Vector2 = segment["a"]
		var b: Vector2 = segment["b"]
		var control := (a + b) * 0.5 + (b - a).orthogonal().normalized() * 46.0
		return a.lerp(control, 0.5).lerp(control.lerp(b, 0.5), 0.5)


var _map: Dictionary
var _regions: Dictionary = {}
var _blocks: Dictionary = {}
var _base_size := Vector2(2200, 1350)
var _layer: Control
var _routes: RouteCanvas
var _token: PanelContainer
var _token_base := Vector2.ZERO
var _cost_chip: PanelContainer
var _cost_label: Label
var _fit := 1.0
var _zoom := 1.0
var _press_pos := Vector2.ZERO
var _layer_start := Vector2.ZERO
var _maybe_drag := false
var _dragging := false
var _traveling := false
var _selected_id := ""
var _hover_id := ""
var _sense := false
var _highlight: Dictionary = {}
var _title_font: SystemFont
var _body_font: SystemFont
var _date: Label
var _slot_icon: Kit.MicroIcon
var _place: Label
var _mp_meter: ProgressBar
var _mp_text: Label
var _ration_text: Label
var _badge_row: HBoxContainer
var _last_badges: PackedStringArray
var _drawer: PanelContainer
var _drawer_page: VBoxContainer
var _top_bar: Control
var _tools: HBoxContainer
var _sense_button: Button
var _cabin_button: Button
var _light_tween: Tween
var _elapsed := 0.0


func _ready() -> void:
	clip_contents = true
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	theme = Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 22
	_map = WorldBlackboard.read_config(MAP_PATH)
	_base_size = Vector2(float(_map["base_size"][0]), float(_map["base_size"][1]))
	for region: Dictionary in _map.get("regions", []):
		_regions[str(region["id"])] = region
	var base_texture := Art.load_texture("res://assets/maps/demon_continent/map_base.png")
	if base_texture == null:
		base_texture = Art.make_map_base()
	_build_map_layer(base_texture)
	_build_top()
	_build_drawer()
	_build_toolbar()
	resized.connect(_on_resized)
	WorldBlackboard.state_changed.connect(_refresh)
	WorldBlackboard.world_time_changed.connect(_on_time_changed)
	WorldBlackboard.region_location_changed.connect(func(_id: String) -> void: _refresh())
	_on_resized()
	_center_on(WorldBlackboard.current_location_id, false)
	_refresh()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_top_bar, _tools, _drawer]


func _build_map_layer(base_texture: Texture2D) -> void:
	_layer = Control.new()
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	_layer.size = _base_size
	var base_rect := TextureRect.new()
	base_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base_rect.stretch_mode = TextureRect.STRETCH_SCALE
	base_rect.texture = base_texture
	_layer.add_child(base_rect)
	base_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_routes = RouteCanvas.new()
	_routes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_routes)
	_routes.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var seen := {}
	for region: Dictionary in _map.get("regions", []):
		for route: Dictionary in region.get("routes", []):
			var key := _route_key(str(region["id"]), str(route["to"]))
			if seen.has(key):
				continue
			seen[key] = true
			_routes.segments.append({
				"key": key,
				"from": str(region["id"]),
				"to": str(route["to"]),
				"a": _anchor_px(str(region["id"])),
				"b": _anchor_px(str(route["to"]))
			})
	var base_image := base_texture.get_image()
	for region: Dictionary in _map.get("regions", []):
		var block := Block.new()
		block.configure(region, base_image, _base_size, _title_font)
		_layer.add_child(block)
		block.position = Vector2(block.bounds.position)
		_blocks[str(region["id"])] = block
	_token = PanelContainer.new()
	_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var token_style := Kit.style(Kit.PAPER, 0, 0, 4, 3, Kit.AMBER)
	token_style.set_corner_radius_all(28)
	_token.add_theme_stylebox_override("panel", token_style)
	_token.custom_minimum_size = Vector2(56, 56)
	_token.add_child(Kit.create_label("诺", 26, Kit.INK, _title_font))
	_layer.add_child(_token)
	_cost_chip = Kit.create_chip("", _title_font, 20)
	_cost_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_cost_chip)
	_cost_label = _cost_chip.get_child(0) as Label
	_cost_chip.hide()


func _build_top() -> void:
	var bar := Kit.create_folio_panel(Kit.WASH, 20, 12, 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar = bar
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	bar.offset_left = SIDE_MARGIN
	bar.offset_top = 26.0
	bar.offset_right = 900.0
	bar.offset_bottom = 118.0
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	bar.add_child(row)
	var date_group := HBoxContainer.new()
	date_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date_group.add_theme_constant_override("separation", 8)
	row.add_child(date_group)
	_slot_icon = Kit.create_micro_icon("morning", 22.0, SLOT_TONES[0])
	date_group.add_child(_slot_icon)
	_date = Kit.create_label("", 21, Color("#ead5b7"), _body_font)
	date_group.add_child(_date)
	_place = Kit.create_label("", 25, Kit.PAPER, _title_font)
	row.add_child(_place)
	var mp_group := HBoxContainer.new()
	mp_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mp_group.add_theme_constant_override("separation", 8)
	row.add_child(mp_group)
	mp_group.add_child(Kit.create_micro_icon("drop", 19.0, Color("#8fc0dc")))
	_mp_meter = Kit.create_meter(Kit.BLUE, Color("#5a4436"))
	_mp_meter.custom_minimum_size.x = 120
	_mp_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mp_group.add_child(_mp_meter)
	_mp_text = Kit.create_label("", 19, Kit.PAPER, _body_font)
	mp_group.add_child(_mp_text)
	var ration_group := HBoxContainer.new()
	ration_group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ration_group.add_theme_constant_override("separation", 7)
	row.add_child(ration_group)
	ration_group.add_child(Kit.create_micro_icon("bag", 19.0, Color("#d9b36a")))
	_ration_text = Kit.create_label("", 20, Color("#ead5b7"), _title_font)
	ration_group.add_child(_ration_text)
	_badge_row = HBoxContainer.new()
	_badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_badge_row.add_theme_constant_override("separation", 8)
	row.add_child(_badge_row)


func _build_drawer() -> void:
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(slot)
	slot.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	slot.offset_left = -SIDE_MARGIN - DRAWER_WIDTH
	slot.offset_right = -SIDE_MARGIN
	slot.offset_top = 140.0
	slot.offset_bottom = -120.0
	_drawer = Kit.create_folio_panel(Kit.PAPER, 26, 20, 9)
	slot.add_child(_drawer)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer.add_child(scroll)
	Kit.style_scrollbar(scroll.get_v_scroll_bar())
	_drawer_page = VBoxContainer.new()
	_drawer_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_page.add_theme_constant_override("separation", 12)
	scroll.add_child(_drawer_page)
	_drawer.hide()


func _build_toolbar() -> void:
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.alignment = BoxContainer.ALIGNMENT_END
	_tools = tools
	add_child(tools)
	tools.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tools.offset_left = -900.0
	tools.offset_right = -SIDE_MARGIN
	tools.offset_top = -96.0
	tools.offset_bottom = -30.0
	_cabin_button = _tool_button("回到木屋", _back_to_cabin, "primary")
	tools.add_child(_cabin_button)
	_sense_button = _tool_button("区域高亮 Tab", _toggle_sense, "accent")
	_sense_button.toggle_mode = true
	tools.add_child(_sense_button)
	tools.add_child(_tool_button("定位诺缇雅", func() -> void: _center_on(WorldBlackboard.current_location_id, true)))
	tools.add_child(_tool_button("−", func() -> void: _set_zoom(_zoom * 0.85)))
	tools.add_child(_tool_button("＋", func() -> void: _set_zoom(_zoom * 1.18)))


func _tool_button(text: String, callback: Callable, variant := "secondary") -> Button:
	var button := Kit.create_tactile_button(text, variant, _title_font, 22)
	button.custom_minimum_size = Vector2(0, 62)
	button.pressed.connect(callback)
	return button


func _on_resized() -> void:
	_fit = minf(size.x / _base_size.x, size.y / _base_size.y) * 0.94
	_layer.scale = Vector2.ONE * (_fit * _zoom)
	_layer.position = _clamped(_layer.position)


func _clamped(pos: Vector2, scale_override: float = -1.0) -> Vector2:
	var scaled := _base_size * (scale_override if scale_override > 0.0 else _layer.scale.x)
	var margin := 90.0
	var result := pos
	if scaled.x > size.x:
		result.x = clampf(pos.x, size.x - scaled.x - margin, margin)
	else:
		result.x = clampf(pos.x, (size.x - scaled.x) * 0.5 - margin, (size.x - scaled.x) * 0.5 + margin)
	if scaled.y > size.y:
		result.y = clampf(pos.y, size.y - scaled.y - margin, margin)
	else:
		result.y = clampf(pos.y, (size.y - scaled.y) * 0.5 - margin, (size.y - scaled.y) * 0.5 + margin)
	return result


func _center_on(region_id: String, animated: bool) -> void:
	var usable_width := size.x - (DRAWER_WIDTH + SIDE_MARGIN if _drawer.visible else 0.0)
	var target := Vector2(usable_width * 0.5, size.y * 0.5) - _anchor_px(region_id) * _layer.scale.x
	if animated:
		Motion.spring(_layer, "position", _layer.position, _clamped(target), 0.5, 9.0, 7.0)
	else:
		_layer.position = _clamped(target)


func _set_zoom(target: float) -> void:
	_zoom = clampf(target, 0.6, 2.2)
	var old_scale := _layer.scale.x
	var new_scale := _fit * _zoom
	var center := size * 0.5
	var target_pos := center - (center - _layer.position) * (new_scale / old_scale)
	Motion.spring(_layer, "scale", _layer.scale, Vector2.ONE * new_scale, 0.36, 9.0, 7.0)
	Motion.spring(_layer, "position", _layer.position, _clamped(target_pos, new_scale), 0.36, 9.0, 7.0)


func _anchor_px(region_id: String) -> Vector2:
	var region: Dictionary = _regions.get(region_id, {})
	var anchor: Array = region.get("anchor", [0.5, 0.5])
	return Vector2(float(anchor[0]), float(anchor[1])) * _base_size


func _route_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _route_between(a: String, b: String) -> Dictionary:
	for segment: Dictionary in _routes.segments:
		if str(segment["key"]) == _route_key(a, b):
			return segment
	return {}


func _is_adjacent(a: String, b: String) -> bool:
	return not _route_between(a, b).is_empty()


func _input(event: InputEvent) -> void:
	if SceneTransition.is_busy() or _traveling:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		_sense_button.button_pressed = not _sense_button.button_pressed
		get_viewport().set_input_as_handled()
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if _over_ui(button.position):
			return
		_press_pos = button.position
		_layer_start = _layer.position
		_maybe_drag = true
		_dragging = false
		return
	if button != null and not button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if _dragging:
			Motion.spring(_layer, "position", _layer.position, _clamped(_layer.position), 0.42, 9.0, 7.0)
		elif _maybe_drag and not _over_ui(button.position):
			_click_at(button.position)
		_maybe_drag = false
		_dragging = false
		return
	if button != null and button.pressed and button.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		if not _over_ui(button.position):
			_set_zoom(_zoom * (1.12 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 0.89))
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _maybe_drag and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if not _dragging and motion.position.distance_to(_press_pos) > 6.0:
			_dragging = true
		if _dragging:
			_layer.position = _layer_start + (motion.position - _press_pos)
		return
	if not _maybe_drag:
		_hover_at(motion.position)


func _over_ui(point: Vector2) -> bool:
	if _drawer.visible and _drawer.get_global_rect().has_point(point):
		return true
	if _top_bar.get_global_rect().has_point(point):
		return true
	return _tools.get_global_rect().has_point(point)


func _local_point(viewport_point: Vector2) -> Vector2:
	return (viewport_point - _layer.position) / _layer.scale.x


func _block_at(viewport_point: Vector2) -> Block:
	var local := _local_point(viewport_point)
	for id: String in _blocks:
		var block: Block = _blocks[id]
		if block.contains_point(local - block.position):
			return block
	return null


func _click_at(point: Vector2) -> void:
	var block := _block_at(point)
	if block != null:
		block.press_feedback()
		_select(block.region_id)
	elif _selected_id != "":
		_selected_id = ""
		_drawer.hide()
		_update_highlight()


func _hover_at(point: Vector2) -> void:
	var block := _block_at(point) if not _over_ui(point) else null
	var id := block.region_id if block != null else ""
	if id == _hover_id:
		return
	if _hover_id != "" and _blocks.has(_hover_id):
		(_blocks[_hover_id] as Block).set_hover(false)
	_hover_id = id
	if block != null:
		var local := _local_point(point) - block.position
		block.set_hover(true, (local.x / block.size.x - 0.5) * 2.0)
		AudioManager.play_sfx("ui_hover")
	_update_statuses()
	_update_highlight()


func _select(region_id: String) -> void:
	_selected_id = region_id
	_rebuild_drawer()
	if not _drawer.visible:
		_drawer.show()
		Motion.slide_drawer_in(_drawer, DRAWER_WIDTH + SIDE_MARGIN)
	_update_highlight()


func _update_highlight() -> void:
	var current := WorldBlackboard.current_location_id
	var target := _hover_id if _hover_id != "" else _selected_id
	_highlight = {}
	if target != "" and target != current and _is_adjacent(current, target):
		_highlight = _route_between(current, target)
	elif target != "" and target != current and _is_adjacent(target, current):
		_highlight = _route_between(target, current)
	_routes.highlight_key = str(_highlight.get("key", ""))
	_routes.queue_redraw()
	if _highlight.is_empty():
		_cost_chip.hide()
		return
	var route := _route_data(str(_highlight["from"]), str(_highlight["to"]))
	var rations := WorldBlackboard.get_total_rations()
	var cost := int(route.get("ration_cost", 0))
	if rations < cost:
		_cost_label.text = "干粮不足 · 将陷入疲惫"
		_cost_label.add_theme_color_override("font_color", Kit.VERMILLION)
	else:
		_cost_label.text = "耗时 %d 时段 · 干粮 -%d" % [int(route.get("time_cost", 0)), cost]
		_cost_label.add_theme_color_override("font_color", Kit.INK)
	_cost_chip.show()
	_cost_chip.position = _routes.midpoint(_highlight) - _cost_chip.get_combined_minimum_size() * 0.5


func _route_data(from: String, to: String) -> Dictionary:
	var region: Dictionary = _regions.get(from, {})
	for route: Dictionary in region.get("routes", []):
		if str(route["to"]) == to:
			return route
	return {}


func _update_statuses() -> void:
	var current := WorldBlackboard.current_location_id
	for id: String in _blocks:
		var block: Block = _blocks[id]
		var color := Color("#8a6f4d")
		var state := 0
		if id == current:
			color = Kit.BLUE
			state = 1
		elif _is_adjacent(current, id):
			color = Kit.AMBER
			state = 1
		if _sense:
			state = maxi(state, 1)
		if id == _hover_id:
			state = 2
		block.set_status(color, state)


func _toggle_sense() -> void:
	_sense = _sense_button.button_pressed
	_update_statuses()


func _back_to_cabin() -> void:
	AudioManager.play_sfx("page_flip")
	SceneTransition.change_to(ROOM_SCENE, {"return_scene": scene_file_path})


func _travel_to(route: Dictionary, forced: bool) -> void:
	if _traveling:
		return
	var target := str(route["to"])
	_traveling = true
	_cost_chip.hide()
	var from_pos := _token_base
	var to_pos := _anchor_px(target) - Vector2(28, 28)
	var control := (from_pos + to_pos) * 0.5 + (to_pos - from_pos).orthogonal().normalized() * 70.0
	var last_step := 0.0
	var tween := create_tween()
	var move := func(weight: float) -> void:
		var eased := weight * weight * (3.0 - 2.0 * weight)
		_token_base = from_pos.lerp(control, eased).lerp(control.lerp(to_pos, eased), eased)
		for mark: float in [0.2, 0.45, 0.7, 0.95]:
			if last_step < mark and weight >= mark:
				AudioManager.play_sfx("travel_step", 1.0 + mark * 0.2)
		last_step = weight
	tween.tween_method(move, 0.0, 1.0, 1.35)
	tween.tween_callback(func() -> void:
		var result := WorldBlackboard.resolve_travel(target, int(route.get("time_cost", 1)), int(route.get("ration_cost", 1)), forced)
		_traveling = false
		_token_base = to_pos
		_center_on(target, true)
		_refresh()
		_rebuild_drawer()
		if bool(result["fatigue"]):
			StoryletScheduler.show_hint("干粮不够了。饥饿疲惫缠上了你——休整或进食可以解除。")
		StoryletScheduler.check_arrival(target))


func _process(delta: float) -> void:
	_elapsed += delta
	if not _traveling:
		_token.position = _token_base + Vector2(0, sin(_elapsed * 1.6) * 3.0)
	else:
		_token.position = _token_base
	if not _highlight.is_empty():
		_routes.flow += delta * 2.0
		_routes.queue_redraw()


func _on_time_changed() -> void:
	_refresh()
	var tint: Color = LIGHT[int(WorldBlackboard.get_world_time()["slot"])]
	if _light_tween != null:
		_light_tween.kill()
	_light_tween = create_tween()
	_light_tween.tween_property(_layer, "modulate", Color(1, 1, 1).lerp(tint, 0.30), 0.7)


func _refresh() -> void:
	var time := WorldBlackboard.get_world_time()
	_date.text = WorldBlackboard.date_text()
	var slot := int(time["slot"])
	_slot_icon.setup(SLOT_ICONS[slot], 22.0, SLOT_TONES[slot])
	_slot_icon.queue_redraw()
	var current := WorldBlackboard.current_location_id
	_place.text = str(_regions.get(current, {}).get("name", current))
	var protagonist := WorldBlackboard.get_protagonist()
	var mp: Dictionary = protagonist.get("mp", {})
	_mp_meter.max_value = maxi(1, int(mp.get("max", 1)))
	_mp_meter.value = int(mp.get("current", 0))
	_mp_text.text = "%d/%d" % [int(mp.get("current", 0)), int(mp.get("max", 0))]
	_ration_text.text = "干粮 %d" % WorldBlackboard.get_total_rations()
	var badges := PackedStringArray()
	for buff_name: String in WorldBlackboard.get_buff_names():
		badges.append(buff_name)
	if badges != _last_badges:
		_last_badges = badges.duplicate()
		for child: Node in _badge_row.get_children():
			_badge_row.remove_child(child)
			child.queue_free()
		for buff_name: String in badges:
			var tone := Kit.GREEN
			if buff_name == WorldBlackboard.TRAVEL_FATIGUE_NAME:
				tone = Kit.VERMILLION
			elif buff_name.begins_with("+") or buff_name.begins_with("-"):
				tone = Kit.AMBER
			var badge := Kit.create_badge(buff_name, tone, _title_font, 17)
			_badge_row.add_child(badge)
			Motion.pop_badge(badge, 0.4)
	_token_base = _anchor_px(current) - Vector2(28, 28)
	_cabin_button.visible = current == "migurd_village"
	_update_statuses()
	for id: String in _blocks:
		(_blocks[id] as Block).set_star_count(StoryletScheduler.get_available_storylets(id, "manual").size())
	if _drawer.visible and _selected_id != "":
		_rebuild_drawer()
	_update_highlight()


func _rebuild_drawer() -> void:
	for child: Node in _drawer_page.get_children():
		_drawer_page.remove_child(child)
		child.queue_free()
	var region: Dictionary = _regions.get(_selected_id, {})
	if region.is_empty():
		return
	var current := WorldBlackboard.current_location_id
	var here := _selected_id == current
	var ribbon := Kit.create_ribbon_header(str(region["name"]), _title_font, 26, Kit.BLUE if here else Kit.AMBER)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer_page.add_child(ribbon)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 8)
	_drawer_page.add_child(tags)
	tags.add_child(Kit.create_badge(str(region.get("terrain", "")), Kit.BLUE, _title_font, 17))
	tags.add_child(Kit.create_badge(str(region.get("safety", "")), Kit.GREEN, _title_font, 17))
	var description := Kit.create_label(str(region.get("description", "")), 21, Kit.INK, _body_font)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_drawer_page.add_child(description)
	if not here:
		var hint := Kit.create_label("抵达该区域后可探索；启程需从当前所在区域出发。", 19, Kit.MUTED, _body_font)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_drawer_page.add_child(hint)
	for route: Dictionary in region.get("routes", []):
		var cost := int(route.get("ration_cost", 1))
		var rations := WorldBlackboard.get_total_rations()
		var forced := rations < cost
		var label := "启程前往 %s\n%s · 干粮 -%d" % [str(_regions.get(str(route["to"]), {}).get("name", route["to"])), str(route.get("distance_label", "")), cost]
		if forced:
			label = "强行前往 %s [陷入饥饿疲惫]\n%s" % [str(_regions.get(str(route["to"]), {}).get("name", route["to"])), str(route.get("distance_label", ""))]
		var button := Kit.create_tactile_button(label, "accent" if forced else "primary", _title_font, 21)
		button.custom_minimum_size.y = 76
		button.disabled = not here or _traveling
		button.tooltip_text = str(route.get("risk_hint", ""))
		button.pressed.connect(_travel_to.bind(route, forced))
		_drawer_page.add_child(button)
	if here and WorldBlackboard.get_buff_names().has(WorldBlackboard.TRAVEL_FATIGUE_NAME):
		var eat := Kit.create_tactile_button("进食干粮 · 解除疲惫", "secondary", _title_font, 21)
		eat.custom_minimum_size.y = 60
		eat.disabled = WorldBlackboard.get_total_rations() < 1
		eat.pressed.connect(func() -> void:
			if WorldBlackboard.consume_rations(1) == 1:
				WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
				StoryletScheduler.show_hint("干粮下肚，饥饿疲惫消散了。"))
		_drawer_page.add_child(eat)
	var storylets := StoryletScheduler.get_available_storylets(_selected_id, "manual")
	if not storylets.is_empty():
		_drawer_page.add_child(Kit.create_label("此地手账事件", 20, Kit.BLUE, _title_font))
	for storylet: Dictionary in storylets:
		var card := Kit.create_folio_panel(Kit.PAPER_DEEP, 16, 12, 0)
		_drawer_page.add_child(card)
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 7)
		card.add_child(page)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		page.add_child(head)
		var title := Kit.create_label(str(storylet.get("title", "")), 23, Kit.INK, _title_font)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		head.add_child(title)
		head.add_child(Kit.create_badge(str(storylet.get("category", "")), Kit.AMBER, _title_font, 15))
		var summary := Kit.create_label(str(storylet.get("summary", "")), 19, Kit.MUTED, _body_font)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(summary)
		var is_hook := str(storylet.get("category", "")) == "hook"
		var execute := Kit.create_tactile_button("查看接口状态" if is_hook else "执行", "primary" if here else "secondary", _title_font, 20)
		execute.custom_minimum_size.y = 54
		execute.disabled = not here and not is_hook
		execute.pressed.connect(StoryletScheduler.execute_storylet.bind(str(storylet.get("id", ""))))
		page.add_child(execute)

