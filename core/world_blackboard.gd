extends Node

signal world_time_changed
signal protagonist_changed
signal buffs_changed
signal inventory_changed
signal flags_changed
signal stat_changed(stat_key: String, delta: int, new_value: int, reason_text: String)
signal location_changed(city_id: String)
signal region_location_changed(region_id: String)
signal transport_changed(mode: String)
signal currency_changed(copper: int)
signal currency_display_changed(text: String)
signal chronicle_recorded(entry: Dictionary)
signal state_changed

const SLOTS: Array[String] = ["上午", "下午", "傍晚", "深夜"]
const VALID_TRANSPORTS: Array[String] = ["foot", "caravan", "ship", "teleport"]
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const PROTAGONIST_PATH := "res://data/protagonists/notia.json" # Legacy importer path.
const Catalog := preload("res://core/character_catalog.gd")
const RATION_ID := "smoked_meat"
const TRAVEL_FATIGUE_ID := "travel_fatigue"
const TRAVEL_FATIGUE_NAME := "旅途疲惫"
const HOME_CITY := "city_migurd"
const LEGACY_REGIONS: Dictionary[String, String] = {HOME_CITY: "migurd_village", "city_rikarisu": "rikarisu_gate"}

var current_location_id := "migurd_village"
var current_city_id: String = HOME_CITY
var current_transport := "foot"
var currency_copper := 45
var local_currency_text := ""

var _world_time: Dictionary[String, int] = {"year": 418, "month": 1, "day": 1, "slot": 0}
var catalog: Catalog
var _character: Dictionary = {}
var _state_extras: Dictionary = {}
var _calendar_extras: Dictionary = {}
var _chronicle: Array[Dictionary] = []

var profile: Dictionary:
	get: return _character["profile"]
var traits: Array[String]:
	get: return _character["traits"]
var stats: Dictionary:
	get: return _character["stats"]
var resources: Dictionary:
	get: return _character["resources"]
var proficiencies: Dictionary:
	get: return _character["proficiencies"]
var equipment: Dictionary:
	get: return _character["equipment"]
var relations: Dictionary:
	get: return _character["relations"]
var combat_profile: Dictionary:
	get: return _character["combat_profile"]
var extra_data: Dictionary:
	get: return _character["extra_data"]
var STAT_NAMES: Dictionary:
	get: return catalog.definitions.get("stats", {}).duplicate()
var _buffs: Dictionary[String, Dictionary] = {}
var _inventory: Dictionary[String, Dictionary] = {}
var _flags: Dictionary[String, Variant] = {}
var _performed: Dictionary[String, bool] = {}
var _city_journey: Dictionary[String, Variant] = {}


func _ready() -> void:
	catalog = Catalog.new(read_config)
	reset_new_game()


static func read_config(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("无法读取配置 " + path)
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("无效的 JSON 配置 %s（第 %d 行）" % [path, json.get_error_line()])
		return {}
	return json.data


func get_world_time() -> Dictionary[String, int]:
	return _world_time.duplicate()


func date_text() -> String:
	return "甲龙历 %d 年 %d 月 %d 日   %s" % [
		_world_time["year"], _world_time["month"], _world_time["day"], SLOTS[_world_time["slot"]]
	]


func advance_time(slots: int) -> void:
	if slots <= 0:
		return
	_shift_time(slots)
	world_time_changed.emit()


func advance_days(days: int) -> void:
	advance_time(days * SLOTS.size())


func month_after_days(calendar: Dictionary[String, int], days: int) -> int:
	@warning_ignore("integer_division")
	var passed_months := (calendar["day"] - 1 + days) / DAYS_PER_MONTH
	return posmod(calendar["month"] - 1 + passed_months, MONTHS_PER_YEAR) + 1


func is_milis_rainy_season(month: int = 0) -> bool:
	var active_month := _world_time["month"] if month == 0 else month
	return active_month >= 6 and active_month <= 8


func is_northern_winter(month: int = 0) -> bool:
	var active_month := _world_time["month"] if month == 0 else month
	return active_month >= 11 or active_month <= 2


func format_currency(copper: int) -> String:
	@warning_ignore("integer_division")
	var gold := absi(copper) / 10000
	@warning_ignore("integer_division")
	var silver := absi(copper) / 100 % 100
	var remainder := absi(copper) % 100
	var parts := PackedStringArray()
	if gold > 0:
		parts.append("%d 金" % gold)
	if silver > 0:
		parts.append("%d 银" % silver)
	if remainder > 0 or parts.is_empty():
		parts.append("%d 铜" % remainder)
	return ("−" if copper < 0 else "") + " ".join(parts)


func get_currency_display_text() -> String:
	return local_currency_text if not local_currency_text.is_empty() else format_currency(currency_copper)


func sync_economy_display(copper_equiv: int, formatted_text: String) -> void:
	var next_copper := maxi(0, copper_equiv)
	var copper_dirty := next_copper != currency_copper
	var text_dirty := formatted_text != local_currency_text
	currency_copper = next_copper
	local_currency_text = formatted_text
	if copper_dirty:
		currency_changed.emit(currency_copper)
	if text_dirty:
		currency_display_changed.emit(get_currency_display_text())
	if copper_dirty or text_dirty:
		state_changed.emit()


func restore_vitals(hp_delta: int, mp_delta: int, full_restore: bool = false) -> void:
	var max_hp := int(resources.get("max_hp", 0))
	var max_mp := int(resources.get("max_mp", 0))
	var next_hp := max_hp if full_restore else clampi(int(resources.get("hp", 0)) + maxi(0, hp_delta), 0, max_hp)
	var next_mp := max_mp if full_restore else clampi(int(resources.get("mp", 0)) + maxi(0, mp_delta), 0, max_mp)
	if next_hp != int(resources.get("hp", 0)) or next_mp != int(resources.get("mp", 0)):
		resources["hp"] = next_hp
		resources["mp"] = next_mp
		protagonist_changed.emit()
		state_changed.emit()


func can_afford(copper: int) -> bool:
	return copper >= 0 and copper <= currency_copper - int(_city_journey.get("fare", 0))


func spend_currency(copper: int) -> bool:
	if not can_afford(copper):
		return false
	add_currency(-copper)
	return true


func add_currency(copper: int) -> void:
	var next := maxi(int(_city_journey.get("fare", 0)), currency_copper + copper)
	if next != currency_copper:
		currency_copper = next
		currency_changed.emit(currency_copper)
		state_changed.emit()


func _shift_time(slots: int) -> void:
	@warning_ignore("integer_division")
	var days := slots / SLOTS.size()
	var slot := _world_time["slot"] + slots % SLOTS.size()
	@warning_ignore("integer_division")
	days += slot / SLOTS.size()
	_world_time["slot"] = slot % SLOTS.size()
	days += _world_time["day"] - 1
	@warning_ignore("integer_division")
	var months := _world_time["month"] - 1 + days / DAYS_PER_MONTH
	_world_time["day"] = days % DAYS_PER_MONTH + 1
	_world_time["month"] = months % MONTHS_PER_YEAR + 1
	@warning_ignore("integer_division")
	_world_time["year"] += months / MONTHS_PER_YEAR


func reset_new_game(character_id: String = "") -> bool:
	var id := catalog.default_character if character_id.is_empty() else character_id
	var preset: Dictionary = catalog.presets.get(id, {})
	if preset.is_empty() or bool(preset.get("locked", false)):
		return false
	deserialize_state({"character": {"profile": {"character_id": id}}})
	return true


func serialize_state() -> Dictionary:
	var result := _state_extras.duplicate(true)
	result.merge({
		"character": _character.duplicate(true),
		"world_time": Catalog.merge(_calendar_extras, _world_time),
		"current_city_id": current_city_id, "current_location_id": current_location_id,
		"current_transport": current_transport,
		"currency_copper": currency_copper,
		"inventory": _inventory.duplicate(true), "buffs": _buffs.duplicate(true),
		"flags": _flags.duplicate(true), "performed": _performed.duplicate(true),
		"chronicle": _chronicle.duplicate(true)
	}, true)
	return result


func deserialize_state(payload: Dictionary) -> bool:
	if not payload is Dictionary:
		return false
	var actor: Dictionary = payload.get("character", {}) if payload.get("character") is Dictionary else {}
	if actor.is_empty() and payload.get("protagonist") is Dictionary:
		actor = _import_legacy_actor(payload["protagonist"])
	var identity: Dictionary = actor.get("profile", {}) if actor.get("profile") is Dictionary else {}
	var id := str(identity.get("character_id", catalog.default_character))
	var preset: Dictionary = catalog.presets.get(id, {})
	if not preset.get("character") is Dictionary:
		preset = catalog.presets.get(catalog.default_character, {})
	if not preset.get("character") is Dictionary:
		return false
	_character = Catalog.merge(preset["character"], actor)
	for container: String in ["profile", "stats", "resources", "proficiencies", "equipment", "relations", "combat_profile", "extra_data"]:
		if not _character.get(container) is Dictionary:
			_character[container] = {}
	var race_id := str(profile.get("race_id", ""))
	if str(profile.get("race_name", "")).is_empty() and not race_id.is_empty():
		var race_entry: Dictionary = catalog.races.get(race_id, {})
		profile["race_name"] = str(race_entry.get("label", race_id))
	var normalized_tags: Array[String] = []
	for tag: Variant in _character.get("traits", []):
		if tag is String:
			normalized_tags.append(tag)
	_character["traits"] = normalized_tags
	for key: String in stats:
		var fallback: Variant = preset["character"]["stats"].get(key)
		if fallback is int or fallback is float or stats[key] is int or stats[key] is float:
			stats[key] = Catalog.integer(stats[key], Catalog.integer(fallback, 10))
	for key: String in ["hp", "max_hp", "mp", "max_mp"]:
		resources[key] = Catalog.integer(resources[key], Catalog.integer(preset["character"]["resources"][key]))
	var preset_start: Dictionary = preset.get("start", {})
	var date: Dictionary = _dictionary(payload.get("world_time", {}))
	_calendar_extras = date.duplicate(true)
	for part: String in _world_time:
		_world_time[part] = Catalog.integer(date.get(part), Catalog.integer(preset_start.get(part, 0)))
		_calendar_extras.erase(part)
	_world_time["month"] = clampi(_world_time["month"], 1, MONTHS_PER_YEAR)
	_world_time["day"] = clampi(_world_time["day"], 1, DAYS_PER_MONTH)
	_world_time["slot"] = clampi(_world_time["slot"], 0, SLOTS.size() - 1)
	current_location_id = str(payload.get("current_location_id", preset_start.get("legacy_location", "")))
	var fallback_city := str(LEGACY_REGIONS.find_key(current_location_id)) if LEGACY_REGIONS.values().has(current_location_id) else str(preset_start.get("city_id", ""))
	current_city_id = str(payload.get("current_city_id", fallback_city))
	if not catalog.city_names.has(current_city_id):
		current_city_id = fallback_city
	if not payload.has("current_location_id"):
		current_location_id = LEGACY_REGIONS.get(current_city_id, current_city_id)
	var raw_transport := str(payload.get("current_transport", preset_start.get("transport", "foot")))
	current_transport = raw_transport if raw_transport in VALID_TRANSPORTS else "foot"
	currency_copper = maxi(0, Catalog.integer(payload.get("currency_copper"), Catalog.integer(preset_start.get("currency_copper", 0))))
	local_currency_text = ""
	_inventory = _record_dictionary(_dictionary(payload.get("inventory", preset.get("inventory", {}))))
	_buffs = _record_dictionary(_dictionary(payload.get("buffs", {})))
	_flags.clear()
	_flags.assign(_dictionary(payload.get("flags", {})).duplicate(true))
	_performed.clear()
	for key: String in _dictionary(payload.get("performed", {})):
		_performed[key] = bool(payload["performed"][key])
	_chronicle.clear()
	if payload.get("chronicle") is Array:
		for observation: Variant in payload["chronicle"]:
			if observation is Dictionary:
				_chronicle.append(observation.duplicate(true))
	_city_journey.clear()
	_state_extras = payload.duplicate(true)
	for key: String in serialize_state_keys():
		_state_extras.erase(key)
	_state_extras.erase("protagonist")
	world_time_changed.emit()
	protagonist_changed.emit()
	buffs_changed.emit()
	inventory_changed.emit()
	flags_changed.emit()
	location_changed.emit(current_city_id)
	region_location_changed.emit(current_location_id)
	transport_changed.emit(current_transport)
	currency_changed.emit(currency_copper)
	state_changed.emit()
	return true


func serialize_state_keys() -> PackedStringArray:
	return ["character", "world_time", "current_city_id", "current_location_id", "current_transport",
		"currency_copper", "inventory", "buffs", "flags", "performed", "chronicle"]


func set_current_transport(mode: String) -> bool:
	if mode not in VALID_TRANSPORTS:
		return false
	if current_transport == mode:
		return true
	current_transport = mode
	transport_changed.emit(current_transport)
	state_changed.emit()
	return true


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _record_dictionary(raw: Dictionary) -> Dictionary[String, Dictionary]:
	var result: Dictionary[String, Dictionary] = {}
	for key: String in raw:
		if raw[key] is Dictionary:
			result[key] = raw[key].duplicate(true)
	return result


func _import_legacy_actor(legacy: Dictionary) -> Dictionary:
	var identity: Dictionary = {}
	var meters: Dictionary = {}
	var result := legacy.duplicate(true)
	for key: String in ["id", "name", "birth_year", "portrait"]:
		if legacy.has(key):
			identity["character_id" if key == "id" else key] = legacy[key]
			result.erase(key)
	for meter: String in ["hp", "mp"]:
		var pool := _dictionary(legacy.get(meter))
		if not pool.is_empty():
			meters[meter] = Catalog.integer(pool.get("current", 0))
			meters["max_" + meter] = Catalog.integer(pool.get("max", 0))
			result.erase(meter)
	result["profile"] = identity
	result["resources"] = meters
	if legacy.get("traits") is Array:
		var tags: Array[String] = []
		var old_skills: Dictionary = {}
		var skill_labels: Dictionary = catalog.definitions.get("groups", {}).get("skills", {}).get("items", {})
		for entry: Variant in legacy["traits"]:
			if entry is String:
				tags.append(entry)
			elif entry is Dictionary and entry.has("skill"):
				var label := str(entry["skill"])
				var key: Variant = skill_labels.find_key(label)
				old_skills[label if key == null else str(key)] = int(entry.get("modifier", 0))
		if not tags.is_empty():
			result["traits"] = tags
		else:
			result.erase("traits")
		result["proficiencies"] = {"skills": old_skills}
	return result


func age() -> int:
	return maxi(0, _world_time["year"] - int(profile.get("birth_year", _world_time["year"])))


func award_resource_growth(growth_id: String, amount: int) -> int:
	var rule: Dictionary = catalog.definitions.get("resource_growth", {}).get(growth_id, {})
	if rule.is_empty() or amount <= 0 or age() > int(rule.get("max_age", 999)):
		return 0
	var tags := actor_tags()
	for required: String in rule.get("actor_tags_all", []):
		if not tags.has(required):
			return 0
	var experience := str(rule["experience"])
	var capacity := str(rule["capacity"])
	var threshold := maxi(1, int(rule["threshold"]))
	var earned := int(resources.get(experience, 0)) + amount
	@warning_ignore("integer_division")
	var growth := earned / threshold
	resources[experience] = earned % threshold
	resources[capacity] = int(resources.get(capacity, 0)) + growth
	protagonist_changed.emit()
	state_changed.emit()
	return growth


func stat_label(key: String) -> String:
	return str(catalog.definitions.get("stats", {}).get(key, key))


func city_label() -> String:
	return catalog.city_names.get(current_city_id, current_city_id)


func race_label() -> String:
	var explicit := str(profile.get("race_name", "")).strip_edges()
	if not explicit.is_empty():
		return explicit
	var race_id := str(profile.get("race_id", ""))
	var race: Dictionary = catalog.races.get(race_id, {})
	return str(race.get("label", race_id))


func chapter_hint() -> String:
	if current_city_id != HOME_CITY:
		return "旅途 · " + city_label()
	if bool(_flags.get("village_gate_completed", false)):
		return "雾中来客 · 聚落余波"
	if bool(_flags.get("survival_418_won", false)):
		return "荒野初试 · 归返木屋"
	return "序章 · " + city_label()


func status_polarity(buff: Dictionary) -> int:
	var declared := str(buff.get("polarity", "")).to_lower()
	if declared == "positive":
		return 1
	if declared == "negative":
		return -1
	var tags: Variant = buff.get("tags", [])
	if tags is Array or tags is PackedStringArray:
		for tag: Variant in tags:
			var text := str(tag)
			if text.begins_with("condition:fatigued") or text.begins_with("debuff:"):
				return -1
	var net := 0
	for group: String in ["stat_bonus", "check_bonus"]:
		var map := _dictionary(buff.get(group))
		for val: Variant in map.values():
			net += Catalog.integer(val)
	if net < 0:
		return -1
	return 1


func actor_tags() -> Array[String]:
	var result: Array[String] = []
	result.assign(traits)
	var race: Dictionary = catalog.races.get(str(profile.get("race_id", "")), {})
	for tag: String in race.get("tags", []):
		if not result.has(tag):
			result.append(tag)
	return result


func active_equipment() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: String in equipment:
		var item_id := str(equipment[slot])
		var item: Dictionary = catalog.items.get(item_id, {})
		if catalog.slots.has(slot) and str(item.get("slot", "")) == slot and get_item_count(item_id) > 0:
			result.append(item.duplicate(true))
	return result


func equip_item(slot_id: String, item_id: String) -> bool:
	if not catalog.slots.has(slot_id):
		return false
	if item_id.is_empty():
		equipment.erase(slot_id)
	else:
		var item: Dictionary = catalog.items.get(item_id, {})
		if str(item.get("slot", "")) != slot_id or get_item_count(item_id) < 1:
			return false
		equipment[slot_id] = item_id
	protagonist_changed.emit()
	state_changed.emit()
	return true


func inventory_entries() -> Dictionary[String, Dictionary]:
	return _inventory.duplicate(true)


func active_statuses() -> Array[Dictionary]:
	return _buffs.values()


func flag_facts() -> Dictionary[String, Variant]:
	return _flags.duplicate(true)


func record_chronicle(title: String, description: String = "") -> void:
	var entry := {"title": title, "text": description, "date": date_text(), "city_id": current_city_id}
	_chronicle.append(entry)
	chronicle_recorded.emit(entry.duplicate(true))


func get_chronicle() -> Array[Dictionary]:
	return _chronicle.duplicate(true)


func is_journey_active() -> bool:
	return not _city_journey.is_empty()


func get_protagonist() -> Dictionary:
	var result := profile.duplicate(true)
	result["id"] = str(profile.get("character_id", ""))
	result["age"] = age()
	result["stats"] = stats.duplicate(true)
	for meter: String in ["hp", "mp"]:
		result[meter] = {"current": int(resources.get(meter, 0)), "max": int(resources.get("max_" + meter, 0))}
	var legacy_traits: Array[Dictionary] = []
	var groups: Dictionary = catalog.definitions.get("groups", {})
	for key: String in proficiencies:
		var definition: Dictionary = groups.get(key, {})
		if not bool(definition.get("legacy_check_bonus", false)):
			continue
		for skill: String in _dictionary(proficiencies[key]):
			var label := str(definition.get("items", {}).get(skill, skill))
			legacy_traits.append({"id": skill, "name": label, "skill": label, "modifier": int(proficiencies[key][skill])})
	result["traits"] = legacy_traits
	var languages: PackedStringArray = []
	var tongues: Dictionary = proficiencies.get("languages", {})
	for key: String in tongues:
		if int(tongues[key]) > 0:
			languages.append(str(groups.get("languages", {}).get("items", {}).get(key, key)))
	result["languages"] = Array(languages)
	return result


func get_buff_names() -> PackedStringArray:
	var names := PackedStringArray()
	for id: String in _buffs:
		names.append(str(_buffs[id].get("name", id)))
	return names


func has_buff(buff_id: String) -> bool:
	return _buffs.has(buff_id)


func get_inventory_count() -> int:
	var count := 0
	for item: Dictionary in _inventory.values():
		count += maxi(0, Catalog.integer(item.get("count"), 1))
	return count


func get_inventory_item_count(id: String) -> int:
	var entry: Dictionary = _inventory.get(id, {})
	return maxi(0, Catalog.integer(entry.get("count"), 1)) if _inventory.has(id) else 0


func get_item_count(item_id: String) -> int:
	return get_inventory_item_count(item_id)


func get_total_rations() -> int:
	var total := 0
	for id: String in _inventory:
		if _is_ration(id):
			total += get_item_count(id)
	return total


func consume_rations(amount: int) -> int:
	var used := _take_rations(amount)
	if used > 0:
		inventory_changed.emit()
		state_changed.emit()
	return used


func _is_ration(id: String) -> bool:
	return _inventory.has(id) and (id == RATION_ID or str(_inventory[id].get("tag", "")) == "ration")


func is_ration_item(id: String) -> bool:
	return _is_ration(id)


func eat_ration(item_id: String = "") -> bool:
	var consumed := false
	if item_id.is_empty():
		consumed = consume_rations(1) == 1
	elif _is_ration(item_id):
		consumed = consume_item(item_id, 1)
	if not consumed:
		return false
	if has_buff(TRAVEL_FATIGUE_ID):
		remove_buff(TRAVEL_FATIGUE_ID)
	var hp_now := int(resources.get("hp", 0))
	var hp_max := int(resources.get("max_hp", hp_now))
	if hp_now < hp_max:
		resources["hp"] = mini(hp_max, hp_now + 6)
		protagonist_changed.emit()
		state_changed.emit()
	return true


func _take_rations(amount: int) -> int:
	var remaining := maxi(0, amount)
	for id: String in _inventory.keys():
		if remaining == 0:
			break
		if not _is_ration(id):
			continue
		var count := get_item_count(id)
		var take := mini(remaining, count)
		if take == count:
			_inventory.erase(id)
		else:
			_inventory[id]["count"] = count - take
		remaining -= take
	return maxi(0, amount) - remaining


func consume_item(item_id: String, amount: int = 1) -> bool:
	if amount <= 0 or get_inventory_item_count(item_id) < amount:
		return false
	var remaining := get_inventory_item_count(item_id) - amount
	if remaining <= 0:
		_inventory.erase(item_id)
	else:
		_inventory[item_id]["count"] = remaining
	inventory_changed.emit()
	state_changed.emit()
	return true


func remove_buff(buff_id: String) -> void:
	if not _buffs.has(buff_id):
		return
	_buffs.erase(buff_id)
	buffs_changed.emit()
	protagonist_changed.emit()
	state_changed.emit()


func restore_mp(amount: int) -> void:
	if amount <= 0:
		return
	resources["mp"] = clampi(int(resources["mp"]) + amount, 0, int(resources["max_mp"]))
	protagonist_changed.emit()
	state_changed.emit()


func apply_travel_fatigue() -> void:
	var status: Dictionary = catalog.statuses.get(TRAVEL_FATIGUE_ID, {})
	add_buff(TRAVEL_FATIGUE_ID, TRAVEL_FATIGUE_NAME, {}, status.get("check_bonus", {}), status)


func begin_city_travel(to_city_id: String, days: int, rations: int, fare: int) -> bool:
	if not _city_journey.is_empty() or to_city_id.is_empty() or to_city_id == current_city_id:
		return false
	if days < 1 or rations < 0 or not can_afford(fare):
		return false
	_city_journey = {"destination": to_city_id, "days": days, "elapsed": 0, "rations": rations, "fare": fare}
	return true


func advance_city_travel(elapsed_days: int) -> void:
	if _city_journey.is_empty():
		return
	var elapsed := int(_city_journey["elapsed"])
	var next := clampi(elapsed_days, elapsed, int(_city_journey["days"]))
	_city_journey["elapsed"] = next
	advance_days(next - elapsed)


func finish_city_travel() -> Dictionary[String, Variant]:
	return finish_city_travel_at("")


func finish_city_travel_at(override_city_id: String, actual_days: int = -1, actual_rations: int = -1, actual_fare: int = -1) -> Dictionary[String, Variant]:
	if _city_journey.is_empty():
		return {}
	var journey := _city_journey
	_city_journey = {}
	var settled_days := int(journey["days"]) if actual_days < 0 else maxi(int(journey["elapsed"]), actual_days)
	var remaining := maxi(0, settled_days - int(journey["elapsed"]))
	if remaining > 0:
		_shift_time(remaining * SLOTS.size())
	var fare := int(journey["fare"]) if actual_fare < 0 else clampi(actual_fare, 0, currency_copper)
	currency_copper = maxi(0, currency_copper - fare)
	var needed_rations := int(journey["rations"]) if actual_rations < 0 else maxi(0, actual_rations)
	var used := _take_rations(needed_rations)
	var fatigued := used < needed_rations
	var status: Dictionary = catalog.statuses.get(TRAVEL_FATIGUE_ID, {})
	var added_fatigue := fatigued and _store_buff(TRAVEL_FATIGUE_ID, TRAVEL_FATIGUE_NAME, {}, status.get("check_bonus", {}), status)
	var dest_city := str(journey["destination"]) if override_city_id.is_empty() or not catalog.city_names.has(override_city_id) else override_city_id
	var stopped_early := not override_city_id.is_empty() and dest_city != str(journey["destination"])
	current_city_id = dest_city
	current_location_id = LEGACY_REGIONS.get(current_city_id, current_city_id)
	if stopped_early:
		record_chronicle("驻停于%s" % city_label(), "行进途中暂歇于%s（耗时 %d 天）。" % [city_label(), settled_days])
	else:
		record_chronicle("抵达%s" % city_label(), "行进 %d 天后抵达。" % settled_days)
	if remaining > 0:
		world_time_changed.emit()
	if fare > 0:
		currency_changed.emit(currency_copper)
	if used > 0:
		inventory_changed.emit()
	if added_fatigue:
		buffs_changed.emit()
		protagonist_changed.emit()
	location_changed.emit(current_city_id)
	region_location_changed.emit(current_location_id)
	state_changed.emit()
	return {
		"city_id": current_city_id,
		"days": settled_days,
		"rations_consumed": used,
		"fatigue": fatigued,
		"fare": fare,
		"stopped_early": stopped_early
	}


func resolve_travel(to_region_id: String, time_cost: int, ration_cost: int, forced_without_rations: bool) -> Dictionary:
	var available := get_total_rations()
	var consumed := consume_rations(ration_cost)
	var fatigued := forced_without_rations or available < ration_cost
	if fatigued:
		apply_travel_fatigue()
	current_location_id = to_region_id
	if time_cost > 0:
		advance_time(time_cost)
	var city_id: String = LEGACY_REGIONS.find_key(to_region_id) if LEGACY_REGIONS.values().has(to_region_id) else ""
	if not city_id.is_empty() and current_city_id != city_id:
		current_city_id = city_id
		location_changed.emit(city_id)
	region_location_changed.emit(to_region_id)
	protagonist_changed.emit()
	state_changed.emit()
	return {
		"region": to_region_id,
		"time_cost": time_cost,
		"rations_consumed": consumed,
		"forced": forced_without_rations,
		"fatigue": fatigued,
		"rations_left": get_total_rations()
	}


func get_combat_snapshot() -> Dictionary:
	var checks := {}
	var actor := get_protagonist()
	var attributes: Dictionary = actor["stats"]
	for stat: String in attributes:
		checks[stat] = get_check_breakdown(stat)
	var counts := {}
	for id: String in _inventory:
		counts[id] = get_inventory_item_count(id)
	var skills := {}
	for trait_data: Dictionary in actor["traits"]:
		var skill := str(trait_data["skill"])
		skills[skill] = int(skills.get(skill, 0)) + int(trait_data["modifier"])
	return {
		"attributes": actor, "checks": checks, "items": counts,
		"trait_skills": skills, "buff_names": get_buff_names()
	}


func apply_combat_outcome(health: int, mana: int, consumed: Dictionary, flags: Dictionary) -> void:
	resources["hp"] = clampi(health, 0, int(resources["max_hp"]))
	resources["mp"] = clampi(mana, 0, int(resources["max_mp"]))
	for id: String in consumed:
		var remaining := get_inventory_item_count(id) - int(consumed[id])
		if remaining <= 0:
			_inventory.erase(id)
		elif _inventory.has(id):
			_inventory[id]["count"] = remaining
	for flag_id: String in flags:
		_flags[flag_id] = flags[flag_id]
	protagonist_changed.emit()
	if not consumed.is_empty():
		inventory_changed.emit()
	if not flags.is_empty():
		flags_changed.emit()


func get_flag(id: String, default_value: Variant = null) -> Variant:
	return _flags.get(id, default_value)


func get_stat_modifier(stat: String) -> int:
	return int(get_check_breakdown(stat)["base_mod"])


func modify_stat(stat_key: String, delta: int, reason_text: String = "") -> void:
	if delta == 0:
		return
	if not stats.has(stat_key):
		return
	var new_value := int(stats[stat_key]) + delta
	stats[stat_key] = new_value
	var narrative := reason_text
	if narrative.is_empty():
		var stat_name: String = stat_label(stat_key)
		var who := str(profile.get("name", "角色"))
		narrative = "%s的%s%s了" % [who, stat_name, "提升" if delta > 0 else "下降"]
	protagonist_changed.emit()
	state_changed.emit()
	stat_changed.emit(stat_key, delta, new_value, narrative)


func get_check_breakdown(stat_name: String) -> Dictionary[String, Variant]:
	var base := Catalog.integer(stats.get(stat_name), 10)
	var effective := base
	var check_bonus := 0
	var bonus_list: Array[Dictionary] = []
	for id: String in _buffs:
		var buff := _buffs[id]
		var stat_bonuses := _dictionary(buff.get("stat_bonus"))
		var check_bonuses := _dictionary(buff.get("check_bonus"))
		effective += Catalog.integer(stat_bonuses.get(stat_name))
		var bonus := Catalog.integer(check_bonuses.get(stat_name))
		if bonus != 0:
			bonus_list.append({
				"id": id, "name": str(buff.get("name", id)), "label": str(buff.get("name", id)),
				"category": str(buff.get("category", "")), "value": bonus,
				"tags": buff.get("tags", []), "suppressible_by": buff.get("suppressible_by", [])
			})
			check_bonus += bonus
	var base_mod := floori((effective - 10) / 2.0)
	var result: Dictionary[String, Variant] = {
		"base_stat": base,
		"effective_stat": effective,
		"base_mod": base_mod,
		"bonus_list": bonus_list,
		"total_mod": base_mod + check_bonus
	}
	return result


func add_buff(id: String, label: String, stat_bonus: Dictionary = {}, check_bonus: Dictionary = {}, details: Dictionary = {}) -> bool:
	if not _store_buff(id, label, stat_bonus, check_bonus, details):
		return false
	buffs_changed.emit()
	protagonist_changed.emit()
	state_changed.emit()
	return true


func _store_buff(id: String, label: String, stat_bonus: Dictionary, check_bonus: Dictionary, details: Dictionary = {}) -> bool:
	if id.is_empty() or _buffs.has(id):
		return false
	var buff: Dictionary = details.duplicate(true)
	buff.merge({"id": id, "name": label, "stat_bonus": stat_bonus.duplicate(true), "check_bonus": check_bonus.duplicate(true)}, true)
	_buffs[id] = buff
	return true


func add_item(id: String, label: String, count: int = 1, tag: String = "") -> bool:
	if not _store_item(id, label, count, tag):
		return false
	inventory_changed.emit()
	state_changed.emit()
	return true


func _store_item(id: String, label: String, count: int, tag: String = "") -> bool:
	if id.is_empty() or count <= 0:
		return false
	var item: Dictionary = _inventory.get(id, {"name": label})
	item["count"] = get_item_count(id) + count
	if not tag.is_empty():
		item["tag"] = tag
	_inventory[id] = item
	return true


func set_flag(id: String, value: Variant) -> void:
	var entry: Dictionary = catalog.definitions.get("chronicle_flags", {}).get(id, {})
	if not entry.is_empty() and bool(value) and not bool(_flags.get(id, false)):
		record_chronicle(str(entry.get("title", id)), str(entry.get("text", "")))
	_flags[id] = value
	flags_changed.emit()


func has_performed(action_id: String) -> bool:
	return _performed.has(action_id)


func perform(action_id: String, once: bool, effect: Dictionary, time_cost: int) -> bool:
	if action_id.is_empty() or time_cost < 0 or (once and has_performed(action_id)):
		return false
	var type := str(effect.get("type", ""))
	var id := str(effect.get("id", ""))
	var label := str(effect.get("name", ""))
	match type:
		"buff":
			var stat_bonus: Variant = effect.get("stat_bonus", effect.get("stats", {}))
			var check_bonus: Variant = effect.get("check_bonus", {})
			if not stat_bonus is Dictionary or not check_bonus is Dictionary:
				return false
			if not _store_buff(id, label, stat_bonus, check_bonus, effect):
				return false
		"item":
			if not _store_item(id, label, int(effect.get("count", 1)), str(effect.get("tag", ""))):
				return false
		"counter":
			var amount := int(effect.get("amount", 0))
			if id.is_empty() or amount <= 0:
				return false
			_flags[id] = int(_flags.get(id, 0)) + amount
		"observe":
			pass
		_:
			return false

	if once:
		_performed[action_id] = true
	if time_cost > 0:
		_shift_time(time_cost)

	# Publish only after every part of the action has been applied.
	match type:
		"buff":
			buffs_changed.emit()
			protagonist_changed.emit()
		"item":
			inventory_changed.emit()
		"counter":
			flags_changed.emit()
	if time_cost > 0:
		world_time_changed.emit()
	return true



