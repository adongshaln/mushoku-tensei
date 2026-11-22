extends RefCounted

const ROUTE_PATH := "res://data/maps/world_routes.json"
const FOOT := "foot"
const CARAVAN := "caravan"
const SHIP := "ship"
const TELEPORT := "teleport"
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
	var required_transport: String
	var stability_weight := 1.0
	var danger_tag := "safe_road"
	var season := ""
	var days: float
	var fare_copper := 0
	var is_actionable := true
	var via: Array[Vector2] = []


class Itinerary extends RefCounted:
	var path_cities: Array[String] = []
	var legs: Array[Leg] = []
	var actionable_cities: Array[String] = []
	var actionable_legs: Array[Leg] = []
	var preview_remaining_cities: Array[String] = []
	var preview_remaining_legs: Array[Leg] = []
	var manual_waypoints: Array[String] = []
	var is_manual := false
	var requires_hub_transfer := false
	var transfer_hub_id := ""
	var required_next_transport := ""
	var transfer_hint := ""
	var total_km := 0
	var total_days := 0
	var ration_cost := 0
	var fare := 0
	var ship_fare := 0
	var caravan_fare := 0
	var actionable_km := 0
	var actionable_days := 0
	var actionable_ration_cost := 0
	var actionable_fare := 0
	var actionable_ship_fare := 0
	var actionable_caravan_fare := 0
	var risk_level := "steady"
	var risk_label := "官道稳健"
	var risk_tags: Array[String] = []
	var warnings: Array[String] = []


var _cities: Dictionary[String, Dictionary] = {}
var _regions: Dictionary[String, Dictionary] = {}
var _city_region: Dictionary[String, String] = {}
var _city_continent: Dictionary[String, String] = {}
var _adjacent: Dictionary[String, Array] = {}


static func format_geo_hierarchy(continent: String, country: String, region: String, location: String) -> Dictionary:
	var c := continent.strip_edges()
	var k := country.strip_edges()
	var r := region.strip_edges()
	var l := location.strip_edges()
	var prefix: Array[String] = []
	for part: String in [c, k, r]:
		if not part.is_empty() and not prefix.has(part):
			prefix.append(part)
	var title := l if not l.is_empty() else (prefix.back() as String if not prefix.is_empty() else "")
	var eyebrow_parts: Array[String] = []
	for part: String in prefix:
		if part != title or prefix.size() == 1:
			eyebrow_parts.append(part)
	if eyebrow_parts.is_empty() and not prefix.is_empty():
		eyebrow_parts = prefix.duplicate()
	var all_parts: Array[String] = prefix.duplicate()
	if not title.is_empty() and not all_parts.has(title):
		all_parts.append(title)
	return {
		"eyebrow": " · ".join(PackedStringArray(eyebrow_parts)),
		"eyebrow_dash": " - ".join(PackedStringArray(eyebrow_parts)),
		"title": title,
		"full": " · ".join(PackedStringArray(all_parts)),
		"parts": all_parts
	}


static func transport_label(mode: String) -> String:
	match mode:
		CARAVAN:
			return "商队马车"
		SHIP:
			return "跨海客船"
		TELEPORT:
			return "转移魔法阵"
		_:
			return "徒步"


static func transport_verb(mode: String) -> String:
	match mode:
		CARAVAN:
			return "雇佣商队"
		SHIP:
			return "乘船"
		TELEPORT:
			return "启动转移"
		_:
			return "下船改走陆路"


static func danger_label(tag: String) -> String:
	match tag:
		"demon_wilds":
			return "魔物频发"
		"bandit_road":
			return "强盗出没"
		"border_check":
			return "城门盘查"
		"mountain_pass":
			return "险道缓行"
		"sea_lane":
			return "跨海航道"
		_:
			return "官道稳健"


func configure(atlas: Dictionary) -> void:
	_cities.clear()
	_regions.clear()
	_city_region.clear()
	_city_continent.clear()
	_adjacent.clear()
	for continent: Dictionary in atlas.get("continents", []):
		var cid := str(continent.get("id", ""))
		var cname := str(continent.get("name", ""))
		for region: Dictionary in continent.get("regions", []):
			var rid := str(region.get("id", ""))
			var rcopy := region.duplicate(true)
			if str(rcopy.get("continent_name", "")).is_empty():
				rcopy["continent_name"] = cname
			rcopy["continent_id"] = cid
			_regions[rid] = rcopy
			for city: Dictionary in region.get("cities", []):
				_register_city(city, cid, cname, rid, rcopy)
				for site: Dictionary in city.get("sites", []):
					_register_city(site, cid, cname, rid, rcopy)
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


func get_city_info(city_id: String) -> Dictionary:
	return _cities.get(city_id, {})


func get_region_info(region_id: String) -> Dictionary:
	return _regions.get(region_id, {})


func city_region_id(city_id: String) -> String:
	return _city_region.get(city_id, "")


func city_continent_id(city_id: String) -> String:
	return _city_continent.get(city_id, "")


func city_geo_formatted(city_id: String) -> Dictionary:
	var info := get_city_info(city_id)
	var geo := format_geo_hierarchy(
		str(info.get("continent_name", "")),
		str(info.get("country_name", "")),
		str(info.get("region_name", "")),
		str(info.get("location_name", info.get("name", city_id)))
	)
	geo["poetic_subtitle"] = str(info.get("poetic_subtitle", info.get("subtitle", "")))
	geo["city_id"] = city_id
	geo["region_id"] = city_region_id(city_id)
	return geo


func region_geo_formatted(region_id: String) -> Dictionary:
	var info := get_region_info(region_id)
	var geo := format_geo_hierarchy(
		str(info.get("continent_name", "")),
		str(info.get("country_name", "")),
		str(info.get("region_name", info.get("name", region_id))),
		str(info.get("location_name", info.get("name", region_id)))
	)
	geo["poetic_subtitle"] = str(info.get("poetic_subtitle", info.get("subtitle", "")))
	geo["region_id"] = region_id
	return geo


func get_hub_services(city_id: String) -> Dictionary:
	var info := get_city_info(city_id)
	var services: Variant = info.get("hub_services", {})
	if services is Dictionary and not services.is_empty():
		return services
	return {
		FOOT: {"enabled": true, "label": "徒步出行", "note": "轻装踏上旅途。"},
		CARAVAN: {"enabled": false, "label": "雇佣商队马车", "note": "此地暂无商队。"},
		SHIP: {"enabled": false, "label": "码头办理乘船", "note": "此地无海港码头。"},
		TELEPORT: {"enabled": false, "unlocked": false, "label": "古代转移魔法阵", "note": "尚未唤醒。"}
	}


func can_switch_transport_at(city_id: String, target_transport: String) -> Dictionary:
	if target_transport not in WorldBlackboard.VALID_TRANSPORTS:
		return {"ok": false, "reason": "未知的交通方式。", "service": {}}
	var services := get_hub_services(city_id)
	var entry: Dictionary = services.get(target_transport, {})
	if entry.is_empty():
		return {"ok": false, "reason": "此地不提供该出行方式。", "service": {}}
	if target_transport == TELEPORT and not bool(entry.get("unlocked", false)):
		return {"ok": false, "reason": str(entry.get("note", "古代转移魔法阵尚未开启。")), "service": entry}
	if not bool(entry.get("enabled", false)):
		return {"ok": false, "reason": str(entry.get("note", "当前地点无法办理此交通方式。")), "service": entry}
	return {"ok": true, "reason": str(entry.get("note", "")), "service": entry}


func request_hub_transport_switch(city_id: String, target_transport: String) -> Dictionary:
	if city_id != WorldBlackboard.current_city_id:
		return {"ok": false, "reason": "需先抵达【%s】才可在此办理交通换乘。" % city_name(city_id)}
	var check := can_switch_transport_at(city_id, target_transport)
	if not bool(check["ok"]):
		return check
	var changed := WorldBlackboard.set_current_transport(target_transport)
	return {
		"ok": changed,
		"transport": target_transport,
		"city_id": city_id,
		"reason": "已于%s切换为%s。" % [city_name(city_id), transport_label(target_transport)]
	}


func _register_city(city: Dictionary, cid: String, cname: String, rid: String, region: Dictionary) -> void:
	var city_id := str(city["node"])
	var copy := city.duplicate(true)
	if str(copy.get("continent_name", "")).is_empty():
		copy["continent_name"] = cname
	if not copy.has("country_name"):
		copy["country_name"] = str(region.get("country_name", ""))
	if str(copy.get("region_name", "")).is_empty():
		copy["region_name"] = str(region.get("region_name", region.get("name", "")))
	if str(copy.get("location_name", "")).is_empty():
		copy["location_name"] = str(copy.get("name", city_id))
	copy["continent_id"] = cid
	copy["region_id"] = rid
	_cities[city_id] = copy
	_city_region[city_id] = rid
	_city_continent[city_id] = cid
	var connections: Array[Dictionary] = []
	_adjacent[city_id] = connections


func plan(from_city: String, to_city: String, transport: String, posture: String,
		calendar: Dictionary[String, int]) -> Itinerary:
	if from_city == to_city or not _cities.has(from_city) or not _cities.has(to_city):
		return null
	if not POSTURE_SPEED.has(posture):
		return null
	var resolved_transport := transport if transport in WorldBlackboard.VALID_TRANSPORTS else FOOT
	var seg := _shortest_stable_segment(from_city, to_city, calendar)
	if seg.is_empty():
		return null
	var path_cities: Array[String] = seg["cities"]
	var route_edges: Array[Dictionary] = seg["edges"]
	return _build_itinerary(path_cities, route_edges, resolved_transport, posture, calendar, false, [])


func plan_manual_waypoints(from_city: String, waypoints: Array[String], transport: String, posture: String,
		calendar: Dictionary[String, int]) -> Itinerary:
	if waypoints.is_empty() or not _cities.has(from_city) or not POSTURE_SPEED.has(posture):
		return null
	var resolved_transport := transport if transport in WorldBlackboard.VALID_TRANSPORTS else FOOT
	var clean_waypoints: Array[String] = []
	var cursor := from_city
	var full_cities: Array[String] = [from_city]
	var full_edges: Array[Dictionary] = []
	for raw_wp: String in waypoints:
		if raw_wp.is_empty() or not _cities.has(raw_wp) or raw_wp == cursor:
			continue
		clean_waypoints.append(raw_wp)
		var direct := _find_direct_edge(cursor, raw_wp)
		if not direct.is_empty():
			full_edges.append(direct)
			full_cities.append(raw_wp)
		else:
			var seg := _shortest_stable_segment(cursor, raw_wp, calendar)
			if seg.is_empty():
				return null
			var seg_cities: Array[String] = seg["cities"]
			var seg_edges: Array[Dictionary] = seg["edges"]
			for i: int in range(1, seg_cities.size()):
				full_cities.append(seg_cities[i])
			for edge: Dictionary in seg_edges:
				full_edges.append(edge)
		cursor = raw_wp
	if full_edges.is_empty():
		return null
	return _build_itinerary(full_cities, full_edges, resolved_transport, posture, calendar, true, clean_waypoints)


func _find_direct_edge(a: String, b: String) -> Dictionary:
	for route: Dictionary in _adjacent.get(a, []):
		if _neighbor(route, a) == b:
			return route
	return {}


func _shortest_stable_segment(from_city: String, to_city: String, calendar: Dictionary[String, int]) -> Dictionary:
	var costs: Dictionary[String, float] = {from_city: 0.0}
	var paths: Dictionary[String, Dictionary] = {}
	var remaining: Array[String] = [from_city]
	while not remaining.is_empty():
		var city := remaining[0]
		for candidate: String in remaining:
			if costs[candidate] < costs[city]:
				city = candidate
		if city == to_city:
			var seg_cities: Array[String] = [to_city]
			var seg_edges: Array[Dictionary] = []
			var walk := to_city
			while walk != from_city:
				var edge := paths[walk]
				seg_edges.push_front(edge)
				walk = _neighbor(edge, walk)
				seg_cities.push_front(walk)
			return {"cities": seg_cities, "edges": seg_edges}
		remaining.erase(city)
		for route: Dictionary in _adjacent.get(city, []):
			var peer := _neighbor(route, city)
			var weight := _edge_stability_cost(route, calendar)
			var next_cost := costs[city] + weight
			if next_cost >= costs.get(peer, 1e18):
				continue
			costs[peer] = next_cost
			paths[peer] = route
			if not remaining.has(peer):
				remaining.append(peer)
	return {}


func _edge_stability_cost(route: Dictionary, calendar: Dictionary[String, int]) -> float:
	var km := float(route["km"])
	var stab := float(route.get("stability_weight", 1.0))
	var season_risk := 1.0
	var season := str(route.get("season", ""))
	if not season.is_empty():
		var month := int(calendar.get("month", 1))
		if (season == "milis_rain" and WorldBlackboard.is_milis_rainy_season(month)) or (
			season == "northern_winter" and WorldBlackboard.is_northern_winter(month)):
			season_risk = 1.35
	return km * stab * season_risk


func _neighbor(route: Dictionary, city: String) -> String:
	return str(route["to"]) if city == str(route["from"]) else str(route["from"])


func _transport_satisfies(current_mode: String, required: String) -> bool:
	match required:
		"land":
			return current_mode == FOOT or current_mode == CARAVAN
		SHIP:
			return current_mode == SHIP
		TELEPORT:
			return current_mode == TELEPORT
		_:
			return true


func _build_itinerary(path_cities: Array[String], route_edges: Array[Dictionary],
		transport: String, posture: String, calendar: Dictionary[String, int],
		is_manual: bool, manual_waypoints: Array[String]) -> Itinerary:
	var itinerary := Itinerary.new()
	itinerary.path_cities = path_cities.duplicate()
	itinerary.is_manual = is_manual
	itinerary.manual_waypoints = manual_waypoints.duplicate()

	var land_preview_transport := CARAVAN if transport == CARAVAN else FOOT
	var elapsed := 0.0
	var provisions := 0.0
	var land_km := 0
	var act_elapsed := 0.0
	var act_provisions := 0.0
	var act_land_km := 0
	var blocked_yet := false
	var max_stability := 0.0

	for index: int in route_edges.size():
		var route := route_edges[index]
		var leg := Leg.new()
		leg.from_city = path_cities[index]
		leg.to_city = path_cities[index + 1]
		leg.km = int(route["km"])
		leg.required_transport = str(route.get("required_transport", SHIP if str(route.get("mode", "")) == SHIP else "land"))
		leg.stability_weight = float(route.get("stability_weight", 1.0))
		leg.danger_tag = str(route.get("danger_tag", "sea_lane" if leg.required_transport == SHIP else "safe_road"))
		leg.season = str(route.get("season", ""))
		leg.fare_copper = int(route.get("fare_copper", 0))
		leg.mode = SHIP if leg.required_transport == SHIP else land_preview_transport
		for point: Array in route.get("via", []):
			leg.via.append(Vector2(float(point[0]), float(point[1])))
		if leg.from_city != str(route["from"]):
			leg.via.reverse()

		if not blocked_yet and not _transport_satisfies(transport, leg.required_transport):
			blocked_yet = true
			itinerary.requires_hub_transfer = true
			itinerary.transfer_hub_id = leg.from_city
			if leg.required_transport == SHIP:
				itinerary.required_next_transport = SHIP
			elif leg.required_transport == TELEPORT:
				itinerary.required_next_transport = TELEPORT
			else:
				itinerary.required_next_transport = FOOT
			if index == 0:
				itinerary.transfer_hint = "已在【%s】，请先办理%s手续再启程" % [
					city_name(leg.from_city), transport_verb(itinerary.required_next_transport)
				]
			else:
				itinerary.transfer_hint = "需先抵达%s，抵港后再办理%s手续" % [
					city_name(leg.from_city), transport_verb(itinerary.required_next_transport)
				]

		leg.is_actionable = not blocked_yet

		if leg.mode == SHIP:
			leg.days = leg.km / 120.0
			itinerary.ship_fare += leg.fare_copper
			if leg.is_actionable:
				itinerary.actionable_ship_fare += leg.fare_copper
		else:
			land_km += leg.km
			if leg.is_actionable:
				act_land_km += leg.km
			leg.days = _land_days(route, elapsed, LAND_SPEED[land_preview_transport] * POSTURE_SPEED[posture], calendar, itinerary.warnings)

		var daily_rations := 0.75 if leg.mode == CARAVAN else 1.0
		if leg.mode != SHIP and posture == FORCED:
			daily_rations *= 1.25
		var leg_rations := leg.days * daily_rations
		provisions += leg_rations
		elapsed += leg.days
		itinerary.total_km += leg.km
		itinerary.legs.append(leg)

		if leg.is_actionable:
			act_provisions += leg_rations
			act_elapsed += leg.days
			itinerary.actionable_km += leg.km
			itinerary.actionable_legs.append(leg)
		else:
			itinerary.preview_remaining_legs.append(leg)

		max_stability = maxf(max_stability, leg.stability_weight)
		_collect_risk_tags(leg, itinerary.risk_tags)

	# Build split city chains for 3D route stage rendering.
	if itinerary.actionable_legs.is_empty():
		itinerary.actionable_cities = [path_cities[0]]
		itinerary.preview_remaining_cities = path_cities.duplicate()
	else:
		var split_idx := itinerary.actionable_legs.size()
		for i: int in range(split_idx + 1):
			itinerary.actionable_cities.append(path_cities[i])
		if not itinerary.preview_remaining_legs.is_empty():
			for i: int in range(split_idx, path_cities.size()):
				itinerary.preview_remaining_cities.append(path_cities[i])

	if land_preview_transport == CARAVAN:
		itinerary.caravan_fare = ceili(land_km / CARAVAN_KM_PER_COPPER)
		itinerary.actionable_caravan_fare = ceili(act_land_km / CARAVAN_KM_PER_COPPER) if act_land_km > 0 else 0
	itinerary.fare = itinerary.ship_fare + itinerary.caravan_fare
	itinerary.actionable_fare = itinerary.actionable_ship_fare + itinerary.actionable_caravan_fare
	itinerary.total_days = maxi(1, roundi(elapsed))
	itinerary.ration_cost = ceili(itinerary.total_days * provisions / maxf(elapsed, 0.0001) - 0.000001)
	if not itinerary.actionable_legs.is_empty():
		itinerary.actionable_days = maxi(1, roundi(act_elapsed))
		itinerary.actionable_ration_cost = ceili(itinerary.actionable_days * act_provisions / maxf(act_elapsed, 0.0001) - 0.000001)

	_finalize_risk_summary(itinerary, max_stability)
	return itinerary


func _collect_risk_tags(leg: Leg, risk_tags: Array[String]) -> void:
	var dest_info := get_city_info(leg.to_city)
	if bool(dest_info.get("checkpoint", false)) and not risk_tags.has("城门盘查"):
		risk_tags.append("城门盘查")
	if leg.danger_tag != "safe_road" and leg.danger_tag != "sea_lane":
		var lbl := danger_label(leg.danger_tag)
		if not risk_tags.has(lbl):
			risk_tags.append(lbl)


func _finalize_risk_summary(itinerary: Itinerary, max_stability: float) -> void:
	if max_stability >= 1.75 or itinerary.risk_tags.has("强盗出没") or itinerary.risk_tags.has("魔物频发"):
		itinerary.risk_level = "danger"
		if itinerary.risk_tags.has("强盗出没"):
			itinerary.risk_label = "高危 · 强盗出没"
		elif itinerary.risk_tags.has("魔物频发"):
			itinerary.risk_label = "高危 · 魔物频发"
		else:
			itinerary.risk_label = "险途警觉"
	elif max_stability >= 1.15 or itinerary.risk_tags.has("城门盘查"):
		itinerary.risk_level = "caution"
		itinerary.risk_label = "需留意 · 城门盘查" if itinerary.risk_tags.has("城门盘查") else "林道慎行"
	else:
		itinerary.risk_level = "steady"
		itinerary.risk_label = "官道稳健"
	if itinerary.risk_tags.is_empty():
		itinerary.risk_tags.append("官道稳健")


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
