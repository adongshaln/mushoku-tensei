extends RefCounted

const ENCOUNTER_PATH := "res://data/maps/region_encounters.json"
const Planner := preload("res://core/travel_planner.gd")

var _config: Dictionary = {}
var _pools: Array[Dictionary] = []
var _posture_mult: Dictionary = {}


func _init() -> void:
	reload()


func reload() -> void:
	_config = WorldBlackboard.read_config(ENCOUNTER_PATH)
	_pools.clear()
	for entry: Variant in _config.get("pools", []):
		if entry is Dictionary:
			_pools.append(entry)
	var mults: Variant = _config.get("posture_multipliers", {})
	_posture_mult = mults if mults is Dictionary else {}


func roll_leg_encounter(leg: Planner.Leg, dest_info: Dictionary, posture: String,
		rng: RandomNumberGenerator, force_pool_id: String = "") -> Dictionary:
	if leg == null or leg.mode == Planner.SHIP:
		return {}
	var mult := float(_posture_mult.get(posture, 1.0))
	var is_checkpoint := bool(dest_info.get("checkpoint", false))
	var zone := str(dest_info.get("encounter_zone", ""))

	for pool: Dictionary in _pools:
		var pool_id := str(pool.get("id", ""))
		if not force_pool_id.is_empty():
			if pool_id != force_pool_id:
				continue
			return _pick_from_pool(pool, rng)
		if leg.km < int(pool.get("min_km", 0)):
			continue
		if not _pool_matches(pool, leg.danger_tag, zone, is_checkpoint):
			continue
		var base_chance := float(pool.get("base_chance", 0.2))
		var dist_scale := clampf(float(leg.km) / 420.0, 0.55, 1.35) if not bool(pool.get("match_checkpoint", false)) else 1.0
		var chance := clampf(base_chance * mult * dist_scale, 0.04, 0.90)
		if rng.randf() < chance:
			return _pick_from_pool(pool, rng)
	return {}


func _pool_matches(pool: Dictionary, danger_tag: String, zone: String, is_checkpoint: bool) -> bool:
	if bool(pool.get("match_checkpoint", false)) and is_checkpoint:
		return true
	var tags: Array = pool.get("match_danger_tags", [])
	if danger_tag in tags:
		return true
	var zones: Array = pool.get("match_zones", [])
	if not zone.is_empty() and zone in zones:
		return true
	return false


func _pick_from_pool(pool: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var events: Array = pool.get("events", [])
	if events.is_empty():
		return {}
	var chosen: Dictionary = (events[rng.randi_range(0, events.size() - 1)] as Dictionary).duplicate(true)
	chosen["pool_id"] = str(pool.get("id", ""))
	chosen["trigger_progress"] = clampf(float(pool.get("trigger_progress", 0.50)), 0.25, 0.90)
	return chosen


func build_check_for_option(option: Dictionary) -> Dictionary:
	var check_cfg: Dictionary = option.get("check", {})
	if check_cfg.is_empty():
		return {}
	var stat := str(check_cfg.get("stat", "WIL"))
	var dc := int(check_cfg.get("dc", 12))
	var ctx: Dictionary = (check_cfg.get("context", {}) as Dictionary).duplicate(true)
	var hood_item := str(check_cfg.get("hood_bonus_item", ""))
	var hood_applied := false
	if not hood_item.is_empty() and WorldBlackboard.get_item_count(hood_item) > 0:
		var extras: Array = ctx.get("extra_modifiers", [])
		extras.append({
			"id": hood_item,
			"label": "旅行兜帽遮掩",
			"category": "装备",
			"value": int(check_cfg.get("hood_bonus_value", 2))
		})
		ctx["extra_modifiers"] = extras
		hood_applied = true
	var rolled := RuleEngine.roll_check(stat, dc, "natural", 0, ctx)
	return {
		"check": rolled,
		"label": str(check_cfg.get("label", WorldBlackboard.stat_label(stat))),
		"hood_applied": hood_applied
	}


func resolve_direct_option(option: Dictionary) -> String:
	var effects: Array = option.get("effects", [])
	if _can_pay_effects(effects):
		apply_effects(effects)
		return str(option.get("outcome_text", "处理完毕，继续踏上行程。"))
	var fallback: Array = option.get("fallback_effects", [])
	apply_effects(fallback)
	return str(option.get("fallback_text", option.get("outcome_text", "物资略显拮据，好在平安脱身。")))


func apply_check_outcome(option: Dictionary, passed: bool) -> String:
	var effects: Array = option.get("success_effects", []) if passed else option.get("fail_effects", [])
	apply_effects(effects)
	return str(option.get("success_text", "应对顺利，继续前行。")) if passed else str(option.get("fail_text", "略受波折，整顿后继续前行。"))


func _can_pay_effects(effects: Array) -> bool:
	for entry: Variant in effects:
		if not entry is Dictionary:
			continue
		var eff: Dictionary = entry
		match str(eff.get("type", "")):
			"spend_copper":
				if not WorldBlackboard.can_afford(int(eff.get("amount", 0))):
					return false
			"consume_rations":
				if WorldBlackboard.get_total_rations() < int(eff.get("amount", 0)):
					return false
	return true


func apply_effects(effects: Array) -> void:
	for entry: Variant in effects:
		if not entry is Dictionary:
			continue
		var eff: Dictionary = entry
		match str(eff.get("type", "")):
			"spend_copper":
				var cost := int(eff.get("amount", 0))
				if cost > 0:
					WorldBlackboard.spend_currency(mini(cost, WorldBlackboard.currency_copper))
			"consume_rations":
				var amt := int(eff.get("amount", 0))
				if amt > 0:
					WorldBlackboard.consume_rations(amt)
			"add_item":
				WorldBlackboard.add_item(
					str(eff.get("id", "trail_rations")),
					str(eff.get("name", "旅途干粮")),
					int(eff.get("count", 1)),
					str(eff.get("tag", ""))
				)
			"restore_mp":
				WorldBlackboard.restore_mp(int(eff.get("amount", 0)))
			"advance_time":
				WorldBlackboard.advance_time(int(eff.get("slots", 0)))
			"set_flag":
				WorldBlackboard.set_flag(str(eff.get("id", "")), eff.get("value", true))
			"add_buff":
				WorldBlackboard.add_buff(
					str(eff.get("id", "")),
					str(eff.get("name", "")),
					eff.get("stat_bonus", {}),
					eff.get("check_bonus", {}),
					eff
				)
			"remove_buff":
				WorldBlackboard.remove_buff(str(eff.get("id", "")))
