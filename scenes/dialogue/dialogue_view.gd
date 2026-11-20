extends Control

const Art := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Runner := preload("res://core/dialogue_runner.gd")
const Portrait := preload("res://scenes/dialogue/portrait_slot.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const DEFAULT_RETURN := "res://scenes/room/room_explorer.tscn"
const MODES := ["natural", "force_success", "force_fail"]
const SLOTS := ["left", "center", "right"]
const TYPE_SPEED := 43.0

var _runner := Runner.new()
var _return_scene := DEFAULT_RETURN
var _background: TextureRect
var _village_placeholder: Texture2D
var _portraits: Array[Portrait] = []
var _hud: Control
var _roll_mode: OptionButton
var _line_box: PanelContainer
var _speaker: Label
var _speaker_chip: PanelContainer
var _line: Label
var _prompt: Label
var _voice_button: Button
var _auto_button: Button
var _skip_button: Button
var _choice_overlay: CenterContainer
var _choices: VBoxContainer
var _log_overlay: CenterContainer
var _log_rows: VBoxContainer
var _log_scroll: ScrollContainer
var _dice_overlay: DiceOverlay
var _title_font: SystemFont
var _body_font: SystemFont
var _characters := 0.0
var _pace_elapsed := 0.0
var _hidden := false
var _leaving := false
var _voice_path := ""


func _ready() -> void:
	var context := SceneTransition.take_context()
	_return_scene = str(context.get("return_scene", DEFAULT_RETURN))
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	theme = Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 25
	var started := _runner.start(str(context.get("dialogue_id", "418_village_gate")))
	_build_stage()
	_build_hud()
	_build_log()
	_dice_overlay = DiceOverlay.new()
	add_child(_dice_overlay)
	_dice_overlay.completed.connect(_on_dice_completed)
	if started:
		_present_node()
	else:
		_show_error()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_hud, _log_overlay]


func _build_stage() -> void:
	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_background)
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_set_background(str(_runner.script_data.get("bg", "")))

	var atmosphere := TextureRect.new()
	atmosphere.mouse_filter = Control.MOUSE_FILTER_IGNORE
	atmosphere.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.58, 1.0])
	gradient.colors = PackedColorArray([Color("#29231f65"), Color("#bba78b16"), Color("#30262118"), Color("#2820199c")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	atmosphere.texture = texture
	add_child(atmosphere)
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for center: float in [0.224, 0.5, 0.776]:
		var slot := Portrait.new()
		_place(slot, self, Vector4(center, 0.115, center, 0.697), Vector4(-236, 0, 236, 0))
		_portraits.append(slot)
	for actor: Dictionary in _runner.script_data.get("opening_cast", []):
		_set_portrait(actor)


func _build_hud() -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var location := _panel(Kit.WASH, 20, 11, 3)
	location.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(location)
	location.position = Vector2(46, 34)
	var titles := VBoxContainer.new()
	titles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	titles.add_theme_constant_override("separation", 6)
	location.add_child(titles)
	var ribbon := Kit.create_ribbon_header(str(_runner.script_data.get("title", "")), _title_font, 26, Kit.AMBER)
	titles.add_child(ribbon)
	titles.add_child(_label(str(_runner.script_data.get("location", "")), 19, Color("#ead5b7")))

	_roll_mode = OptionButton.new()
	_roll_mode.add_item("自然掷骰")
	_roll_mode.add_item("强制成功")
	_roll_mode.add_item("失败推进")
	_roll_mode.tooltip_text = "检定分支测试"
	_roll_mode.add_theme_font_size_override("font_size", 20)
	_roll_mode.add_theme_stylebox_override("normal", Kit.style(Kit.PAPER_DEEP, 13, 5, 2))
	_roll_mode.add_theme_stylebox_override("hover", Kit.style(Kit.PAPER, 13, 5, 2))
	_roll_mode.add_theme_color_override("font_color", Kit.INK)
	_roll_mode.add_theme_color_override("font_hover_color", Kit.INK)
	_roll_mode.add_theme_color_override("font_focus_color", Kit.INK)
	_roll_mode.item_selected.connect(func(_index: int) -> void: AudioManager.play_sfx("ui_click"))
	_place(_roll_mode, _hud, Vector4(1, 0, 1, 0), Vector4(-254, 34, -46, 84))

	_line_box = _panel(Kit.PAPER, 44, 31, 9)
	_line_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_line_box, _hud, Vector4(0.058, 1, 0.942, 1), Vector4(0, -264, 0, -39))
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 2)
	_line_box.add_child(page)
	_line = _label("", 33, Kit.INK, true)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_constant_override("line_spacing", 13)
	_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_line)
	_prompt = _label("▾", 26, Kit.BLUE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page.add_child(_prompt)

	_speaker_chip = _panel(Kit.BLUE, 22, 6, 4)
	_speaker_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_speaker_chip, _hud, Vector4(0.058, 1, 0.058, 1), Vector4(24, -326, 218, -267))
	_speaker = _label("", 27, Kit.PAPER, true)
	_speaker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speaker_chip.add_child(_speaker)
	_voice_button = _button("重播语音", _replay_current, "subtle")
	_voice_button.add_theme_font_size_override("font_size", 21)
	_voice_button.custom_minimum_size.y = 53
	_place(_voice_button, _hud, Vector4(0.058, 1, 0.058, 1), Vector4(235, -324, 389, -269))

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 10)
	tools.alignment = BoxContainer.ALIGNMENT_END
	_place(tools, _hud, Vector4(0.942, 1, 0.942, 1), Vector4(-560, -333, 0, -268))
	tools.add_child(_button("回顾", _open_log))
	_auto_button = _toggle("自动", _on_auto)
	tools.add_child(_auto_button)
	_skip_button = _toggle("快进", _on_skip)
	tools.add_child(_skip_button)
	tools.add_child(_button("隐藏", _set_hidden.bind(true), "subtle"))

	_choice_overlay = CenterContainer.new()
	_choice_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_choice_overlay, _hud, Vector4(0, 0, 1, 1), Vector4(0, 48, 0, -128))
	var option_page := _panel(Kit.PAPER, 28, 23, 10)
	option_page.custom_minimum_size.x = 815
	_choice_overlay.add_child(option_page)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 11)
	option_page.add_child(_choices)
	_choice_overlay.hide()


func _build_log() -> void:
	_log_overlay = _modal()
	var panel := _panel(Kit.PAPER, 35, 24, 11)
	panel.custom_minimum_size = Vector2(1060, 744)
	_log_overlay.add_child(panel)
	var journal := VBoxContainer.new()
	journal.add_theme_constant_override("separation", 15)
	panel.add_child(journal)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	journal.add_child(title_row)
	var ribbon := Kit.create_ribbon_header("对话回顾", _title_font, 30, Kit.BLUE)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(ribbon)
	title_row.add_child(_button("合上", _close_log, "subtle"))
	_rule(journal)
	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal.add_child(_log_scroll)
	Kit.style_scrollbar(_log_scroll.get_v_scroll_bar())
	_log_rows = VBoxContainer.new()
	_log_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows.add_theme_constant_override("separation", 13)
	_log_scroll.add_child(_log_rows)
	_log_overlay.hide()


func _modal() -> CenterContainer:
	var shade := ColorRect.new()
	shade.color = Color("#29221da8")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CenterContainer.new()
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visibility_changed.connect(func() -> void: shade.visible = layer.visible)
	return layer


func _present_node() -> void:
	AudioManager.stop_voice()
	_pace_elapsed = 0.0
	_choice_overlay.hide()
	_line_box.hide()
	_speaker_chip.hide()
	_voice_button.hide()
	match str(_runner.current.get("type", "error")):
		"line":
			_present_line(_runner.current)
		"choice":
			_skip_button.set_pressed_no_signal(false)
			_present_choices()
		"end":
			_return_to_room()
		_:
			_show_error()


func _present_line(node: Dictionary) -> void:
	if node.has("bg"):
		_set_background(str(node["bg"]))
	_set_portrait(node)
	for i: int in _portraits.size():
		_portraits[i].set_active(SLOTS[i] == node.get("portrait_slot", ""))
	var speaker_name := str(node.get("speaker", ""))
	_speaker.text = speaker_name if not speaker_name.is_empty() else "旁白"
	_line.text = str(node.get("text", ""))
	_characters = float(_line.text.length()) if _skip_button.button_pressed else 0.0
	_line.visible_characters = int(_characters)
	_speaker_chip.show()
	_line_box.show()
	_voice_button.show()
	_voice_path = str(node.get("voice", ""))
	var recorded := AudioManager.has_voice(_voice_path)
	_voice_button.disabled = not recorded
	_voice_button.tooltip_text = "播放当前一句" if recorded else "尚未录入配音"
	if not _skip_button.button_pressed:
		AudioManager.play_voice(_voice_path)
	_prompt.hide()


func _present_choices() -> void:
	_clear(_choices)
	for option: Dictionary in _runner.choices():
		var description := str(option["text"])
		var check: Dictionary = option.get("check", {})
		var bonuses := PackedStringArray()
		if not check.is_empty():
			var breakdown := RuleEngine.collect_check(str(check["stat"]), check.get("context", {}))
			description += "\n[%s DC %d · 总修正 %+d]" % [
				check.get("label", check["stat"]), int(check["dc"]), int(breakdown["total_mod"])
			]
			bonuses = _bonus_labels(breakdown["bonus_list"])
		var option_button := _button(description, _select_option.bind(str(option["id"])), "primary" if not check.is_empty() else "secondary")
		option_button.add_theme_font_size_override("font_size", 27)
		option_button.custom_minimum_size.y = 94 if not check.is_empty() else 65
		_choices.add_child(option_button)
		if not bonuses.is_empty():
			var tags := _center_text("    ".join(bonuses), 23, Kit.BLUE)
			tags.add_theme_stylebox_override("normal", Kit.style(Kit.PAPER_DEEP, 16, 8))
			_choices.add_child(tags)
	_choice_overlay.show()
	Motion.fade_in(_choice_overlay, 0.24)


func _select_option(id: String) -> void:
	if _leaving or SceneTransition.is_busy() or _dice_overlay.is_active() or _log_overlay.visible:
		return
	var option_text := ""
	var check_label := ""
	for option: Dictionary in _runner.choices():
		if str(option["id"]) == id:
			option_text = str(option["text"])
			var check: Dictionary = option.get("check", {})
			check_label = str(check.get("label", check.get("stat", "检定")))
	if not _runner.choose(id, MODES[maxi(_roll_mode.selected, 0)]):
		return
	_choice_overlay.hide()
	if _runner.pending_check.is_empty():
		_present_node()
	else:
		for portrait: Portrait in _portraits:
			portrait.set_captions_visible(false)
		_dice_overlay.present(_runner.pending_check, check_label, option_text, false)


func _on_dice_completed() -> void:
	for portrait: Portrait in _portraits:
		portrait.set_captions_visible(not _hidden)
	_runner.continue_check()
	_present_node()


func _process(delta: float) -> void:
	if _leaving or _hidden or SceneTransition.is_busy() or _log_overlay.visible or _dice_overlay.is_active() or _runner.current.get("type") != "line":
		return
	var full := _line.text.length()
	if _characters < full:
		_characters = minf(float(full), _characters + TYPE_SPEED * delta)
		_line.visible_characters = int(_characters)
		return
	_prompt.show()
	_prompt.modulate.a = 0.64 + sin(Time.get_ticks_msec() * 0.005) * 0.26
	if _skip_button.button_pressed or (_auto_button.button_pressed and not AudioManager.is_voice_playing()):
		_pace_elapsed += delta
		var delay := 0.10 if _skip_button.button_pressed else 1.20
		if _pace_elapsed >= delay:
			_advance()
	else:
		_pace_elapsed = 0.0


func _advance() -> void:
	if _leaving or _hidden or SceneTransition.is_busy() or _log_overlay.visible or _dice_overlay.is_active() or _runner.current.get("type") != "line":
		return
	var full := _line.text.length()
	if _characters < full:
		_characters = float(full)
		_line.visible_characters = full
		return
	AudioManager.play_sfx("page_flip")
	_runner.next_line()
	_present_node()


func _on_auto(enabled: bool) -> void:
	if enabled:
		_skip_button.set_pressed_no_signal(false)
		_pace_elapsed = 0.0


func _on_skip(enabled: bool) -> void:
	if enabled and _runner.current.get("type") == "line":
		_auto_button.set_pressed_no_signal(false)
		AudioManager.stop_voice()
		_characters = float(_line.text.length())
		_line.visible_characters = int(_characters)
	elif enabled:
		_skip_button.set_pressed_no_signal(false)
	_pace_elapsed = 0.0


func _replay_current() -> void:
	AudioManager.play_voice(_voice_path)


func _input(event: InputEvent) -> void:
	if _leaving or SceneTransition.is_busy():
		return
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if _hidden and ((click != null and click.pressed) or (key != null and key.pressed and key.keycode in [KEY_ESCAPE, KEY_SPACE])):
		_set_hidden(false)
		get_viewport().set_input_as_handled()
		return
	var escape := key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE
	var right_click := click != null and click.pressed and click.button_index == MOUSE_BUTTON_RIGHT
	if (escape or right_click) and not _dice_overlay.is_active():
		if _log_overlay.visible:
			_close_log()
		else:
			_set_hidden(true)
		get_viewport().set_input_as_handled()
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE and not _dice_overlay.is_active() and not _log_overlay.visible:
		_advance()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _set_hidden(hidden: bool) -> void:
	_hidden = hidden
	_hud.visible = not hidden
	for portrait: Portrait in _portraits:
		portrait.set_captions_visible(not hidden)


func _open_log() -> void:
	if _dice_overlay.is_active():
		return
	_drop_focus()
	_clear(_log_rows)
	for entry: Dictionary in _runner.history:
		var row := _panel(Kit.PAPER_DEEP, 17, 12)
		_log_rows.add_child(row)
		var sections := VBoxContainer.new()
		sections.add_theme_constant_override("separation", 8)
		row.add_child(sections)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		sections.add_child(header)
		var name := str(entry.get("speaker", ""))
		var speaker_label := _label(name if not name.is_empty() else "旁白", 22, Kit.BLUE, true)
		speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(speaker_label)
		var voice := str(entry.get("voice", ""))
		var replay := _button("重播语音", AudioManager.play_voice.bind(voice), "subtle")
		replay.add_theme_font_size_override("font_size", 20)
		replay.custom_minimum_size.y = 49
		replay.disabled = not AudioManager.has_voice(voice)
		replay.tooltip_text = "尚未录入配音" if replay.disabled else "播放这句台词"
		header.add_child(replay)
		var text := _label(str(entry["text"]), 26, Kit.INK, true)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sections.add_child(text)
	_log_overlay.show()
	await get_tree().process_frame
	_log_scroll.scroll_vertical = ceili(_log_scroll.get_v_scroll_bar().max_value)


func _close_log() -> void:
	AudioManager.stop_voice()
	_pace_elapsed = 0.0
	_log_overlay.hide()


func _return_to_room() -> void:
	if _leaving:
		return
	_leaving = true
	if not SceneTransition.change_to(_return_scene):
		_leaving = false
		_show_error()


func _show_error() -> void:
	_clear(_choices)
	_choices.add_child(_center_text("剧本暂时无法继续。", 26, Kit.INK))
	_choices.add_child(_button("返回木屋", _return_to_room, "primary"))
	_choice_overlay.show()


func _set_background(id: String) -> void:
	var texture := Art.load_texture("res://assets/backgrounds/%s.png" % id) if not id.is_empty() else null
	if texture == null:
		if _village_placeholder == null:
			_village_placeholder = Art.make_village()
		texture = _village_placeholder
	_background.texture = texture


func _set_portrait(node: Dictionary) -> void:
	var index := SLOTS.find(str(node.get("portrait_slot", "")))
	var id := str(node.get("portrait_id", ""))
	if index < 0 or id.is_empty():
		return
	var cast: Dictionary = _runner.script_data.get("cast", {})
	_portraits[index].show_portrait(id, str(node.get("expression", "")), cast.get(id, {"name": id}))


func _bonus_labels(bonuses: Array) -> PackedStringArray:
	var output := PackedStringArray()
	for bonus: Dictionary in bonuses:
		output.append("%+d %s" % [int(bonus["value"]), RuleEngine.bonus_label(bonus)])
	return output


func _button(text: String, callback: Callable, variant := "secondary") -> Button:
	var button := Kit.create_tactile_button(text, variant, _title_font)
	button.pressed.connect(callback)
	return button


func _toggle(text: String, callback: Callable) -> Button:
	var button := Kit.create_tactile_button(text, "subtle", _title_font)
	button.toggle_mode = true
	button.toggled.connect(callback)
	return button


func _label(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	return Kit.create_label(text, font_size, color, _title_font if title else _body_font)


func _center_text(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	var label := _label(text, font_size, color, title)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _panel(color: Color, horizontal: int, vertical: int, shadow: int = 0) -> PanelContainer:
	return Kit.create_folio_panel(color, horizontal, vertical, shadow)


func _rule(parent: Control) -> void:
	var line := ColorRect.new()
	line.color = Color("#b59c7c")
	line.custom_minimum_size.y = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)


func _place(control: Control, parent: Control, anchors: Vector4, offsets: Vector4) -> void:
	parent.add_child(control)
	control.anchor_left = anchors.x
	control.anchor_top = anchors.y
	control.anchor_right = anchors.z
	control.anchor_bottom = anchors.w
	control.offset_left = offsets.x
	control.offset_top = offsets.y
	control.offset_right = offsets.z
	control.offset_bottom = offsets.w


func _clear(container: Control) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _drop_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
