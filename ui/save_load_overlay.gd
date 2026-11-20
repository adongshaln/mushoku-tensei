extends "res://ui/folio_overlay.gd"

var _allow_save := false
var _save_mode := false
var _pending_id := ""
var _pending_delete := false
var _pending_row: HBoxContainer
var _confirm_text: Label
var _message: Label
var _mode: HBoxContainer
var _save_tab: Button
var _load_tab: Button
var _slots: VBoxContainer


func _ready() -> void:
	build("旅程手账", Vector2(1060.0, 844.0))
	_mode = HBoxContainer.new()
	_mode.add_theme_constant_override("separation", 10)
	page.add_child(_mode)
	_save_tab = _button("保存进度", "secondary", _set_mode.bind(true))
	_load_tab = _button("读取进度", "secondary", _set_mode.bind(false))
	var tabs := ButtonGroup.new()
	for button: Button in [_save_tab, _load_tab]:
		button.toggle_mode = true
		button.button_group = tabs
	_mode.add_child(_save_tab)
	_mode.add_child(_load_tab)
	_slots = scroll_into(page)
	_pending_row = HBoxContainer.new()
	_pending_row.add_theme_constant_override("separation", 10)
	page.add_child(_pending_row)
	_confirm_text = line("", 20, Kit.VERMILLION)
	_confirm_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pending_row.add_child(_confirm_text)
	_pending_row.add_child(_button("确认", "accent", _confirm))
	_pending_row.add_child(_button("取消", "secondary", _cancel))
	_pending_row.hide()
	_message = line("", 18, Kit.BLUE)
	_message.hide()
	page.add_child(_message)
	SaveManager.slots_changed.connect(func() -> void:
		if is_open():
			_refresh())


func open(can_write: bool) -> void:
	_allow_save = can_write
	_message.hide()
	_set_mode(can_write)
	reveal()


func close() -> void:
	if not _pending_id.is_empty():
		_cancel()
		return
	super.close()


func _set_mode(saving: bool) -> void:
	_save_mode = saving
	_mode.visible = _allow_save
	_save_tab.set_pressed_no_signal(saving)
	_load_tab.set_pressed_no_signal(not saving)
	_cancel()
	_refresh()


func _refresh() -> void:
	clear(_slots)
	for id: String in SaveManager.SLOTS:
		var info := SaveManager.slot_info(id)
		var state := str(info["status"])
		var row_panel := Kit.create_folio_panel(Kit.PAPER_DEEP, 14, 5, 0)
		_slots.add_child(row_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row_panel.add_child(row)
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		details.add_child(line(SaveManager.slot_label(id), 23, Kit.INK, true))
		var caption := "空白"
		if state == "invalid":
			caption = "档案损坏或版本不受支持"
		elif state == "ready":
			var identity := str(info.get("name", "旧手账"))
			var location := str(info.get("location", ""))
			var date := str(info.get("date", ""))
			caption = identity if location.is_empty() else "%s · %s" % [identity, location]
			if not date.is_empty():
				caption += "    " + date
		details.add_child(line(caption, 18, Kit.VERMILLION if state == "invalid" else Kit.MUTED))
		var text := "读取" if not _save_mode else ("保存" if state == "empty" else "覆盖")
		var action := _button(text, "primary", _choose.bind(id, state))
		action.disabled = (state != "ready") if not _save_mode else id == "auto"
		action.visible = not (_save_mode and id == "auto")
		row.add_child(action)
		var delete := _button("删除", "subtle", _ask.bind(id, true))
		delete.disabled = state == "empty"
		row.add_child(delete)


func _choose(id: String, state: String) -> void:
	_cancel()
	if _save_mode:
		if state == "empty":
			_save(id)
		else:
			_ask(id, false)
	elif SaveManager.load_slot(id):
		super.close()
	else:
		_status("无法读取该手账。")


func _ask(id: String, deleting: bool) -> void:
	_pending_id = id
	_pending_delete = deleting
	_confirm_text.text = "%s「%s」？" % ["删除" if deleting else "覆盖", SaveManager.slot_label(id)]
	_pending_row.show()


func _cancel() -> void:
	_pending_id = ""
	_pending_row.hide()


func _confirm() -> void:
	var id := _pending_id
	var deleting := _pending_delete
	_cancel()
	if deleting:
		_status("手账已删除。" if SaveManager.remove_slot(id) else "删除失败。")
	else:
		_save(id)


func _save(id: String) -> void:
	_status("已保存至「%s」。" % SaveManager.slot_label(id) if SaveManager.save_slot(id) else "此刻无法保存。")


func _status(message: String) -> void:
	_message.text = message
	_message.show()


func _button(text: String, style: String, callback: Callable) -> Button:
	var button := Kit.create_tactile_button(text, style, title_font, 21)
	button.custom_minimum_size = Vector2(94.0, 46.0)
	button.pressed.connect(callback)
	return button
