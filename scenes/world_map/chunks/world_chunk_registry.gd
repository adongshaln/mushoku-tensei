extends RefCounted

const Chunk := preload("res://scenes/world_map/chunks/world_chunk.gd")
const MANIFEST := "res://scenes/world_map/chunks/world_chunks_manifest.json"
const MAX_CHUNKS := 12
const TERRAIN_LAYER := 1 << 14
const OCEAN_RESOLUTION := 256
const ROUTES_PATH := "res://data/maps/world_routes.json"

var active: Array[Chunk] = []
var detailed_roads: Dictionary[String, Dictionary] = {}
var _city_chunks: Dictionary[String, Chunk] = {}


func mount(parent: Node3D, terrain: ShaderMaterial, ocean: ShaderMaterial) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1 or terrain == null:
		return
	var world: Array = parsed.get("world_bounds", [])
	if world.size() != 4:
		return
	var world_rect := Rect2(float(world[0]), float(world[1]), float(world[2]) - float(world[0]), float(world[3]) - float(world[1]))
	var rects := PackedVector4Array()
	rects.resize(MAX_CHUNKS)
	var depth_layers: Array[Image] = []
	var limit := clampi(int(parsed.get("maximum_active_chunks", MAX_CHUNKS)), 0, MAX_CHUNKS)
	var configs: Array = parsed.get("chunks", [])
	var atomic_groups := PackedStringArray(parsed.get("atomic_terrain_groups", []))
	var incomplete: Dictionary[String, bool] = {}
	for config: Dictionary in configs:
		var group := str(config.get("terrain_group", ""))
		if atomic_groups.has(group) and not _can_mount(config):
			incomplete[group] = true
	for config: Dictionary in configs:
		if active.size() >= limit:
			break
		if incomplete.has(str(config.get("terrain_group", ""))) or not _can_mount(config):
			continue
		var path := str(config.get("scene", ""))
		var scene := load(path) as PackedScene
		var candidate := scene.instantiate() as Chunk if scene != null else null
		if candidate == null:
			continue
		parent.add_child(candidate)
		if not candidate.build(config, terrain, TERRAIN_LAYER) or _overlaps(candidate.bounds) or not world_rect.encloses(candidate.bounds):
			candidate.free()
			continue
		active.append(candidate)
	_keep_complete_groups(configs, atomic_groups)
	for index: int in active.size():
		var candidate: Chunk = active[index]
		rects[index] = candidate.world_bounds_uniform()
		for city: String in candidate.city_ids:
			_city_chunks[city] = candidate
		depth_layers.append(candidate.depth_image(OCEAN_RESOLUTION))
	terrain.set_shader_parameter("sculpted_count", active.size())
	terrain.set_shader_parameter("sculpted_rects", rects)
	_set_transition_bounds()
	_load_detailed_roads(parsed.get("detailed_roads", []))
	if ocean != null and not depth_layers.is_empty():
		var depth := Texture2DArray.new()
		if depth.create_from_images(depth_layers) == OK:
			ocean.set_shader_parameter("sculpted_count", active.size())
			ocean.set_shader_parameter("sculpted_rects", rects)
			ocean.set_shader_parameter("sculpted_depth", depth)


func _can_mount(config: Dictionary) -> bool:
	if not bool(config.get("enabled", true)) or not ResourceLoader.exists(str(config.get("scene", "")), "PackedScene"):
		return false
	if not ResourceLoader.exists(str(config.get("terrain", "")), "PackedScene"):
		return false
	var prefix := str(config.get("pbr_prefix", ""))
	for channel: String in ["albedo", "normal", "ao", "roughness"]:
		if not ResourceLoader.exists("%s_%s.png" % [prefix, channel], "Texture2D"):
			return false
	return true


func _keep_complete_groups(configs: Array, atomic_groups: PackedStringArray) -> void:
	for group: String in atomic_groups:
		var expected := 0
		for config: Dictionary in configs:
			if str(config.get("terrain_group", "")) == group:
				expected += 1
		var members: Array[Chunk] = []
		for chunk: Chunk in active:
			if chunk.terrain_group == group:
				members.append(chunk)
		if members.size() == expected:
			continue
		for chunk: Chunk in members:
			active.erase(chunk)
			chunk.hide()
			chunk.queue_free()


func _overlaps(rect: Rect2) -> bool:
	for chunk: Chunk in active:
		if rect.intersection(chunk.bounds).get_area() > 0.00001:
			return true
	return false


func _set_transition_bounds() -> void:
	var group_bounds: Dictionary[String, Rect2] = {}
	var group_area: Dictionary[String, float] = {}
	for chunk: Chunk in active:
		var group := chunk.terrain_group
		if group.is_empty():
			continue
		group_bounds[group] = group_bounds.get(group, chunk.bounds).merge(chunk.bounds)
		group_area[group] = group_area.get(group, 0.0) + chunk.bounds.get_area()
	for chunk: Chunk in active:
		var group := chunk.terrain_group
		var rect: Rect2 = group_bounds.get(group, chunk.bounds)
		if absf(rect.get_area() - group_area.get(group, 0.0)) > 0.001:
			rect = chunk.bounds
		chunk.material.set_shader_parameter("sculpted_transition_bounds",
			Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))


static func road_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func _load_detailed_roads(definitions: Array) -> void:
	if definitions.is_empty():
		return
	var catalog: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	if not catalog is Dictionary:
		return
	var configured: Dictionary[String, Dictionary] = {}
	for entry: Dictionary in definitions:
		configured[road_key(str(entry.get("from", "")), str(entry.get("to", "")))] = entry
	for route: Dictionary in catalog.get("routes", []):
		var from := str(route.get("from", ""))
		var to := str(route.get("to", ""))
		var key := road_key(from, to)
		if str(route.get("mode", "")) != "land" or not configured.has(key) or city_chunk(from) == null or city_chunk(to) == null:
			continue
		var definition: Dictionary = configured[key]
		var via: Array[Vector2] = []
		if definition.has("via"):
			for world_value: Array in definition["via"]:
				via.append(Vector2(float(world_value[0]), float(world_value[1])))
			if str(definition["from"]) != from:
				via.reverse()
		else:
			for pixel: Array in route.get("via", []):
				via.append((Vector2(float(pixel[0]), float(pixel[1])) - Vector2(836.0, 470.5)) * 0.01)
		detailed_roads[key] = {"from": from, "to": to, "via": via}


func at(xz: Vector2) -> Chunk:
	for chunk: Chunk in active:
		if chunk.bounds.has_point(xz):
			return chunk
	return null


func city_chunk(city_id: String) -> Chunk:
	return _city_chunks.get(city_id)


func excludes_scatter(xz: Vector2, is_deadwood: bool) -> bool:
	for chunk: Chunk in active:
		var exclusion := chunk.bounds.grow(chunk.scatter_exclusion_margin) if is_deadwood else chunk.bounds
		if exclusion.has_point(xz):
			return true
	return false


func sync_materials(terrain: ShaderMaterial) -> void:
	for chunk: Chunk in active:
		for key: String in ["atlas_blend", "hovered_region_idx", "selected_region_idx", "hovered_continent_idx",
				"active_continent_idx", "crossing_continent_idx", "hover_pulse", "winter_snow_push",
				"wetness_boost", "rain_cloud_boost"]:
			chunk.material.set_shader_parameter(key, terrain.get_shader_parameter(key))
