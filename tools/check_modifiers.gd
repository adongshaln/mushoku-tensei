extends SceneTree

var failures := 0


func _initialize() -> void:
	_check_rules.call_deferred()


func _check_rules() -> void:
	var world := root.get_node("WorldBlackboard")
	var rules := root.get_node("RuleEngine")
	var facts: Dictionary = {"tags": [
		"intent:persuade", "target_race:human", "faction:millis_church",
		"npc_attitude:wary", "region_lang:human_tongue"
	]}
	var before: Dictionary = rules.roll_check("CHA", 13, "force_success", 0, facts)
	expect(values(before) == {"shared_trade_customs": 1, "church_suspicion": -2,
		"hostile_attitude": -1, "human_language_gap": -2}, "combined traits, attitude, and language")
	expect(world.equip_item("cloak", "travel_hood"), "equip hood")
	var after: Dictionary = rules.roll_check("CHA", 13, "force_success", 0, facts)
	expect(values(after) == {"shared_trade_customs": 1, "hostile_attitude": -1,
		"human_language_gap": -2}, "mask only suppresses the appearance modifier")
	expect(after["suppressed_modifiers"].size() == 1 and after["total_mod"] == before["total_mod"] + 2, "suppression bookkeeping")
	world.equip_item("cloak", "")
	world.relations["npcs"]["porter"] = {"value": 30, "label": "守门人"}
	facts["npc_id"] = "porter"
	var related: Dictionary = rules.collect_check("CHA", facts)
	expect(values(related).has("trusted_affinity") and not values(related).has("church_suspicion"), "relationship provider affects check")
	world.proficiencies["languages"]["human_tongue"] = 3
	world.relations["regions"]["market"] = {"value": 24}
	facts["region_id"] = "market"
	var skilled: Dictionary = rules.collect_check("CHA", facts)
	expect(values(skilled).has("regional_goodwill") and not values(skilled).has("human_language_gap"), "numeric language and reputation conditions")

	rules.register_modifier_provider("example_condition", func(_context: Dictionary) -> Dictionary:
		return {"modifiers": [{
			"id": "wind_pressure", "label": "大风", "category": "环境",
			"value": -2, "suppressible_by": ["shelter:stone"]
		}]}, 10)
	rules.register_modifier_provider("example_shelter", func(_context: Dictionary) -> Dictionary:
		return {"active_suppress_tags": ["shelter:stone"]}, 90)
	facts["extra_modifiers"] = [{"id": "prepared", "label": "提前准备", "value": 2}]
	var provided: Dictionary = rules.collect_check("CHA", facts)
	expect(not values(provided).has("wind_pressure") and values(provided).get("prepared") == 2, "provider suppression and scripted modifiers")
	rules.unregister_modifier_provider("example_shelter")
	expect(values(rules.collect_check("CHA", facts)).get("wind_pressure") == -2, "provider can be removed")
	rules.unregister_modifier_provider("example_condition")
	world.reset_new_game()
	print("MODIFIER CHECK failures=", failures)
	quit(1 if failures else 0)


func values(result: Dictionary) -> Dictionary[String, int]:
	var bonuses: Dictionary[String, int] = {}
	for entry: Dictionary in result["bonus_list"]:
		bonuses[str(entry["id"])] = int(entry["value"])
	return bonuses


func expect(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
