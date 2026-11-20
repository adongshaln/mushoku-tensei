extends CanvasLayer

signal hook_triggered(hook_id: String, context: Dictionary)

const STORYLET_DIR := "res://data/storylets/"
const ROOM_SCENE := "res://scenes/room/room_explorer.tscn"
const DIALOGUE_SCENE := "res://scenes/dialogue/dialogue_view.tscn"
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const DiceOverlay := preload("res://ui/dice_roll_overlay.gd")
const Planner := preload("res://core/travel_planner.gd")


class Interruption extends RefCounted:
	var leg_index: int
	var storylet: Dictionary

var _pool: Array[Dictionary] = []
var _save_extras: Dictionary = {}
var _completed: Dictionary[String, bool] = {}
var _handlers: Dictionary[String, Callable] = {}
var _arrival_queue: Array[Dictionary] = []
var _running := false
var _toast: PanelContainer
var _toast_text: Label
var _toast_timer: Timer
var _dice: DiceOverlay
var _title_font: SystemFont
var _body_font: SystemFont
var _encounter: Control
var _encounter_title: Label
var _encounter_summary: Label
var _encounter_continue: Button


func _ready() -> void:
	layer = 105
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	for file: String in DirAccess.get_files_at(STORYLET_DIR):
		if not file.ends_with(".json"):
			continue
		var data := WorldBlackboard.read_config(STORYLET_DIR + file)
		for storylet: Dictionary in data.get("storylets", []):
			var conditions: Dictionary = storylet.get("conditions", {})
			var slots: Array[int] = []
			slots.assign(conditions.get("allowed_slots", []))
			conditions["allowed_slots"] = slots
			storylet["conditions"] = conditions
			_pool.append(storylet)
	_toast = Kit.create_folio_panel(Kit.PAPER_DEEP, 26, 14, 6)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_left = -410
	_toast.offset_right = 410
	_toast.offset_top = -190
	_toast.offset_bottom = -122
	_toast_text = Kit.create_label("", 22, Kit.INK, _title_font)
	_toast_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_text)
	_toast.hide()
	_toast_timer = Timer.new()
	_toast_timer.one_shot = true
	_toast_timer.timeout.connect(_toast.hide)
	add_child(_toast_timer)
	_dice = DiceOverlay.new()
	add_child(_dice)
	_build_encounter()


func is_busy() -> bool:
	return _running


func serialize_state() -> Dictionary:
	var result := _save_extras.duplicate(true)
	result["completed"] = _completed.duplicate()
	return result


func deserialize_state(state: Dictionary) -> void:
	_save_extras = state.duplicate(true)
	_save_extras.erase("completed")
	_completed.clear()
	if state.get("completed") is Dictionary:
		for id: String in state["completed"]:
			if bool(state["completed"][id]):
				_completed[id] = true
	_arrival_queue.clear()
	_toast_timer.stop()
	_toast.hide()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_toast]


func get_available_storylets(location_id: String, trigger_mode: String = "manual") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for storylet: Dictionary in _pool:
		if not _matches_location(storylet, location_id):
			continue
		var mode := str(storylet.get("trigger_mode", "manual"))
		if mode != trigger_mode:
			var hook_status := trigger_mode == "manual" and mode == "auto_on_arrive" and str(storylet.get("category", "")) == "hook"
			if not hook_status:
				continue
		if not _conditions_pass(storylet):
			continue
		result.append(storylet.duplicate(true))
	return result


func mark_completed(storylet_id: String) -> void:
	_completed[storylet_id] = true


func show_hint(text: String) -> void:
	_notify(text)


func register_hook_handler(hook_id: String, handler: Callable) -> void:
	_handlers[hook_id] = handler


func has_hook_handler(hook_id: String) -> bool:
	return _handlers.has(hook_id)


func check_arrival(location_id: String) -> void:
	for storylet: Dictionary in _pool:
		if str(storylet.get("trigger_mode", "")) != "auto_on_arrive":
			continue
		if not _matches_location(storylet, location_id):
			continue
		if not _conditions_pass(storylet):
			continue
		_arrival_queue.append({"storylet": storylet, "location": location_id})
	_run_arrival()


func can_execute(storylet: Dictionary) -> bool:
	var action: Dictionary = storylet.get("action", {})
	return WorldBlackboard.can_afford(int(action.get("fare_copper", 0))) and (
		WorldBlackboard.get_total_rations() >= int(action.get("ration_cost", 0)))


func execute_storylet(storylet_id: String, location_id: String = "") -> void:
	if _running:
		return
	var location := WorldBlackboard.current_location_id if location_id.is_empty() else location_id
	for storylet: Dictionary in _pool:
		if str(storylet.get("id", "")) == storylet_id:
			var mode := str(storylet.get("trigger_mode", "manual"))
			if not _matches_location(storylet, location) or not _conditions_pass(storylet):
				return
			if mode != "manual" and str(storylet.get("category", "")) != "hook":
				return
			_running = true
			await _execute(storylet, location)
			_running = false
			_run_arrival()
			return
	_notify("手账中找不到这条记录。")


func pick_en_route(plan: Planner.Itinerary, posture: String, rng: RandomNumberGenerator) -> Interruption:
	var risk := 0.55 if posture == Planner.STEALTH else (1.35 if posture == Planner.FORCED else 1.0)
	var raw_days := 0.0
	for leg: Planner.Leg in plan.legs:
		raw_days += leg.days
	var elapsed := 0.0
	for index: int in plan.legs.size():
		var leg := plan.legs[index]
		var encounter_day := floori((elapsed + leg.days * 0.5) / raw_days * plan.total_days)
		elapsed += leg.days
		if leg.mode == Planner.SHIP:
			continue
		var candidates: Array[Dictionary] = []
		for storylet: Dictionary in _pool:
			if str(storylet.get("trigger_mode", "")) != "en_route":
				continue
			if leg.km >= int(storylet.get("min_km", 1)) and _matches_location(storylet, leg.to_city) and _conditions_pass(storylet, encounter_day):
				candidates.append(storylet)
		if not candidates.is_empty() and rng.randf() < 1.0 - exp(-leg.km * risk / 720.0):
			var result := Interruption.new()
			result.leg_index = index
			result.storylet = candidates[rng.randi_range(0, candidates.size() - 1)]
			return result
	return null


func run_en_route(interruption: Interruption, location_id: String) -> void:
	var storylet := interruption.storylet
	if _running or not _conditions_pass(storylet):
		return
	_running = true
	_encounter_title.text = str(storylet["title"])
	_encounter_summary.text = str(storylet["summary"])
	_encounter.show()
	Motion.fade_in(_encounter, 0.27)
	AudioManager.play_sfx("page_flip")
	_encounter_continue.grab_focus()
	await _encounter_continue.pressed
	_encounter.hide()
	await _execute(storylet, location_id)
	_running = false
	_run_arrival()


func _run_arrival() -> void:
	if _running or _arrival_queue.is_empty():
		return
	_running = true
	var entry: Dictionary = _arrival_queue.pop_front()
	await _execute(entry["storylet"], str(entry["location"]))
	_running = false
	_run_arrival()


func _matches_location(storylet: Dictionary, location_id: String) -> bool:
	if storylet.has("locations"):
		return location_id in storylet["locations"]
	if bool(storylet.get("city_only", false)) and not location_id.begins_with("city_"):
		return false
	var location := str(storylet.get("location", "any"))
	return location == "any" or location == location_id


func _conditions_pass(storylet: Dictionary, days_ahead: int = 0) -> bool:
	var conditions: Dictionary = storylet["conditions"]
	if bool(conditions.get("once_only", false)) and _completed.has(str(storylet.get("id", ""))):
		return false
	var time := WorldBlackboard.get_world_time()
	var month_length := WorldBlackboard.DAYS_PER_MONTH
	var day_index := ((time["year"] - 418) * WorldBlackboard.MONTHS_PER_YEAR + time["month"] - 1) * month_length + time["day"] - 1 + days_ahead
	if day_index < int(conditions.get("min_day", 0)):
		return false
	var slots: Array[int] = conditions["allowed_slots"]
	if not slots.is_empty() and time["slot"] not in slots:
		return false
	for flag: String in conditions.get("required_flags", []):
		if not bool(WorldBlackboard.get_flag(flag, false)):
			return false
	for flag: String in conditions.get("forbidden_flags", []):
		if bool(WorldBlackboard.get_flag(flag, false)):
			return false
	var buff := str(conditions.get("required_buff", ""))
	if not buff.is_empty() and not WorldBlackboard.has_buff(buff):
		return false
	var items: Dictionary = conditions.get("required_items", {})
	for item: String in items:
		if WorldBlackboard.get_item_count(item) < int(items[item]):
			return false
	return true


func _execute(storylet: Dictionary, location_id: String) -> void:
	var action: Dictionary = storylet.get("action", {})
	var cost := int(storylet.get("time_cost", 0))
	if not can_execute(storylet):
		_notify("钱币或干粮不足。")
		return
	match str(action.get("type", "")):
		"open_room":
			_settle(storylet, cost)
			SceneTransition.change_to(str(action.get("scene", ROOM_SCENE)), {"return_scene": _caller_path()})
		"open_dialogue":
			_settle(storylet, cost)
			SceneTransition.change_to(DIALOGUE_SCENE, {
				"dialogue_id": str(action.get("dialogue_id", "")),
				"return_scene": _caller_path()
			})
		"quick_action":
			var quick := str(action.get("quick", ""))
			if quick == "check":
				var check := RuleEngine.roll_check(str(action.get("stat", "WIL")), int(action.get("dc", 12)), "natural", 0, action.get("context", {}))
				var passed := bool(check["passed"])
				_dice.present(check, str(action.get("label", "野外检定")), str(storylet.get("summary", "")), false)
				await _dice.completed
				var effects: Array = action.get("success_effects", []) if passed else action.get("fail_effects", [])
				for effect: Dictionary in effects:
					_apply_effect(effect)
				_notify(str(action.get("success_text", "")) if passed else str(action.get("fail_text", "")))
				_settle(storylet, cost)
			elif quick == "rest":
				WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
				WorldBlackboard.restore_mp(int(action.get("mp_restore", 12)))
				_notify(str(action.get("done_text", "休整完毕，疲惫消散了。")))
				_settle(storylet, cost)
			elif quick == "forage":
				WorldBlackboard.spend_currency(int(action.get("fare_copper", 0)))
				var item := str(action.get("item", WorldBlackboard.RATION_ID))
				WorldBlackboard.add_item(item, str(action.get("item_name", "魔大陆熏肉干粮")), int(action.get("count", 1)), "ration")
				_notify(str(action.get("done_text", "补充了旅途干粮。")))
				_settle(storylet, cost)
			elif quick == "eat":
				WorldBlackboard.consume_rations(int(action["ration_cost"]))
				WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
				_notify("进食后，旅途疲惫消散了。")
				_settle(storylet, cost)
			elif quick == "earn":
				WorldBlackboard.add_currency(int(action["copper"]))
				_notify(str(action.get("done_text", "领取了帮工报酬。")))
				_settle(storylet, cost)
			elif quick == "train":
				WorldBlackboard.modify_stat(str(action.get("stat", "WIL")), int(action.get("delta", 1)), str(action.get("reason", "")))
				_settle(storylet, cost)
			else:
				_notify("未知的休整行动。")
		"event_hook":
			_settle(storylet, cost)
			_fire_hook(str(action.get("hook_id", "")), {
				"storylet": str(storylet.get("id", "")),
				"location": location_id,
				"pending_hint": str(action.get("pending_hint", ""))
			})
		_:
			_notify("这条故事行动暂未开放。")


func _fire_hook(hook_id: String, context: Dictionary) -> void:
	hook_triggered.emit(hook_id, context)
	if _handlers.has(hook_id):
		var handler: Callable = _handlers[hook_id]
		handler.call(context)
		return
	var hint := str(context.get("pending_hint", ""))
	_notify(hint if not hint.is_empty() else "事件接口「%s」已就位，待接入正式剧情。" % hook_id)


func _settle(storylet: Dictionary, cost: int) -> void:
	if bool(storylet.get("conditions", {}).get("once_only", false)):
		mark_completed(str(storylet.get("id", "")))
	if cost > 0:
		WorldBlackboard.advance_time(cost)


func _apply_effect(effect: Dictionary) -> void:
	var id := str(effect.get("id", ""))
	match str(effect.get("type", "")):
		"set_flag":
			WorldBlackboard.set_flag(id, effect.get("value", true))
		"add_item":
			WorldBlackboard.add_item(id, str(effect.get("name", "")), int(effect.get("count", 1)), str(effect.get("tag", "")))
		"add_buff":
			WorldBlackboard.add_buff(id, str(effect.get("name", "")), effect.get("stat_bonus", {}), effect.get("check_bonus", {}), effect)
		"remove_buff":
			WorldBlackboard.remove_buff(id)
		"advance_time":
			WorldBlackboard.advance_time(int(effect.get("slots", 0)))


func _caller_path() -> String:
	var current := get_tree().current_scene
	if current != null and not current.scene_file_path.is_empty():
		return current.scene_file_path
	return ROOM_SCENE


func _notify(text: String) -> void:
	if text.is_empty():
		return
	_toast_text.text = text
	_toast.show()
	Motion.fade_in(_toast, 0.24)
	_toast_timer.start(3.0)


func _build_encounter() -> void:
	_encounter = CenterContainer.new()
	_encounter.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_encounter)
	_encounter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := Kit.create_folio_panel(Kit.PAPER, 30, 22, 12)
	card.custom_minimum_size.x = 510.0
	_encounter.add_child(card)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	card.add_child(page)
	page.add_child(Kit.create_ribbon_header("途中奇遇", _title_font, 21, Kit.AMBER))
	_encounter_title = Kit.create_label("", 36, Kit.INK, _title_font)
	page.add_child(_encounter_title)
	_encounter_summary = Kit.create_label("", 21, Kit.MUTED, _body_font)
	_encounter_summary.custom_minimum_size.x = 440.0
	_encounter_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_encounter_summary)
	_encounter_continue = Kit.create_tactile_button("掷骰应对", "primary", _title_font, 24)
	_encounter_continue.custom_minimum_size.y = 52.0
	page.add_child(_encounter_continue)
	_encounter.hide()


