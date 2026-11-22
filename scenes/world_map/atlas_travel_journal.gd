extends VBoxContainer

signal options_changed
signal route_mode_changed(manual: bool)
signal waypoint_undo_requested
signal waypoint_clear_requested
signal hub_transfer_requested(target_transport: String)
signal manual_requested(storylet_id: String)

const Kit := preload("res://ui/ui_theme_kit.gd")
const Planner := preload("res://core/travel_planner.gd")
const WARNING := Color("#AA4438")

var posture := Planner.STEADY
var manual_mode := false

var _mode_bar: VBoxContainer
var _rec_btn: Button
var _man_btn: Button
var _wp_panel: PanelContainer
var _wp_chain_lbl: Label
var _wp_undo_btn: Button
var _wp_clear_btn: Button

var _quote: VBoxContainer
var _summary: Label
var _transfer_panel: PanelContainer
var _transfer_lbl: Label
var _risk_flow: HFlowContainer
var _expenses: HFlowContainer
var _warning: Label
var _season: Label
var _path: Label
var _posture_group: VBoxContainer

var _hub_box: VBoxContainer
var _manual: VBoxContainer
var _title_font: Font
var _body_font: Font


func configure(title_font: Font, body_font: Font) -> void:
	_title_font = title_font
	_body_font = body_font
	add_theme_constant_override("separation", 10)

	# Dual-mode routing bar (最稳推荐 / 手动串点).
	_mode_bar = VBoxContainer.new()
	_mode_bar.add_theme_constant_override("separation", 7)
	add_child(_mode_bar)
	_mode_bar.add_child(Kit.create_ribbon_header("路线规划模式", _title_font, 19, Kit.WAX_GOLD))
	var toggle_row := HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 8)
	_mode_bar.add_child(toggle_row)
	var mode_group := ButtonGroup.new()
	_rec_btn = Kit.create_gold_tab_button("最稳推荐", _title_font, 18)
	_rec_btn.custom_minimum_size = Vector2(0.0, 44.0)
	_rec_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_btn.button_group = mode_group
	_rec_btn.set_pressed_no_signal(true)
	_rec_btn.pressed.connect(_set_route_mode.bind(false))
	toggle_row.add_child(_rec_btn)

	_man_btn = Kit.create_gold_tab_button("手动串点", _title_font, 18)
	_man_btn.custom_minimum_size = Vector2(0.0, 44.0)
	_man_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_man_btn.button_group = mode_group
	_man_btn.pressed.connect(_set_route_mode.bind(true))
	toggle_row.add_child(_man_btn)

	_wp_panel = Kit.create_folio_panel(Kit.PAPER_DEEP, 12, 10, 2)
	_mode_bar.add_child(_wp_panel)
	var wp_col := VBoxContainer.new()
	wp_col.add_theme_constant_override("separation", 7)
	_wp_panel.add_child(wp_col)
	_wp_chain_lbl = _line("请依次点击地图上的城池串联路线。", 15, Kit.INK)
	wp_col.add_child(_wp_chain_lbl)
	var wp_actions := HBoxContainer.new()
	wp_actions.add_theme_constant_override("separation", 8)
	wp_col.add_child(wp_actions)
	_wp_undo_btn = Kit.create_tactile_button("撤销上一点", "subtle", _title_font, 15)
	_wp_undo_btn.custom_minimum_size = Vector2(0.0, 44.0)
	_wp_undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wp_undo_btn.pressed.connect(func() -> void: waypoint_undo_requested.emit())
	wp_actions.add_child(_wp_undo_btn)
	_wp_clear_btn = Kit.create_tactile_button("清空", "subtle", _title_font, 15)
	_wp_clear_btn.custom_minimum_size = Vector2(72.0, 44.0)
	_wp_clear_btn.pressed.connect(func() -> void: waypoint_clear_requested.emit())
	wp_actions.add_child(_wp_clear_btn)
	var back_rec := Kit.create_tactile_button("切回推荐", "subtle", _title_font, 15)
	back_rec.custom_minimum_size = Vector2(88.0, 44.0)
	back_rec.pressed.connect(_set_route_mode.bind(false))
	wp_actions.add_child(back_rec)
	_wp_panel.hide()

	# Quote / itinerary panel.
	_quote = VBoxContainer.new()
	_quote.add_theme_constant_override("separation", 8)
	add_child(_quote)
	_summary = _line("", 21, Kit.INK, _title_font)
	_quote.add_child(_summary)

	_transfer_panel = Kit.create_folio_panel(Color("#e6eef4"), 12, 9, 2)
	_transfer_lbl = _line("", 16, Kit.SAPPHIRE, _title_font)
	_transfer_panel.add_child(_transfer_lbl)
	_quote.add_child(_transfer_panel)
	_transfer_panel.hide()

	_risk_flow = HFlowContainer.new()
	_risk_flow.add_theme_constant_override("h_separation", 8)
	_risk_flow.add_theme_constant_override("v_separation", 6)
	_quote.add_child(_risk_flow)

	_expenses = HFlowContainer.new()
	_expenses.add_theme_constant_override("h_separation", 8)
	_expenses.add_theme_constant_override("v_separation", 6)
	_quote.add_child(_expenses)

	_warning = _line("", 16, WARNING)
	_quote.add_child(_warning)

	_posture_group = _build_posture_group()
	_quote.add_child(_posture_group)

	_season = _line("", 15, Kit.SAPPHIRE)
	_quote.add_child(_season)
	_path = _line("", 15, Kit.SAPPHIRE)
	_quote.add_child(_path)

	# Current city hub transport services + local manual storylets.
	_hub_box = VBoxContainer.new()
	_hub_box.add_theme_constant_override("separation", 8)
	add_child(_hub_box)

	_manual = VBoxContainer.new()
	_manual.add_theme_constant_override("separation", 9)
	add_child(_manual)
	hide()


func set_manual_mode_silent(enabled: bool) -> void:
	manual_mode = enabled
	_rec_btn.set_pressed_no_signal(not enabled)
	_man_btn.set_pressed_no_signal(enabled)
	_wp_panel.visible = enabled


func present_plan(plan: Planner.Itinerary, route: String, waypoint_chain_text: String, waypoint_count: int, traveling: bool) -> void:
	show()
	_mode_bar.show()
	_hub_box.hide()
	_manual.hide()
	_wp_panel.visible = manual_mode
	_wp_chain_lbl.text = waypoint_chain_text if not waypoint_chain_text.is_empty() else "请依次点击地图上的城池添加途经点（相邻直连，跨城自动最稳补线）。"
	_wp_undo_btn.disabled = traveling or waypoint_count == 0
	_wp_clear_btn.disabled = traveling or waypoint_count == 0
	_rec_btn.disabled = traveling
	_man_btn.disabled = traveling

	if plan == null:
		_quote.hide()
		return
	_quote.show()

	var cur_mode_label := Planner.transport_label(WorldBlackboard.current_transport)
	if plan.requires_hub_transfer and not plan.actionable_legs.is_empty():
		_summary.text = "本段 %d km · %d 天（全程 %d km）· %s" % [
			plan.actionable_km, plan.actionable_days, plan.total_km, cur_mode_label
		]
	else:
		_summary.text = "%d km · 预计 %d 天 · %s" % [plan.total_km, plan.total_days, cur_mode_label]

	if plan.requires_hub_transfer:
		_transfer_lbl.text = "⚓ " + plan.transfer_hint
		_transfer_panel.show()
	else:
		_transfer_panel.hide()

	_clear(_risk_flow)
	var risk_col := Kit.WAX_GOLD if plan.risk_level == "steady" else (Kit.SAPPHIRE if plan.risk_level == "caution" else WARNING)
	_risk_flow.add_child(Kit.create_badge(plan.risk_label, risk_col, _title_font, 14))
	for tag: String in plan.risk_tags:
		if plan.risk_label.contains(tag):
			continue
		var tcol := WARNING if tag in ["魔物频发", "强盗出没"] else (Kit.SAPPHIRE if tag == "城门盘查" else Kit.AMBER)
		_risk_flow.add_child(Kit.create_badge(tag, tcol, _body_font, 14))

	_clear(_expenses)
	var use_act := plan.requires_hub_transfer and not plan.actionable_legs.is_empty()
	var req_rations := plan.actionable_ration_cost if use_act else plan.ration_cost
	var req_fare := plan.actionable_fare if use_act else plan.fare
	var req_ship := plan.actionable_ship_fare if use_act else plan.ship_fare

	var enough_ration := WorldBlackboard.get_total_rations() >= req_rations
	_expenses.add_child(Kit.create_status_badge("干粮 −%d" % req_rations, enough_ration, _body_font, 15))
	var enough_coin := WorldBlackboard.can_afford(req_fare)
	_expenses.add_child(Kit.create_status_badge("路费 " + WorldBlackboard.format_currency(req_fare), enough_coin, _body_font, 15))
	if req_ship > 0:
		_expenses.add_child(Kit.create_badge("含船票 " + WorldBlackboard.format_currency(req_ship), Kit.SAPPHIRE, _body_font, 14))
	elif plan.ship_fare > 0:
		_expenses.add_child(Kit.create_badge("后续海段船票参考 " + WorldBlackboard.format_currency(plan.ship_fare), Kit.SAPPHIRE, _body_font, 14))

	_path.text = route
	_season.text = "\n".join(plan.warnings)
	_season.visible = not _season.text.is_empty()
	var warnings: PackedStringArray = []
	if not traveling:
		if not WorldBlackboard.can_afford(req_fare):
			var shortage := req_fare - WorldBlackboard.currency_copper
			if not WorldBlackboard.can_afford(req_ship):
				warnings.append("船票不足 · 还差 " + WorldBlackboard.format_currency(req_ship - WorldBlackboard.currency_copper))
			elif (plan.actionable_caravan_fare if use_act else plan.caravan_fare) > 0:
				warnings.append("车马费用不足 · 还差 %s，可在当前城池切换徒步" % WorldBlackboard.format_currency(shortage))
		var missing := req_rations - WorldBlackboard.get_total_rations()
		if missing > 0:
			warnings.append("缺 %d 份干粮 · 强行赶路将陷入旅途疲惫" % missing)
	_warning.text = "\n".join(warnings)
	_warning.visible = not warnings.is_empty()
	for button: Button in _posture_group.find_children("*", "Button", true, false):
		button.disabled = traveling


func present_local_hub(city_name: String, hub_services: Dictionary, entries: Array[Dictionary], traveling: bool) -> void:
	show()
	_mode_bar.show()
	_wp_panel.visible = manual_mode
	_rec_btn.disabled = traveling
	_man_btn.disabled = traveling
	_quote.hide()
	_hub_box.show()
	_manual.show()

	_clear(_hub_box)
	_hub_box.add_child(Kit.create_ribbon_header("枢纽交通换乘 · %s" % city_name, _title_font, 19, Kit.SAPPHIRE))
	var current_mode := WorldBlackboard.current_transport
	_hub_box.add_child(_line("当前出行形态：%s（需在对应枢纽办理换乘）" % Planner.transport_label(current_mode), 15, Kit.MUTED))

	for mode: String in [Planner.FOOT, Planner.CARAVAN, Planner.SHIP, Planner.TELEPORT]:
		var svc: Dictionary = hub_services.get(mode, {})
		if svc.is_empty():
			continue
		var is_current := mode == current_mode
		var is_teleport := mode == Planner.TELEPORT
		var enabled := bool(svc.get("enabled", false)) and (not is_teleport or bool(svc.get("unlocked", false)))
		var ticket := Kit.create_folio_panel(Kit.PAPER_DEEP if (enabled or is_current) else Color("#eee4d2"), 13, 10, 2 if enabled else 0)
		_hub_box.add_child(ticket)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)
		ticket.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var icon_name := _transport_icon(mode, enabled)
		var ic := Kit.create_micro_icon(icon_name, 19.0, Kit.SAPPHIRE if mode == Planner.SHIP else (Kit.WAX_GOLD if enabled else Kit.MUTED))
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var title := Kit.create_label(str(svc.get("label", Planner.transport_label(mode))), 18, Kit.INK if (enabled or is_current) else Kit.MUTED, _title_font)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(title)
		var btn_label := "当前方式" if is_current else ("未开启" if is_teleport else ("办理" if enabled else "不可用"))
		var btn := Kit.create_tactile_button(btn_label, "primary" if (enabled and not is_current) else "subtle", _title_font, 15)
		btn.custom_minimum_size = Vector2(86.0, 44.0)
		btn.disabled = traveling or is_current or not enabled
		btn.pressed.connect(func() -> void: hub_transfer_requested.emit(mode))
		row.add_child(btn)
		var note := str(svc.get("note", ""))
		if not note.is_empty():
			col.add_child(_line(note, 14, Kit.MUTED))

	_clear(_manual)
	if entries.is_empty():
		return
	_manual.add_child(Kit.create_ribbon_header("此地委托与行动", _title_font, 19, Kit.WAX_GOLD))
	for entry: Dictionary in entries:
		var action: Dictionary = entry.get("action", {})
		var executable := StoryletScheduler.can_execute(entry)
		var is_room := str(action.get("type", "")) == "open_room"
		var ticket := Kit.create_folio_panel(Kit.PAPER_DEEP if executable else Color("#eee4d2"), 13, 10, 2 if executable else 0)
		_manual.add_child(ticket)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)
		ticket.add_child(col)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		var ic := Kit.create_micro_icon(_action_icon(action), 19.0, Kit.SAPPHIRE if is_room else Kit.WAX_GOLD)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ic)
		var t_lbl := Kit.create_label(str(entry["title"]), 19, Kit.INK if executable else Kit.MUTED, _title_font)
		t_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(t_lbl)
		var btn := Kit.create_tactile_button("前往" if is_room else "执行", "primary" if is_room else "secondary", _title_font, 16)
		btn.custom_minimum_size = Vector2(82.0, 44.0)
		btn.disabled = traveling or not executable
		btn.pressed.connect(manual_requested.emit.bind(str(entry["id"])))
		row.add_child(btn)
		var summary := str(entry.get("summary", ""))
		if not summary.is_empty():
			col.add_child(_line(summary, 15, WARNING if not executable else Kit.MUTED))


func _transport_icon(mode: String, enabled: bool) -> String:
	if mode == Planner.TELEPORT and not enabled:
		return "lock"
	match mode:
		Planner.CARAVAN:
			return "caravan"
		Planner.SHIP:
			return "ship"
		Planner.TELEPORT:
			return "star"
		_:
			return "foot"


func _action_icon(action: Dictionary) -> String:
	var atype := str(action.get("type", ""))
	if atype == "open_room":
		return "door"
	if atype == "event_hook":
		return "star"
	match str(action.get("quick", "")):
		"forage", "eat":
			return "ration"
		"rest":
			return "night"
		"earn":
			return "coin"
		"train":
			return "drop"
		"check":
			return "d20"
		_:
			return "compass"


func _line(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Kit.create_label(text, font_size, color, _body_font if font == null else font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _build_posture_group() -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 5)
	group.add_child(Kit.create_label("行军姿态（潜行压低沿途遇险概率）", 15, Kit.MUTED, _body_font))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	group.add_child(row)
	var buttons := ButtonGroup.new()
	var labels: Array[String] = ["稳健", "急行", "潜行"]
	var values: Array[String] = [Planner.STEADY, Planner.FORCED, Planner.STEALTH]
	var icons: Array[String] = ["compass", "spark", "eye"]
	for index: int in labels.size():
		var button := Kit.create_icon_button(icons[index], labels[index], "secondary", _title_font, 16, Kit.WAX_GOLD)
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = buttons
		button.set_pressed_no_signal(index == 0)
		button.pressed.connect(_set_posture.bind(values[index]))
		row.add_child(button)
	return group


func _set_posture(value: String) -> void:
	if posture == value:
		return
	posture = value
	options_changed.emit()


func _set_route_mode(manual: bool) -> void:
	if manual_mode == manual:
		return
	manual_mode = manual
	_rec_btn.set_pressed_no_signal(not manual)
	_man_btn.set_pressed_no_signal(manual)
	_wp_panel.visible = manual
	route_mode_changed.emit(manual)


func _clear(container: Control) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()
