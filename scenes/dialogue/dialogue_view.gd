extends Control

const Art := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Runner := preload("res://core/dialogue_runner.gd")
const Portrait := preload("res://scenes/dialogue/portrait_slot.gd")
const Widgets := preload("res://scenes/dialogue/dialogue_widgets.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const CURTAIN_SHADER := preload("res://shaders/dialogue_curtain.gdshader")

const DEFAULT_RETURN := "res://scenes/room/room_explorer.tscn"
const MODES: Array[String] = ["natural", "force_success", "force_fail"]
const MODE_LABELS: Array[String] = ["自然掷骰", "强制成功", "失败推进"]
const SLOTS: Array[String] = ["left", "center", "right"]
const STAGE_CENTERS: Array[float] = [0.195, 0.50, 0.805]
const TYPE_SPEED := 43.0

var _runner := Runner.new()
var _return_scene := DEFAULT_RETURN
var _protagonist_id := "notia"
var _roll_mode_index := 0

var _background: TextureRect
var _village_placeholder: Texture2D
var _portraits: Array[Portrait] = []
var _speaker_bust: Portrait

var _hud: Control
var _curtain: ColorRect
var _line_stage: Control
var _speaker_diamond: Widgets.SpeakerDiamond
var _speaker: Label
var _hairline: Widgets.GoldHairline
var _line: Label
var _continue_mark: Widgets.ContinueDiamond
var _voice_button: Widgets.GhostActionButton

var _bottom_controls: HBoxContainer
var _log_button: Widgets.GhostActionButton
var _auto_button: Widgets.GhostActionButton
var _skip_button: Widgets.GhostActionButton
var _hide_button: Widgets.GhostActionButton

var _roll_mode_btn: Widgets.GhostActionButton
var _roll_dismiss: Button
var _roll_popover: PanelContainer
var _roll_checks: Array[Widgets.DialogueGlyph] = []
var _roll_row_labels: Array[Label] = []

var _choice_overlay: CenterContainer
var _choices: VBoxContainer
var _log_overlay: CenterContainer
var _log_rows: VBoxContainer
var _log_scroll: ScrollContainer
var _dice_overlay: DiceOverlay

var _title_font: SystemFont
var _body_font: SystemFont
var _curtain_tween: Tween
var _characters := 0.0
var _pace_elapsed := 0.0
var _hidden := false
var _leaving := false
var _voice_path := ""
var _speaker_id := ""
var _chars_per_sec := TYPE_SPEED
var _instant_text := false
var _auto_play_delay := 2.0


func _ready() -> void:
	var context := SceneTransition.take_context()
	_return_scene = str(context.get("return_scene", DEFAULT_RETURN))
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	theme = Theme.new()
	theme.default_font = _body_font
	theme.default_font_size = 24
	_bind_reading_settings()
	var started := _runner.start(str(context.get("dialogue_id", "418_village_gate")))
	_protagonist_id = str(_runner.script_data.get("protagonist_id", WorldBlackboard.profile.get("character_id", "notia")))
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


func _exit_tree() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null:
		if sm.is_connected("settings_changed", _on_settings_changed):
			sm.disconnect("settings_changed", _on_settings_changed)
		if sm.is_connected("settings_loaded", _sync_reading_settings):
			sm.disconnect("settings_loaded", _sync_reading_settings)
		if sm.is_connected("settings_reset", _sync_reading_settings):
			sm.disconnect("settings_reset", _sync_reading_settings)


func _bind_reading_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null:
		if sm.has_signal("settings_changed") and not sm.is_connected("settings_changed", _on_settings_changed):
			sm.connect("settings_changed", _on_settings_changed)
		if sm.has_signal("settings_loaded") and not sm.is_connected("settings_loaded", _sync_reading_settings):
			sm.connect("settings_loaded", _sync_reading_settings)
		if sm.has_signal("settings_reset") and not sm.is_connected("settings_reset", _sync_reading_settings):
			sm.connect("settings_reset", _sync_reading_settings)
	_sync_reading_settings()


func _on_settings_changed(section: String, _key: String, _value: Variant) -> void:
	if section == "reading":
		_sync_reading_settings()


func _sync_reading_settings() -> void:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		_chars_per_sec = TYPE_SPEED
		_instant_text = false
		_auto_play_delay = 2.0
		return
	_chars_per_sec = maxf(10.0, float(sm.call("get_text_speed_chars_per_sec")))
	_instant_text = bool(sm.call("is_instant_text_enabled"))
	_auto_play_delay = maxf(0.2, float(sm.call("get_auto_play_delay")))


func get_effective_chars_per_sec() -> float:
	return _chars_per_sec


func is_instant_text_enabled() -> bool:
	return _instant_text


func get_effective_auto_delay() -> float:
	return _auto_play_delay


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_hud, _log_overlay]


func set_roll_mode(index: int) -> void:
	_roll_mode_index = clampi(index, 0, MODES.size() - 1)
	_sync_roll_mode_visual()


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
	gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color("#140d096e"), Color("#1a120c00"), Color("#1a120c08"), Color("#120b0766")
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	atmosphere.texture = texture
	add_child(atmosphere)
	atmosphere.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	for center: float in STAGE_CENTERS:
		var slot := Portrait.new()
		slot.configure_stage_standing()
		_place(slot, self, Vector4(center, 0.125, center, 1.008), Vector4(-350.0, 0.0, 350.0, 0.0))
		_portraits.append(slot)
	for actor: Dictionary in _runner.script_data.get("opening_cast", []):
		_set_stage_portrait(actor)
	for portrait: Portrait in _portraits:
		if portrait.visible:
			portrait.set_active(false, true, true)


func _build_hud() -> void:
	_hud = Control.new()
	_hud.z_index = 10
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_build_top_bar()
	_build_bottom_stage()
	_build_choice_layer()
	_build_roll_popover()


func _build_top_bar() -> void:
	# Soft corner radial veil for frameless top-left light-novel chapter crest.
	var tl_veil := _make_corner_veil(Vector2(0.0, 0.0), Vector2(0.88, 0.0), 0.46)
	_place(tl_veil, _hud, Vector4(0.0, 0.0, 0.0, 0.0), Vector4(0.0, 0.0, 520.0, 180.0))

	var crest := VBoxContainer.new()
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest.add_theme_constant_override("separation", 3)
	_place(crest, _hud, Vector4(0.0, 0.0, 0.0, 0.0), Vector4(36.0, 22.0, 440.0, 114.0))

	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 9)
	crest.add_child(title_row)

	var star := Widgets.DialogueGlyph.new()
	star.setup("star", 15.0, Widgets.GOLD_WARM)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(star)

	var ch_title := _label(str(_runner.script_data.get("title", "")), 26, Widgets.IVORY_SOFT, true)
	ch_title.add_theme_color_override("font_shadow_color", Color("#090503d4"))
	ch_title.add_theme_constant_override("shadow_offset_y", 2)
	title_row.add_child(ch_title)

	var crest_rule := Widgets.GoldHairline.new()
	crest_rule.setup(true, 0.62, 6.0)
	crest_rule.custom_minimum_size = Vector2(215.0, 6.0)
	crest_rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	crest.add_child(crest_rule)

	var subtitle := _label(str(_runner.script_data.get("location", "")), 15, Color(Widgets.PARCHMENT_MUTED, 0.86))
	subtitle.add_theme_color_override("font_shadow_color", Color("#090503c8"))
	subtitle.add_theme_constant_override("shadow_offset_y", 1)
	crest.add_child(subtitle)

	# Soft corner radial veil for whisper-quiet top-right micro-icon cluster.
	var tr_veil := _make_corner_veil(Vector2(1.0, 0.0), Vector2(0.12, 0.0), 0.44)
	_place(tr_veil, _hud, Vector4(1.0, 0.0, 1.0, 0.0), Vector4(-320.0, 0.0, 0.0, 150.0))

	var utility_row := HBoxContainer.new()
	utility_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	utility_row.alignment = BoxContainer.ALIGNMENT_END
	utility_row.add_theme_constant_override("separation", 10)
	_place(utility_row, _hud, Vector4(1.0, 0.0, 1.0, 0.0), Vector4(-260.0, 18.0, -28.0, 62.0))

	var journal_btn := Widgets.GhostActionButton.new()
	journal_btn.setup("book", "", _title_font, 15, 19.0, 0.64, false)
	journal_btn.tooltip_text = "人物手账"
	journal_btn.pressed.connect(_open_character_journal)
	utility_row.add_child(journal_btn)

	var load_btn := Widgets.GhostActionButton.new()
	load_btn.setup("quill", "", _title_font, 15, 19.0, 0.64, false)
	load_btn.tooltip_text = "翻阅旧章 · 读档"
	load_btn.pressed.connect(_open_load_journal)
	utility_row.add_child(load_btn)

	var settings_btn := Widgets.GhostActionButton.new()
	settings_btn.setup("gear", "", _title_font, 15, 19.0, 0.64, false)
	settings_btn.tooltip_text = "系统设置"
	settings_btn.pressed.connect(_open_settings)
	utility_row.add_child(settings_btn)

	_roll_mode_btn = Widgets.GhostActionButton.new()
	_roll_mode_btn.setup("d20", "", _title_font, 15, 20.0, 0.66, false)
	_roll_mode_btn.pressed.connect(_toggle_roll_popover)
	utility_row.add_child(_roll_mode_btn)


func _build_bottom_stage() -> void:
	# Full-width cinematic feathered warm-espresso bottom curtain (zero boxy frame).
	_curtain = ColorRect.new()
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = CURTAIN_SHADER
	_curtain.material = mat
	_place(_curtain, _hud, Vector4(0.0, 1.0, 1.0, 1.0), Vector4(0.0, -326.0, 0.0, 0.0))

	# Off-stage speaker frameless feathered bust docked cleanly in the left cinema margin.
	_speaker_bust = Portrait.new()
	_place(_speaker_bust, _hud, Vector4(0.0, 1.0, 0.0, 1.0), Vector4(18.0, -284.0, 248.0, -2.0))
	_speaker_bust.configure_side_bust()
	_speaker_bust.hide()

	# Centered 72% light-novel reading column (generous 14% left & right film margins).
	_line_stage = Control.new()
	_line_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_line_stage, _hud, Vector4(0.14, 1.0, 0.86, 1.0), Vector4(0.0, -262.0, 0.0, -52.0))

	var stack := VBoxContainer.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_theme_constant_override("separation", 6)
	_line_stage.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var speaker_row := HBoxContainer.new()
	speaker_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	speaker_row.add_theme_constant_override("separation", 10)
	stack.add_child(speaker_row)

	_speaker_diamond = Widgets.SpeakerDiamond.new()
	_speaker_diamond.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speaker_row.add_child(_speaker_diamond)

	_speaker = _label("", 28, Widgets.IVORY_SOFT, true)
	_speaker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speaker.add_theme_color_override("font_shadow_color", Color("#080402dc"))
	_speaker.add_theme_constant_override("shadow_offset_y", 2)
	speaker_row.add_child(_speaker)

	_voice_button = Widgets.GhostActionButton.new()
	_voice_button.setup("voice", "", _title_font, 15, 17.0, 0.62, false)
	_voice_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_voice_button.pressed.connect(_replay_current)
	speaker_row.add_child(_voice_button)

	_hairline = Widgets.GoldHairline.new()
	_hairline.setup(true, 0.78, 8.0)
	stack.add_child(_hairline)

	var text_row := HBoxContainer.new()
	text_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_row.add_theme_constant_override("separation", 12)
	stack.add_child(text_row)

	var line_pad := MarginContainer.new()
	line_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line_pad.add_theme_constant_override("margin_top", 4)
	text_row.add_child(line_pad)

	_line = _label("", 30, Widgets.IVORY_SOFT, true)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.add_theme_constant_override("line_spacing", 12)
	_line.add_theme_color_override("font_shadow_color", Color("#090503d4"))
	_line.add_theme_constant_override("shadow_offset_y", 2)
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line.size_flags_vertical = Control.SIZE_EXPAND_FILL
	line_pad.add_child(_line)

	_continue_mark = Widgets.ContinueDiamond.new()
	_continue_mark.size_flags_vertical = Control.SIZE_SHRINK_END
	text_row.add_child(_continue_mark)
	_continue_mark.hide()

	# Bottom-right frameless micro-control strip (touch-safe >= 44px height, >= 10px spacing).
	_bottom_controls = HBoxContainer.new()
	_bottom_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom_controls.alignment = BoxContainer.ALIGNMENT_END
	_bottom_controls.add_theme_constant_override("separation", 12)
	_place(_bottom_controls, _hud, Vector4(0.14, 1.0, 0.86, 1.0), Vector4(0.0, -50.0, 0.0, -6.0))

	_log_button = _ghost_control("log", "回顾", false, _open_log)
	_auto_button = _ghost_control("auto", "自动", true, _on_auto)
	_skip_button = _ghost_control("skip", "快进", true, _on_skip)
	_hide_button = _ghost_control("hide", "隐藏", false, _set_hidden.bind(true))


func _build_choice_layer() -> void:
	# Lower-mid floating choice stack: keeps all standing character faces unobstructed.
	_choice_overlay = CenterContainer.new()
	_choice_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(_choice_overlay, _hud, Vector4(0.0, 0.44, 1.0, 0.90), Vector4(0.0, 0.0, 0.0, 0.0))
	_choices = VBoxContainer.new()
	_choices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_choices.custom_minimum_size.x = 840.0
	_choices.add_theme_constant_override("separation", 14)
	_choice_overlay.add_child(_choices)
	_choice_overlay.hide()


func _build_roll_popover() -> void:
	_roll_dismiss = Button.new()
	Widgets.clear_button_chrome(_roll_dismiss)
	_roll_dismiss.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_roll_dismiss.pressed.connect(_close_roll_popover)
	_hud.add_child(_roll_dismiss)
	_roll_dismiss.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_roll_dismiss.hide()

	# Warm parchment capsule popover replacing raw OptionButton.
	_roll_popover = Kit.create_folio_panel(Kit.PAPER, 12, 10, 12)
	_roll_popover.pivot_offset_ratio = Vector2(0.90, 0.0)
	_place(_roll_popover, _hud, Vector4(1.0, 0.0, 1.0, 0.0), Vector4(-214.0, 68.0, -26.0, 224.0))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	_roll_popover.add_child(col)

	var caption := Kit.create_label("检定掷骰模式", 13, Kit.MUTED, _title_font)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(caption)
	col.add_child(Kit.create_gold_divider(0.0, true, 6.0))

	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color("#dfc9a280")
	hover_box.set_corner_radius_all(8)
	var empty := StyleBoxEmpty.new()

	for i: int in MODE_LABELS.size():
		var item_btn := Button.new()
		item_btn.focus_mode = Control.FOCUS_NONE
		item_btn.custom_minimum_size = Vector2(160.0, 40.0)
		item_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item_btn.add_theme_stylebox_override("normal", empty)
		item_btn.add_theme_stylebox_override("hover", hover_box)
		item_btn.add_theme_stylebox_override("pressed", hover_box)
		item_btn.add_theme_stylebox_override("focus", empty)
		item_btn.pressed.connect(_select_roll_mode.bind(i))
		col.add_child(item_btn)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		item_btn.add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var lead := Control.new()
		lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lead.custom_minimum_size = Vector2(6.0, 1.0)
		row.add_child(lead)

		var check_ic := Widgets.DialogueGlyph.new()
		check_ic.setup("check", 14.0, Kit.WAX_GOLD)
		check_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(check_ic)
		_roll_checks.append(check_ic)

		var lbl := Kit.create_label(MODE_LABELS[i], 16, Kit.INK, _title_font)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		_roll_row_labels.append(lbl)

	_roll_popover.hide()
	_sync_roll_mode_visual()


func _build_log() -> void:
	_log_overlay = _modal()
	var book := Kit.create_grimoire_book(Vector2(1080.0, 760.0), 0.5, false)
	var binding := book["binding"] as PanelContainer
	var spread := book["spread"] as PanelContainer
	_log_overlay.add_child(binding)
	var journal := VBoxContainer.new()
	journal.add_theme_constant_override("separation", 14)
	spread.add_child(journal)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	journal.add_child(title_row)
	var ribbon := Kit.create_ribbon_header("对话回顾", _title_font, 28, Kit.WAX_GOLD)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(ribbon)
	var close_log_btn := Kit.create_icon_button("close", "合上", "dark_brass", _title_font, 18, Kit.BRASS)
	close_log_btn.custom_minimum_size = Vector2(104.0, 46.0)
	close_log_btn.pressed.connect(_close_log)
	title_row.add_child(close_log_btn)
	journal.add_child(Kit.create_gold_divider(0.0, true, 10.0))
	_log_scroll = ScrollContainer.new()
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	journal.add_child(_log_scroll)
	Kit.style_scrollbar(_log_scroll.get_v_scroll_bar())
	_log_rows = VBoxContainer.new()
	_log_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_rows.add_theme_constant_override("separation", 12)
	_log_scroll.add_child(_log_rows)
	_log_overlay.hide()


func _modal() -> CenterContainer:
	var shade := ColorRect.new()
	shade.z_index = 20
	shade.color = Color("#16100cc0")
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CenterContainer.new()
	layer.z_index = 21
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.visibility_changed.connect(func() -> void: shade.visible = layer.visible)
	return layer


func _present_node() -> void:
	AudioManager.stop_voice()
	_close_roll_popover(true)
	_pace_elapsed = 0.0
	_choice_overlay.hide()
	_line_stage.hide()
	match str(_runner.current.get("type", "error")):
		"line":
			_present_line(_runner.current)
		"choice":
			_skip_button.set_pressed_no_signal(false)
			_skip_button.refresh_visual()
			_present_choices()
		"end":
			_return_to_room()
		_:
			_show_error()


func _present_line(node: Dictionary) -> void:
	if node.has("bg"):
		_set_background(str(node["bg"]))
	var pid := str(node.get("portrait_id", ""))
	var slot_name := str(node.get("portrait_slot", ""))
	var expression := str(node.get("expression", ""))
	var is_protagonist := not pid.is_empty() and pid == _protagonist_id
	var cast: Dictionary = _runner.script_data.get("cast", {})
	var actor: Dictionary = cast.get(pid, {})

	if not pid.is_empty() and not is_protagonist:
		_set_stage_portrait(node)
	var on_stage := _is_speaker_on_stage(pid)

	for i: int in _portraits.size():
		if not _portraits[i].visible:
			continue
		if not on_stage:
			_portraits[i].set_active(false, true)
		else:
			var is_speaker_slot := _portraits[i].is_showing_actor(pid) or (not slot_name.is_empty() and SLOTS[i] == slot_name)
			_portraits[i].set_active(is_speaker_slot, false)

	var speaker_name := str(node.get("speaker", ""))
	var is_narration := speaker_name.is_empty()
	_speaker.text = "旁白" if is_narration else speaker_name
	_speaker.add_theme_color_override("font_color", Color("#ead2a8") if is_narration else Widgets.IVORY_SOFT)

	var accent := Widgets.accent_color_for(pid, actor)
	_speaker_diamond.set_tone(accent)
	_hairline.set_accent(accent)

	_line.text = str(node.get("text", ""))
	var show_all_now := _skip_button.button_pressed or _instant_text
	_characters = float(_line.text.length()) if show_all_now else 0.0
	_line.visible_characters = int(_characters)
	_line_stage.show()
	_fade_curtain(1.0)
	_auto_button.set_soft_disabled(false)
	_skip_button.set_soft_disabled(false)

	# Smart anti-duplicate portrait rule:
	# Hide side bust whenever speaker already stands on stage; only show frameless feathered bust for off-stage speakers with art.
	if (not pid.is_empty()) and (not on_stage) and _speaker_bust.has_portrait_art(pid, expression):
		var actor_data: Dictionary = actor if not actor.is_empty() else {"name": speaker_name if not is_narration else pid}
		_speaker_bust.show_portrait(pid, expression, actor_data)
	else:
		_speaker_bust.hide_side_bust()

	_speaker_id = pid
	_voice_path = str(node.get("voice", ""))
	var recorded := AudioManager.has_voice(_voice_path)
	_voice_button.set_soft_disabled(not recorded)
	_voice_button.tooltip_text = "重播当前一句语音" if recorded else "尚未录入配音"
	if not _skip_button.button_pressed:
		AudioManager.play_voice(_voice_path, _speaker_id)
	_continue_mark.visible = show_all_now


func _present_choices() -> void:
	_speaker_bust.hide_side_bust()
	_fade_curtain(0.36)
	_auto_button.set_soft_disabled(true)
	_skip_button.set_soft_disabled(true)
	for portrait: Portrait in _portraits:
		if portrait.visible:
			portrait.set_active(false, true)

	_clear(_choices)
	var options := _runner.choices()
	for idx: int in options.size():
		var option: Dictionary = options[idx]
		var opt_id := str(option["id"])
		var text := str(option["text"])
		var check: Dictionary = option.get("check", {})
		var is_check := not check.is_empty()
		var meta: Array[Dictionary] = []
		if is_check:
			var breakdown := RuleEngine.collect_check(str(check["stat"]), check.get("context", {}))
			var total_mod := int(breakdown["total_mod"])
			meta.append({
				"text": "%s · DC %d" % [str(check.get("label", check["stat"])), int(check["dc"])],
				"color": Color("#a4d0ea")
			})
			meta.append({
				"text": "总修正 %+d" % total_mod,
				"color": Kit.MODIFIER_WARM_VALUE if total_mod >= 0 else Kit.MODIFIER_COLD_VALUE
			})
			for bonus: Dictionary in breakdown["bonus_list"]:
				var bval := int(bonus["value"])
				meta.append({
					"text": "%s %+d" % [RuleEngine.bonus_label(bonus), bval],
					"color": Kit.MODIFIER_WARM_LIGHT if bval >= 0 else Kit.MODIFIER_COLD_LIGHT
				})

		var ribbon := Widgets.ChoiceRibbon.new()
		ribbon.setup(text, is_check, meta, _title_font, _body_font)
		ribbon.pressed.connect(_select_option.bind(opt_id))
		_choices.add_child(ribbon)
		ribbon.modulate.a = 0.0
		var delay := float(idx) * 0.055
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		tw.tween_property(ribbon, "modulate:a", 1.0, 0.24).set_delay(delay)

	_choice_overlay.show()


func _select_option(id: String) -> void:
	if _leaving or SceneTransition.is_busy() or _dice_overlay.is_active() or _log_overlay.visible or JournalUI.is_open():
		return
	_close_roll_popover(true)
	var option_text := ""
	var check_label := ""
	for option: Dictionary in _runner.choices():
		if str(option["id"]) == id:
			option_text = str(option["text"])
			var check: Dictionary = option.get("check", {})
			check_label = str(check.get("label", check.get("stat", "检定")))
	if not _runner.choose(id, MODES[_roll_mode_index]):
		return
	AudioManager.play_sfx("ui_click")
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
	if _leaving or _hidden or SceneTransition.is_busy() or _log_overlay.visible or _dice_overlay.is_active() or JournalUI.is_open() or _roll_popover.visible or _runner.current.get("type") != "line":
		return
	var full := _line.text.length()
	if _characters < full:
		if _instant_text:
			_characters = float(full)
		else:
			_characters = minf(float(full), _characters + _chars_per_sec * delta)
		_line.visible_characters = int(_characters)
		return
	_continue_mark.show()
	if _skip_button.button_pressed or (_auto_button.button_pressed and not AudioManager.is_voice_playing()):
		_pace_elapsed += delta
		var delay := 0.10 if _skip_button.button_pressed else _auto_play_delay
		if _pace_elapsed >= delay:
			_advance()
	else:
		_pace_elapsed = 0.0


func _advance() -> void:
	if _leaving or _hidden or SceneTransition.is_busy() or _log_overlay.visible or _dice_overlay.is_active() or JournalUI.is_open() or _roll_popover.visible or _runner.current.get("type") != "line":
		return
	var full := _line.text.length()
	if _characters < full:
		_characters = float(full)
		_line.visible_characters = full
		_continue_mark.show()
		return
	AudioManager.play_sfx("page_flip")
	_runner.next_line()
	_present_node()


func _on_auto(enabled: bool) -> void:
	if enabled:
		_skip_button.set_pressed_no_signal(false)
		_skip_button.refresh_visual()
		_pace_elapsed = 0.0


func _on_skip(enabled: bool) -> void:
	if enabled and _runner.current.get("type") == "line":
		_auto_button.set_pressed_no_signal(false)
		_auto_button.refresh_visual()
		AudioManager.stop_voice()
		_characters = float(_line.text.length())
		_line.visible_characters = int(_characters)
		_continue_mark.show()
	elif enabled:
		_skip_button.set_pressed_no_signal(false)
		_skip_button.refresh_visual()
	_pace_elapsed = 0.0


func _replay_current() -> void:
	AudioManager.play_voice(_voice_path, _speaker_id)


func _open_settings() -> void:
	if _dice_overlay.is_active() or _log_overlay.visible or JournalUI.is_open():
		return
	_close_roll_popover(true)
	AudioManager.play_sfx("ui_click")
	JournalUI.open_settings("reading")


func _open_character_journal() -> void:
	if _dice_overlay.is_active() or _log_overlay.visible or JournalUI.is_open():
		return
	_close_roll_popover(true)
	AudioManager.play_sfx("ui_click")
	JournalUI.character.open()


func _open_load_journal() -> void:
	if _dice_overlay.is_active() or _log_overlay.visible or JournalUI.is_open():
		return
	_close_roll_popover(true)
	AudioManager.play_sfx("ui_click")
	JournalUI.saves.open(false)


func _toggle_roll_popover() -> void:
	if _dice_overlay.is_active() or _log_overlay.visible or JournalUI.is_open():
		return
	AudioManager.play_sfx("ui_click")
	if _roll_popover.visible:
		_close_roll_popover()
	else:
		_open_roll_popover()


func _open_roll_popover() -> void:
	_roll_dismiss.show()
	_roll_popover.show()
	_roll_popover.modulate.a = 0.0
	Motion.fade_alpha(_roll_popover, 1.0, 0.16)
	Motion.spring(_roll_popover, ^"scale", Vector2(0.90, 0.84), Vector2.ONE, 0.34, 9.5, 8.0)


func _close_roll_popover(instant: bool = false) -> void:
	_roll_dismiss.hide()
	if not _roll_popover.visible:
		return
	Motion.cancel(_roll_popover, ^"scale")
	Motion.cancel(_roll_popover, ^"modulate:a")
	if instant:
		_roll_popover.scale = Vector2.ONE
		_roll_popover.modulate.a = 1.0
		_roll_popover.hide()
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tw.tween_property(_roll_popover, "modulate:a", 0.0, 0.12)
	tw.tween_property(_roll_popover, "scale", Vector2(0.94, 0.90), 0.12)
	tw.chain().tween_callback(func() -> void:
		_roll_popover.hide()
		_roll_popover.scale = Vector2.ONE)


func _select_roll_mode(index: int) -> void:
	AudioManager.play_sfx("ui_click")
	set_roll_mode(index)
	_close_roll_popover()


func _sync_roll_mode_visual() -> void:
	for i: int in _roll_checks.size():
		var active := i == _roll_mode_index
		_roll_checks[i].modulate.a = 1.0 if active else 0.0
		_roll_row_labels[i].add_theme_color_override("font_color", Kit.WAX_GOLD.darkened(0.28) if active else Kit.INK)
	if _roll_mode_btn != null:
		_roll_mode_btn.tooltip_text = "掷骰模式：%s（点击切换）" % MODE_LABELS[_roll_mode_index]
		match _roll_mode_index:
			1:
				_roll_mode_btn.set_indicator_dot(Color("#54c48a"))
			2:
				_roll_mode_btn.set_indicator_dot(Color("#e06258"))
			_:
				_roll_mode_btn.set_indicator_dot(Color(0.0, 0.0, 0.0, 0.0))


func _input(event: InputEvent) -> void:
	if _leaving or SceneTransition.is_busy():
		return
	if JournalUI.handle_scene_input(event, false):
		return
	var key := event as InputEventKey
	var click := event as InputEventMouseButton
	if _roll_popover.visible and key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		_close_roll_popover()
		get_viewport().set_input_as_handled()
		return
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
	elif key != null and key.pressed and not key.echo and key.keycode == KEY_SPACE and not _dice_overlay.is_active() and not _log_overlay.visible and not _roll_popover.visible:
		_advance()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()


func _set_hidden(hidden: bool) -> void:
	_close_roll_popover(true)
	_hidden = hidden
	_hud.visible = not hidden
	for portrait: Portrait in _portraits:
		portrait.set_captions_visible(not hidden)


func _open_log() -> void:
	if _dice_overlay.is_active() or JournalUI.is_open():
		return
	_close_roll_popover(true)
	_drop_focus()
	_clear(_log_rows)
	var cast: Dictionary = _runner.script_data.get("cast", {})
	for entry: Dictionary in _runner.history:
		var row := _panel(Kit.PAPER_DEEP, 17, 12)
		_log_rows.add_child(row)
		var sections := VBoxContainer.new()
		sections.add_theme_constant_override("separation", 8)
		row.add_child(sections)
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		sections.add_child(header)
		var pid := str(entry.get("portrait_id", ""))
		var speaker_name := str(entry.get("speaker", ""))
		var tone := Widgets.accent_color_for(pid, cast.get(pid, {})).darkened(0.24) if not speaker_name.is_empty() else Kit.MUTED
		var speaker_label := _label(speaker_name if not speaker_name.is_empty() else "旁白", 21, tone, true)
		speaker_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speaker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		header.add_child(speaker_label)
		var voice := str(entry.get("voice", ""))
		var replay := _button("重播语音", AudioManager.play_voice.bind(voice), "subtle")
		replay.add_theme_font_size_override("font_size", 18)
		replay.custom_minimum_size.y = 44.0
		replay.disabled = not AudioManager.has_voice(voice)
		replay.tooltip_text = "尚未录入配音" if replay.disabled else "播放这句台词"
		header.add_child(replay)
		var text := _label(str(entry["text"]), 24, Kit.INK, true)
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
	_choices.add_child(_center_text("剧本暂时无法继续。", 26, Widgets.IVORY_SOFT))
	_choices.add_child(_button("返回木屋", _return_to_room, "primary"))
	_choice_overlay.show()


func _set_background(id: String) -> void:
	var texture := Art.load_texture("res://assets/backgrounds/%s.png" % id) if not id.is_empty() else null
	if texture == null:
		if _village_placeholder == null:
			_village_placeholder = Art.make_village()
		texture = _village_placeholder
	_background.texture = texture


func _set_stage_portrait(node: Dictionary) -> void:
	var id := str(node.get("portrait_id", ""))
	if id.is_empty() or id == _protagonist_id:
		return
	var index := SLOTS.find(str(node.get("portrait_slot", "")))
	if index < 0:
		return
	var cast: Dictionary = _runner.script_data.get("cast", {})
	_portraits[index].show_portrait(id, str(node.get("expression", "")), cast.get(id, {"name": id}))


func _is_speaker_on_stage(pid: String) -> bool:
	if pid.is_empty():
		return false
	for portrait: Portrait in _portraits:
		if portrait.is_showing_actor(pid):
			return true
	return false


func _fade_curtain(target_alpha: float) -> void:
	if _curtain_tween != null and _curtain_tween.is_valid():
		_curtain_tween.kill()
	_curtain_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_curtain_tween.tween_property(_curtain, "modulate:a", target_alpha, 0.22)


func _make_corner_veil(from_uv: Vector2, to_uv: Vector2, peak_alpha: float) -> TextureRect:
	var veil := TextureRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.42, 0.78, 1.0])
	grad.colors = PackedColorArray([
		Color(0.08, 0.055, 0.038, peak_alpha),
		Color(0.08, 0.055, 0.038, peak_alpha * 0.42),
		Color(0.08, 0.055, 0.038, peak_alpha * 0.08),
		Color(0.08, 0.055, 0.038, 0.0)
	])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = from_uv
	tex.fill_to = to_uv
	veil.texture = tex
	return veil


func _ghost_control(icon_kind: String, text_str: String, is_toggle: bool, callback: Callable) -> Widgets.GhostActionButton:
	var btn := Widgets.GhostActionButton.new()
	btn.setup(icon_kind, text_str, _title_font, 16, 15.0, 0.56, true)
	btn.toggle_mode = is_toggle
	if is_toggle:
		btn.toggled.connect(callback)
	else:
		btn.pressed.connect(callback)
	_bottom_controls.add_child(btn)
	return btn


func _button(text: String, callback: Callable, variant := "secondary") -> Button:
	var button := Kit.create_tactile_button(text, variant, _title_font, 18)
	button.pressed.connect(callback)
	return button


func _label(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	return Kit.create_label(text, font_size, color, _title_font if title else _body_font)


func _center_text(text: String, font_size: int, color: Color, title: bool = false) -> Label:
	var label := _label(text, font_size, color, title)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _panel(color: Color, horizontal: int, vertical: int, shadow: int = 0) -> PanelContainer:
	return Kit.create_folio_panel(color, horizontal, vertical, shadow)


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
