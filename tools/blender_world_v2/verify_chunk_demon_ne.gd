extends Node

const ATLAS := preload("res://scenes/world_map/world_atlas_view.tscn")
const Terrain := preload("res://scenes/world_map/world_terrain_sampler.gd")
const Registry := preload("res://scenes/world_map/chunks/world_chunk_registry.gd")
const Journey := preload("res://scenes/world_map/atlas_travel_stage.gd")
const Planner := preload("res://core/travel_planner.gd")

var _failed := false


func _ready() -> void:
	call_deferred("_verify")


func _check(pass_check: bool, detail: String) -> void:
	if pass_check:
		print("PASS ", detail)
	else:
		_failed = true
		push_error(detail)


func _frames(count: int) -> void:
	for frame: int in count:
		await get_tree().process_frame


func _verify() -> void:
	if OS.get_cmdline_user_args().has("--previous-slot"):
		await _verify_previous_slot()
		get_tree().quit(1 if _failed else 0)
		return
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
	await _frames(5)
	var sampler := atlas.get_terrain_sampler() as Terrain
	if sampler == null or sampler.chunks == null:
		push_error("The atlas stage did not initialize")
		get_tree().quit(1)
		return
	var chunk := sampler.chunks.city_chunk("city_migurd")
	if OS.get_cmdline_user_args().has("--fallback"):
		var cities: Dictionary = atlas.get("_cities")
		_check(chunk == null, "Missing terrain leaves macro fallback active")
		_check(cities.has("city_migurd") and cities.has("city_rikarisu"), "Fallback city selection still available")
		get_tree().quit(1 if _failed else 0)
		return
	if chunk == null:
		push_error("Demon northeast terrain did not mount")
		get_tree().quit(1)
		return

	var viewport := atlas.get("_render") as SubViewport
	var space := viewport.world_3d.direct_space_state
	_check(sampler.chunks.active.has(chunk), "Northeast registered")
	_check(chunk.custom_props.get_child_count() == 3, "Three ore clusters (%d)" % chunk.custom_props.get_child_count())
	var ray_tolerance := 0.0
	for point: Vector2 in [Vector2(6.02, -3.295), Vector2(6.71, -3.795), Vector2(6.40, -3.56), Vector2(6.17, -3.82), Vector2(6.78, -3.21)]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, 2.0, point.y), Vector3(point.x, -0.5, point.y), Registry.TERRAIN_LAYER)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			ray_tolerance = INF
			continue
		var position: Vector3 = hit["position"]
		ray_tolerance = maxf(ray_tolerance, absf(position.y - sampler.sample_height(point.x, point.y)))
	_check(ray_tolerance <= 0.00005, "Height samples match collider; max deviation %.8f" % ray_tolerance)

	var anchor := Marker3D.new()
	var anchor_xz := Vector2(6.26, -3.96)
	var offset := 0.013
	var placed := chunk.custom_props.snap_node_to_terrain(anchor, anchor_xz, offset, 1.0)
	var origin := Vector3(anchor_xz.x, 2.0, anchor_xz.y)
	var ray := PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 2.5, Registry.TERRAIN_LAYER)
	var hit := space.intersect_ray(ray)
	var ray_point: Vector3 = hit.get("position", Vector3.INF)
	var ray_normal: Vector3 = hit.get("normal", Vector3.ZERO)
	_check(placed and anchor.get_parent() == chunk.custom_props and absf(anchor.global_position.y - ray_point.y - offset) <= 0.00005
		and anchor.global_basis.y.normalized().dot(ray_normal) >= 0.9999, "New CustomProps marker follows collider height, bias and normal")
	var outside := chunk.custom_props.snap_node_to_terrain(anchor, Vector2.ZERO, 0.0, 0.0)
	_check(not outside, "Outside point rejected")
	if is_instance_valid(anchor):
		anchor.free()

	var seam_error := 0.0
	var neighbor := sampler.chunks.city_chunk("city_kurasuma")
	for z: float in [-4.25, -3.88, -3.44, -3.00, -2.50]:
		var seam := Vector2(chunk.bounds.position.x, z)
		var neighbor_height := neighbor.sample_surface(seam).w
		seam_error = maxf(seam_error, absf(chunk.sample_surface(seam).w - neighbor_height))
	_check(seam_error <= 0.00005, "West transition meets adjacent terrain; max deviation %.8f" % seam_error)

	var cities: Dictionary = atlas.get("_cities")
	var positions := sampler.get_all_city_positions()
	var radii: Dictionary[String, float] = {}
	for id: String in cities:
		var piece: RefCounted = cities[id]
		radii[id] = piece.get("outer_radius")
	for id: String in ["city_migurd", "city_rikarisu"]:
		var piece: RefCounted = cities[id]
		var mesh := piece.get("model") as MeshInstance3D
		_check(mesh.get_parent() == chunk.assets_root and mesh.layers == 0 and mesh.get_node_or_null("HeroMiniature") != null,
			id + " hero mounted above sculpted ground")
	_check(positions["city_migurd"].distance_to(Vector3(6.71, positions["city_migurd"].y, -3.795)) < 0.00001
		and positions["city_rikarisu"].distance_to(Vector3(6.02, positions["city_rikarisu"].y, -3.295)) < 0.00001, "Existing world XZ and city IDs retained")

	var planner := atlas.get("_planner") as Planner
	var journey := atlas.get("_journey_stage") as Journey
	var calendar: Dictionary[String, int] = world.call("get_world_time")
	var land := planner.plan("city_migurd", "city_rikarisu", Planner.FOOT, Planner.STEADY, calendar)
	var sea := planner.plan("city_wind_port", "city_zanto_port", Planner.SHIP, Planner.STEADY, calendar)
	_check(land != null and not land.actionable_legs.is_empty() and sea != null and not sea.actionable_legs.is_empty(), "Land and sea plans available")
	if not _failed:
		journey.set_itinerary(land, positions, radii)
		journey.set_travel_mode(Planner.FOOT, false)
		journey.follow(0, 0.38, true)
		var pawn := journey.get_pawn_world_position()
		_check(absf(pawn.y - sampler.sample_surface_height(pawn.x, pawn.z) - 0.004) <= 0.002, "Travel pawn follows sculpted road height")
		var paths: Array[Curve3D] = journey.get("_paths")
		var clear := true
		for point: Vector3 in paths[0].get_baked_points():
			for id: String in ["city_migurd", "city_rikarisu"]:
				var city: RefCounted = cities[id]
				var half: Vector2 = city.get("hero_half_extents")
				if absf(point.x - positions[id].x) < half.x and absf(point.z - positions[id].z) < half.y:
					clear = false
		_check(clear, "Gold route stays outside building footprints")
		journey.set_itinerary(sea, positions, radii)
		journey.set_travel_mode(Planner.SHIP, false)
		journey.follow(0, 0.5, true)
		_check(absf(journey.get_pawn_world_position().y - sampler.sea_level - 0.014) <= 0.002,
			"Sea travel stays at its existing water level")

	var args := OS.get_cmdline_user_args()
	if not _failed and not args.is_empty() and DisplayServer.get_name() != "headless":
		await _capture(atlas, sampler, journey, world, state, positions, radii, land, args[0])
	print("CHUNK VERIFICATION COMPLETE")
	get_tree().quit(1 if _failed else 0)


func _verify_previous_slot() -> void:
	var tree := get_tree()
	var placeholder := Node.new()
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	var saves := tree.root.get_node("SaveManager")
	_check(bool(saves.call("load_slot", "slot_6")), "Pre-chunk save accepted")
	if _failed:
		return
	var deadline := Time.get_ticks_msec() + 8000
	while not is_instance_valid(tree.current_scene) or tree.current_scene == placeholder:
		if Time.get_ticks_msec() >= deadline:
			break
		await tree.create_timer(0.1).timeout
	var atlas := tree.current_scene
	var world := tree.root.get_node("WorldBlackboard")
	_check(atlas != null and atlas.scene_file_path == ATLAS.resource_path and str(world.get("current_city_id")) == "city_migurd",
		"Pre-chunk save restores the atlas and the old city ID")
	if not _failed:
		var sampler := atlas.call("get_terrain_sampler") as Terrain
		_check(sampler != null and sampler.chunks.city_chunk("city_migurd") != null, "Restored atlas mounts the sculpted chunk")


func _capture(
	atlas: Control, sampler: Terrain, journey: Journey, world: Node, state: Dictionary,
	positions: Dictionary[String, Vector3], radii: Dictionary[String, float], land: Planner.Itinerary, destination: String
) -> void:
	DirAccess.make_dir_recursive_absolute(destination)
	var viewport := atlas.get("_render") as SubViewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var date: Dictionary = state["world_time"]
	atlas.set("_traveling", true)
	for label: String in ["morning", "dusk", "midrange"]:
		date["slot"] = 2 if label == "dusk" else 0
		world.call("deserialize_state", state)
		atlas.call("_refresh_time_atmosphere")
		var far := label == "midrange"
		var distance := 6.0 if far else 2.90
		atlas.set("_center", Vector3(5.88, 0.0, -3.18) if far else Vector3(6.29, 0.0, -3.42))
		atlas.set("_pan", Vector3.ZERO)
		atlas.set("_distance", distance)
		atlas.set("_distance_target", distance)
		atlas.set("_camera_pitch", deg_to_rad(48.0))
		atlas.set("_aim_height", 0.20 if far else 0.29)
		atlas.set("_drawer_shift", 0.0)
		journey.set_itinerary(land, positions, radii)
		journey.set_travel_mode(Planner.FOOT, false)
		journey.set_waypoints_visible(false)
		var roadside := Vector3(6.49, 0.0, -3.26)
		roadside.y = sampler.sample_surface_height(roadside.x, roadside.z)
		journey.park(roadside)
		RenderingServer.render_loop_enabled = false
		for frame: int in 18:
			await get_tree().process_frame
			RenderingServer.force_draw(true)
		var start := Time.get_ticks_usec()
		for frame: int in 32:
			await get_tree().process_frame
			RenderingServer.force_draw(true)
		var fps := 32000000.0 / float(Time.get_ticks_usec() - start)
		var image := viewport.get_texture().get_image()
		_check(image != null and image.save_png(destination.path_join("chunk_demon_ne_%s.png" % label)) == OK, "Captured " + label)
		print("CAPTURE ", label, " FPS ", snappedf(fps, 0.1), " ", viewport.size)
		RenderingServer.render_loop_enabled = true
	atlas.set("_traveling", false)
