extends VBoxContainer

signal options_changed
signal manual_requested(storylet_id: String)

const Kit := preload("res://ui/ui_theme_kit.gd")
const Planner := preload("res://core/travel_planner.gd")
const WARNING := Color("#AA4438")

var transport := Planner.FOOT
var posture := Planner.STEADY

var _quote: VBoxContainer
var _summary: Label
var _path: Label
var _season: Label
var _expenses: Label
var _warning: Label
var _manual: VBoxContainer
var _title_font: Font
var _body_font: Font


func configure(title_font: Font, body_font: Font) -> void:
	_title_font = title_font
	_body_font = body_font
	add_theme_constant_override("separation", 10)
	_quote = VBoxContainer.new()
	_quote.add_theme_constant_override("separation", 8)
	add_child(_quote)
	_quote.add_child(Kit.create_ribbon_header("行程", _title_font, 21, Kit.AMBER))
	_summary = _line("", 22, Kit.INK, _title_font)
	_quote.add_child(_summary)
	_expenses = _line("", 18, Kit.MUTED)
	_quote.add_child(_expenses)
	_warning = _line("", 18, WARNING)
	_quote.add_child(_warning)

	_quote.add_child(_choose("出行方式", ["徒步", "商队"], [Planner.FOOT, Planner.CARAVAN], true))
	_quote.add_child(_choose("行军姿态", ["稳健", "急行", "谨慎潜行"], [Planner.STEADY, Planner.FORCED, Planner.STEALTH], false))
	_season = _line("", 17, Kit.BLUE)
	_quote.add_child(_season)
	_path = _line("", 17, Kit.BLUE)
	_quote.add_child(_path)

	_manual = VBoxContainer.new()
	_manual.add_theme_constant_override("separation", 8)
	add_child(_manual)
	hide()


func present_plan(plan: Planner.Itinerary, route: String, traveling: bool) -> void:
	show()
	_manual.hide()
	_quote.show()
	_summary.text = "%d km · 预计 %d 天" % [plan.total_km, plan.total_days]
	_expenses.text = "干粮 −%d   ·   路费 %s" % [plan.ration_cost, WorldBlackboard.format_currency(plan.fare)]
	if plan.ship_fare > 0:
		_expenses.text += "\n船票 %s" % WorldBlackboard.format_currency(plan.ship_fare)
		if plan.caravan_fare > 0:
			_expenses.text += "   ·   车马 " + WorldBlackboard.format_currency(plan.caravan_fare)
	_path.text = route
	_season.text = "\n".join(plan.warnings)
	_season.visible = not _season.text.is_empty()
	var warnings: PackedStringArray = []
	if not traveling:
		if not WorldBlackboard.can_afford(plan.fare):
			var shortage := plan.fare - WorldBlackboard.currency_copper
			if not WorldBlackboard.can_afford(plan.ship_fare):
				warnings.append("船票不足 · 还差 " + WorldBlackboard.format_currency(plan.ship_fare - WorldBlackboard.currency_copper))
			elif plan.caravan_fare > 0:
				warnings.append("车马费用不足 · 还差 %s，可改徒步" % WorldBlackboard.format_currency(shortage))
		var missing := plan.ration_cost - WorldBlackboard.get_total_rations()
		if missing > 0:
			warnings.append("缺 %d 份干粮 · 强行赶路会疲惫" % missing)
	_warning.text = "\n".join(warnings)
	_warning.visible = not warnings.is_empty()
	for child: Node in _quote.get_children():
		if child is VBoxContainer:
			for button: Button in child.find_children("*", "Button", true, false):
				button.disabled = traveling


func present_manual(entries: Array[Dictionary]) -> void:
	show()
	_quote.hide()
	_manual.show()
	for child: Node in _manual.get_children():
		_manual.remove_child(child)
		child.queue_free()
	if entries.is_empty():
		return
	_manual.add_child(Kit.create_ribbon_header("此地行动", _title_font, 21, Kit.BLUE))
	for entry: Dictionary in entries:
		var action: Dictionary = entry.get("action", {})
		var style := "primary" if str(action.get("type", "")) == "open_room" else "secondary"
		var button := Kit.create_tactile_button(str(entry["title"]), style, _title_font, 20)
		button.custom_minimum_size.y = 48
		button.disabled = not StoryletScheduler.can_execute(entry)
		button.pressed.connect(manual_requested.emit.bind(str(entry["id"])))
		_manual.add_child(button)
		var summary := str(entry.get("summary", ""))
		if not summary.is_empty():
			_manual.add_child(_line(summary, 17, WARNING if button.disabled else Kit.MUTED))


func _line(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Kit.create_label(text, font_size, color, _body_font if font == null else font)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _choose(title: String, labels: Array[String], values: Array[String], is_transport: bool) -> VBoxContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 5)
	group.add_child(Kit.create_label(title, 17, Kit.MUTED, _body_font))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	group.add_child(row)
	var buttons := ButtonGroup.new()
	for index: int in labels.size():
		var button := Kit.create_tactile_button(labels[index], "secondary", _title_font, 19)
		button.custom_minimum_size.y = 46
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = buttons
		button.set_pressed_no_signal(index == 0)
		button.pressed.connect(_set_choice.bind(values[index], is_transport))
		row.add_child(button)
	return group


func _set_choice(value: String, is_transport: bool) -> void:
	if is_transport:
		if transport == value:
			return
		transport = value
	else:
		if posture == value:
			return
		posture = value
	options_changed.emit()
