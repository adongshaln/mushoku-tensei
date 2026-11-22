extends "res://ui/folio_overlay.gd"

var _allow_save := false
var _save_mode := false
var _pending_id := ""
var _pending_delete := false
var _last_stamped_slot := ""

var _mode_bar: HBoxContainer
var _save_tab: Button
var _load_tab: Button
var _auto_slot_box: Control
var _grid: GridContainer
var _message_panel: PanelContainer
var _message: Label
var _confirm_layer: Control
var _confirm_card: PanelContainer
var _confirm_title: Label
var _confirm_detail: Label


func _ready() -> void:
	build("旅程手账", Vector2(1440.0, 916.0), false)

	_mode_bar = HBoxContainer.new()
	_mode_bar.add_theme_constant_override("separation", 18)
	page.add_child(_mode_bar)
	var tabs := ButtonGroup.new()
	_save_tab = Kit.create_gold_tab_button("记入手账 · 保存", title_font, 23)
	_load_tab = Kit.create_gold_tab_button("翻阅旧章 · 读取", title_font, 23)
	for button: Button in [_save_tab, _load_tab]:
		button.button_group = tabs
		button.custom_minimum_size = Vector2(214.0, 48.0)
	_save_tab.pressed.connect(_set_mode.bind(true, true))
	_load_tab.pressed.connect(_set_mode.bind(false, true))
	_mode_bar.add_child(_save_tab)
	_mode_bar.add_child(_load_tab)

	_auto_slot_box = VBoxContainer.new()
	_auto_slot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_slot_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	page.add_child(_auto_slot_box)

	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	page.add_child(_grid)

	_message_panel = Kit.create_smoked_hud_panel(18, 8, 4)
	_message_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message = line("", 18, Kit.BRASS, true)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_panel.add_child(_message)
	_message_panel.hide()
	page.add_child(_message_panel)

	_build_confirm_popup()

	SaveManager.slots_changed.connect(func() -> void:
		if is_open():
			_refresh())


func open(can_write: bool) -> void:
	_allow_save = can_write
	_last_stamped_slot = ""
	_message_panel.hide()
	_cancel()
	_set_mode(can_write, false)
	reveal()


func close() -> void:
	if not _pending_id.is_empty():
		_cancel()
		return
	super.close()


func _set_mode(saving: bool, animated: bool) -> void:
	_save_mode = saving and _allow_save
	_mode_bar.visible = _allow_save
	title_label.text = "记入手账" if _save_mode else "翻阅旧章 · 读取手账"
	_save_tab.set_pressed_no_signal(_save_mode)
	_load_tab.set_pressed_no_signal(not _save_mode)
	_sync_tab_underline(_save_tab, _save_mode)
	_sync_tab_underline(_load_tab, not _save_mode)
	_cancel()
	_refresh()
	if animated:
		Motion.fade_in(_grid, 0.18)
		AudioManager.play_sfx("page_flip")


func _sync_tab_underline(tab: Button, active: bool) -> void:
	var underline := tab.get_meta(&"gold_underline", null) as Control
	if underline != null:
		Motion.fade_alpha(underline, 1.0 if active else 0.0, 0.18)


func _refresh() -> void:
	clear(_auto_slot_box)
	clear(_grid)
	var slots := SaveManager.list_slots()
	for info: Dictionary in slots:
		if bool(info.get("is_auto", false)):
			_auto_slot_box.add_child(_build_auto_strip(info))
		else:
			_grid.add_child(_build_manual_card(info))
	_last_stamped_slot = ""


func _build_auto_strip(info: Dictionary) -> PanelContainer:
	var id := str(info["slot_id"])
	var state := str(info["status"])
	var strip := Kit.create_folio_panel(Kit.PAPER_DEEP, 18, 12, 3)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	strip.add_child(row)

	var seal := Kit.WaxSeal.new()
	seal.setup(Kit.WAX_RED if state == "invalid" else Kit.SAPPHIRE, "star", 44.0, state == "invalid")
	seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(seal)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	row.add_child(left)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	var auto_badge := Kit.create_badge("自动手账", Kit.SAPPHIRE, title_font, 16)
	auto_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(auto_badge)
	var sub_hint := "跨天与抵达城池时静默记录"
	if state == "ready":
		sub_hint = "%s  ·  保存于 %s" % [str(info.get("chapter_hint", "")), str(info.get("saved_at", ""))]
	var sub_lbl := Kit.create_label(sub_hint, 16, Kit.MUTED, body_font)
	sub_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(sub_lbl)

	if state == "ready":
		var summary := "%s（%d 岁）  ·  %s  ·  %s  ·  %s" % [
			str(info.get("character_name", "旅人")),
			int(info.get("age", 0)),
			str(info.get("location_name", "")),
			str(info.get("date_text", "")).replace("   ", " "),
			str(info.get("currency_text", ""))
		]
		var sum_lbl := Kit.create_label(summary, 19, Kit.INK, title_font)
		sum_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.add_child(sum_lbl)
	elif state == "invalid":
		left.add_child(Kit.create_label("自动存档损坏或版本不受支持，可删除清理。", 18, Kit.VERMILLION, body_font))
	else:
		left.add_child(Kit.create_label("— 尚无自动手账记录 —", 18, Kit.MUTED, body_font))

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 10)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	if _save_mode:
		var note := Kit.create_label("系统静默维护", 16, Kit.MUTED, body_font)
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		actions.add_child(note)
	else:
		var load_btn := _button("读取", "primary", _choose.bind(id, state, info))
		load_btn.disabled = state == "empty"
		actions.add_child(load_btn)
	var del_btn := _button("删除", "subtle", _ask.bind(id, true, info))
	del_btn.disabled = state == "empty"
	actions.add_child(del_btn)
	return strip


func _build_manual_card(info: Dictionary) -> PanelContainer:
	var id := str(info["slot_id"])
	var state := str(info["status"])
	var fill := Kit.PAPER if state == "ready" else Color("#efe5d3")
	var card := Kit.create_folio_panel(fill, 18, 14, 5 if state == "ready" else 1)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0.0, 232.0)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	card.add_child(body)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)

	var title_stack := VBoxContainer.new()
	title_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_stack.add_theme_constant_override("separation", 1)
	top.add_child(title_stack)
	title_stack.add_child(Kit.create_label(str(info["label"]), 23, Kit.INK, title_font))
	if state == "ready":
		title_stack.add_child(Kit.create_label(str(info.get("chapter_hint", "")), 15, Kit.SAPPHIRE, body_font))
	elif state == "empty":
		title_stack.add_child(Kit.create_label("空白章节", 15, Color("#9a856f"), body_font))
	else:
		title_stack.add_child(Kit.create_label("档案异常", 15, Kit.VERMILLION, body_font))

	# Wax seal stamp per slot.
	if state == "ready":
		var seal := Kit.WaxSeal.new()
		seal.setup(Kit.WAX_GOLD, "star", 40.0)
		seal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(seal)
		if id == _last_stamped_slot:
			Motion.stamp_impact(seal, 0.45)
	elif state == "invalid":
		var cracked := Kit.WaxSeal.new()
		cracked.setup(Kit.WAX_RED, "lock", 40.0, true)
		cracked.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(cracked)

	body.add_child(Kit.create_gold_divider(0.0, false, 6.0))

	if state == "empty":
		var center := VBoxContainer.new()
		center.size_flags_vertical = Control.SIZE_EXPAND_FILL
		center.alignment = BoxContainer.ALIGNMENT_CENTER
		center.add_theme_constant_override("separation", 4)
		body.add_child(center)
		var empty_mark := line("— 淡墨留白 —", 20, Color("#8f7a64"), true)
		empty_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(empty_mark)
		var sub := line("点击下方按钮记入此刻旅程" if _save_mode else "尚无记录，留待书写新章", 16, Color("#9a856f"))
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(sub)
	elif state == "invalid":
		var err_box := VBoxContainer.new()
		err_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		err_box.alignment = BoxContainer.ALIGNMENT_CENTER
		err_box.add_theme_constant_override("separation", 6)
		body.add_child(err_box)
		var err_title := line("档案损坏或版本不受支持", 19, Kit.VERMILLION, true)
		err_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_box.add_child(err_title)
		var err_hint := line("无法解析该手账内容，可覆盖或删除清理。", 15, Kit.MUTED)
		err_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		err_box.add_child(err_hint)
	else:
		var who_row := HBoxContainer.new()
		who_row.add_theme_constant_override("separation", 8)
		body.add_child(who_row)
		var who := Kit.create_label("%s  ·  %d 岁" % [str(info.get("character_name", "旅人")), int(info.get("age", 0))], 21, Kit.INK, title_font)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who_row.add_child(who)
		var coin_ic := Kit.create_micro_icon("coin", 16.0, Kit.WAX_GOLD)
		coin_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who_row.add_child(coin_ic)
		var money := Kit.create_label(str(info.get("currency_text", "")), 17, Kit.WAX_GOLD, title_font)
		money.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		who_row.add_child(money)

		var loc_row := HBoxContainer.new()
		loc_row.add_theme_constant_override("separation", 6)
		body.add_child(loc_row)
		var comp_ic := Kit.create_micro_icon("compass", 15.0, Kit.SAPPHIRE)
		comp_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		loc_row.add_child(comp_ic)
		loc_row.add_child(Kit.create_label(str(info.get("location_name", "")), 17, Kit.SAPPHIRE, body_font))

		body.add_child(Kit.create_label(str(info.get("date_text", "")).replace("   ", " "), 16, Kit.INK, body_font))

		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(spacer)

		body.add_child(Kit.create_label("封存于  " + str(info.get("saved_at", "")), 14, Color("#8a7560"), body_font))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	body.add_child(footer)
	var primary_text := "读取旧章" if not _save_mode else ("记入此页" if state == "empty" else "覆盖手账")
	var primary_variant := "primary"
	if _save_mode:
		primary_variant = "primary" if state == "empty" else "accent"
	elif state != "ready":
		primary_variant = "subtle"
	var action := _button(primary_text, primary_variant, _choose.bind(id, state, info))
	action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action.disabled = not _save_mode and state == "empty"
	footer.add_child(action)
	var delete := _button("删除", "subtle", _ask.bind(id, true, info))
	delete.disabled = state == "empty"
	footer.add_child(delete)
	return card


func _build_confirm_popup() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(_confirm_layer)
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var veil := ColorRect.new()
	veil.color = Color("#140d08bd")
	veil.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box_book := Kit.create_grimoire_book(Vector2(520.0, 240.0), 0.5, false)
	_confirm_card = box_book["binding"] as PanelContainer
	var inner := box_book["spread"] as PanelContainer
	center.add_child(_confirm_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	inner.add_child(box)
	_confirm_title = line("", 26, Kit.INK, true)
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_confirm_title)
	box.add_child(Kit.create_gold_divider(0.0, true, 10.0))
	_confirm_detail = line("", 18, Kit.MUTED)
	_confirm_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_confirm_detail)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	var cancel_btn := _button("取消", "secondary", _cancel)
	cancel_btn.custom_minimum_size = Vector2(142.0, 48.0)
	var ok_btn := _button("确认执行", "accent", _confirm)
	ok_btn.custom_minimum_size = Vector2(154.0, 48.0)
	row.add_child(cancel_btn)
	row.add_child(ok_btn)
	_confirm_layer.hide()


func _choose(id: String, state: String, info: Dictionary = {}) -> void:
	_cancel()
	if _save_mode:
		if state == "empty":
			_save(id)
		else:
			_ask(id, false, info)
	else:
		if state != "ready":
			_status("该手账档案损坏或版本不受支持，无法读取。", true)
			return
		if SaveManager.load_slot(id):
			AudioManager.play_sfx("page_flip")
			close_immediately()
		else:
			_status("此刻无法读取该手账。", true)


func _ask(id: String, deleting: bool, info: Dictionary = {}) -> void:
	_pending_id = id
	_pending_delete = deleting
	var slot_name := SaveManager.slot_label(id)
	_confirm_title.text = "确认删除「%s」？" % slot_name if deleting else "确认覆盖「%s」？" % slot_name
	var desc := "原有记录将被永久移除，无法撤销。" if deleting else "将使用当前旅程进度覆写此页原有记录。"
	if str(info.get("status", "")) == "ready":
		desc = "%s · %s\n%s" % [str(info.get("character_name", "")), str(info.get("date_text", "")).replace("   ", " "), desc]
	_confirm_detail.text = desc
	_confirm_layer.show()
	Motion.fade_in(_confirm_layer, 0.16)
	Motion.pop_badge(_confirm_card, 0.30)


func _cancel() -> void:
	_pending_id = ""
	if _confirm_layer != null:
		_confirm_layer.hide()


func _confirm() -> void:
	var id := _pending_id
	var deleting := _pending_delete
	_cancel()
	if deleting:
		var ok := SaveManager.delete_slot(id)
		_status("已删除「%s」。" % SaveManager.slot_label(id) if ok else "删除手账失败。", not ok)
		if ok:
			AudioManager.play_sfx("page_flip")
	else:
		_save(id)


func _save(id: String) -> void:
	_last_stamped_slot = id
	var ok := SaveManager.save_slot(id)
	_status("已盖印封存至「%s」。" % SaveManager.slot_label(id) if ok else "此刻无法记入手账。", not ok)
	if ok:
		AudioManager.play_sfx("page_flip")


func _status(message: String, warning: bool = false) -> void:
	_message.text = message
	_message.add_theme_color_override("font_color", Color("#ff9d8e") if warning else Kit.BRASS)
	_message_panel.show()
	Motion.fade_in(_message_panel, 0.18)


func _button(text: String, style_name: String, callback: Callable) -> Button:
	var button := Kit.create_tactile_button(text, style_name, title_font, 19)
	button.custom_minimum_size = Vector2(90.0, 46.0)
	button.pressed.connect(callback)
	return button
