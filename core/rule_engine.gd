extends Node

const RULES_PATH := "res://data/rules/context_rules.json"

var _rng := RandomNumberGenerator.new()
var _rules: Array[Dictionary] = []
var _bands: Dictionary = {}
var _providers: Dictionary[String, Dictionary] = {}


func _ready() -> void:
	_rng.randomize()
	var data := WorldBlackboard.read_config(RULES_PATH)
	_rules.assign(data.get("rules", []))
	_bands = data.get("relation_bands", {})


func set_seed(seed_value: int) -> void:
	_rng.seed = seed_value


func bonus_label(bonus: Dictionary) -> String:
	for key: String in ["label", "name"]:
		var value: Variant = bonus.get(key)
		if value is String or value is StringName:
			var label := str(value).strip_edges()
			if not label.is_empty():
				return label
	return "检定修正"


func roll_check(stat: String, dc: int, mode: String = "natural", advantage: int = 0,
		context: Dictionary = {}) -> Dictionary[String, Variant]:
	var summary := collect_check(stat, context)
	var outcome := roll_modified_check(summary, dc, mode, advantage)
	outcome["suppressed_modifiers"] = summary["suppressed_modifiers"]
	return outcome


func register_modifier_provider(provider_id: String, callback: Callable, priority: int = 100) -> bool:
	if provider_id.is_empty() or not callback.is_valid():
		return false
	_providers[provider_id] = {"id": provider_id, "callback": callback, "priority": priority}
	return true


func unregister_modifier_provider(provider_id: String) -> void:
	_providers.erase(provider_id)


func collect_check(stat: String, context: Dictionary = {}) -> Dictionary[String, Variant]:
	var summary := WorldBlackboard.get_check_breakdown(stat)
	var facts := _facts(stat, context)
	var candidates: Array[Dictionary] = []
	candidates.assign(summary["bonus_list"])
	var providers: Array[Dictionary] = _providers.values()
	providers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["id"] < b["id"] if a["priority"] == b["priority"] else a["priority"] < b["priority"])
	var tags: Array[String] = facts["actor_tags"]
	var contextual: Array[String] = facts["tags"]
	var suppress: Array[String] = facts["active_suppress_tags"]
	# Evaluate providers from a shared fact snapshot before applying any suppression.
	var base_facts := facts.duplicate(true)
	for provider: Dictionary in providers:
		var callback: Callable = provider["callback"]
		if not callback.is_valid():
			continue
		var response: Variant = callback.call(base_facts.duplicate(true))
		if response is Dictionary:
			_add_tags(tags, response.get("actor_tags", []))
			_add_tags(contextual, response.get("tags", []))
			_add_tags(suppress, response.get("active_suppress_tags", []))
			_add_modifiers(candidates, response.get("modifiers", []))
		else:
			_add_modifiers(candidates, response)
	for entry: Dictionary in _rules:
		if _matches(entry.get("conditions", {}), facts):
			candidates.append(entry)
	for item: Dictionary in WorldBlackboard.active_equipment():
		for entry: Dictionary in item.get("modifiers", []):
			if _matches(entry.get("conditions", {}), facts):
				candidates.append(entry)
	_add_modifiers(candidates, context.get("extra_modifiers", []))

	var applied: Array[Dictionary] = []
	var suppressed: Array[Dictionary] = []
	var total := int(summary["base_mod"])
	for entry: Dictionary in candidates:
		var amount := int(entry.get("value", 0))
		if amount == 0:
			continue
		var label := bonus_label(entry)
		var modifier := {
			"id": str(entry.get("id", label)), "name": label, "label": label,
			"category": str(entry.get("category", "")), "value": amount,
			"tags": entry.get("tags", []), "suppressible_by": entry.get("suppressible_by", [])
		}
		if _overlaps(suppress, modifier["suppressible_by"]):
			suppressed.append(modifier)
		else:
			applied.append(modifier)
			total += amount
	summary["bonus_list"] = applied
	summary["suppressed_modifiers"] = suppressed
	summary["active_suppress_tags"] = suppress
	summary["total_mod"] = total
	return summary


func _facts(stat: String, context: Dictionary) -> Dictionary:
	var facts := context.duplicate(true)
	var actor_tags := WorldBlackboard.actor_tags()
	var tags: Array[String] = ["stat:" + stat]
	var suppress: Array[String] = []
	_add_tags(tags, context.get("tags", []))
	_add_tags(suppress, context.get("active_suppress_tags", []))
	_add_tags(suppress, WorldBlackboard.profile.get("suppress_tags", []))
	var race: Dictionary = WorldBlackboard.catalog.races.get(str(WorldBlackboard.profile.get("race_id", "")), {})
	_add_tags(suppress, race.get("suppress_tags", []))
	for item: Dictionary in WorldBlackboard.active_equipment() + WorldBlackboard.active_statuses():
		_add_tags(actor_tags, item.get("tags", []))
		_add_tags(suppress, item.get("suppress_tags", []))
	var relation_ids: Dictionary[String, String] = {
		"npcs": str(context.get("npc_id", "")),
		"regions": str(context.get("region_id", "")),
		"factions": str(context.get("faction_id", ""))
	}
	for tag: String in tags:
		for kind: String in ["factions", "regions"]:
			var prefix := "faction:" if kind == "factions" else "region:"
			if relation_ids[kind].is_empty() and tag.begins_with(prefix):
				relation_ids[kind] = tag.trim_prefix(prefix)
	if relation_ids["regions"].is_empty():
		relation_ids["regions"] = WorldBlackboard.current_city_id
	var active_relations: Dictionary[String, float] = {}
	for group: String in relation_ids:
		var group_id := relation_ids[group]
		var entries: Dictionary = WorldBlackboard.relations.get(group, {})
		if group_id.is_empty() or not entries.has(group_id):
			continue
		var entry: Variant = entries[group_id]
		var relation: Dictionary = entry if entry is Dictionary else {"value": entry}
		var value := float(relation.get("value", 0))
		active_relations[group] = value
		_add_tags(tags, relation.get("tags", []))
		_add_tags(suppress, relation.get("suppress_tags", []))
		for band: Dictionary in _bands.get(group, []):
			if _within(band, value):
				_add_tags(tags, band.get("tags", []))
				_add_tags(suppress, band.get("suppress_tags", []))
	for flag: String in WorldBlackboard.flag_facts():
		if bool(WorldBlackboard.get_flag(flag)):
			tags.append("flag:" + flag)
	var skill := str(context.get("skill_id", ""))
	if not skill.is_empty():
		tags.append("skill:" + skill)
	facts["stat"] = stat
	facts["actor_tags"] = actor_tags
	facts["tags"] = tags
	facts["active_suppress_tags"] = suppress
	facts["proficiencies"] = WorldBlackboard.proficiencies.duplicate(true)
	facts["relation_values"] = active_relations
	facts["relations"] = WorldBlackboard.relations.duplicate(true)
	facts["flags"] = WorldBlackboard.flag_facts()
	facts["stats"] = WorldBlackboard.stats.duplicate(true)
	facts["resources"] = WorldBlackboard.resources.duplicate(true)
	facts["combat_profile"] = WorldBlackboard.combat_profile.duplicate(true)
	return facts


func _matches(conditions: Dictionary, facts: Dictionary) -> bool:
	var actor: Array[String] = facts["actor_tags"]
	var tags: Array[String] = facts["tags"]
	for required: String in conditions.get("actor_tags_all", []):
		if not actor.has(required):
			return false
	for required: String in conditions.get("context_tags_all", []):
		if not tags.has(required):
			return false
	var any: Array = conditions.get("context_tags_any", [])
	if (not any.is_empty() and not _overlaps(tags, any)) or _overlaps(tags, conditions.get("context_tags_none", [])):
		return false
	if conditions.has("min_value") or conditions.has("max_value"):
		var path := str(conditions.get("value_path", "value"))
		var value: Variant = facts
		for key: String in path.split("."):
			value = value.get(key, 0) if value is Dictionary else 0
		if not (value is int or value is float) or not _within(conditions, float(value)):
			return false
	return true


func _within(rule: Dictionary, value: float) -> bool:
	return value >= float(rule.get("min_value", -INF)) and value <= float(rule.get("max_value", INF))


func _overlaps(active: Array[String], requested: Variant) -> bool:
	if not (requested is Array or requested is PackedStringArray):
		return false
	for tag: String in requested:
		if active.has(tag):
			return true
	return false


func _add_tags(target: Array[String], values: Variant) -> void:
	if values is Array or values is PackedStringArray:
		for value: Variant in values:
			if value is String and not target.has(value):
				target.append(value)


func _add_modifiers(target: Array[Dictionary], values: Variant) -> void:
	if values is Array:
		for entry: Variant in values:
			if entry is Dictionary:
				target.append(entry)


func build_modifier(value: int, extra: int = 0, label: String = "") -> Dictionary[String, Variant]:
	var base := floori((value - 10) / 2.0)
	var bonuses: Array[Dictionary] = []
	if extra != 0:
		bonuses.append({"name": label, "value": extra})
	var modifiers: Dictionary[String, Variant] = {
		"base_stat": value, "effective_stat": value, "base_mod": base,
		"bonus_list": bonuses, "total_mod": base + extra
	}
	return modifiers


func attack_check(modifiers: Dictionary, defense: int, rng: RandomNumberGenerator) -> Dictionary[String, Variant]:
	return roll_modified_check(modifiers, defense, "natural", 0, rng)


func defense_check(modifiers: Dictionary, dc: int, advantage: int, rng: RandomNumberGenerator) -> Dictionary[String, Variant]:
	return roll_modified_check(modifiers, dc, "natural", advantage, rng)


func concentration_check(modifiers: Dictionary, damage: int, config: Dictionary, rng: RandomNumberGenerator) -> Dictionary[String, Variant]:
	var dc := maxi(int(config["dc_min"]), floori(damage * float(config["damage_factor"])))
	return roll_modified_check(modifiers, dc, "natural", 0, rng)


func roll_modified_check(modifiers: Dictionary, dc: int, mode: String = "natural", advantage: int = 0, rng: RandomNumberGenerator = null) -> Dictionary[String, Variant]:
	var generator := _rng if rng == null else rng
	var total_mod := int(modifiers["total_mod"])
	var rolls: Array[int] = []
	var roll := 0
	match mode:
		"force_success":
			roll = clampi(maxi(14, dc - total_mod), 1, 20)
			rolls.append(roll)
			if advantage != 0:
				rolls.append(clampi(roll - signi(advantage) * 5, 1, 20))
		"force_fail":
			roll = clampi(mini(6, dc - total_mod - 1), 1, 20)
			rolls.append(roll)
			if advantage != 0:
				rolls.append(clampi(roll - signi(advantage) * 4, 1, 20))
		_:
			mode = "natural"
			rolls.append(generator.randi_range(1, 20))
			roll = rolls[0]
			if advantage != 0:
				rolls.append(generator.randi_range(1, 20))
				roll = maxi(roll, rolls[1]) if advantage > 0 else mini(roll, rolls[1])
	var total := roll + total_mod
	var passed := total >= dc
	if mode != "natural":
		passed = mode == "force_success"
	var result: Dictionary[String, Variant] = {
		"raw_roll": roll,
		"rolls": rolls,
		"advantage": signi(advantage),
		"base_stat": modifiers["base_stat"],
		"effective_stat": modifiers["effective_stat"],
		"base_mod": modifiers["base_mod"],
		"bonus_list": modifiers["bonus_list"],
		"total_mod": total_mod,
		"total": total,
		"dc": dc,
		"passed": passed,
		"is_nat20": roll == 20,
		"is_nat1": roll == 1,
		"mode": mode
	}
	return result
