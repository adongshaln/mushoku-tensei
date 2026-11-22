extends Node

const ATLAS := preload("res://scenes/world_map/world_atlas_view.tscn")
const Terrain := preload("res://scenes/world_map/world_terrain_sampler.gd")
const Registry := preload("res://scenes/world_map/chunks/world_chunk_registry.gd")
const Chunk := preload("res://scenes/world_map/chunks/world_chunk.gd")
const Journey := preload("res://scenes/world_map/atlas_travel_stage.gd")
const Planner := preload("res://core/travel_planner.gd")

var _failed := false


func _ready() -> void:
	call_deferred("_verify")


func _check(result: bool, detail: String) -> void:
	if result:
		print("PASS ", detail)
	else:
		_failed = true
		push_error(detail)


func _verify() -> void:
	var world := get_tree().root.get_node("WorldBlackboard")
	var state: Dictionary = world.call("serialize_state")
	state["current_city_id"] = "city_migurd"
	state["current_location_id"] = "demon_biegoya"
	state["current_transport"] = "foot"
	var date: Dictionary = state["world_time"]
	date["slot"] = 0
	world.call("deserialize_state", state)
	var atlas := ATLAS.instantiate() as Control
	get_tree().root.add_child(atlas)
	get_tree().current_scene = atlas
	for i: int in 8:
		await get_tree().physics_frame
	var sampler := atlas.call("get_terrain_sampler") as Terrain
	var registry: Registry = sampler.chunks
	_check(registry.active.size() == 3, "All three chunks registered")
	if _failed:
		get_tree().quit(1)
		return
	var viewport := atlas.get("_render") as SubViewport
	var space := viewport.world_3d.direct_space_state
	var ne: Chunk = registry.city_chunk("city_migurd")
	var nw: Chunk = registry.city_chunk("city_kurasuma")
	var south: Chunk = registry.city_chunk("city_wind_port")
	_check(ne.custom_props.get_child_count() == 3, "Northeast retains three crystal clusters")
	_check(_seam_error(ne, nw, false) < 0.00002, "Northeast to northwest seam")
	_check(_seam_error(ne, south, true) < 0.00002, "Northeast to south seam")
	_check(_seam_error(nw, south, true) < 0.00002, "Northwest to south seam")
	for chunk: Chunk in registry.active:
		_verify_placement(chunk, space)

	var cities: Dictionary = atlas.get("_cities")
	var expected: Dictionary[String, Vector2] = {
		"city_migurd": Vector2(6.71, -3.795),
		"city_rikarisu": Vector2(6.02, -3.295),
		"city_kurasuma": Vector2(3.36, -3.435),
		"city_wind_port": Vector2(5.80, -0.215),
	}
	for city: String in expected:
		var pos := sampler.get_city_position(city)
		_check(Vector2(pos.x, pos.z).distance_to(expected[city]) < 0.00001,
			"%s preserves canonical XZ" % city)
		var piece: RefCounted = cities[city]
		var model := piece.get("model") as MeshInstance3D
		var chunk := registry.city_chunk(city)
		_check(model.get_parent() == chunk.assets_root and absf(float(piece.get("ground_y")) - pos.y) < 0.00001,
			"%s follows its sculpted platform" % city)
		if chunk.hide_legacy_plinth:
			_check(_plinth_indices(model.mesh) == 0, "%s legacy brass and stone base triangles removed" % city)

	var journey := atlas.get("_journey_stage") as Journey
	var permanent: Dictionary = journey.get("_chunk_roads")
	_check(permanent.size() == 4, "Four continuous gilded land routes")
	_verify_road_meshes(permanent, sampler)
	_verify_travel(atlas, sampler, journey, world)

	var args := OS.get_cmdline_user_args()
	if not _failed and not args.is_empty() and DisplayServer.get_name() != "headless":
		await _capture(atlas, sampler, journey, world, state, args[0])
	print("DEMON CONTINENT VERIFICATION COMPLETE")
	get_tree().quit(1 if _failed else 0)


func _seam_error(a: Chunk, b: Chunk, east_west_line: bool) -> float:
	var largest := 0.0
	for index: int in 130:
		var t := float(index) / 129.0
		var point := Vector2(a.bounds.position.x, lerpf(a.bounds.position.y, a.bounds.end.y, t))
		if east_west_line:
			point = Vector2(lerpf(a.bounds.position.x, a.bounds.end.x, t), a.bounds.end.y)
		largest = maxf(largest, absf(a.sample_surface(point).w - b.sample_surface(point).w))
	print("SEAM ", a.name, " / ", b.name, " max ", largest)
	return largest


func _verify_placement(chunk: Chunk, space: PhysicsDirectSpaceState3D) -> void:
	var center := chunk.bounds.get_center()
	var anchor := Marker3D.new()
	var bias := 0.017
	if not chunk.custom_props.snap_node_to_terrain(anchor, center, bias, 1.0):
		_check(false, "%s rejected its interior anchor" % chunk.name)
		anchor.free()
		return
	var ray := PhysicsRayQueryParameters3D.create(Vector3(center.x, 2.0, center.y), Vector3(center.x, -0.5, center.y), Registry.TERRAIN_LAYER)
	var hit := space.intersect_ray(ray)
	var position: Vector3 = hit.get("position", Vector3.INF)
	var normal: Vector3 = hit.get("normal", Vector3.ZERO)
	var difference := absf(anchor.global_position.y - position.y - bias)
	_check(difference < 0.00012 and anchor.global_basis.y.normalized().dot(normal) > 0.9998,
		"%s CustomProps ray tolerance %.8f" % [chunk.name, difference])
	anchor.free()


func _plinth_indices(mesh: Mesh) -> int:
	var result := 0
	for surface: int in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if material == null or not material.resource_name.begins_with("Aged brass") and not material.resource_name.begins_with("Warm cut limestone"):
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index: int in range(0, indices.size(), 3):
			if maxf(vertices[indices[index]].y, maxf(vertices[indices[index + 1]].y, vertices[indices[index + 2]].y)) < 0.17501:
				result += 3
	return result


func _verify_road_meshes(permanent: Dictionary, sampler: Terrain) -> void:
	for key: String in permanent:
		var ribbon: MeshInstance3D = permanent[key]
		var arrays := ribbon.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var low := INF
		var high := -INF
		var driest_low := INF
		for point: Vector3 in vertices:
			var height := sampler.sample_height(point.x, point.z)
			driest_low = minf(driest_low, height)
			var clearance := point.y - height
			low = minf(low, clearance)
			high = maxf(high, clearance)
		_check(low >= 0.015 and high <= 0.025 and driest_low > 0.002,
			"%s ribbon clearance %.6f..%.6f; min land %.6f" % [key, low, high, driest_low])


func _verify_travel(atlas: Control, sampler: Terrain, journey: Journey, world: Node) -> void:
	var planner := atlas.get("_planner") as Planner
	var positions := sampler.get_all_city_positions()
	var calendar: Dictionary[String, int] = world.call("get_world_time")
	var land := planner.plan("city_kurasuma", "city_wind_port", Planner.FOOT, Planner.STEADY, calendar)
	var sea := planner.plan("city_wind_port", "city_zanto_port", Planner.SHIP, Planner.STEADY, calendar)
	_check(land != null and sea != null and not land.actionable_legs.is_empty() and not sea.actionable_legs.is_empty(),
		"Net travel and sea crossing plan")
	if _failed:
		return
	journey.set_itinerary(land, positions)
	journey.set_travel_mode(Planner.FOOT, false)
	journey.follow(0, 0.59, true)
	var foot := journey.get_pawn_world_position()
	_check(absf(foot.y - sampler.sample_surface_height(foot.x, foot.z) - 0.004) < 0.002, "Walking pawn follows sculpted height")
	journey.set_itinerary(sea, positions)
	journey.set_travel_mode(Planner.SHIP, false)
	journey.follow(0, 0.58, true)
	_check(absf(journey.get_pawn_world_position().y - sampler.sea_level - 0.014) < 0.002, "Ship retains sea level")
	journey.set_itinerary(null, positions)


func _capture(atlas: Control, sampler: Terrain, journey: Journey, world: Node, state: Dictionary, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path)
	var viewport := atlas.get("_render") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var date: Dictionary = state["world_time"]
	var labels: Array[String] = ["ne", "nw", "south", "overview"]
	var centers: Array[Vector3] = [Vector3(6.29, 0.29, -3.42), Vector3(3.72, 0.21, -3.52),
		Vector3(5.67, 0.20, -0.73), Vector3(5.06, 0.19, -2.00)]
	var distances: Array[float] = [2.90, 3.10, 3.80, 8.34]
	var seats: Array[Vector2] = [Vector2(6.49, -3.26), Vector2(3.69, -3.21), Vector2(5.54, -0.39), Vector2(6.49, -3.26)]
	atlas.set("_traveling", true)
	journey.set_travel_mode(Planner.FOOT, false)
	journey.set_waypoints_visible(false)
	for i: int in labels.size():
		date["slot"] = 2 if labels[i] == "south" else 0
		world.call("deserialize_state", state)
		atlas.call("_refresh_time_atmosphere")
		atlas.set("_center", Vector3(centers[i].x, 0.0, centers[i].z))
		atlas.set("_aim_height", centers[i].y)
		atlas.set("_pan", Vector3.ZERO)
		atlas.set("_distance", distances[i])
		atlas.set("_distance_target", distances[i])
		atlas.set("_camera_pitch", deg_to_rad(48.0))
		atlas.set("_drawer_shift", 0.0)
		var seat := seats[i]
		journey.park(Vector3(seat.x, sampler.sample_height(seat.x, seat.y), seat.y))
		RenderingServer.render_loop_enabled = false
		for frame: int in 16:
			await get_tree().process_frame
			RenderingServer.force_draw(true)
		var start := Time.get_ticks_usec()
		for frame: int in 32:
			await get_tree().process_frame
			RenderingServer.force_draw(true)
		var fps := 32000000.0 / float(Time.get_ticks_usec() - start)
		var image := viewport.get_texture().get_image()
		_check(image != null and image.save_png(path.path_join("demon_continent_%s.png" % labels[i])) == OK,
			"Captured " + labels[i])
		print("CAPTURE ", labels[i], " FPS ", snappedf(fps, 0.1), " ", viewport.size)
		RenderingServer.render_loop_enabled = true
	atlas.set("_traveling", false)
