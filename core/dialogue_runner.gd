extends RefCounted

const DIALOGUE_DIR := "res://data/dialogues/"

var script_data: Dictionary = {}
var current: Dictionary = {}
var history: Array[Dictionary] = []
var pending_check: Dictionary[String, Variant] = {}
var _nodes: Dictionary[String, Dictionary] = {}
var _check_destination := ""


func start(dialogue_id: String) -> bool:
	current = {}
	history.clear()
	pending_check = {}
	_check_destination = ""
	_nodes.clear()
	script_data = WorldBlackboard.read_config(DIALOGUE_DIR + dialogue_id + ".json")
	for node: Dictionary in script_data.get("nodes", []):
		_nodes[str(node["id"])] = node
	var entry := str(script_data.get("start", ""))
	for alternate: Dictionary in script_data.get("entry_overrides", []):
		if _matches(alternate.get("condition", {})):
			entry = str(alternate["next"])
			break
	_enter(entry)
	return current.get("type") != "error"


func next_line() -> void:
	if current.get("type") == "line":
		_enter(str(current.get("next", "")))


func choices() -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	if current.get("type") != "choice":
		return available
	for option: Dictionary in current.get("options", []):
		if _matches(option.get("condition", {})):
			available.append(option)
	return available


func choose(option_id: String, mode: String = "natural") -> bool:
	if not pending_check.is_empty():
		return false
	for option: Dictionary in choices():
		if str(option["id"]) != option_id:
			continue
		var check: Dictionary = option.get("check", {})
		if check.is_empty():
			_enter(str(option.get("next", "")))
		else:
			pending_check = RuleEngine.roll_check(str(check["stat"]), int(check["dc"]), mode, 0, check.get("context", {}))
			_check_destination = str(check["success_next"] if pending_check["passed"] else check["fail_next"])
		return true
	return false


func continue_check() -> void:
	if pending_check.is_empty():
		return
	var destination := _check_destination
	pending_check = {}
	_check_destination = ""
	_enter(destination)


func _enter(node_id: String) -> void:
	var visited: Dictionary[String, bool] = {}
	while _nodes.has(node_id) and not visited.has(node_id):
		visited[node_id] = true
		var node := _nodes[node_id]
		match str(node.get("type", "")):
			"effect":
				for effect: Dictionary in node.get("effects", []):
					_apply_effect(effect)
				node_id = str(node.get("next", ""))
			"line":
				current = node
				history.append(node)
				return
			"choice", "end":
				current = node
				return
			_:
				break
	push_error("对话节点缺失、类型无效或效果节点循环：%s" % node_id)
	current = {"type": "error"}


func _matches(condition: Dictionary) -> bool:
	if condition.is_empty():
		return true
	var flag := str(condition.get("flag", ""))
	if flag.is_empty():
		return false
	return WorldBlackboard.get_flag(flag, condition.get("default")) == condition.get("equals", true)


func _apply_effect(effect: Dictionary) -> void:
	var id := str(effect.get("id", ""))
	var label := str(effect.get("name", ""))
	match str(effect.get("type", "")):
		"set_flag":
			WorldBlackboard.set_flag(id, effect["value"])
		"add_item":
			WorldBlackboard.add_item(id, label, int(effect.get("count", 1)))
		"add_buff":
			WorldBlackboard.add_buff(id, label, effect.get("stat_bonus", effect.get("stats", {})), effect.get("check_bonus", {}), effect)
		"advance_time":
			WorldBlackboard.advance_time(int(effect.get("slots", 0)))
