extends Node

signal wallet_changed
signal survival_state_changed
signal economy_state_changed
signal exchange_completed(result: Dictionary)
signal purchase_completed(kind: String, result: Dictionary)

const CURRENCIES_PATH := "res://data/economy/currencies.json"
const CATALOG_PATH := "res://data/economy/town_economy_catalog.json"
const MAX_STAMINA := 100
const DEFAULT_STAMINA := 100

var _currency_order: Array[String] = []
var _currencies: Dictionary[String, Dictionary] = {}
var _venues: Dictionary[String, Dictionary] = {}
var _cities: Dictionary[String, Dictionary] = {}
var _supplies: Array[Dictionary] = []
var _supplies_by_id: Dictionary[String, Dictionary] = {}
var _inn_tiers: Array[Dictionary] = []
var _inn_tiers_by_id: Dictionary[String, Dictionary] = {}
var _restaurant_menus: Dictionary[String, Array] = {}
var _sea_ferry_fares: Array[Dictionary] = []
var _modifier_defs: Dictionary[String, Dictionary] = {}
var _legacy_copper_to_base := 100

var wallet: Dictionary[String, int] = {}
var stamina := DEFAULT_STAMINA
var max_stamina := MAX_STAMINA
var hunger_days := 0
var active_modifiers: Dictionary[String, Dictionary] = {}
var _syncing_blackboard := false


func _ready() -> void:
	_load_configs()
	_init_empty_wallet()
	reset_from_blackboard()
	SaveManager.register_save_module("economy", serialize_state, deserialize_state)
	RuleEngine.register_modifier_provider("economy_survival", _provide_rule_modifiers, 80)
	WorldBlackboard.location_changed.connect(_on_world_location_changed)


func _load_configs() -> void:
	var curr_data := WorldBlackboard.read_config(CURRENCIES_PATH)
	_legacy_copper_to_base = maxi(1, int(curr_data.get("legacy_copper_to_base", 100)))
	_currency_order.clear()
	for raw_id: Variant in curr_data.get("default_currency_order", []):
		if raw_id is String and not raw_id.is_empty():
			_currency_order.append(raw_id)
	_currencies.clear()
	var raw_currencies: Variant = curr_data.get("currencies", {})
	if raw_currencies is Dictionary:
		for key: Variant in raw_currencies:
			var cid := str(key)
			if raw_currencies[key] is Dictionary:
				_currencies[cid] = (raw_currencies[key] as Dictionary).duplicate(true)
				if not _currency_order.has(cid):
					_currency_order.append(cid)
	_venues.clear()
	var raw_venues: Variant = curr_data.get("exchange_venues", {})
	if raw_venues is Dictionary:
		for key: Variant in raw_venues:
			if raw_venues[key] is Dictionary:
				_venues[str(key)] = (raw_venues[key] as Dictionary).duplicate(true)

	var cat_data := WorldBlackboard.read_config(CATALOG_PATH)
	_cities.clear()
	var raw_cities: Variant = cat_data.get("cities", {})
	if raw_cities is Dictionary:
		for key: Variant in raw_cities:
			if raw_cities[key] is Dictionary:
				_cities[str(key)] = (raw_cities[key] as Dictionary).duplicate(true)

	_supplies.clear()
	_supplies_by_id.clear()
	for entry: Variant in cat_data.get("supplies", []):
		if entry is Dictionary:
			var copy := (entry as Dictionary).duplicate(true)
			_supplies.append(copy)
			_supplies_by_id[str(copy.get("id", ""))] = copy

	_inn_tiers.clear()
	_inn_tiers_by_id.clear()
	for entry: Variant in cat_data.get("inn_tiers", []):
		if entry is Dictionary:
			var copy := (entry as Dictionary).duplicate(true)
			_inn_tiers.append(copy)
			_inn_tiers_by_id[str(copy.get("id", ""))] = copy

	_restaurant_menus.clear()
	var raw_menus: Variant = cat_data.get("restaurant_menus", {})
	if raw_menus is Dictionary:
		for cont_key: Variant in raw_menus:
			if raw_menus[cont_key] is Array:
				var dishes: Array = []
				for dish: Variant in raw_menus[cont_key]:
					if dish is Dictionary:
						dishes.append((dish as Dictionary).duplicate(true))
				_restaurant_menus[str(cont_key)] = dishes

	_sea_ferry_fares.clear()
	for fare: Variant in cat_data.get("sea_ferry_fares", []):
		if fare is Dictionary:
			_sea_ferry_fares.append((fare as Dictionary).duplicate(true))

	_modifier_defs.clear()
	var raw_mods: Variant = cat_data.get("modifiers", {})
	if raw_mods is Dictionary:
		for mod_key: Variant in raw_mods:
			if raw_mods[mod_key] is Dictionary:
				_modifier_defs[str(mod_key)] = (raw_mods[mod_key] as Dictionary).duplicate(true)


func _init_empty_wallet() -> void:
	wallet.clear()
	for cid: String in _currency_order:
		wallet[cid] = 0


func get_currency_order() -> Array[String]:
	return _currency_order.duplicate()


func get_currency_def(currency_id: String) -> Dictionary:
	return _currencies.get(currency_id, {}).duplicate(true)


func get_unit_base_value(currency_id: String) -> int:
	var def: Dictionary = _currencies.get(currency_id, {})
	return maxi(1, int(def.get("unit_base_value", 1)))


func get_venue_def(venue_type: String) -> Dictionary:
	return _venues.get(venue_type, {}).duplicate(true)


func normalize_city_id(city_id: String) -> String:
	var raw := city_id.strip_edges()
	if raw.is_empty():
		raw = WorldBlackboard.current_city_id
	if _cities.has(raw):
		return raw
	var prefixed := "city_" + raw
	if _cities.has(prefixed):
		return prefixed
	return raw


func get_city_economy(city_id: String = "") -> Dictionary:
	var resolved := normalize_city_id(city_id)
	if _cities.has(resolved):
		return _cities[resolved].duplicate(true)
	return {
		"city_id": resolved,
		"name": WorldBlackboard.catalog.city_names.get(resolved, resolved),
		"continent": "demon",
		"currency_id": "demon_ore",
		"price_multiplier": 1.0,
		"town_tier": "medium",
		"services": {"adventurer_guild": true, "inn": true, "restaurant": true, "merchant": true}
	}


func get_all_city_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _cities:
		ids.append(key)
	ids.sort()
	return ids


func get_local_currency_id(city_id: String = "") -> String:
	var city := get_city_economy(city_id)
	var cid := str(city.get("currency_id", "demon_ore"))
	return cid if _currencies.has(cid) else "demon_ore"


func has_city_service(city_id: String, service_key: String) -> bool:
	var city := get_city_economy(city_id)
	var services: Variant = city.get("services", {})
	if services is Dictionary:
		return bool((services as Dictionary).get(service_key, false))
	return false


func has_exchange_venue(city_id: String, venue_type: String) -> bool:
	var venue: Dictionary = _venues.get(venue_type, {})
	if venue.is_empty():
		return false
	var service_key := str(venue.get("service_key", venue_type))
	return has_city_service(city_id, service_key)


func get_balance(currency_id: String) -> int:
	return maxi(0, int(wallet.get(currency_id, 0)))


func set_balance(currency_id: String, min_units: int) -> void:
	if not _currencies.has(currency_id):
		return
	wallet[currency_id] = maxi(0, min_units)
	_sync_to_blackboard()
	wallet_changed.emit()
	economy_state_changed.emit()


func add_currency(currency_id: String, delta_min_units: int) -> bool:
	if not _currencies.has(currency_id):
		return false
	var next := get_balance(currency_id) + delta_min_units
	if next < 0:
		return false
	wallet[currency_id] = next
	_sync_to_blackboard()
	wallet_changed.emit()
	economy_state_changed.emit()
	return true


func get_total_wealth_in_base() -> int:
	var total := 0
	for cid: String in _currency_order:
		total += get_balance(cid) * get_unit_base_value(cid)
	return total


func format_currency(currency_id: String, min_units: int, use_full_names: bool = false) -> String:
	var def: Dictionary = _currencies.get(currency_id, {})
	if def.is_empty():
		return "%d 基准点" % min_units
	var denoms_raw: Variant = def.get("denominations", [])
	if not denoms_raw is Array or (denoms_raw as Array).is_empty():
		return "%d" % min_units
	var negative := min_units < 0
	var remaining := absi(min_units)
	var parts := PackedStringArray()
	var denoms: Array = denoms_raw
	for entry_var: Variant in denoms:
		if not entry_var is Dictionary:
			continue
		var entry: Dictionary = entry_var
		var step := maxi(1, int(entry.get("min_units", 1)))
		@warning_ignore("integer_division")
		var count := remaining / step
		remaining = remaining % step
		if count > 0:
			var label := str(entry.get("name" if use_full_names else "short_name", ""))
			parts.append("%d %s" % [count, label])
	if parts.is_empty():
		var smallest: Dictionary = denoms[denoms.size() - 1]
		var zero_label := str(smallest.get("name" if use_full_names else "short_name", ""))
		parts.append("0 %s" % zero_label)
	return ("−" if negative else "") + " ".join(parts)


func format_wallet_summary(city_id: String = "") -> String:
	var local_id := get_local_currency_id(city_id)
	var local_def := get_currency_def(local_id)
	var short_tag := str(local_def.get("short_name", local_id))
	return "%s（%s）" % [format_currency(local_id, get_balance(local_id)), short_tag]


func get_held_currencies(include_zero: bool = false) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cid: String in _currency_order:
		var amount := get_balance(cid)
		if amount <= 0 and not include_zero:
			continue
		var def := get_currency_def(cid)
		result.append({
			"currency_id": cid,
			"name": str(def.get("name", cid)),
			"short_name": str(def.get("short_name", cid)),
			"region_label": str(def.get("region_label", "")),
			"multiplier": float(def.get("multiplier", 1.0)),
			"unit_base_value": get_unit_base_value(cid),
			"min_units": amount,
			"base_value": amount * get_unit_base_value(cid),
			"formatted": format_currency(cid, amount),
			"accent_hex": str(def.get("accent_hex", "#8c6548"))
		})
	return result


func get_exact_lossless_step(from_currency: String, to_currency: String) -> int:
	var u_from := get_unit_base_value(from_currency)
	var u_to := get_unit_base_value(to_currency)
	@warning_ignore("integer_division")
	return u_to / _gcd(u_from, u_to)


func get_exchange_rate_text(from_currency: String, to_currency: String) -> String:
	var u_from := get_unit_base_value(from_currency)
	var u_to := get_unit_base_value(to_currency)
	var divisor := _gcd(u_from, u_to)
	@warning_ignore("integer_division")
	var from_count := u_to / divisor
	@warning_ignore("integer_division")
	var to_count := u_from / divisor
	return "%s = %s" % [
		format_currency(from_currency, from_count),
		format_currency(to_currency, to_count)
	]


func compute_local_price_units(city_id: String, catalog_base_price: int, quantity: int = 1) -> int:
	var city := get_city_economy(city_id)
	var mult := float(city.get("price_multiplier", 1.0))
	var local_id := get_local_currency_id(city_id)
	var u_local := get_unit_base_value(local_id)
	var unit_base := maxi(u_local, roundi(float(catalog_base_price) * mult))
	var unit_local := maxi(1, ceili(float(unit_base) / float(u_local)))
	return unit_local * maxi(1, quantity)


func get_supplies_catalog(city_id: String = "") -> Array[Dictionary]:
	var resolved := normalize_city_id(city_id)
	var local_id := get_local_currency_id(resolved)
	var u_local := get_unit_base_value(local_id)
	var out: Array[Dictionary] = []
	for item: Dictionary in _supplies:
		var entry := item.duplicate(true)
		var local_units := compute_local_price_units(resolved, int(item.get("base_price", 100)), 1)
		entry["currency_id"] = local_id
		entry["local_units"] = local_units
		entry["local_base_price"] = local_units * u_local
		entry["formatted_price"] = format_currency(local_id, local_units)
		entry["owned_count"] = WorldBlackboard.get_item_count(str(item.get("id", "")))
		out.append(entry)
	return out


func get_inn_tiers(city_id: String = "") -> Array[Dictionary]:
	var resolved := normalize_city_id(city_id)
	var city := get_city_economy(resolved)
	var local_id := get_local_currency_id(resolved)
	var u_local := get_unit_base_value(local_id)
	var town_tier := str(city.get("town_tier", "medium"))
	var has_inn := has_city_service(resolved, "inn")
	var out: Array[Dictionary] = []
	for tier: Dictionary in _inn_tiers:
		var entry := tier.duplicate(true)
		var large_only := bool(tier.get("large_town_only", false))
		var tier_allowed := has_inn and (not large_only or town_tier in ["medium", "large", "capital"])
		var local_units := compute_local_price_units(resolved, int(tier.get("base_price", 500)), 1)
		entry["currency_id"] = local_id
		entry["local_units"] = local_units
		entry["local_base_price"] = local_units * u_local
		entry["formatted_price"] = format_currency(local_id, local_units)
		entry["available"] = tier_allowed
		entry["unavailable_reason"] = "" if tier_allowed else (
			"该城镇未设旅馆" if not has_inn else "仅中大型城镇或王都旅馆提供热水浴套房"
		)
		out.append(entry)
	return out


func get_restaurant_menu(city_id: String = "") -> Array[Dictionary]:
	var resolved := normalize_city_id(city_id)
	var city := get_city_economy(resolved)
	var continent := str(city.get("continent", "demon"))
	var local_id := get_local_currency_id(resolved)
	var u_local := get_unit_base_value(local_id)
	var raw_dishes: Array = _restaurant_menus.get(continent, _restaurant_menus.get("demon", []))
	var out: Array[Dictionary] = []
	for dish_var: Variant in raw_dishes:
		if not dish_var is Dictionary:
			continue
		var dish: Dictionary = dish_var
		var entry := dish.duplicate(true)
		var local_units := compute_local_price_units(resolved, int(dish.get("base_price", 200)), 1)
		entry["currency_id"] = local_id
		entry["local_units"] = local_units
		entry["local_base_price"] = local_units * u_local
		entry["formatted_price"] = format_currency(local_id, local_units)
		out.append(entry)
	return out


func get_sea_ferry_fares() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _sea_ferry_fares:
		var copy := entry.duplicate(true)
		var from_city := str(entry.get("from_city_id", ""))
		var local_id := get_local_currency_id(from_city)
		var u_local := get_unit_base_value(local_id)
		var base_fare := int(entry.get("base_fare", 0))
		var local_units := ceili(float(base_fare) / float(u_local))
		copy["from_currency_id"] = local_id
		copy["from_local_units"] = local_units
		copy["formatted_from_fare"] = format_currency(local_id, local_units)
		out.append(copy)
	return out


func get_ferry_fare_quote(from_city_id: String, to_city_id: String, pay_currency_id: String = "") -> Dictionary:
	var src := normalize_city_id(from_city_id)
	var dst := normalize_city_id(to_city_id)
	for entry: Dictionary in _sea_ferry_fares:
		var a := str(entry.get("from_city_id", ""))
		var b := str(entry.get("to_city_id", ""))
		if (src == a and dst == b) or (src == b and dst == a):
			var local_id := get_local_currency_id(src)
			var u_local := get_unit_base_value(local_id)
			var base_fare := int(entry.get("base_fare", 0))
			var local_units := ceili(float(base_fare) / float(u_local))
			var payment := quote_purchase(src, local_units, "traveling_merchant", pay_currency_id)
			payment["ferry_id"] = str(entry.get("id", ""))
			payment["label"] = str(entry.get("label", ""))
			payment["duration_days"] = int(entry.get("duration_days", 1))
			return payment
	return {"ok": false, "reason": "ferry_not_found", "reason_text": "两港之间无定期跨海客船航线"}


func quote_exchange(from_currency: String, to_currency: String, from_min_units: int,
		venue_type: String, city_id: String = "") -> Dictionary:
	var resolved_city := normalize_city_id(city_id)
	var city := get_city_economy(resolved_city)
	var base_quote := {
		"ok": false,
		"reason": "",
		"reason_text": "",
		"city_id": resolved_city,
		"city_name": str(city.get("name", resolved_city)),
		"venue_type": venue_type,
		"venue_name": str(_venues.get(venue_type, {}).get("name", venue_type)),
		"from_currency": from_currency,
		"to_currency": to_currency,
		"fee_rate": 0.0,
		"rate_ratio": 1.0,
		"rate_text": "",
		"requested_from_units": from_min_units,
		"actual_from_units": 0,
		"refund_from_units": 0,
		"received_units": 0,
		"requested_gross_base": 0,
		"requested_fee_base": 0,
		"gross_base": 0,
		"fee_base": 0,
		"net_base": 0,
		"received_base": 0,
		"remainder_base": 0,
		"affordable": false,
		"exact_step_from_units": 1,
		"formatted_actual_from": "",
		"formatted_refund_from": "",
		"formatted_received": ""
	}
	if not _currencies.has(from_currency) or not _currencies.has(to_currency):
		base_quote["reason"] = "invalid_currency"
		base_quote["reason_text"] = "未知的货币类型"
		return base_quote
	if from_currency == to_currency:
		base_quote["reason"] = "same_currency"
		base_quote["reason_text"] = "源货币与目标货币相同，无需换汇"
		return base_quote
	if not _venues.has(venue_type):
		base_quote["reason"] = "invalid_venue"
		base_quote["reason_text"] = "未知的换汇渠道"
		return base_quote
	if not has_exchange_venue(resolved_city, venue_type):
		base_quote["reason"] = "venue_unavailable"
		base_quote["reason_text"] = str(city.get("guild_absence_note",
			"%s未设%s，无法通过此渠道换汇" % [str(city.get("name", resolved_city)), str(_venues[venue_type].get("name", venue_type))]))
		return base_quote
	if from_min_units <= 0:
		base_quote["reason"] = "non_positive_amount"
		base_quote["reason_text"] = "请输入大于 0 的兑换金额"
		return base_quote

	var venue: Dictionary = _venues[venue_type]
	var fee_rate := float(venue.get("fee_rate", 0.0))
	var fee_num := int(venue.get("fee_numerator", roundi(fee_rate * 100.0)))
	var fee_den := maxi(1, int(venue.get("fee_denominator", 100)))
	var u_from := get_unit_base_value(from_currency)
	var u_to := get_unit_base_value(to_currency)

	var requested_gross_base := from_min_units * u_from
	var requested_fee_base := _compute_fee_base(requested_gross_base, fee_num, fee_den)
	var requested_net_base := maxi(0, requested_gross_base - requested_fee_base)
	@warning_ignore("integer_division")
	var received_units := requested_net_base / u_to

	base_quote["fee_rate"] = fee_rate
	base_quote["rate_ratio"] = float(u_from) / float(u_to)
	base_quote["rate_text"] = get_exchange_rate_text(from_currency, to_currency)
	base_quote["requested_gross_base"] = requested_gross_base
	base_quote["requested_fee_base"] = requested_fee_base
	base_quote["exact_step_from_units"] = get_exact_lossless_step(from_currency, to_currency)

	if received_units <= 0:
		var min_needed := _min_source_units_for_target_base(u_from, u_to, fee_num, fee_den)
		base_quote["reason"] = "amount_too_small"
		base_quote["min_required_from_units"] = min_needed
		base_quote["reason_text"] = "金额不足以兑换 1 枚目标最小币（至少需要 %s）" % format_currency(from_currency, min_needed)
		return base_quote

	var target_base := received_units * u_to
	var actual_from_units := _min_source_units_for_target_base(u_from, target_base, fee_num, fee_den, from_min_units)
	var refund_from_units := maxi(0, from_min_units - actual_from_units)
	var actual_gross_base := actual_from_units * u_from
	var actual_fee_base := _compute_fee_base(actual_gross_base, fee_num, fee_den)
	var actual_net_base := actual_gross_base - actual_fee_base
	var remainder_base := maxi(0, actual_net_base - target_base)

	base_quote["ok"] = true
	base_quote["actual_from_units"] = actual_from_units
	base_quote["refund_from_units"] = refund_from_units
	base_quote["received_units"] = received_units
	base_quote["gross_base"] = actual_gross_base
	base_quote["fee_base"] = actual_fee_base
	base_quote["net_base"] = actual_net_base
	base_quote["received_base"] = target_base
	base_quote["remainder_base"] = remainder_base
	base_quote["affordable"] = get_balance(from_currency) >= actual_from_units
	base_quote["formatted_actual_from"] = format_currency(from_currency, actual_from_units)
	base_quote["formatted_refund_from"] = format_currency(from_currency, refund_from_units)
	base_quote["formatted_received"] = format_currency(to_currency, received_units)
	return base_quote


func execute_exchange(from_currency: String, to_currency: String, from_min_units: int,
		venue_type: String, city_id: String = "") -> Dictionary:
	var quote := quote_exchange(from_currency, to_currency, from_min_units, venue_type, city_id)
	if not bool(quote.get("ok", false)):
		quote["executed"] = false
		return quote
	var actual_from := int(quote["actual_from_units"])
	var received := int(quote["received_units"])
	if get_balance(from_currency) < actual_from:
		quote["ok"] = false
		quote["executed"] = false
		quote["reason"] = "insufficient_funds"
		quote["reason_text"] = "%s余额不足（需要 %s，当前持有 %s）" % [
			str(get_currency_def(from_currency).get("short_name", from_currency)),
			format_currency(from_currency, actual_from),
			format_currency(from_currency, get_balance(from_currency))
		]
		return quote
	wallet[from_currency] = get_balance(from_currency) - actual_from
	wallet[to_currency] = get_balance(to_currency) + received
	quote["executed"] = true
	_sync_to_blackboard()
	wallet_changed.emit()
	exchange_completed.emit(quote.duplicate(true))
	economy_state_changed.emit()
	return quote


func quote_purchase(city_id: String, local_units_cost: int, venue_type: String,
		pay_currency_id: String = "") -> Dictionary:
	var resolved_city := normalize_city_id(city_id)
	var local_id := get_local_currency_id(resolved_city)
	var pay_id := local_id if pay_currency_id.is_empty() else pay_currency_id
	var u_local := get_unit_base_value(local_id)
	var cost_units := maxi(0, local_units_cost)
	var local_base_cost := cost_units * u_local
	var result := {
		"ok": false,
		"reason": "",
		"reason_text": "",
		"city_id": resolved_city,
		"venue_type": venue_type,
		"local_currency_id": local_id,
		"local_units_cost": cost_units,
		"local_base_cost": local_base_cost,
		"formatted_local_cost": format_currency(local_id, cost_units),
		"pay_currency_id": pay_id,
		"is_foreign_payment": pay_id != local_id,
		"fee_rate": 0.0,
		"fee_base": 0,
		"pay_units": 0,
		"pay_gross_base": 0,
		"pay_net_base": 0,
		"change_local_units": 0,
		"formatted_pay": "",
		"formatted_change": "",
		"affordable": false
	}
	if not _currencies.has(pay_id):
		result["reason"] = "invalid_currency"
		result["reason_text"] = "无效的支付货币"
		return result
	if cost_units == 0:
		result["ok"] = true
		result["affordable"] = true
		result["formatted_pay"] = format_currency(pay_id, 0)
		return result

	if pay_id == local_id:
		result["ok"] = true
		result["pay_units"] = cost_units
		result["pay_gross_base"] = local_base_cost
		result["pay_net_base"] = local_base_cost
		result["formatted_pay"] = format_currency(local_id, cost_units)
		result["affordable"] = get_balance(local_id) >= cost_units
		if not bool(result["affordable"]):
			result["reason"] = "insufficient_funds"
			result["reason_text"] = "本地货币余额不足，可切换外币折算直付（5% 手续费）"
		return result

	# Foreign currency direct checkout at merchant / inn / restaurant (5% fee).
	var venue: Dictionary = _venues.get(venue_type, _venues.get("traveling_merchant", {}))
	if venue.is_empty():
		result["reason"] = "invalid_venue"
		result["reason_text"] = "该场所不支持外币折算直付"
		return result
	var fee_rate := float(venue.get("fee_rate", 0.05))
	var fee_num := int(venue.get("fee_numerator", 5))
	var fee_den := maxi(1, int(venue.get("fee_denominator", 100)))
	var u_pay := get_unit_base_value(pay_id)
	var pay_units := _min_source_units_for_target_base(u_pay, local_base_cost, fee_num, fee_den)
	var pay_gross_base := pay_units * u_pay
	var fee_base := _compute_fee_base(pay_gross_base, fee_num, fee_den)
	var pay_net_base := pay_gross_base - fee_base
	var surplus_base := maxi(0, pay_net_base - local_base_cost)
	@warning_ignore("integer_division")
	var change_local_units := surplus_base / u_local

	result["ok"] = true
	result["fee_rate"] = fee_rate
	result["fee_base"] = fee_base
	result["pay_units"] = pay_units
	result["pay_gross_base"] = pay_gross_base
	result["pay_net_base"] = pay_net_base
	result["change_local_units"] = change_local_units
	result["formatted_pay"] = format_currency(pay_id, pay_units)
	result["formatted_change"] = format_currency(local_id, change_local_units) if change_local_units > 0 else ""
	result["affordable"] = get_balance(pay_id) >= pay_units
	if not bool(result["affordable"]):
		result["reason"] = "insufficient_funds"
		result["reason_text"] = "%s余额不足以折算支付（需 %s）" % [
			str(get_currency_def(pay_id).get("short_name", pay_id)),
			format_currency(pay_id, pay_units)
		]
	return result


func execute_purchase(city_id: String, local_units_cost: int, venue_type: String,
		pay_currency_id: String = "") -> Dictionary:
	var quote := quote_purchase(city_id, local_units_cost, venue_type, pay_currency_id)
	if not bool(quote.get("ok", false)) or not bool(quote.get("affordable", false)):
		quote["ok"] = false
		quote["executed"] = false
		return quote
	var pay_id := str(quote["pay_currency_id"])
	var local_id := str(quote["local_currency_id"])
	var pay_units := int(quote["pay_units"])
	var change_units := int(quote["change_local_units"])
	wallet[pay_id] = get_balance(pay_id) - pay_units
	if change_units > 0:
		wallet[local_id] = get_balance(local_id) + change_units
	quote["executed"] = true
	_sync_to_blackboard()
	wallet_changed.emit()
	economy_state_changed.emit()
	return quote


func buy_supply(city_id: String, supply_id: String, quantity: int = 1, pay_currency_id: String = "") -> Dictionary:
	var resolved_city := normalize_city_id(city_id)
	if not has_city_service(resolved_city, "merchant"):
		return {"ok": false, "executed": false, "reason": "service_unavailable", "reason_text": "该据点暂无旅商补给摊位"}
	if quantity <= 0 or not _supplies_by_id.has(supply_id):
		return {"ok": false, "executed": false, "reason": "invalid_supply", "reason_text": "无效的补给品或数量"}
	var item: Dictionary = _supplies_by_id[supply_id]
	var total_local_units := compute_local_price_units(resolved_city, int(item.get("base_price", 200)), quantity)
	var payment := execute_purchase(resolved_city, total_local_units, "traveling_merchant", pay_currency_id)
	if not bool(payment.get("executed", false)):
		return payment
	WorldBlackboard.add_item(supply_id, str(item.get("name", supply_id)), quantity, str(item.get("tag", "")))
	payment["supply_id"] = supply_id
	payment["supply_name"] = str(item.get("name", supply_id))
	payment["quantity"] = quantity
	payment["rations_total"] = get_total_rations()
	purchase_completed.emit("supply", payment.duplicate(true))
	economy_state_changed.emit()
	return payment


func rest_at_inn(city_id: String, tier_id: String, pay_currency_id: String = "") -> Dictionary:
	var resolved_city := normalize_city_id(city_id)
	var tiers := get_inn_tiers(resolved_city)
	var chosen: Dictionary = {}
	for entry: Dictionary in tiers:
		if str(entry.get("id", "")) == tier_id:
			chosen = entry
			break
	if chosen.is_empty():
		return {"ok": false, "executed": false, "reason": "invalid_inn_tier", "reason_text": "未找到对应的旅馆房型"}
	if not bool(chosen.get("available", false)):
		return {"ok": false, "executed": false, "reason": "tier_unavailable", "reason_text": str(chosen.get("unavailable_reason", "当前城镇不提供该房型"))}
	var local_units := int(chosen.get("local_units", 0))
	var payment := execute_purchase(resolved_city, local_units, "inn", pay_currency_id)
	if not bool(payment.get("executed", false)):
		return payment

	# Advance Dragon Calendar cleanly to next day morning (slot 0).
	var wt := WorldBlackboard.get_world_time()
	var current_slot := int(wt.get("slot", 0))
	var slots_to_next_morning := WorldBlackboard.SLOTS.size() - current_slot
	WorldBlackboard.advance_time(slots_to_next_morning)

	# Expire previous day's meal/rest buffs, then apply fresh inn recovery.
	_tick_timed_modifiers(1)
	if bool(chosen.get("clears_hunger", true)):
		clear_hunger_penalties(false)
	if bool(chosen.get("clears_fatigue", true)) and WorldBlackboard.has_buff(WorldBlackboard.TRAVEL_FATIGUE_ID):
		WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)

	if bool(chosen.get("full_stamina", false)):
		stamina = max_stamina
	else:
		stamina = mini(max_stamina, stamina + int(chosen.get("stamina_restore", 60)))

	var hp_ratio := float(chosen.get("hp_restore_ratio", 0.5))
	var mp_ratio := float(chosen.get("mp_restore_ratio", 0.5))
	var max_hp := int(WorldBlackboard.resources.get("max_hp", 0))
	var max_mp := int(WorldBlackboard.resources.get("max_mp", 0))
	WorldBlackboard.restore_vitals(
		roundi(float(max_hp) * hp_ratio),
		roundi(float(max_mp) * mp_ratio),
		hp_ratio >= 0.999 and mp_ratio >= 0.999
	)

	var mod_id := str(chosen.get("grants_modifier", ""))
	if not mod_id.is_empty():
		_apply_modifier(mod_id)

	payment["tier_id"] = tier_id
	payment["tier_name"] = str(chosen.get("name", tier_id))
	payment["slots_advanced"] = slots_to_next_morning
	payment["new_date_text"] = WorldBlackboard.date_text()
	payment["stamina"] = stamina
	payment["granted_modifier"] = mod_id
	payment["travel_check_modifier"] = get_travel_check_modifier()
	survival_state_changed.emit()
	purchase_completed.emit("inn", payment.duplicate(true))
	economy_state_changed.emit()
	return payment


func order_meal(city_id: String, dish_id: String, pay_currency_id: String = "") -> Dictionary:
	var resolved_city := normalize_city_id(city_id)
	if not has_city_service(resolved_city, "restaurant"):
		return {"ok": false, "executed": false, "reason": "service_unavailable", "reason_text": "该城镇暂无酒馆或餐馆"}
	var menu := get_restaurant_menu(resolved_city)
	var chosen: Dictionary = {}
	for dish: Dictionary in menu:
		if str(dish.get("id", "")) == dish_id:
			chosen = dish
			break
	if chosen.is_empty():
		return {"ok": false, "executed": false, "reason": "dish_not_found", "reason_text": "本餐馆今日不供应此道菜品"}
	var local_units := int(chosen.get("local_units", 0))
	var payment := execute_purchase(resolved_city, local_units, "restaurant", pay_currency_id)
	if not bool(payment.get("executed", false)):
		return payment

	clear_hunger_penalties(false)
	if WorldBlackboard.has_buff(WorldBlackboard.TRAVEL_FATIGUE_ID):
		WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
	stamina = mini(max_stamina, stamina + int(chosen.get("stamina_restore", 25)))
	var hp_gain := int(chosen.get("hp_restore", 8))
	if hp_gain > 0:
		WorldBlackboard.restore_vitals(hp_gain, 0, false)
	var mod_id := str(chosen.get("grants_modifier", "well_fed"))
	if not mod_id.is_empty():
		_apply_modifier(mod_id)

	payment["dish_id"] = dish_id
	payment["dish_name"] = str(chosen.get("name", dish_id))
	payment["stamina"] = stamina
	payment["granted_modifier"] = mod_id
	payment["travel_check_modifier"] = get_travel_check_modifier()
	survival_state_changed.emit()
	purchase_completed.emit("meal", payment.duplicate(true))
	economy_state_changed.emit()
	return payment


func get_ration_counts() -> Dictionary:
	var normal := WorldBlackboard.get_item_count("ration_normal")
	var fine := WorldBlackboard.get_item_count("ration_fine")
	var legacy := WorldBlackboard.get_item_count(WorldBlackboard.RATION_ID)
	var total := WorldBlackboard.get_total_rations()
	return {
		"normal": normal,
		"fine": fine,
		"legacy": legacy,
		"total": total
	}


func get_total_rations() -> int:
	return WorldBlackboard.get_total_rations()


func get_total_ration_weight_kg() -> float:
	var counts := get_ration_counts()
	var w_normal := float(_supplies_by_id.get("ration_normal", {}).get("weight_kg", 0.6))
	var w_fine := float(_supplies_by_id.get("ration_fine", {}).get("weight_kg", 0.5))
	return float(int(counts["normal"]) + int(counts["legacy"])) * w_normal + float(int(counts["fine"])) * w_fine


func consume_daily_rations(days: int = 1, party_size: int = 1, strategy: String = "normal_first") -> Dictionary:
	var total_days := maxi(0, days)
	var members := maxi(1, party_size)
	var consumed_normal := 0
	var consumed_fine := 0
	var consumed_legacy := 0
	var shortfall_days := 0

	var order: Array[String] = []
	if strategy == "fine_first":
		order = ["ration_fine", "ration_normal", WorldBlackboard.RATION_ID]
	else:
		order = [WorldBlackboard.RATION_ID, "ration_normal", "ration_fine"]

	for _day: int in range(total_days):
		_tick_timed_modifiers(1)
		var remaining := members
		var ate_fine_today := false
		for item_id: String in order:
			if remaining <= 0:
				break
			var available := WorldBlackboard.get_item_count(item_id)
			if available <= 0:
				continue
			var take := mini(remaining, available)
			if WorldBlackboard.consume_item(item_id, take):
				remaining -= take
				if item_id == "ration_fine":
					consumed_fine += take
					ate_fine_today = true
				elif item_id == "ration_normal":
					consumed_normal += take
				else:
					consumed_legacy += take
		if remaining == 0:
			hunger_days = 0
			active_modifiers.erase("hungry")
			active_modifiers.erase("starving")
			if WorldBlackboard.has_buff(WorldBlackboard.TRAVEL_FATIGUE_ID):
				WorldBlackboard.remove_buff(WorldBlackboard.TRAVEL_FATIGUE_ID)
			if ate_fine_today:
				var restore := int(_supplies_by_id.get("ration_fine", {}).get("stamina_restore", 12))
				stamina = mini(max_stamina, stamina + restore)
			else:
				stamina = maxi(20, stamina - 6)
		else:
			shortfall_days += 1
			hunger_days += 1
			stamina = maxi(0, stamina - 25)
			active_modifiers.erase("well_fed")
			if hunger_days == 1:
				active_modifiers.erase("starving")
				_apply_modifier("hungry")
			else:
				active_modifiers.erase("hungry")
				_apply_modifier("starving")

	survival_state_changed.emit()
	economy_state_changed.emit()
	return {
		"days": total_days,
		"party_size": members,
		"strategy": strategy,
		"consumed_total": consumed_normal + consumed_fine + consumed_legacy,
		"consumed_normal": consumed_normal + consumed_legacy,
		"consumed_fine": consumed_fine,
		"shortfall_days": shortfall_days,
		"hunger_days": hunger_days,
		"stamina": stamina,
		"rations_left": get_total_rations(),
		"travel_check_modifier": get_travel_check_modifier()
	}


func clear_hunger_penalties(emit_signals: bool = true) -> void:
	hunger_days = 0
	active_modifiers.erase("hungry")
	active_modifiers.erase("starving")
	if emit_signals:
		survival_state_changed.emit()
		economy_state_changed.emit()


func get_travel_check_modifier() -> int:
	var total := 0
	for mod: Dictionary in active_modifiers.values():
		total += int(mod.get("value", 0))
	return total


func get_active_modifiers_list() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for key: String in active_modifiers:
		result.append(active_modifiers[key].duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var va := int(a.get("value", 0))
		var vb := int(b.get("value", 0))
		if va == vb:
			return str(a.get("id", "")) < str(b.get("id", ""))
		return va > vb)
	return result


func migrate_legacy_wallet(city_id: String, legacy_copper: int, legacy_gold: int = 0) -> void:
	_init_empty_wallet()
	var total_legacy_copper := maxi(0, legacy_gold) * 10000 + maxi(0, legacy_copper)
	var base_points := total_legacy_copper * _legacy_copper_to_base
	var local_id := get_local_currency_id(city_id)
	var u_local := get_unit_base_value(local_id)
	@warning_ignore("integer_division")
	var local_units := base_points / u_local
	var remainder_base := base_points % u_local
	wallet[local_id] = local_units
	if remainder_base > 0 and _currencies.has("demon_ore"):
		wallet["demon_ore"] = get_balance("demon_ore") + remainder_base


func reset_from_blackboard() -> void:
	stamina = DEFAULT_STAMINA
	hunger_days = 0
	active_modifiers.clear()
	migrate_legacy_wallet(WorldBlackboard.current_city_id, WorldBlackboard.currency_copper, 0)
	_sync_to_blackboard()
	wallet_changed.emit()
	survival_state_changed.emit()
	economy_state_changed.emit()


func serialize_state() -> Dictionary:
	var wallet_copy: Dictionary = {}
	for cid: String in _currency_order:
		wallet_copy[cid] = get_balance(cid)
	var mods_copy: Dictionary = {}
	for mod_id: String in active_modifiers:
		mods_copy[mod_id] = active_modifiers[mod_id].duplicate(true)
	return {
		"schema_version": 1,
		"wallet": wallet_copy,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"hunger_days": hunger_days,
		"active_modifiers": mods_copy
	}


func deserialize_state(payload: Dictionary) -> bool:
	if not payload is Dictionary:
		return false
	# Legacy save or fresh new_game without an economy module: migrate cleanly from WorldBlackboard.
	if payload.is_empty() or (not payload.has("wallet") and not payload.has("copper") and not payload.has("gold")):
		reset_from_blackboard()
		return true

	# Legacy standalone copper/gold dict support.
	if not payload.has("wallet") and (payload.has("copper") or payload.has("gold")):
		stamina = clampi(int(payload.get("stamina", DEFAULT_STAMINA)), 0, MAX_STAMINA)
		hunger_days = maxi(0, int(payload.get("hunger_days", 0)))
		active_modifiers.clear()
		migrate_legacy_wallet(
			WorldBlackboard.current_city_id,
			int(payload.get("copper", WorldBlackboard.currency_copper)),
			int(payload.get("gold", 0))
		)
		_sync_to_blackboard()
		wallet_changed.emit()
		survival_state_changed.emit()
		economy_state_changed.emit()
		return true

	_init_empty_wallet()
	var raw_wallet: Variant = payload.get("wallet", {})
	if raw_wallet is Dictionary:
		for key: Variant in raw_wallet:
			var cid := str(key)
			if _currencies.has(cid):
				wallet[cid] = maxi(0, int(raw_wallet[key]))
	max_stamina = maxi(1, int(payload.get("max_stamina", MAX_STAMINA)))
	stamina = clampi(int(payload.get("stamina", max_stamina)), 0, max_stamina)
	hunger_days = maxi(0, int(payload.get("hunger_days", 0)))
	active_modifiers.clear()
	var raw_mods: Variant = payload.get("active_modifiers", {})
	if raw_mods is Dictionary:
		for mod_key: Variant in raw_mods:
			if raw_mods[mod_key] is Dictionary:
				var mod_id := str(mod_key)
				var copy := (raw_mods[mod_key] as Dictionary).duplicate(true)
				copy["id"] = mod_id
				active_modifiers[mod_id] = copy
	_sync_to_blackboard()
	wallet_changed.emit()
	survival_state_changed.emit()
	economy_state_changed.emit()
	return true


func _apply_modifier(mod_id: String) -> void:
	var template: Dictionary = _modifier_defs.get(mod_id, {})
	if template.is_empty():
		return
	var entry := template.duplicate(true)
	entry["remaining_days"] = int(template.get("duration_days", 1))
	active_modifiers[mod_id] = entry


func _tick_timed_modifiers(days_passed: int) -> void:
	if days_passed <= 0:
		return
	var to_remove: Array[String] = []
	for mod_id: String in active_modifiers:
		var entry: Dictionary = active_modifiers[mod_id]
		var remaining := int(entry.get("remaining_days", -1))
		if remaining < 0:
			continue
		remaining -= days_passed
		if remaining <= 0:
			to_remove.append(mod_id)
		else:
			entry["remaining_days"] = remaining
	for mod_id: String in to_remove:
		active_modifiers.erase(mod_id)


func _provide_rule_modifiers(_facts: Dictionary) -> Dictionary:
	var list: Array[Dictionary] = []
	for mod: Dictionary in active_modifiers.values():
		var val := int(mod.get("value", 0))
		if val == 0:
			continue
		list.append({
			"id": "economy:" + str(mod.get("id", "")),
			"name": str(mod.get("name", "")),
			"label": str(mod.get("name", "")),
			"category": str(mod.get("category", "旅途状态")),
			"value": val,
			"tags": ["economy", "survival:" + str(mod.get("id", ""))],
			"suppressible_by": []
		})
	return {"modifiers": list}


func _on_world_location_changed(_city_id: String) -> void:
	if SaveManager.is_restoring():
		return
	_sync_to_blackboard()


func _sync_to_blackboard() -> void:
	if _syncing_blackboard:
		return
	_syncing_blackboard = true
	var local_id := get_local_currency_id(WorldBlackboard.current_city_id)
	var formatted := format_currency(local_id, get_balance(local_id))
	@warning_ignore("integer_division")
	var copper_equiv := get_total_wealth_in_base() / _legacy_copper_to_base
	WorldBlackboard.sync_economy_display(copper_equiv, formatted)
	_syncing_blackboard = false


static func _compute_fee_base(gross_base: int, fee_numerator: int, fee_denominator: int) -> int:
	if gross_base <= 0 or fee_numerator <= 0:
		return 0
	@warning_ignore("integer_division")
	return (gross_base * fee_numerator + fee_denominator - 1) / fee_denominator


static func _min_source_units_for_target_base(u_from: int, target_base: int,
		fee_numerator: int, fee_denominator: int, upper_hint: int = -1) -> int:
	if target_base <= 0:
		return 0
	var lo := 1
	var hi := upper_hint
	if hi <= 0:
		var net_den := maxi(1, fee_denominator - fee_numerator)
		@warning_ignore("integer_division")
		var approx_gross := (target_base * fee_denominator + net_den - 1) / net_den + 2
		@warning_ignore("integer_division")
		hi = maxi(1, (approx_gross + u_from - 1) / u_from + 2)
		while hi * u_from - _compute_fee_base(hi * u_from, fee_numerator, fee_denominator) < target_base:
			hi *= 2
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		var gross := mid * u_from
		var net := gross - _compute_fee_base(gross, fee_numerator, fee_denominator)
		if net >= target_base:
			hi = mid
		else:
			lo = mid + 1
	return lo


static func _gcd(a: int, b: int) -> int:
	var x := absi(a)
	var y := absi(b)
	while y != 0:
		var t := x % y
		x = y
		y = t
	return maxi(1, x)
