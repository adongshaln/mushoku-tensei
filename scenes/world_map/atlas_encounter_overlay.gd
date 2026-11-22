extends CanvasLayer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const Encounter := preload("res://core/encounter_engine.gd")

signal _choice_picked(index: int)
signal _continue_pressed

var _engine: Encounter
var _shade: ColorRect
var _center: CenterContainer
var _card: PanelContainer
var _badge_box: HBoxContainer
var _title_lbl: Label
var _summary_lbl: Label
var _options_box: VBoxContainer
var _result_box: VBoxContainer
var _result_lbl: Label
var _continue_btn: Button
var _dice: DiceOverlay
var _title_font: SystemFont
var _body_font: SystemFont
var _active := false


func _ready() -> void:
	layer = 104
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()

	_shade = ColorRect.new()
	_shade.color = Color("#130d099e")
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()

	_center = CenterContainer.new()
	_center.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_card = Kit.create_folio_panel(Kit.PAPER, 30, 24, 14)
	_card.custom_minimum_size = Vector2(580.0, 0.0)
	_card.pivot_offset_ratio = Vector2(0.5, 0.5)
	_center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_card.add_child(col)

	_badge_box = HBoxContainer.new()
	_badge_box.add_theme_constant_override("separation", 10)
	col.add_child(_badge_box)

	_title_lbl = Kit.create_label("", 32, Kit.INK, _title_font)
	_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_title_lbl)

	col.add_child(Kit.create_gold_divider(0.0, true, 8.0))

	_summary_lbl = Kit.create_label("", 20, Kit.MUTED, _body_font)
	_summary_lbl.custom_minimum_size.x = 510.0
	_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary_lbl.add_theme_constant_override("line_spacing", 5)
	col.add_child(_summary_lbl)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 10)
	col.add_child(_options_box)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 12)
	col.add_child(_result_box)

	_result_lbl = Kit.create_label("", 20, Kit.INK, _title_font)
	_result_lbl.custom_minimum_size.x = 510.0
	_result_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_lbl.add_theme_constant_override("line_spacing", 5)
	_result_box.add_child(_result_lbl)

	_continue_btn = Kit.create_tactile_button("整顿启程 · 继续前行", "primary", _title_font, 20)
	_continue_btn.custom_minimum_size = Vector2(0.0, 50.0)
	_continue_btn.pressed.connect(func() -> void: _continue_pressed.emit())
	_result_box.add_child(_continue_btn)
	_result_box.hide()

	_center.hide()

	_dice = DiceOverlay.new()
	add_child(_dice)


func configure(engine: Encounter) -> void:
	_engine = engine


func is_active() -> bool:
	return _active


func present_encounter(encounter: Dictionary) -> void:
	if _active or encounter.is_empty():
		return
	_active = true
	_populate_encounter(encounter)
	_shade.show()
	_center.show()
	Motion.fade_in(_shade, 0.22)
	Motion.fade_in(_center, 0.24)
	Motion.spring(_card, ^"scale", Vector2(0.94, 0.94), Vector2.ONE, 0.34, 9.0, 7.5)
	AudioManager.play_sfx("page_flip")

	var picked_idx: int = await _choice_picked
	var options: Array = encounter.get("options", [])
	var outcome_text := "整顿行装后，继续踏上旅途。"
	if picked_idx >= 0 and picked_idx < options.size():
		var option: Dictionary = options[picked_idx]
		var check_cfg: Dictionary = option.get("check", {})
		if not check_cfg.is_empty():
			_center.hide()
			_shade.hide()
			var bundle := _engine.build_check_for_option(option)
			var rolled: Dictionary = bundle["check"]
			_dice.present(rolled, str(bundle["label"]), str(option.get("label", "")), false)
			await _dice.completed
			outcome_text = _engine.apply_check_outcome(option, bool(rolled.get("passed", false)))
			_shade.show()
			_center.show()
			Motion.fade_in(_center, 0.20)
		else:
			outcome_text = _engine.resolve_direct_option(option)

	_options_box.hide()
	_result_lbl.text = outcome_text
	_result_box.show()
	Motion.fade_in(_result_box, 0.20)
	AudioManager.play_sfx("page_flip")
	await _continue_pressed

	_center.hide()
	_shade.hide()
	_active = false


func _populate_encounter(encounter: Dictionary) -> void:
	for child: Node in _badge_box.get_children():
		_badge_box.remove_child(child)
		child.queue_free()
	var cat := str(encounter.get("category", "safe_road"))
	var cat_label := str(encounter.get("category_label", "旅途遭遇"))
	var tone := Kit.WAX_GOLD
	match cat:
		"demon_wilds", "bandit_road":
			tone = Kit.VERMILLION
		"border_check":
			tone = Kit.SAPPHIRE
		_:
			tone = Kit.AMBER
	var ribbon := Kit.create_ribbon_header("旅途见闻", _title_font, 19, tone)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_badge_box.add_child(ribbon)
	_badge_box.add_child(Kit.create_badge(cat_label, tone, _title_font, 15))

	_title_lbl.text = str(encounter.get("title", "沿途事件"))
	_summary_lbl.text = str(encounter.get("summary", ""))
	_result_box.hide()
	_options_box.show()

	for child: Node in _options_box.get_children():
		_options_box.remove_child(child)
		child.queue_free()

	var options: Array = encounter.get("options", [])
	for idx: int in options.size():
		var opt: Dictionary = options[idx]
		var label_text := str(opt.get("label", "继续"))
		var check_cfg: Dictionary = opt.get("check", {})
		var is_check := not check_cfg.is_empty()
		var suffix := ""
		if is_check:
			var stat_name := WorldBlackboard.stat_label(str(check_cfg.get("stat", "WIL")))
			suffix = "  [%s · DC %d" % [stat_name, int(check_cfg.get("dc", 12))]
			var hood_item := str(check_cfg.get("hood_bonus_item", ""))
			if not hood_item.is_empty() and WorldBlackboard.get_item_count(hood_item) > 0:
				suffix += " · 兜帽 +%d" % int(check_cfg.get("hood_bonus_value", 2))
			suffix += "]"
		var btn := Kit.create_icon_button("d20" if is_check else "compass", label_text + suffix,
			"primary" if idx == 0 else "secondary", _title_font, 17, Kit.IVORY if idx == 0 else Kit.WAX_GOLD)
		btn.custom_minimum_size = Vector2(0.0, 50.0)
		btn.pressed.connect(func() -> void:
			AudioManager.play_sfx("ui_click")
			_choice_picked.emit(idx))
		_options_box.add_child(btn)
