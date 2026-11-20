extends RefCounted

signal changed
signal event_occurred(kind: String, info: Dictionary)
signal reaction_window_opened(enemy_attack_info: Dictionary)
signal finished(outcome: String)

enum Band { NEAR, MID, FAR }
const BANDS := ["近距", "中距", "远距"]
const READY := "READY"
const CASTING := "CASTING"
const RECOVERING := "RECOVERING"
const CONFIG_DIR := "res://data/combat/"

var _rng := RandomNumberGenerator.new()
var _skills: Dictionary
var _reactions: Dictionary
var _rules: Dictionary
var _preset: Dictionary = {}
var _enemy_card: Dictionary = {}
var _support: Dictionary = {}
var _player: Dictionary
var _enemy: Dictionary
var _inventory: Dictionary
var _consumed: Dictionary
var _tokens: int
var _support_left: int
var _distance: int
var _tick: int
var _incoming: Dictionary = {}
var _outcome := ""
var _started := false


func start(preset_id: String, seed_value: int = -1) -> bool:
	if _started and _outcome.is_empty():
		return false
	var definitions := WorldBlackboard.read_config(CONFIG_DIR + "skills.json")
	var presets := WorldBlackboard.read_config(CONFIG_DIR + "presets.json")
	var enemies := WorldBlackboard.read_config(CONFIG_DIR + "enemies.json")
	var contracts := WorldBlackboard.read_config(CONFIG_DIR + "contracts.json")
	if not presets.has(preset_id) or not definitions.has("rules"):
		return false
	_preset = presets[preset_id]
	_enemy_card = enemies.get(_preset.get("enemy", ""), {})
	if _enemy_card.is_empty():
		return false
	_support = contracts.get(_preset.get("support", ""), {})
	_skills = definitions["actions"]
	_reactions = definitions["reactions"]
	_rules = definitions["rules"]
	_support_left = int(_support.get("charges", 0))
	_tokens = int(_rules["reactions_per_turn"])
	_distance = int(_preset["distance"])
	_tick = 0
	_outcome = ""
	_incoming = {}
	_consumed = {}
	if seed_value < 0:
		_rng.randomize()
	else:
		_rng.seed = seed_value
	_player = _make_player()
	_enemy = _make_actor(_enemy_card, int(_enemy_card["initial_ticks"]), int(_enemy_card["defense"]))
	_enemy["weaknesses"] = _enemy_card.get("weaknesses", {})
	_started = true
	changed.emit()
	return true


func _make_actor(card: Dictionary, ticks: int, defense: int) -> Dictionary:
	return {
		"name": card["name"], "hp": int(card["hp"]), "max_hp": int(card["hp"]),
		"mp": int(card["mp"]), "max_mp": int(card["mp"]), "shield": 0, "defense": defense,
		"state": READY if ticks == 0 else RECOVERING, "ticks_to_act": ticks, "cast": "",
		"stats": card["stats"], "checks": {}, "statuses": {},
		"magic_resist": float(card.get("magic_resist", 0.0)), "weaknesses": {},
		"traits": card.get("traits", []), "trait_skills": card.get("trait_skills", {}),
		"buff_names": [], "damage_multipliers": card.get("damage_multipliers", {})
	}


func _make_player() -> Dictionary:
	var start_ticks := int(_preset["player_ticks"])
	var defense := int(_preset["defense"])
	if _preset["mode"] == "isolated_sandbox":
		var character: Dictionary = _preset["character"]
		var actor := _make_actor(character, start_ticks, defense)
		_inventory = character.get("items", {}).duplicate(true)
		return actor
	var sheet := WorldBlackboard.get_combat_snapshot()
	var attributes: Dictionary = sheet["attributes"]
	var hp: Dictionary = attributes["hp"]
	var mp: Dictionary = attributes["mp"]
	var player := _make_actor({
		"name": attributes["name"], "hp": hp["max"], "mp": mp["max"], "stats": attributes["stats"]
	}, start_ticks, defense)
	player["hp"] = int(hp["current"])
	player["mp"] = int(mp["current"])
	player["checks"] = sheet["checks"]
	player["trait_skills"] = sheet["trait_skills"]
	player["buff_names"] = sheet["buff_names"]
	_inventory = sheet["items"]
	return player


func get_presets() -> Dictionary:
	return WorldBlackboard.read_config(CONFIG_DIR + "presets.json")


func snapshot() -> Dictionary:
	return {
		"player": _actor_view(_player), "enemy": _actor_view(_enemy),
		"enemy_card": _enemy_card.duplicate(true), "preset": _preset.duplicate(true),
		"distance": _distance, "tick": _tick, "reaction": _tokens,
		"support_left": _support_left, "support": _support.duplicate(true),
		"support_reason": _support_reason(), "outcome": _outcome, "inventory": _inventory.duplicate()
	}


func _actor_view(actor: Dictionary) -> Dictionary:
	var result := actor.duplicate(true)
	var statuses: Dictionary = actor["statuses"]
	var labels: Array[String] = []
	for id: String in statuses:
		labels.append("%s %d" % [_rules["statuses"][id]["name"], statuses[id]])
	result["status_labels"] = labels
	var action_id := str(actor["cast"])
	result["cast_name"] = str(_skills.get(action_id, {}).get("name", ""))
	result["cast_total"] = int(_skills.get(action_id, {}).get("cast_ticks", 0))
	return result


func intent() -> String:
	if not _outcome.is_empty():
		return ""
	if not _incoming.is_empty():
		return str(_incoming["action"]["name"]) + " · 即将命中"
	var id := str(_enemy["cast"])
	if id.is_empty():
		id = _enemy_action()
	var skill: Dictionary = _skills.get(id, {})
	var text := str(skill.get("intent", skill.get("name", "调整步伐")))
	var ticks := int(_enemy["ticks_to_act"])
	return "%s · %d 刻度" % [text, ticks] if ticks > 0 else text


func is_player_ready() -> bool:
	return _started and _outcome.is_empty() and _incoming.is_empty() and _player["state"] == READY


func can_advance() -> bool:
	return _started and _outcome.is_empty() and _incoming.is_empty() and not is_player_ready()


func get_actions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _preset["skills"]:
		var action: Dictionary = _skills[id].duplicate(true)
		action["id"] = id
		action["reason"] = _action_reason(action, _player)
		if action.has("item"):
			action["stock"] = int(_inventory.get(action["item"], 0))
		result.append(action)
	return result


func _action_reason(skill: Dictionary, actor: Dictionary) -> String:
	if not _is_in_range(skill["ranges"]):
		return "当前距离不可用"
	if int(actor["mp"]) < int(skill.get("mp", 0)):
		return "MP 不足"
	if skill.has("item") and int(_inventory.get(skill["item"], 0)) < 1:
		return "行囊无干粮"
	return ""


func _is_in_range(bands: Array) -> bool:
	for band: Variant in bands:
		if int(band) == _distance:
			return true
	return false


func choose_action(id: String) -> bool:
	if not is_player_ready() or id not in _preset["skills"]:
		return false
	if not _action_reason(_skills[id], _player).is_empty():
		return false
	_begin_action("player", id)
	changed.emit()
	return true


func advance() -> bool:
	if not can_advance():
		return false
	# Due enemy attacks are resolved before the player's due spell. This is
	# where a same-tick hit can break concentration.
	if int(_enemy["ticks_to_act"]) == 0:
		if _enemy["state"] == CASTING:
			_release("enemy", str(_enemy["cast"]))
		else:
			var id := _enemy_action()
			if id.is_empty():
				_recover(_enemy, 1)
			else:
				_begin_action("enemy", id)
	elif int(_player["ticks_to_act"]) == 0:
		if _player["state"] == CASTING:
			_release("player", str(_player["cast"]))
		else:
			_player["state"] = READY
			_tokens = int(_rules["reactions_per_turn"])
	else:
		_tick += 1
		_age(_player)
		_age(_enemy)
		_emit("tick", {"tick": _tick, "sound": "timeline_tick"})
	changed.emit()
	return true


func _age(actor: Dictionary) -> void:
	actor["ticks_to_act"] = maxi(0, int(actor["ticks_to_act"]) - 1)
	var statuses: Dictionary = actor["statuses"]
	for id: String in statuses.keys():
		var remaining := int(statuses[id]) - 1
		if remaining <= 0:
			statuses.erase(id)
		else:
			statuses[id] = remaining


func _enemy_action() -> String:
	for id: String in _enemy_card["skills"]:
		if _action_reason(_skills[id], _enemy).is_empty():
			return id
	return ""


func _begin_action(side: String, id: String) -> void:
	var actor := _actor(side)
	var skill: Dictionary = _skills[id]
	actor["mp"] = int(actor["mp"]) - int(skill["mp"])
	var cast_ticks := int(skill["cast_ticks"])
	if cast_ticks > 0:
		actor["state"] = CASTING
		actor["ticks_to_act"] = cast_ticks
		actor["cast"] = id
		_emit("cast", {"side": side, "name": skill["name"], "ticks": cast_ticks, "sound": "cast_start"})
	else:
		_release(side, id)


func _release(side: String, id: String) -> void:
	var actor := _actor(side)
	var target := _opponent(side)
	var skill: Dictionary = _skills[id]
	var action_info := {"side": side, "name": skill["name"], "cast_ticks": skill["cast_ticks"]}
	var recovery := int(skill["recovery_ticks"])
	if skill.has("move") or skill.has("move_to"):
		recovery += _status_value(actor, "movement_recovery")
	_recover(actor, recovery)
	if not _is_in_range(skill["ranges"]):
		_emit("range_miss", action_info)
		return
	_emit("action", action_info)
	if skill.has("move_to"):
		_set_distance(int(skill["move_to"]))
	elif skill.has("move"):
		_set_distance(_distance + int(skill["move"]))
	if skill.has("item"):
		var item := str(skill["item"])
		_inventory[item] = int(_inventory[item]) - 1
		_consumed[item] = int(_consumed.get(item, 0)) + 1
	_apply_self_effects(actor, action_info, skill)
	if not skill.has("damage") or not _is_in_range(skill.get("attack_ranges", [Band.NEAR, Band.MID, Band.FAR])):
		return
	var check := RuleEngine.attack_check(_modifiers(actor, str(skill["stat"])), int(target["defense"]), _rng)
	if not check["passed"]:
		_emit_check(check, "命中 · " + str(skill["name"]), side)
		_emit("miss", action_info)
		return
	var damage := _calculate_damage(skill, actor, target)
	if side == "enemy":
		_queue_enemy_attack(skill, check, damage)
	else:
		_emit_check(check, "命中 · " + str(skill["name"]), side)
		_apply_strike("enemy", skill, damage)


func _apply_self_effects(actor: Dictionary, info: Dictionary, skill: Dictionary) -> void:
	if not (skill.has("heal") or skill.has("restore_mp") or skill.has("shield")):
		return
	var hp := int(actor["hp"])
	var mp := int(actor["mp"])
	actor["hp"] = mini(int(actor["max_hp"]), hp + int(skill.get("heal", 0)))
	actor["mp"] = mini(int(actor["max_mp"]), mp + int(skill.get("restore_mp", 0)))
	var shield := int(skill.get("shield", 0))
	actor["shield"] = maxi(int(actor["shield"]), shield)
	var feedback := info.duplicate()
	feedback.merge({
		"health": int(actor["hp"]) - hp, "mana": int(actor["mp"]) - mp,
		"shield": shield, "sound": str(skill.get("sound", ""))
	})
	_emit("restore", feedback)


func _calculate_damage(skill: Dictionary, actor: Dictionary, target: Dictionary) -> int:
	var element := str(skill["element"])
	var damage := float(skill["damage"])
	damage *= float(actor["damage_multipliers"].get(element, 1.0))
	damage *= float(target["weaknesses"].get(element, 1.0))
	if element != "physical":
		var resist := float(target["magic_resist"]) - _status_amount(target, "magic_resist_delta")
		damage *= 1.0 - clampf(resist, 0.0, 0.9)
	return maxi(1, roundi(damage))


func _apply_strike(side: String, skill: Dictionary, damage: int) -> void:
	if damage <= 0 or not _outcome.is_empty():
		return
	var target := _actor(side)
	var combo: Dictionary = _rules["conductive_combo"]
	var statuses: Dictionary = target["statuses"]
	var critical: bool = statuses.has(combo["primer"]) and skill["element"] in combo["elements"]
	if critical:
		statuses.erase(combo["primer"])
		damage = roundi(damage * float(combo["multiplier"]))
		_apply_status(target, side, str(combo["status"]))
	for status: String in skill.get("status", []):
		_apply_status(target, side, status)
	if skill.has("push"):
		_set_distance(_distance + int(skill["push"]))
	_deal_damage(side, damage, skill, critical)


func _queue_enemy_attack(skill: Dictionary, check: Dictionary, damage: int) -> void:
	_incoming = {"action": skill, "check": check, "damage": damage, "hits": int(skill.get("hits", 1))}
	if _support.get("kind") == "intercept" and _support_left > 0 and _is_in_range(_support.get("ranges", [0, 1, 2])):
		_apply_support()
		var kept := 1.0 - float(_support.get("reduction", 0.0))
		_finish_attack(kept)
		return
	if _tokens > 0:
		var public_info := {"name": skill["name"], "foresight": _foresight(), "hits": _incoming["hits"]}
		if _foresight():
			public_info["damage"] = damage * int(_incoming["hits"])
			public_info["raw_roll"] = check["raw_roll"]
			public_info["total"] = check["total"]
		reaction_window_opened.emit(public_info)
	else:
		_finish_attack()


func get_reactions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _preset["reactions"]:
		var reaction: Dictionary = _reactions[id].duplicate(true)
		reaction["id"] = id
		reaction["reason"] = _reaction_reason(reaction)
		result.append(reaction)
	return result


func _reaction_reason(reaction: Dictionary) -> String:
	if int(_player["mp"]) < int(reaction.get("mp", 0)):
		return "MP 不足"
	if reaction.has("requires_trait") and not _has_trait(str(reaction["requires_trait"])):
		return "缺少构筑词条"
	return ""


func resolve_reaction(id: String) -> bool:
	if _incoming.is_empty() or _tokens <= 0 or not _outcome.is_empty():
		return false
	if id == "take_hit":
		_tokens -= 1
		_finish_attack()
		changed.emit()
		return true
	if id not in _preset["reactions"]:
		return false
	var reaction: Dictionary = _reactions[id]
	if not _reaction_reason(reaction).is_empty():
		return false
	_tokens -= 1
	_player["mp"] = int(_player["mp"]) - int(reaction.get("mp", 0))
	_emit_enemy_check()
	var action: Dictionary = _incoming["action"]
	var amount := int(_incoming["damage"])
	var hits := int(_incoming["hits"])
	_emit("reaction", {"name": reaction["name"], "side": "player", "sound": reaction.get("sound", "")})
	match str(reaction["kind"]):
		"guard":
			if _distance == int(reaction["push_from"]):
				_set_distance(int(reaction["push_to"]))
			amount = roundi(amount * (1.0 - float(reaction["reduction"])))
		"dodge", "parry":
			var stat := str(reaction["stat"])
			var skill := str(reaction.get("trait_skill", ""))
			var extra := int(_player["trait_skills"].get(skill, 0))
			var dc := int(_incoming["check"]["total"]) + int(reaction.get("reaction_dc_bonus", 0))
			var check := RuleEngine.defense_check(_modifiers(_player, stat, extra, skill), dc, 1 if _foresight() else 0, _rng)
			_emit_check(check, str(reaction["name"]), "player")
			if check["passed"] and reaction["kind"] == "parry":
				var reflected := roundi(amount * float(reaction["reflect"]))
				_enemy["ticks_to_act"] = int(_enemy["ticks_to_act"]) + int(reaction["enemy_delay"])
				_emit("parry", {"name": reaction["name"], "amount": reflected, "cancelled_hits": hits - 1})
				_deal_damage("enemy", reflected, {"element": "parry", "sound": reaction["sound"]})
				amount -= reflected
				hits = 1
			elif check["passed"]:
				amount = 0
				_emit("evade", {"name": reaction["name"], "side": "player"})
	_incoming = {}
	_apply_strike("player", action, amount * hits)
	changed.emit()
	return true


func _emit_enemy_check() -> void:
	_emit_check(_incoming["check"], "命中 · " + str(_incoming["action"]["name"]), "enemy")


func _finish_attack(multiplier: float = 1.0) -> void:
	_emit_enemy_check()
	var damage := roundi(int(_incoming["damage"]) * multiplier) * int(_incoming["hits"])
	var action: Dictionary = _incoming["action"]
	_incoming = {}
	_apply_strike("player", action, damage)


func _deal_damage(side: String, amount: int, skill: Dictionary, critical: bool = false) -> void:
	if amount <= 0 or not _outcome.is_empty():
		return
	var actor := _actor(side)
	var absorbed := mini(int(actor["shield"]), amount)
	actor["shield"] = int(actor["shield"]) - absorbed
	var lost_hp := mini(int(actor["hp"]), amount - absorbed)
	actor["hp"] = int(actor["hp"]) - lost_hp
	_emit("hit", {
		"side": side, "amount": lost_hp, "absorbed": absorbed, "critical": critical,
		"element": skill.get("element", ""), "sound": skill.get("sound", "")
	})
	if int(actor["hp"]) == 0:
		_end("defeat" if side == "player" else "victory")
	elif actor["state"] == CASTING and (lost_hp > 0 or skill.get("concentration_interrupt", false)):
		_test_concentration(actor, side, lost_hp, bool(skill.get("concentration_interrupt", false)))


func _test_concentration(actor: Dictionary, side: String, amount: int, interrupt: bool) -> void:
	var config: Dictionary = _rules["concentration"]
	var check := RuleEngine.concentration_check(_modifiers(actor, str(config["stat"])), amount, config, _rng)
	_emit_check(check, "意志专注", side)
	if check["passed"]:
		return
	var name := str(_skills[actor["cast"]]["name"])
	if interrupt:
		_recover(actor, int(config["delay"]))
	else:
		actor["ticks_to_act"] = int(actor["ticks_to_act"]) + int(config["delay"])
	_emit("concentration", {"side": side, "name": name, "interrupted": interrupt, "ticks": config["delay"]})


func _apply_status(actor: Dictionary, side: String, id: String) -> void:
	var status: Dictionary = _rules["statuses"][id]
	actor["statuses"][id] = int(status["duration"])
	var delay := int(status.get("delay", 0))
	if delay > 0:
		actor["ticks_to_act"] = int(actor["ticks_to_act"]) + delay
		if status.get("interrupt_cast", false) and actor["state"] == CASTING:
			var name := str(_skills[actor["cast"]]["name"])
			actor["cast"] = ""
			actor["state"] = RECOVERING
			_emit("concentration", {"side": side, "name": name, "interrupted": true, "ticks": delay})
		elif actor["state"] == READY:
			actor["state"] = RECOVERING
	_emit("status", {"side": side, "id": id, "name": status["name"], "delay": delay})


func _recover(actor: Dictionary, ticks: int) -> void:
	actor["cast"] = ""
	actor["state"] = RECOVERING
	actor["ticks_to_act"] = maxi(1, ticks + _status_value(actor, "recovery"))


func _status_value(actor: Dictionary, property: String) -> int:
	return int(_status_amount(actor, property))


func _status_amount(actor: Dictionary, property: String) -> float:
	var value := 0.0
	for id: String in actor["statuses"]:
		value += float(_rules["statuses"][id].get(property, 0.0))
	return value


func _modifiers(actor: Dictionary, stat: String, extra: int = 0, label: String = "") -> Dictionary:
	var base: Dictionary = actor["checks"].get(stat, {})
	if base.is_empty():
		return RuleEngine.build_modifier(int(actor["stats"].get(stat, 10)), extra, label)
	var result := base.duplicate(true)
	if extra != 0:
		result["bonus_list"].append({"name": label, "value": extra})
		result["total_mod"] = int(result["total_mod"]) + extra
	return result


func _has_trait(id: String) -> bool:
	for trait_data: Dictionary in _player["traits"]:
		if trait_data["id"] == id:
			return true
	return false


func _foresight() -> bool:
	return _has_trait(str(_rules["foresight_trait"]))


func use_support() -> bool:
	if not is_player_ready() or not _support_reason().is_empty():
		return false
	_apply_support()
	changed.emit()
	return true


func _support_reason() -> String:
	if _support.is_empty():
		return "未装备契约"
	if _support.get("kind") != "active":
		return "等待被动拦截"
	if _support_left <= 0:
		return "援护次数已用完"
	if not _is_in_range(_support["ranges"]):
		return "需要近距"
	return ""


func _apply_support() -> void:
	_support_left -= 1
	var delay := int(_support.get("enemy_delay", 0))
	_enemy["ticks_to_act"] = int(_enemy["ticks_to_act"]) + delay
	if delay > 0 and _enemy["state"] == READY:
		_enemy["state"] = RECOVERING
	_set_distance(_distance + int(_support.get("push", 0)))
	_emit("support", {"name": _support["name"], "delay": delay, "sound": _support.get("sound", "")})


func retreat() -> void:
	_end("retreat")
	changed.emit()


func _end(outcome: String) -> void:
	if not _started or not _outcome.is_empty():
		return
	_outcome = outcome
	_incoming = {}
	if _preset["mode"] == "story_linked":
		var flags := {str(_preset["outcome_flag"]): outcome}
		if outcome == "victory":
			flags[str(_preset["victory_flag"])] = true
		var hp := int(_player["hp"])
		if outcome == "defeat":
			hp = int(_preset.get("post_defeat_hp", 1))
		WorldBlackboard.apply_combat_outcome(hp, int(_player["mp"]), _consumed, flags)
	finished.emit(outcome)


func _actor(side: String) -> Dictionary:
	return _player if side == "player" else _enemy


func _opponent(side: String) -> Dictionary:
	return _enemy if side == "player" else _player


func _set_distance(target: int) -> void:
	var band := clampi(target, Band.NEAR, Band.FAR)
	if _distance != band:
		_distance = band
		_emit("distance", {"band": band})


func _emit_check(check: Dictionary, label: String, side: String) -> void:
	_emit("check", {"result": check, "name": label, "side": side})


func _emit(kind: String, info: Dictionary) -> void:
	event_occurred.emit(kind, info)
