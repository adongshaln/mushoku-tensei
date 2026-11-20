extends RefCounted

const PATH := "res://data/rules/"

var presets: Dictionary
var default_character: String
var races: Dictionary
var definitions: Dictionary
var slots: Dictionary
var items: Dictionary
var statuses: Dictionary
var city_names: Dictionary[String, String] = {}


func _init(read: Callable) -> void:
	var characters: Dictionary = read.call(PATH + "character_presets.json")
	presets = characters.get("presets", {})
	default_character = str(characters.get("default_character", ""))
	races = read.call(PATH + "races.json").get("races", {})
	definitions = read.call(PATH + "rank_definitions.json")
	slots = read.call(PATH + "equipment_slots.json").get("slots", {})
	items = read.call(PATH + "equipment_items.json").get("items", {})
	statuses = read.call(PATH + "context_rules.json").get("statuses", {})
	var map: Dictionary = read.call("res://data/maps/world_map_data.json")
	for continent: Dictionary in map.get("continents", []):
		for region: Dictionary in continent.get("regions", []):
			for city: Dictionary in region.get("cities", []):
				_register_city(city)
				for site: Dictionary in city.get("sites", []):
					_register_city(site)


func _register_city(city: Dictionary) -> void:
	city_names[str(city["node"])] = str(city["name"])


static func merge(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	for key: Variant in overrides:
		var value: Variant = overrides[key]
		if result.get(key) is Dictionary:
			if value is Dictionary:
				result[key] = merge(result[key], value)
		elif result.get(key) is Array and not value is Array:
			continue
		elif result.get(key) is int:
			result[key] = integer(value, result[key])
		elif result.get(key) is String and not value is String:
			continue
		else:
			result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result


static func integer(value: Variant, fallback: int = 0) -> int:
	if value is int or value is float:
		return int(value)
	if value is String and value.is_valid_int():
		return int(value)
	return fallback
