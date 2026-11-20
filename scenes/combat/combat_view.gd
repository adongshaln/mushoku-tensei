extends Control

const EngineCore := preload("res://core/combat_engine.gd")
const Art := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Portrait := preload("res://scenes/dialogue/portrait_slot.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const Effects := preload("res://scenes/combat/combat_effects.gd")
const OUTLINE := preload("res://shaders/anime_outline.gdshader")
const ROOM := "res://scenes/room/room_explorer.tscn"
const RANGE_SCALE := [1.14, 1.0, 0.86]
const ENEMY_X := 0.626
const TEAL := Color("#4a7fa7")
const FIRE := Color("#b84d42")
const GOLD := Color("#c88a3b")

var _engine := EngineCore.new()
var _state: Dictionary = {}
var _presets: Dictionary
var _context_return := ROOM
var _speed := 1
var _inline := false
var _leaving := false
var _dice_active := false
var _events: Array[Dictionary] = []
var _log_lines := PackedStringArray()
var _elapsed := 0.0
var _delay := 0.0
var _modal_kind := ""
var _shown_distance := -1
var _hovering := false
var _scout_pinned := false
var _art_cache: Dictionary = {}

var _title_font: SystemFont
var _body_font: SystemFont
var _world: Control
var _landscape: TextureRect
var _shoulder: TextureRect
var _enemy_anchor: Control
var _shadow: TextureRect
var _sprite: TextureRect
var _enemy_mask: Image
var _sprite_material: ShaderMaterial
var _range_tween: Tween
var _lift_tween: Tween
var _shake_tween: Tween
var _flash_tween: Tween
var _effects: Effects
var _dice_overlay: DiceOverlay
var _intent: Label
var _foe: Label
var _status: Label
var _scout: PanelContainer
var _scout_detail: Label
var _timeline: Label
var _timeline_casts: Label
var _cast_progress: ProgressBar
var _time_cells: Array[Label] = []
var _bands: Array[Label] = []
var _speed_button: Button
var _dice_button: Button
var _preset_switch: OptionButton
var _pilot: Label
var _hp: ProgressBar
var _mp: ProgressBar
var _shield: ProgressBar
var _meters: Array[Label] = []
var _traits: Label
var _reaction_slot: Label
var _skill_strip: HBoxContainer
var _skill_buttons: Dictionary = {}
var _support: Button
var _support_status: Label
var _last_line: Label
var _shade: ColorRect
var _modal: CenterContainer
var _modal_page: VBoxContainer
var _top_bar: Control
var _console: Control
var _target_plate: Control


func _ready() -> void:
	var context := SceneTransition.take_context()
	_context_return = str(context.get("return_scene", ROOM))
	_presets = _engine.get_presets()
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	theme = Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 22
	clip_contents = true
	_build_stage()
	_build_top()
	_build_console()
	_build_modal()
	_dice_overlay = DiceOverlay.new()
	add_child(_dice_overlay)
	_dice_overlay.completed.connect(_on_dice_completed)
	_engine.changed.connect(_sync_state)
	_engine.event_occurred.connect(_queue_event)
	_engine.reaction_window_opened.connect(_queue_reaction)
	_engine.finished.connect(_queue_outcome)
	_start(str(context.get("combat_preset", "418_survival")))


func _build_stage() -> void:
	_world = Control.new()
	_world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_world)
	_world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landscape = _picture(TextureRect.STRETCH_KEEP_ASPECT_COVERED)
	_world.add_child(_landscape)
	_landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wash := _picture(TextureRect.STRETCH_SCALE)
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0, 0.23, 0.62, 1])
	fade.colors = PackedColorArray([Color("#31282291"), Color("#352a2022"), Color("#27232212"), Color("#30251ab8")])
	var gradient := GradientTexture2D.new()
	gradient.gradient = fade
	gradient.fill_from = Vector2.ZERO
	gradient.fill_to = Vector2(0.0, 1.0)
	wash.texture = gradient
	_world.add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_enemy_anchor = Control.new()
	_enemy_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock(_enemy_anchor, _world, Vector4(ENEMY_X, 0.755, ENEMY_X, 0.755), Vector4(-343, -498, 343, 0))
	_enemy_anchor.pivot_offset = Vector2(343, 457)
	_shadow = _picture(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_enemy_anchor.add_child(_shadow)
	_shadow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shadow_material := ShaderMaterial.new()
	shadow_material.shader = OUTLINE
	shadow_material.set_shader_parameter("show_placeholder", true)
	shadow_material.set_shader_parameter("placeholder_color", Color("#34251e"))
	shadow_material.set_shader_parameter("layer_opacity", 0.23)
	_shadow.material = shadow_material
	_shadow.position = Vector2(13, 18)
	_sprite = _picture(TextureRect.STRETCH_KEEP_ASPECT_CENTERED)
	_enemy_anchor.add_child(_sprite)
	_sprite.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sprite.pivot_offset = Vector2(343, 450)
	_sprite_material = ShaderMaterial.new()
	_sprite_material.shader = OUTLINE
	_sprite_material.set_shader_parameter("use_source_color", true)
	_sprite_material.set_shader_parameter("outline_color", GOLD)
	_sprite.material = _sprite_material

	_shoulder = _picture(TextureRect.STRETCH_SCALE)
	_shoulder.modulate = Color("#d4c7bc")
	_world.add_child(_shoulder)
	resized.connect(_fit_shoulder)

	_effects = Effects.new()
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effects)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var target := _paper_box(Kit.WASH, 21, 11, 4)
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_target_plate = target
	_dock(target, self, Vector4(ENEMY_X, 0, ENEMY_X, 0), Vector4(-281, 174, 281, 266))
	var entries := _stack(target, 2)
	_foe = _text("", 29, Kit.PAPER, true, true)
	_intent = _text("", 22, Color("#f0d1a3"), false, true)
	_status = _text("", 19, Color("#bbe1df"), false, true)
	entries.add_child(_foe)
	entries.add_child(_intent)
	entries.add_child(_status)

	_scout = _paper_box(Kit.PAPER, 22, 17, 9)
	_scout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock(_scout, self, Vector4(1.0, 0.35, 1.0, 0.35), Vector4(-424, 0, -35, 185))
	_scout_detail = _text("", 22, Kit.INK)
	_scout_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scout.add_child(_scout_detail)
	_scout.hide()


func _build_top() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	_top_bar = bar
	_dock(bar, self, Vector4(0, 0, 1, 0), Vector4(30, 23, -30, 151))

	var timeline_box := _paper_box(Kit.PAPER, 18, 9, 5)
	timeline_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline_box.size_flags_stretch_ratio = 1.25
	bar.add_child(timeline_box)
	var timeline_content := _stack(timeline_box, 4)
	_timeline = _text("", 22, Kit.INK, true)
	timeline_content.add_child(_timeline)
	var rail := HBoxContainer.new()
	rail.add_theme_constant_override("separation", 5)
	timeline_content.add_child(rail)
	for index: int in 7:
		var cell := _text("", 18, Kit.INK, false, true)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.custom_minimum_size.y = 41.0
		cell.add_theme_stylebox_override("normal", Kit.style(Kit.PAPER_DEEP, 3, 3))
		rail.add_child(cell)
		_time_cells.append(cell)
	_timeline_casts = _text("", 17, Kit.MUTED)
	timeline_content.add_child(_timeline_casts)
	_cast_progress = Kit.create_meter(TEAL, Kit.PAPER_DEEP, 5.0)
	timeline_content.add_child(_cast_progress)
	_cast_progress.hide()

	var range_box := _paper_box(Kit.PAPER, 18, 10, 5)
	range_box.custom_minimum_size.x = 304
	bar.add_child(range_box)
	var range_content := _stack(range_box, 9)
	range_content.add_child(_text("距离带", 23, Kit.INK, true))
	var ruler := HBoxContainer.new()
	ruler.add_theme_constant_override("separation", 5)
	range_content.add_child(ruler)
	for band: String in EngineCore.BANDS:
		var chip := _text(band, 21, Kit.INK, false, true)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size.y = 47
		ruler.add_child(chip)
		_bands.append(chip)

	var controls := _paper_box(Kit.PAPER, 14, 7, 5)
	controls.custom_minimum_size.x = 470
	bar.add_child(controls)
	var control_content := _stack(controls, 6)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 10)
	control_content.add_child(quick)
	_speed_button = _button("", _toggle_speed, "subtle")
	_dice_button = _button("", _toggle_dice, "subtle")
	for button: Button in [_speed_button, _dice_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 46
		quick.add_child(button)
	var routing := HBoxContainer.new()
	routing.add_theme_constant_override("separation", 10)
	control_content.add_child(routing)
	_preset_switch = OptionButton.new()
	_preset_switch.custom_minimum_size.y = 48
	_preset_switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_switch.add_theme_stylebox_override("normal", Kit.style(Kit.PAPER_DEEP, 16, 4))
	_preset_switch.add_theme_stylebox_override("hover", Kit.style(Kit.PAPER, 16, 4))
	_preset_switch.add_theme_color_override("font_color", Kit.INK)
	_preset_switch.add_theme_color_override("font_hover_color", Kit.INK)
	_preset_switch.tooltip_text = "切换预设"
	for id: String in _presets:
		_preset_switch.add_item(str(_presets[id]["name"]))
		_preset_switch.set_item_metadata(_preset_switch.item_count - 1, id)
	_preset_switch.item_selected.connect(_switch_preset)
	routing.add_child(_preset_switch)
	var retreat_button := _button("撤退返回木屋", _retreat)
	retreat_button.custom_minimum_size.y = 48
	routing.add_child(retreat_button)


func _build_console() -> void:
	var dock := _paper_box(Kit.PAPER, 20, 14, 8)
	_console = dock
	_dock(dock, self, Vector4(0, 1, 1, 1), Vector4(30, -251, -30, -25))
	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	dock.add_child(split)

	var dossier := HBoxContainer.new()
	dossier.custom_minimum_size.x = 353
	dossier.add_theme_constant_override("separation", 10)
	split.add_child(dossier)
	var avatar := Portrait.new()
	avatar.custom_minimum_size = Vector2(77, 131)
	dossier.add_child(avatar)
	var dialogue := WorldBlackboard.read_config("res://data/dialogues/418_village_gate.json")
	avatar.show_portrait("notia", "resolved", dialogue.get("cast", {}).get("notia", {}))
	avatar.set_captions_visible(false)
	var meters := VBoxContainer.new()
	meters.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meters.add_theme_constant_override("separation", 4)
	dossier.add_child(meters)
	_pilot = _text("", 27, Kit.INK, true)
	meters.add_child(_pilot)
	_hp = _meter(meters, FIRE)
	_mp = _meter(meters, Kit.BLUE)
	_shield = _meter(meters, Color("#8f7f52"))
	_reaction_slot = _text("", 18, TEAL)
	meters.add_child(_reaction_slot)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 9)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(actions)
	_traits = _text("", 19, Kit.BLUE)
	actions.add_child(_traits)
	_skill_strip = HBoxContainer.new()
	_skill_strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skill_strip.add_theme_constant_override("separation", 10)
	actions.add_child(_skill_strip)

	var support_panel := _paper_box(Kit.PAPER_DEEP, 12, 9)
	support_panel.custom_minimum_size.x = 295
	split.add_child(support_panel)
	var notes := _stack(support_panel, 5)
	_support = _button("", _use_support, "accent")
	_support.custom_minimum_size.y = 47
	notes.add_child(_support)
	_support_status = _text("", 17, Kit.MUTED)
	notes.add_child(_support_status)
	_last_line = _text("", 17, Kit.INK)
	_last_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_last_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	notes.add_child(_last_line)
	var log_button := _button("展开战报", _show_log, "subtle")
	log_button.custom_minimum_size.y = 42
	notes.add_child(log_button)


func _meter(parent: Control, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var title := _text("", 16, Kit.INK)
	title.custom_minimum_size.x = 98
	row.add_child(title)
	_meters.append(title)
	var bar := Kit.create_meter(color)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	return bar


func _build_modal() -> void:
	_shade = ColorRect.new()
	_shade.color = Color("#272019ac")
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal = CenterContainer.new()
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var paper := _paper_box(Kit.PAPER, 30, 23, 12)
	paper.custom_minimum_size.x = 708
	_modal.add_child(paper)
	_modal_page = _stack(paper, 14)
	_close_modal()


func _start(id: String) -> void:
	_events.clear()
	_log_lines.clear()
	_last_line.text = "观察敌方意图，选择行动。"
	_elapsed = 0.0
	_delay = 0.0
	_shown_distance = -1
	_scout_pinned = false
	_set_hover(false)
	_scout.hide()
	_effects.clear()
	_close_modal()
	if not _engine.start(id):
		_open_modal("result")
		_modal_page.add_child(_text("战斗配置未载入。", 29, Kit.INK, true, true))
		_modal_page.add_child(_button("返回木屋", _return_to_room, "primary"))
		return
	var preset: Dictionary = _state["preset"]
	_speed = int(preset.get("speed", 1))
	_inline = bool(preset.get("inline_dice", false))
	for index: int in _preset_switch.item_count:
		if _preset_switch.get_item_metadata(index) == id:
			_preset_switch.select(index)
			break
	_load_stage(_state["enemy_card"])
	_load_shoulder(preset)
	_rebuild_skills()
	_sync_state()
	_update_mode_labels()


func _load_stage(enemy: Dictionary) -> void:
	var backdrop := str(enemy["background"])
	if not _art_cache.has(backdrop):
		var found := Art.load_texture("res://assets/backgrounds/combat_%s.png" % backdrop)
		_art_cache[backdrop] = Art.make_combat_background(backdrop) if found == null else found
	_landscape.texture = _art_cache[backdrop]
	var path := str(enemy["art"])
	if not _art_cache.has(path):
		var portrait := Art.load_texture(path)
		_art_cache[path] = Art.make_combat_enemy(str(enemy["fallback"]), Color.html(str(enemy["palette"]))) if portrait == null else portrait
	_sprite.texture = _art_cache[path]
	_shadow.texture = _sprite.texture
	_enemy_mask = _sprite.texture.get_image()
	var weaknesses := PackedStringArray()
	for element: String in enemy["weaknesses"]:
		weaknesses.append("%s ×%.2f" % [_element_name(element), float(enemy["weaknesses"][element])])
	_scout_detail.text = "%s\n%s · 防御 %d\n弱点  %s\n\n%s" % [
		enemy["name"], enemy["rank"], int(enemy["defense"]), "、".join(weaknesses), enemy["description"]
	]


func _load_shoulder(preset: Dictionary) -> void:
	var path := str(preset.get("shoulder_art", ""))
	if not _art_cache.has(path):
		var found := Art.load_texture(path)
		if found == null:
			found = Art.make_combat_shoulder(str(preset.get("shoulder_style", "young")))
		var frame := AtlasTexture.new()
		frame.atlas = found
		frame.region = _foreground_region(found.get_image())
		frame.filter_clip = true
		_art_cache[path] = frame
	_shoulder.texture = _art_cache[path]
	_fit_shoulder()


func _foreground_region(image: Image) -> Rect2:
	var bounds := Rect2()
	var found := false
	for y: int in range(0, image.get_height(), 8):
		for x: int in range(0, image.get_width(), 8):
			if image.get_pixel(x, y).a < 0.25:
				continue
			var point := Vector2(x, y)
			bounds = bounds.expand(point) if found else Rect2(point, Vector2.ZERO)
			found = true
	var sheet := Rect2(Vector2.ZERO, Vector2(image.get_size()))
	return bounds.grow(18.0).intersection(sheet) if found else sheet


func _fit_shoulder() -> void:
	if _shoulder.texture == null:
		return
	var art_size := _shoulder.texture.get_size()
	var scale_to_fit := minf(size.x * 0.53 / art_size.x, size.y * 0.93 / art_size.y)
	_shoulder.size = art_size * scale_to_fit
	_shoulder.position = Vector2(-size.x * 0.045, size.y - _shoulder.size.y + 17)


func _rebuild_skills() -> void:
	_clear(_skill_strip)
	_skill_buttons.clear()
	for action: Dictionary in _engine.get_actions():
		var id := str(action["id"])
		var button := Kit.create_tactile_button("", "secondary", _title_font, 22, 1.06, 0.94, true)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.tooltip_text = str(action.get("description", ""))
		button.pressed.connect(_choose_action.bind(id))
		_skill_strip.add_child(button)
		_skill_buttons[id] = button


func _sync_state() -> void:
	_state = _engine.snapshot()
	var player: Dictionary = _state["player"]
	var enemy: Dictionary = _state["enemy"]
	var band := int(_state["distance"])
	_timeline.text = "行动时间轴   ·   刻度 %02d" % int(_state["tick"])
	_timeline_casts.text = "%s   /   %s" % [_actor_time(player), _actor_time(enemy)]
	_cast_progress.visible = player["state"] == EngineCore.CASTING
	if _cast_progress.visible:
		var duration := int(player["cast_total"])
		_cast_progress.max_value = duration
		_cast_progress.value = maxi(0, duration - int(player["ticks_to_act"]))
	for index: int in _time_cells.size():
		var marks := PackedStringArray()
		if mini(6, int(player["ticks_to_act"])) == index:
			marks.append("诺")
		if mini(6, int(enemy["ticks_to_act"])) == index:
			marks.append("敌")
		var value := "+%d" % index if index < 6 else "6+"
		_time_cells[index].text = "%s   %s" % [value, " · ".join(marks)]
		_time_cells[index].add_theme_color_override("font_color", TEAL if not marks.is_empty() else Kit.MUTED)
	for index: int in _bands.size():
		_bands[index].add_theme_stylebox_override("normal", Kit.style(TEAL if index == band else Kit.PAPER_DEEP, 8, 4))
		_bands[index].add_theme_color_override("font_color", Kit.PAPER if index == band else Kit.INK)
	if band != _shown_distance:
		_shown_distance = band
		if _range_tween != null:
			_range_tween.kill()
		_range_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_range_tween.tween_property(_enemy_anchor, "scale", Vector2.ONE * float(RANGE_SCALE[band]), _seconds(0.22))
	_foe.text = "%s   ·   HP %d/%d" % [enemy["name"], int(enemy["hp"]), int(enemy["max_hp"])]
	_intent.text = _engine.intent()
	_status.text = "   ·   ".join(enemy["status_labels"])
	_status.visible = not _status.text.is_empty()
	_pilot.text = str(player["name"])
	_hp.max_value = int(player["max_hp"])
	_hp.value = int(player["hp"])
	_mp.max_value = int(player["max_mp"])
	_mp.value = int(player["mp"])
	_shield.max_value = maxi(30, int(player["shield"]))
	_shield.value = int(player["shield"])
	_meters[0].text = "HP %d/%d" % [int(player["hp"]), int(player["max_hp"])]
	_meters[1].text = "MP %d/%d" % [int(player["mp"]), int(player["max_mp"])]
	_meters[2].text = "护盾 %d" % int(player["shield"])
	_reaction_slot.text = "●  反应槽可用" if int(_state["reaction"]) > 0 else "○  下轮刷新反应"
	var tags := PackedStringArray(player["buff_names"])
	for trait_data: Dictionary in player["traits"]:
		tags.append(str(trait_data["name"]))
	if not player["status_labels"].is_empty():
		tags.append_array(PackedStringArray(player["status_labels"]))
	_traits.text = "    ·    ".join(tags)
	if _traits.text.is_empty():
		_traits.text = "选择行动" if _engine.is_player_ready() else _actor_time(player)
	_refresh_actions()


func _refresh_actions() -> void:
	if _state.is_empty():
		return
	var active := _engine.is_player_ready() and _events.is_empty() and _modal_kind.is_empty() and not _dice_active and not _leaving
	for action: Dictionary in _engine.get_actions():
		var id := str(action["id"])
		if not _skill_buttons.has(id):
			continue
		var button: Button = _skill_buttons[id]
		var reaches := PackedStringArray()
		for band: int in action["ranges"]:
			reaches.append(EngineCore.BANDS[band])
		var timing := "咏唱 %d" % int(action["cast_ticks"]) if int(action["cast_ticks"]) > 0 else "无咏唱"
		var reason := str(action["reason"])
		var label := str(action["name"]).replace("无咏唱·", "")
		if action.has("stock"):
			label += " ×%d" % int(action["stock"])
		button.text = "%s\n%s\n%s · MP %d" % [label, " / ".join(reaches), timing, int(action["mp"])]
		if not reason.is_empty():
			button.text += "\n" + reason
		button.disabled = not active or not reason.is_empty()
	var support: Dictionary = _state["support"]
	_support.text = "%s ×%d" % [support["name"], int(_state["support_left"])] if not support.is_empty() else "援护契约"
	_support.tooltip_text = str(support.get("description", ""))
	_support_status.text = str(_state["support_reason"])
	if _support_status.text.is_empty():
		_support_status.text = "近距逼退 · 延后 %d 刻度" % int(support.get("enemy_delay", 0))
	_support.disabled = not active or not str(_state["support_reason"]).is_empty()


func _actor_time(actor: Dictionary) -> String:
	var name := str(actor["name"])
	var left := int(actor["ticks_to_act"])
	match str(actor["state"]):
		EngineCore.CASTING:
			return "%s · %s %d" % [name, actor["cast_name"], left]
		EngineCore.RECOVERING:
			return "%s · 恢复 %d" % [name, left]
		_:
			return "%s · 就绪" % name


func _process(delta: float) -> void:
	if _leaving or SceneTransition.is_busy() or not _modal_kind.is_empty() or _dice_active:
		return
	if _delay > 0:
		_delay -= delta
		return
	if not _events.is_empty():
		var event: Dictionary = _events.pop_front()
		_play_event(str(event["kind"]), event["info"])
		_refresh_actions()
		return
	if _engine.can_advance():
		_elapsed += delta
		if _elapsed >= _seconds(0.22):
			_elapsed = 0.0
			_engine.advance()


func _queue_event(kind: String, info: Dictionary) -> void:
	_events.append({"kind": kind, "info": info})


func _queue_reaction(info: Dictionary) -> void:
	_queue_event("reaction_window", info)


func _queue_outcome(outcome: String) -> void:
	_queue_event("outcome", {"outcome": outcome})


func _play_event(kind: String, info: Dictionary) -> void:
	AudioManager.play_sfx(str(info.get("sound", "")))
	var name := str(info.get("name", ""))
	match kind:
		"check":
			_play_check(info)
		"cast":
			_record("%s开始咏唱「%s」，%d 刻度。" % [_side_label(info), name, int(info["ticks"])])
		"action":
			_record("%s使用「%s」。 " % [_side_label(info), name])
		"miss":
			_record("%s未命中。" % name)
			_float("未命中", _battle_point(str(info["side"]) == "player"), Kit.PAPER)
		"range_miss":
			_record("距离已变，「%s」落空。" % name)
		"hit":
			_play_hit(info)
		"restore":
			_record("%s · 回血 %d · 回魔 %d · 护盾 %d" % [name, int(info["health"]), int(info["mana"]), int(info["shield"])])
		"status":
			var suffix := "，延后 %d 刻度" % int(info["delay"]) if int(info["delay"]) > 0 else ""
			_record("%s附着%s%s。" % [_side_label(info), name, suffix])
		"concentration":
			var effect := "被打断" if bool(info["interrupted"]) else "延后 %d 刻度" % int(info["ticks"])
			_record("「%s」%s。" % [name, effect])
		"support":
			_record("%s · 行动延后 %d 刻度" % [name, int(info["delay"])])
			_effects.impact(_battle_point(true), "parry", _seconds(0.34))
		"reaction":
			_record("反应 · " + name)
		"evade":
			_record("娇小闪避成功，完全规避伤害。")
			_float("完全规避", _battle_point(false), Color("#bde9e1"))
		"parry":
			_record("弹反 %d 点伤害，打断后续 %d 击。" % [int(info["amount"]), int(info["cancelled_hits"])])
		"distance":
			_record("身位改变 · %s" % EngineCore.BANDS[int(info["band"])])
		"reaction_window":
			_show_reaction(info)
		"outcome":
			_show_outcome(str(info["outcome"]))


func _play_check(info: Dictionary) -> void:
	var result: Dictionary = info["result"]
	var face := _roll_label(result)
	_record("%s · %s" % [info["name"], face])
	if _inline:
		var color := Color("#d0efe6") if result["passed"] else Color("#f2ccb2")
		_float(face, _battle_point(str(info["side"]) == "enemy") + Vector2(0, -105), color)
		AudioManager.play_sfx("dice_success" if result["passed"] else "dice_fail")
		return
	_dice_active = true
	_refresh_actions()
	_dice_overlay.present(result, str(info["name"]), "", true)


func _on_dice_completed() -> void:
	_dice_active = false
	_refresh_actions()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_top_bar, _console, _target_plate, _scout]


func _roll_label(result: Dictionary) -> String:
	var rolls := PackedStringArray()
	for value: int in result["rolls"]:
		rolls.append(str(value))
	var suffix := "成功" if result["passed"] else "未通过"
	return "d20 [%s] %+d = %d  /  DC %d  ·  %s" % [
		" / ".join(rolls), int(result["total_mod"]), int(result["total"]), int(result["dc"]), suffix
	]


func _play_hit(info: Dictionary) -> void:
	var enemy := bool(info["side"] == "enemy")
	var origin := _battle_point(enemy)
	var loss := int(info["amount"])
	var absorb := int(info["absorbed"])
	var hit_text := "−%d HP" % loss
	if bool(info["critical"]):
		hit_text = "冻结暴击   " + hit_text
	if absorb > 0:
		hit_text += "   护盾 −%d" % absorb
	_record("%s %s" % [_side_label(info), hit_text])
	_float(hit_text, origin, GOLD if enemy else Color("#fbc6aa"))
	_effects.impact(origin + Vector2(0, 45), str(info["element"]), _seconds(0.45))
	_delay = _seconds(0.13)
	if _shake_tween != null:
		_shake_tween.kill()
	_shake_tween = create_tween()
	for offset: float in [-7.0, 5.0, -3.0, 0.0]:
		_shake_tween.tween_property(_world, "position:x", offset, _seconds(0.045))
	if enemy:
		if _flash_tween != null:
			_flash_tween.kill()
		_sprite_material.set_shader_parameter("flash_strength", 0.75)
		_flash_tween = create_tween()
		_flash_tween.tween_method(
			func(value: float) -> void: _sprite_material.set_shader_parameter("flash_strength", value),
			0.75, 0.0, _seconds(0.23)
		)
	else:
		var flash := ColorRect.new()
		flash.color = Color("#f9ddd22e")
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_effects.add_child(flash)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var veil := create_tween()
		veil.tween_property(flash, "modulate:a", 0.0, _seconds(0.26))
		veil.tween_callback(flash.queue_free)


func _show_reaction(info: Dictionary) -> void:
	_open_modal("reaction")
	_modal_page.add_child(Kit.create_ribbon_header("反应窗口", _title_font, 30, Kit.VERMILLION))
	_modal_page.add_child(_text("%s即将命中" % info["name"], 26, FIRE, true, true))
	if info["foresight"]:
		_modal_page.add_child(_text(
			"予见眼 · 双骰优势\n来袭 d20 %d · 总点 %d · 预计 %d 伤害" %
			[int(info["raw_roll"]), int(info["total"]), int(info["damage"])], 24, TEAL, false, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_modal_page.add_child(row)
	for reaction: Dictionary in _engine.get_reactions():
		var reason := str(reaction["reason"])
		var text := "%s\n%s" % [reaction["name"], "MP %d" % int(reaction["mp"]) if reason.is_empty() else reason]
		var button := _button(text, _resolve_reaction.bind(str(reaction["id"])), "primary")
		button.tooltip_text = str(reaction["description"])
		button.custom_minimum_size = Vector2(178, 82)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = not reason.is_empty()
		row.add_child(button)
	var accept := _button("直接承受", _resolve_reaction.bind("take_hit"))
	accept.custom_minimum_size.y = 82
	row.add_child(accept)


func _show_outcome(outcome: String) -> void:
	_open_modal("result")
	var label := {"victory": "胜利", "defeat": "战败", "retreat": "撤退"}
	var title := _text(str(label[outcome]), 40, TEAL if outcome == "victory" else FIRE, true, true)
	_modal_page.add_child(title)
	Motion.stamp_impact(title)
	_modal_page.add_child(_text("%s   ·   历经 %d 刻度" % [_state["preset"]["name"], int(_state["tick"])], 24, Kit.MUTED, false, true))
	var player: Dictionary = _state["player"]
	var hp := int(player["hp"])
	if outcome == "defeat" and _state["preset"]["mode"] == "story_linked":
		hp = int(_state["preset"]["post_defeat_hp"])
	var prefix := "返家状态" if _state["preset"]["mode"] == "story_linked" else "本局结算"
	_modal_page.add_child(_text("%s   HP %d/%d   ·   MP %d/%d" % [prefix, hp, int(player["max_hp"]), int(player["mp"]), int(player["max_mp"])], 23, Kit.INK, false, true))
	_modal_page.add_child(_button("返回木屋", _return_to_room, "primary"))


func _show_log() -> void:
	if not _modal_kind.is_empty():
		return
	_open_modal("log")
	_modal_page.add_child(Kit.create_ribbon_header("战报", _title_font, 30, Kit.BLUE))
	var journal := RichTextLabel.new()
	journal.custom_minimum_size = Vector2(690, 374)
	journal.scroll_following = true
	journal.add_theme_color_override("default_color", Kit.INK)
	journal.add_theme_font_size_override("normal_font_size", 22)
	journal.text = "\n".join(_log_lines)
	_modal_page.add_child(journal)
	Kit.style_scrollbar(journal.get_v_scroll_bar())
	_modal_page.add_child(_button("合上战报", _close_modal, "subtle"))


func _open_modal(kind: String) -> void:
	_modal_kind = kind
	_clear(_modal_page)
	_set_hover(false)
	_scout.hide()
	_shade.show()
	_modal.show()
	_refresh_actions()


func _close_modal() -> void:
	_modal_kind = ""
	_modal.hide()
	_shade.hide()
	_refresh_actions()


func _choose_action(id: String) -> void:
	if _modal_kind.is_empty() and _events.is_empty() and not _dice_active and not SceneTransition.is_busy():
		_engine.choose_action(id)


func _resolve_reaction(id: String) -> void:
	if _engine.resolve_reaction(id):
		_close_modal()


func _use_support() -> void:
	if _modal_kind.is_empty() and _events.is_empty() and not _dice_active and not SceneTransition.is_busy():
		_engine.use_support()


func _switch_preset(index: int) -> void:
	if _leaving or _dice_active or SceneTransition.is_busy():
		return
	_engine.retreat()
	_start(str(_preset_switch.get_item_metadata(index)))
	AudioManager.play_sfx("page_flip")


func _retreat() -> void:
	if _leaving or _dice_active or SceneTransition.is_busy():
		return
	_engine.retreat()
	_return_to_room()


func _return_to_room() -> void:
	if not _leaving:
		_leaving = SceneTransition.change_to(_context_return)


func _toggle_speed() -> void:
	_speed = 2 if _speed == 1 else 1
	_update_mode_labels()


func _toggle_dice() -> void:
	_inline = not _inline
	_update_mode_labels()


func _update_mode_labels() -> void:
	_speed_button.text = "2× 极速演出" if _speed == 2 else "1× 标准演出"
	_dice_button.text = "极速内联骰点" if _inline else "标准骰窗"


func _input(event: InputEvent) -> void:
	if SceneTransition.is_busy() or _leaving or _dice_active or _sprite == null:
		return
	if not _modal_kind.is_empty():
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _modal_kind == "log":
			_close_modal()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_set_hover(_hit_enemy(event.position))


func _unhandled_input(event: InputEvent) -> void:
	if SceneTransition.is_busy() or not _modal_kind.is_empty() or _dice_active:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _hit_enemy(event.position):
			_scout_pinned = not _scout_pinned
			_scout.visible = _scout_pinned
			get_viewport().set_input_as_handled()
		elif _scout_pinned:
			_scout_pinned = false
			_scout.hide()


func _hit_enemy(point: Vector2) -> bool:
	if _enemy_mask == null:
		return false
	var at := _sprite.get_global_transform_with_canvas().affine_inverse() * point
	var texture_size := Vector2(_enemy_mask.get_size())
	var fit := minf(_sprite.size.x / texture_size.x, _sprite.size.y / texture_size.y)
	var visible_area := texture_size * fit
	var local := at - (_sprite.size - visible_area) * 0.5
	if not Rect2(Vector2.ZERO, visible_area).has_point(local):
		return false
	return _enemy_mask.get_pixelv(Vector2i(local / fit)).a > 0.1


func _set_hover(hover: bool) -> void:
	if _hovering == hover:
		return
	_hovering = hover
	_scout.visible = hover or _scout_pinned
	_sprite_material.set_shader_parameter("outline_state", 2 if hover else 0)
	if hover:
		AudioManager.play_sfx("ui_hover")
	if _lift_tween != null:
		_lift_tween.kill()
	_lift_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_lift_tween.tween_property(_sprite, "position:y", -11.0 if hover else 0.0, _seconds(0.23))
	_lift_tween.tween_property(_sprite, "scale", Vector2.ONE * (1.035 if hover else 1.0), _seconds(0.23))


func _record(line: String) -> void:
	_last_line.text = line
	_log_lines.append("%02d  %s" % [int(_state["tick"]), line])
	if _log_lines.size() > 90:
		_log_lines.remove_at(0)


func _float(text: String, at: Vector2, color: Color) -> void:
	var label := _text(text, 30, color, true, true)
	label.add_theme_constant_override("outline_size", 7)
	label.add_theme_color_override("font_outline_color", Color("#322620"))
	_effects.add_child(label)
	label.size.x = 620
	label.position = at - Vector2(310, 0)
	var drift := create_tween().set_parallel(true)
	drift.tween_property(label, "position:y", label.position.y - 54.0, _seconds(0.75))
	drift.tween_property(label, "modulate:a", 0.0, _seconds(0.35)).set_delay(_seconds(0.49))
	drift.finished.connect(label.queue_free)


func _battle_point(enemy: bool) -> Vector2:
	return size * (Vector2(ENEMY_X, 0.45) if enemy else Vector2(0.39, 0.66))


func _side_label(info: Dictionary) -> String:
	var side := str(info.get("side", "player"))
	return str(_state[side]["name"])


func _seconds(value: float) -> float:
	return value / float(_speed)


func _element_name(id: String) -> String:
	return str({"water": "水", "ice": "冰", "physical": "物理", "lightning": "雷", "earth": "土"}.get(id, id))


func _dock(node: Control, parent: Control, anchors: Vector4, offsets: Vector4) -> void:
	parent.add_child(node)
	node.anchor_left = anchors.x
	node.anchor_top = anchors.y
	node.anchor_right = anchors.z
	node.anchor_bottom = anchors.w
	node.offset_left = offsets.x
	node.offset_top = offsets.y
	node.offset_right = offsets.z
	node.offset_bottom = offsets.w


func _picture(stretch: int) -> TextureRect:
	var picture := TextureRect.new()
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = stretch
	return picture


func _paper_box(color: Color, horizontal: int, vertical: int, shadow: int = 0) -> PanelContainer:
	return Kit.create_folio_panel(color, horizontal, vertical, shadow)


func _stack(parent: Control, spacing: int) -> VBoxContainer:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", spacing)
	parent.add_child(stack)
	return stack


func _text(text: String, font_size: int, color: Color, title: bool = false, center: bool = false) -> Label:
	var label := Kit.create_label(text, font_size, color, _title_font if title else _body_font)
	if center:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _button(text: String, callback: Callable, variant := "secondary") -> Button:
	var button := Kit.create_tactile_button(text, variant, _title_font, 21)
	button.pressed.connect(callback)
	return button


func _clear(container: Control) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

