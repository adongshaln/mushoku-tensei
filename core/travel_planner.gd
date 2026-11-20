extends RefCounted

const ROUTE_PATH := "res://data/maps/world_routes.json"
const FOOT := "foot"
const CARAVAN := "caravan"
const SHIP := "ship"
const STEADY := "steady"
const FORCED := "forced_march"
const STEALTH := "stealth"

const LAND_SPEED: Dictionary[String, float] = {FOOT: 30.0, CARAVAN: 55.0}
const POSTURE_SPEED: Dictionary[String, float] = {STEADY: 1.0, FORCED: 1.3, STEALTH: 0.75}
const CARAVAN_KM_PER_COPPER := 10.0


class Leg extends RefCounted:
	var from_city: String
	var to_city: String
	var km: int
	var mode: String
	var days: float
	var via: Array[Vector2] = []


class Itinerary extends RefCounted:
	var path_cities: Array[String] = []
	var legs: Array[Leg] = []
	var total_km := 0
	var total_days := 0
	var ration_cost := 0
	var fare := 0
	var ship_fare := 0
	var caravan_fare := 0
	var warnings: Array[String] = []


var _cities: Dictionary[String, Dictionary] = {}
var _adjacent: Dictionary[String, Array] = {}


func configure(atlas: Dictionary) -> void:
	_cities.clear()
	_adjacent.clear()
	for continent: Dictionary in atlas["continents"]:
		for region: Dictionary in continent["regions"]:
			for city: Dictionary in region["cities"]:
				_register_city(city)
				for site: Dictionary in city.get("sites", []):
					_register_city(site)
	var routes := WorldBlackboard.read_config(ROUTE_PATH)
	for route: Dictionary in routes.get("routes", []):
		var from_city := str(route["from"])
		var to_city := str(route["to"])
		if not _cities.has(from_city) or not _cities.has(to_city):
			push_error("路线使用了舆图上不存在的城池 %s / %s" % [from_city, to_city])
			continue
		_adjacent[from_city].append(route)
		_adjacent[to_city].append(route)


func city_name(city_id: String) -> String:
	return str(_cities.get(city_id, {}).get("name", city_id))


func _register_city(city: Dictionary) -> void:
	var city_id := str(city["node"])
	_cities[city_id] = city
	var connections: Array[Dictionary] = []
	_adjacent[city_id] = connections


func plan(from_city: String, to_city: String, transport: String, posture: String,
		calendar: Dictionary[String, int]) -> Itinerary:
	if from_city == to_city or not _cities.has(from_city) or not _cities.has(to_city):
		return null
	if not LAND_SPEED.has(transport) or not POSTURE_SPEED.has(posture):
		return null
	var costs: Dictionary[String, int] = {from_city: 0}
	var paths: Dictionary[String, Dictionary] = {}
	var remaining: Array[String] = [from_city]
	while not remaining.is_empty():
		var city := remaining[0]
		for candidate: String in remaining:
			if costs[candidate] < costs[city]:
				city = candidate
		if city == to_city:
			return _estimate(from_city, to_city, paths, transport, posture, calendar)
		remaining.erase(city)
		for route: Dictionary in _adjacent[city]:
			var peer := _neighbor(route, city)
			var cost := costs[city] + int(route["km"])
			if cost >= costs.get(peer, 0x7fffffff):
				continue
			costs[peer] = cost
			paths[peer] = route
			if not remaining.has(peer):
				remaining.append(peer)
	return null


func _neighbor(route: Dictionary, city: String) -> String:
	return str(route["to"]) if city == str(route["from"]) else str(route["from"])


func _estimate(from_city: String, to_city: String, paths: Dictionary[String, Dictionary],
		transport: String, posture: String, calendar: Dictionary[String, int]) -> Itinerary:
	var itinerary := Itinerary.new()
	var city := to_city
	itinerary.path_cities.append(city)
	while city != from_city:
		city = _neighbor(paths[city], city)
		itinerary.path_cities.push_front(city)
	var elapsed := 0.0
	var provisions := 0.0
	var land_km := 0
	for index: int in range(1, itinerary.path_cities.size()):
		var leg := Leg.new()
		leg.from_city = itinerary.path_cities[index - 1]
		leg.to_city = itinerary.path_cities[index]
		var route := paths[leg.to_city]
		leg.km = int(route["km"])
		leg.mode = SHIP if str(route["mode"]) == SHIP else transport
		for point: Array in route.get("via", []):
			leg.via.append(Vector2(float(point[0]), float(point[1])))
		if leg.from_city != str(route["from"]):
			leg.via.reverse()
		if leg.mode == SHIP:
			leg.days = leg.km / 120.0
			itinerary.ship_fare += int(route["fare_copper"])
		else:
			land_km += leg.km
			leg.days = _land_days(route, elapsed, LAND_SPEED[transport] * POSTURE_SPEED[posture], calendar, itinerary.warnings)
		var daily_rations := 0.75 if leg.mode == CARAVAN else 1.0
		if leg.mode != SHIP and posture == FORCED:
			daily_rations *= 1.25
		provisions += leg.days * daily_rations
		elapsed += leg.days
		itinerary.total_km += leg.km
		itinerary.legs.append(leg)
	if transport == CARAVAN:
		itinerary.caravan_fare = ceili(land_km / CARAVAN_KM_PER_COPPER)
	itinerary.fare = itinerary.ship_fare + itinerary.caravan_fare
	# Round the whole itinerary once so transfer legs do not each add a day.
	itinerary.total_days = maxi(1, roundi(elapsed))
	itinerary.ration_cost = ceili(itinerary.total_days * provisions / elapsed - 0.000001)
	return itinerary


func _land_days(route: Dictionary, elapsed: float, speed: float,
		calendar: Dictionary[String, int], warnings: Array[String]) -> float:
	var km := float(route["km"])
	var base_factor := float(route["terrain_factor"])
	var season := str(route.get("season", ""))
	if season.is_empty():
		return km / (speed * base_factor)
	var days := 0.0
	while km > 0.00001:
		var cursor := elapsed + days
		var day := floori(cursor + 0.00000001)
		var month := WorldBlackboard.month_after_days(calendar, day)
		var rainy := season == "milis_rain" and WorldBlackboard.is_milis_rainy_season(month)
		var snowy := season == "northern_winter" and WorldBlackboard.is_northern_winter(month)
		var factor := float(route["seasonal_factor"]) if rainy or snowy else base_factor
		var time := minf(day + 1.0 - cursor, km / (speed * factor))
		days += time
		km -= time * speed * factor
		if rainy or snowy:
			var message := "米里斯大森林雨季，道路泥泞" if rainy else "中央大陆北方雪季，山道减速"
			if not warnings.has(message):
				warnings.append(message)
	return days
