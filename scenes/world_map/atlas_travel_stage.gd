extends Node3D

const Planner := preload("res://core/travel_planner.gd")
const TerrainSampler := preload("res://scenes/world_map/world_terrain_sampler.gd")
const Registry := preload("res://scenes/world_map/chunks/world_chunk_registry.gd")
const ROUTE_SHADER := preload("res://shaders/map_route_line.gdshader")
const PAWN_CONTACT_SHADER := preload("res://shaders/pawn_contact_shadow.gdshader")

const LAND_GOLD := Color("#E9BE62")
const LAND_GLOW := Color("#FFF2C6")
const LAND_INK := Color("#4D321B")
const SEA_PREVIEW := Color("#76C4E2")
const SEA_GLOW := Color("#D6F4FF")
const SEA_INK := Color("#234B62")
const FOOTPRINT_SEPIA := Color("#6E4F34")
const FOOTPRINT_INK := Color("#3F2918")
const GOLD_HALO := Color("#DCAD54")

const PAWN_PATHS: Dictionary[String, String] = {
	Planner.FOOT: "res://assets/3d/pawns/pawn_notia.glb",
	Planner.CARAVAN: "res://assets/3d/pawns/pawn_caravan.glb",
	Planner.SHIP: "res://assets/3d/pawns/pawn_ship.glb"
}
const PAWN_SCALES: Dictionary[String, float] = {
	Planner.FOOT: 0.255,
	Planner.CARAVAN: 0.305,
	Planner.SHIP: 0.265
}
const WAYPOINT_PATH := "res://assets/3d/pawns/marker_waypoint.glb"
const WAYPOINT_SCALE := 0.225
const DETAILED_ROAD_LIFT := 0.018
const DETAILED_ROAD_STEP := 0.0045

var _routes: Node3D
var _waypoints_root: Node3D
var _trail_mesh_instance: MeshInstance3D
var _trail_mat: ShaderMaterial
var _trail_points: Array[Vector3] = []
var _trail_fade_tween: Tween

var _pawn: Node3D
var _body: Node3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _models: Dictionary[String, Node3D] = {}
var _active_mode := Planner.FOOT
var _swap_tween: Tween
var _target_yaw := 0.22

var _waypoint_nodes: Array[Dictionary] = []
var _waypoint_anchors: Array[Dictionary] = []
var _paths: Array[Curve3D] = []
var _path_modes: Array[String] = []
var _all_paths: Array[Curve3D] = []
var _sampler: TerrainSampler = null
var _hero_footprints: Dictionary[String, Vector2] = {}
var _chunk_roads: Dictionary[String, MeshInstance3D] = {}
var _active_detailed_roads: Dictionary[String, bool] = {}
var _clock := 0.0
var _moving := false
var _paused := false
var bounds: AABB


func set_terrain_sampler(sampler: TerrainSampler) -> void:
	_sampler = sampler


func set_hero_footprint(city_id: String, half_extents: Vector2) -> void:
	_hero_footprints[city_id] = half_extents


func build_chunk_roads(cities: Dictionary[String, Vector3]) -> void:
	if _sampler.chunks == null:
		return
	# Wait for the static chunks to register before tracing the persistent network.
	await get_tree().physics_frame
	var ink := _make_route_material(0, Color("#BE8A49", 0.72), Color("#E8BC76"), Color("#4E341F", 0.28), 0.65, 1.0, 1.0)
	ink.set_shader_parameter("tapered_ends", true)
	for key: String in _sampler.chunks.detailed_roads:
		var definition: Dictionary = _sampler.chunks.detailed_roads[key]
		var from := str(definition["from"])
		var to := str(definition["to"])
		if not cities.has(from) or not cities.has(to):
			continue
		var leg := Planner.Leg.new()
		leg.from_city = from
		leg.to_city = to
		leg.mode = Planner.FOOT
		var path := _curve(leg, cities[from], cities[to])
		var anchor := _sampler.chunks.city_chunk(from).atmosphere_root
		var ribbon := _mesh(anchor, _build_detailed_ribbon(path, 0.009), ink)
		ribbon.name = &"LocalGoldRoad"
		ribbon.visible = not _active_detailed_roads.has(key)
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_chunk_roads[key] = ribbon


func _detailed_road(leg: Planner.Leg) -> Dictionary:
	if _sampler.chunks == null or leg.mode == Planner.SHIP:
		return {}
	return _sampler.chunks.detailed_roads.get(Registry.road_key(leg.from_city, leg.to_city), {})


static func footprint_exit(half_extents: Vector2, direction: Vector2) -> float:
	return minf(half_extents.x / maxf(absf(direction.x), 0.001),
		half_extents.y / maxf(absf(direction.y), 0.001))


func _sample_ground_y(world_x: float, world_z: float, is_ship: bool) -> float:
	if _sampler == null or not _sampler.ready:
		return 0.0
	if is_ship:
		return _sampler.get_sea_level() + 0.014
	return _sampler.sample_surface_height(world_x, world_z) + 0.004


func _ready() -> void:
	_routes = Node3D.new()
	add_child(_routes)
	_waypoints_root = Node3D.new()
	add_child(_waypoints_root)

	_trail_mat = _make_route_material(2, Color(FOOTPRINT_SEPIA, 0.72), Color(FOOTPRINT_SEPIA, 0.72), Color(FOOTPRINT_INK, 0.42), 0.0, 5.4, 0.48)
	_trail_mesh_instance = MeshInstance3D.new()
	_trail_mesh_instance.material_override = _trail_mat
	_trail_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail_mesh_instance)

	_pawn = Node3D.new()
	add_child(_pawn)
	_body = Node3D.new()
	_pawn.add_child(_body)

	var loaded_any := false
	for mode: String in PAWN_PATHS:
		var model := _instantiate_glb(PAWN_PATHS[mode], PAWN_SCALES[mode])
		if model != null:
			_body.add_child(model)
			model.visible = mode == Planner.FOOT
			_models[mode] = model
			loaded_any = true
	if not loaded_any:
		var fallback := _build_fallback_pawn()
		_body.add_child(fallback)
		_models[Planner.FOOT] = fallback

	var contact_plane := PlaneMesh.new()
	contact_plane.size = Vector2(0.32, 0.32)
	var contact_mat := ShaderMaterial.new()
	contact_mat.shader = PAWN_CONTACT_SHADER
	contact_mat.set_shader_parameter("shadow_color", Color("#1F1510"))
	contact_mat.set_shader_parameter("shadow_opacity", 0.38)
	var contact_shadow := MeshInstance3D.new()
	contact_shadow.mesh = contact_plane
	contact_shadow.material_override = contact_mat
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	contact_shadow.position.y = 0.004
	_pawn.add_child(contact_shadow)

	var torus := TorusMesh.new()
	torus.inner_radius = 0.116
	torus.outer_radius = 0.132
	torus.rings = 36
	torus.ring_segments = 8
	_halo_mat = _light(GOLD_HALO, 0.68)
	_halo = _mesh(_pawn, torus, _halo_mat)
	_halo.position.y = 0.011

	if not WorldBlackboard.transport_changed.is_connected(_on_transport_changed):
		WorldBlackboard.transport_changed.connect(_on_transport_changed)
	set_travel_mode(WorldBlackboard.current_transport, false)


func _exit_tree() -> void:
	if WorldBlackboard.transport_changed.is_connected(_on_transport_changed):
		WorldBlackboard.transport_changed.disconnect(_on_transport_changed)


func _on_transport_changed(mode: String) -> void:
	set_travel_mode(mode, true)


func _instantiate_glb(path: String, uniform_scale: float) -> Node3D:
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null:
		return null
	var wrapper := Node3D.new()
	var instance := packed.instantiate() as Node3D
	if instance == null:
		wrapper.free()
		return null
	instance.scale = Vector3.ONE * uniform_scale
	_polish_pawn_materials(instance)
	wrapper.add_child(instance)
	return wrapper


func _polish_pawn_materials(root_node: Node) -> void:
	if root_node is MeshInstance3D:
		var mi := root_node as MeshInstance3D
		if mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				var base_mat := mi.get_active_material(s)
				if base_mat is StandardMaterial3D:
					var std := (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					std.rim_enabled = true
					std.rim = 0.16
					std.rim_tint = 0.50
					mi.set_surface_override_material(s, std)
	for child: Node in root_node.get_children():
		_polish_pawn_materials(child)


func set_travel_mode(mode: String, animate: bool = true) -> void:
	var resolved := mode if _models.has(mode) else Planner.FOOT
	var changed := resolved != _active_mode
	_active_mode = resolved
	for key: String in _models:
		_models[key].visible = key == resolved
	if _halo_mat != null:
		match resolved:
			Planner.CARAVAN:
				_halo_mat.albedo_color = Color("#F5CA76", 0.78)
			Planner.SHIP:
				_halo_mat.albedo_color = Color(SEA_PREVIEW, 0.80)
			_:
				_halo_mat.albedo_color = Color(GOLD_HALO, 0.72)
	if changed and animate and is_inside_tree():
		if _swap_tween != null and _swap_tween.is_valid():
			_swap_tween.kill()
		_body.scale = Vector3.ONE * 0.62
		_halo.scale = Vector3.ONE * 1.55
		_swap_tween = create_tween().set_parallel(true)
		_swap_tween.tween_property(_body, "scale", Vector3.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_swap_tween.tween_property(_halo, "scale", Vector3.ONE, 0.38).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func get_active_mode() -> String:
	return _active_mode


func get_pawn_world_position() -> Vector3:
	return _pawn.global_position if _pawn != null else Vector3.ZERO


func get_pawn_forward_xz() -> Vector3:
	var yaw := _pawn.rotation.y if _pawn != null else _target_yaw
	return Vector3(sin(yaw), 0.0, cos(yaw)).normalized()


func get_waypoint_anchors() -> Array[Dictionary]:
	return _waypoint_anchors.duplicate(true)


func set_paused(paused_state: bool) -> void:
	_paused = paused_state


func set_waypoints_visible(visible_state: bool) -> void:
	if _waypoints_root != null:
		_waypoints_root.visible = visible_state


func _process(delta: float) -> void:
	_clock += delta
	if _pawn != null:
		_pawn.rotation.y = lerp_angle(_pawn.rotation.y, _target_yaw, 1.0 - exp(-delta * 11.5))

	if _moving and not _paused:
		match _active_mode:
			Planner.SHIP:
				_body.position.y = 0.014 + 0.011 * sin(_clock * 3.6)
				_body.rotation.x = cos(_clock * 2.9) * 0.052
				_body.rotation.z = sin(_clock * 4.0) * 0.092
			Planner.CARAVAN:
				_body.position.y = 0.006 * absf(sin(_clock * 9.2))
				_body.rotation.x = sin(_clock * 9.2) * 0.022
				_body.rotation.z = sin(_clock * 4.6) * 0.034
			_:
				_body.position.y = 0.010 * absf(sin(_clock * 8.6))
				_body.rotation.x = 0.048
				_body.rotation.z = sin(_clock * 4.3) * 0.028
	else:
		_body.position.y = 0.006 * (0.5 + 0.5 * sin(_clock * 2.5))
		_body.rotation = _body.rotation.lerp(Vector3.ZERO, 1.0 - exp(-delta * 10.0))

	if _swap_tween == null or not _swap_tween.is_valid():
		_halo.scale = Vector3.ONE * (1.0 + 0.075 * sin(_clock * 2.4))

	for entry: Dictionary in _waypoint_nodes:
		var model := entry["model"] as Node3D
		var halo := entry["halo"] as MeshInstance3D
		var phase := float(entry["phase"])
		if model != null:
			model.rotation.y += delta * 0.72
			model.position.y = 0.014 + 0.012 * sin(_clock * 2.6 + phase)
		if halo != null:
			halo.scale = Vector3.ONE * (1.0 + 0.09 * sin(_clock * 2.9 + phase))


func park(position_on_map: Vector3) -> void:
	_moving = false
	_paused = false
	var grounded := position_on_map
	if _sampler != null and _sampler.ready:
		var terrain_h: float = _sampler.sample_surface_height(grounded.x, grounded.z) + 0.004
		grounded.y = maxf(_sampler.get_sea_level() + 0.014, terrain_h) if _active_mode == Planner.SHIP else terrain_h
	_pawn.position = grounded
	_target_yaw = 0.22


func begin_trail(start_pos: Vector3) -> void:
	if _trail_fade_tween != null and _trail_fade_tween.is_valid():
		_trail_fade_tween.kill()
	_trail_points.clear()
	var lift := 0.022 if _active_mode == Planner.SHIP else 0.028
	var y_val := _sample_ground_y(start_pos.x, start_pos.z, _active_mode == Planner.SHIP) if (_sampler != null and _sampler.ready) else start_pos.y
	_trail_points.append(Vector3(start_pos.x, y_val + lift, start_pos.z))
	_trail_mat.set_shader_parameter("fade_alpha", 0.85)
	_trail_mesh_instance.mesh = null


func record_trail_point(pos: Vector3) -> void:
	var is_ship := _active_mode == Planner.SHIP
	var lift := 0.018 if is_ship else 0.024
	var y_val := _sample_ground_y(pos.x, pos.z, is_ship) if (_sampler != null and _sampler.ready) else pos.y
	var lifted := Vector3(pos.x, maxf(pos.y, y_val) + lift, pos.z)
	if not _trail_points.is_empty() and _trail_points.back().distance_to(lifted) < 0.065:
		return
	_trail_points.append(lifted)
	if _trail_points.size() >= 2:
		_trail_mesh_instance.mesh = _build_polyline_ribbon(_trail_points, 0.019, not is_ship, 0.020)


func fade_out_trail(duration: float = 1.6) -> void:
	if _trail_mesh_instance.mesh == null:
		return
	if _trail_fade_tween != null and _trail_fade_tween.is_valid():
		_trail_fade_tween.kill()
	_trail_fade_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_trail_fade_tween.tween_method(func(a: float) -> void:
		_trail_mat.set_shader_parameter("fade_alpha", a), 0.85, 0.0, duration)
	_trail_fade_tween.tween_callback(func() -> void:
		_trail_points.clear()
		_trail_mesh_instance.mesh = null)


func follow(index: int, fraction: float, snap_facing: bool = false) -> void:
	if index < 0 or index >= _paths.size():
		return
	_moving = true
	var path := _paths[index]
	var leg_mode: String = _path_modes[index] if index < _path_modes.size() else _active_mode
	var is_ship := leg_mode == Planner.SHIP
	var total := path.get_baked_length()
	var offset := total * clampf(fraction, 0.0, 1.0)
	var point := path.sample_baked(offset, true)
	var ahead := path.sample_baked(minf(total, offset + 0.09), true)
	if ahead.distance_squared_to(point) < 0.000001 and offset > 0.05:
		ahead = point
		point = path.sample_baked(maxf(0.0, offset - 0.09), true)
	var pos := path.sample_baked(offset, true)
	if _sampler != null and _sampler.ready:
		if is_ship:
			# Keep ship gliding smoothly on sea_level across water, gently meeting harbor quays at endpoints.
			var sea_y: float = _sampler.get_sea_level() + 0.014
			var port_t: float = smoothstep(0.0, 0.14, fraction) * (1.0 - smoothstep(0.86, 1.0, fraction))
			pos.y = lerpf(pos.y, sea_y, port_t)
			pos.y = maxf(pos.y, sea_y)
		else:
			pos.y = _sampler.sample_surface_height(pos.x, pos.z) + 0.004
	_pawn.position = pos
	if ahead.distance_squared_to(point) > 0.000001:
		_target_yaw = atan2(ahead.x - point.x, ahead.z - point.z)
		if snap_facing:
			_pawn.rotation.y = _target_yaw
	record_trail_point(_pawn.position)


func set_itinerary(plan: Planner.Itinerary, cities: Dictionary[String, Vector3], city_radii: Dictionary[String, float] = {}) -> void:
	_clear_children(_routes)
	_clear_waypoints()
	for ribbon: MeshInstance3D in _chunk_roads.values():
		ribbon.show()
	_active_detailed_roads.clear()
	_paths.clear()
	_path_modes.clear()
	_all_paths.clear()
	bounds = AABB()
	if plan == null or plan.legs.is_empty():
		return

	var actionable_mat := _make_route_material(0, Color(LAND_GOLD, 0.94), LAND_GLOW, Color(LAND_INK, 0.44), 1.45, 1.0, 1.0)
	var detailed_mat := _make_route_material(0, Color("#D0A157", 0.91), Color("#F5D699"), Color("#47301C", 0.30), 1.1, 1.0, 1.0)
	detailed_mat.set_shader_parameter("tapered_ends", true)
	var sea_actionable_mat := _make_route_material(0, Color("#82D2EE", 0.92), SEA_GLOW, Color(SEA_INK, 0.42), 1.35, 1.0, 1.0)
	var preview_mat := _make_route_material(1, Color(SEA_PREVIEW, 0.78), SEA_GLOW, Color(SEA_INK, 0.48), 1.20, 3.8, 0.54)
	var shadow_mat := _light(Color("#24150B"), 0.22, 0)

	var last_trimmed_end := Vector3.ZERO
	var has_last_end := false
	for leg: Planner.Leg in plan.legs:
		if not cities.has(leg.from_city) or not cities.has(leg.to_city):
			continue
		var is_ship := leg.mode == Planner.SHIP
		var detailed := not _detailed_road(leg).is_empty()
		if detailed:
			var key := Registry.road_key(leg.from_city, leg.to_city)
			_active_detailed_roads[key] = true
			if _chunk_roads.has(key):
				_chunk_roads[key].hide()
		var r_from: float = float(city_radii.get(leg.from_city, 0.0))
		var r_to: float = float(city_radii.get(leg.to_city, 0.0))
		var path := _curve(leg, cities[leg.from_city], cities[leg.to_city], r_from, r_to)
		_all_paths.append(path)
		if leg.is_actionable:
			_paths.append(path)
			_path_modes.append(leg.mode)
		var baked_pts := path.get_baked_points()
		if not baked_pts.is_empty():
			last_trimmed_end = baked_pts[baked_pts.size() - 1]
			has_last_end = true
		for pt: Vector3 in baked_pts:
			bounds = bounds.expand(pt) if bounds.has_surface() else AABB(pt, Vector3.ONE * 0.001)

		if leg.is_actionable:
			var ribbon := _build_detailed_ribbon(path, 0.011) if detailed else _build_curve_ribbon(path, 0.025, 0.0, is_ship)
			if not detailed:
				var shadow := _build_curve_ribbon(path, 0.037, -0.009, is_ship)
				var sh_inst := _mesh(_routes, shadow, shadow_mat)
				sh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mat := detailed_mat if detailed else (sea_actionable_mat if is_ship else actionable_mat)
			var inst := _mesh(_routes, ribbon, mat)
			inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			var prev_ribbon := _build_detailed_ribbon(path, 0.010) if detailed else _build_curve_ribbon(path, 0.021, 0.0, is_ship)
			var p_inst := _mesh(_routes, prev_ribbon, preview_mat)
			p_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Place 3D waypoint markers cleanly at city perimeter (never blocking houses or ships!)
	if plan.is_manual and not plan.manual_waypoints.is_empty():
		for i: int in plan.manual_waypoints.size():
			var wp_id := plan.manual_waypoints[i]
			if cities.has(wp_id):
				var r_wp: float = float(city_radii.get(wp_id, 0.0))
				var wp_pos: Vector3 = cities[wp_id] + Vector3(r_wp + 0.06, 0.0, r_wp * 0.55)
				_spawn_waypoint_marker(wp_pos, wp_id, i + 1, Color("#E9BE62"))
	else:
		var dest_id := str(plan.path_cities.back())
		if cities.has(dest_id):
			var marker_pos: Vector3 = last_trimmed_end if has_last_end else cities[dest_id]
			_spawn_waypoint_marker(marker_pos, dest_id, 0, SEA_PREVIEW if plan.requires_hub_transfer else LAND_GOLD)
		if plan.requires_hub_transfer and not plan.transfer_hub_id.is_empty() and plan.transfer_hub_id != plan.path_cities[0] and plan.transfer_hub_id != dest_id:
			if cities.has(plan.transfer_hub_id):
				_spawn_hub_ring(cities[plan.transfer_hub_id], LAND_GOLD)


func _spawn_waypoint_marker(pos: Vector3, city_id: String, badge_index: int, ring_color: Color) -> void:
	var grounded := pos
	if _sampler != null and _sampler.ready:
		grounded.y = _sampler.sample_surface_height(grounded.x, grounded.z) + 0.005
	var holder := Node3D.new()
	holder.position = grounded
	_waypoints_root.add_child(holder)

	var model := _instantiate_glb(WAYPOINT_PATH, WAYPOINT_SCALE)
	if model == null:
		model = Node3D.new()
		var oct := PrismMesh.new()
		oct.size = Vector3(0.14, 0.22, 0.14)
		var crystal := _mesh(model, oct, _material(Color("#72C5E2"), 0.25, 0.22))
		crystal.position.y = 0.16
	holder.add_child(model)

	var ring := TorusMesh.new()
	ring.inner_radius = 0.112
	ring.outer_radius = 0.128
	ring.rings = 36
	ring.ring_segments = 8
	var halo := _mesh(holder, ring, _light(ring_color, 0.72, 1))
	halo.position.y = 0.010

	holder.scale = Vector3.ONE * 0.08
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_property(holder, "scale", Vector3.ONE, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		holder.scale = Vector3.ONE

	_waypoint_nodes.append({"holder": holder, "model": model, "halo": halo, "phase": float(badge_index) * 0.9})
	if badge_index > 0:
		_waypoint_anchors.append({
			"index": badge_index,
			"city_id": city_id,
			"world_pos": grounded + Vector3(0.0, 0.34, 0.0)
		})


func _spawn_hub_ring(pos: Vector3, tone: Color) -> void:
	var grounded := pos
	if _sampler != null and _sampler.ready:
		grounded.y = _sampler.sample_surface_height(grounded.x, grounded.z) + 0.005
	var holder := Node3D.new()
	holder.position = grounded
	_waypoints_root.add_child(holder)
	var ring := TorusMesh.new()
	ring.inner_radius = 0.165
	ring.outer_radius = 0.192
	ring.rings = 36
	ring.ring_segments = 8
	var halo := _mesh(holder, ring, _light(tone, 0.85, 1))
	halo.position.y = 0.015
	_waypoint_nodes.append({"holder": holder, "model": null, "halo": halo, "phase": 1.7})


func _clear_waypoints() -> void:
	_clear_children(_waypoints_root)
	_waypoint_nodes.clear()
	_waypoint_anchors.clear()


func _clear_children(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _make_route_material(mode_idx: int, base_col: Color, glow_col: Color, ink_col: Color,
		speed: float, dash_f: float, dash_d: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = ROUTE_SHADER
	mat.render_priority = 2 if mode_idx == 0 else (1 if mode_idx == 1 else 0)
	mat.set_shader_parameter("line_mode", mode_idx)
	mat.set_shader_parameter("base_color", base_col)
	mat.set_shader_parameter("glow_color", glow_col)
	mat.set_shader_parameter("ink_color", ink_col)
	mat.set_shader_parameter("flow_speed", speed)
	mat.set_shader_parameter("dash_freq", dash_f)
	mat.set_shader_parameter("dash_duty", dash_d)
	mat.set_shader_parameter("fade_alpha", 1.0)
	return mat


func _curve(leg: Planner.Leg, start: Vector3, finish: Vector3, start_radius: float = 0.0, finish_radius: float = 0.0) -> Curve3D:
	# Build smooth horizontal XZ spline trimmed precisely to each city's outer stone perimeter (ZERO house piercing!).
	var start_xz := Vector3(start.x, 0.0, start.z)
	var finish_xz := Vector3(finish.x, 0.0, finish.z)
	var raw_via: Array[Vector3] = []
	for pixel: Vector2 in leg.via:
		raw_via.append(Vector3((pixel.x - 836.0) / 100.0, 0.0, (pixel.y - 470.5) / 100.0))
	var detailed := _detailed_road(leg)
	if not detailed.is_empty():
		raw_via.clear()
		for via: Vector2 in detailed["via"]:
			raw_via.append(Vector3(via.x, 0.0, via.y))
		if leg.from_city != str(detailed["from"]):
			raw_via.reverse()

	var first_target := raw_via[0] if not raw_via.is_empty() else finish_xz
	var last_source := raw_via[raw_via.size() - 1] if not raw_via.is_empty() else start_xz
	var direct_dist := start_xz.distance_to(finish_xz)

	var out_vec := first_target - start_xz
	var in_vec := finish_xz - last_source
	var gap := 0.022 if not detailed.is_empty() else 0.055
	var trim_a := minf(start_radius + 0.032, direct_dist * 0.34) if start_radius > 0.001 else 0.0
	var trim_b := minf(finish_radius + 0.032, direct_dist * 0.34) if finish_radius > 0.001 else 0.0
	if _hero_footprints.has(leg.from_city) and out_vec.length_squared() > 0.0001:
		var heading := Vector2(out_vec.x, out_vec.z).normalized()
		trim_a = footprint_exit(_hero_footprints[leg.from_city], heading) + gap
	if _hero_footprints.has(leg.to_city) and in_vec.length_squared() > 0.0001:
		var heading := Vector2(in_vec.x, in_vec.z).normalized()
		trim_b = footprint_exit(_hero_footprints[leg.to_city], heading) + gap
	var trimmed_start := start_xz + (out_vec.normalized() * trim_a if out_vec.length_squared() > 0.0001 else Vector3.ZERO)
	var trimmed_finish := finish_xz - (in_vec.normalized() * trim_b if in_vec.length_squared() > 0.0001 else Vector3.ZERO)

	var ctrl: Array[Vector3] = [trimmed_start]
	for vp: Vector3 in raw_via:
		ctrl.append(vp)
	if ctrl.size() == 1:
		var mid := (trimmed_start + trimmed_finish) * 0.5
		if leg.mode == Planner.SHIP and _sampler != null and _sampler.ready:
			# Gently bow open-water sea lanes toward the deeper side of the strait so ships sail over clear turquoise water!
			var dir := (trimmed_finish - trimmed_start)
			dir.y = 0.0
			if dir.length_squared() > 0.001:
				var side := dir.normalized().cross(Vector3.UP).normalized()
				var bow := clampf(direct_dist * 0.28, 0.18, 0.42)
				var cand_a := mid + side * bow
				var cand_b := mid - side * bow
				var ha := _sampler.sample_height(cand_a.x, cand_a.z)
				var hb := _sampler.sample_height(cand_b.x, cand_b.z)
				mid = cand_a if ha < hb else cand_b
		ctrl.append(mid)
	ctrl.append(trimmed_finish)

	var xz_curve := Curve3D.new()
	xz_curve.bake_interval = 0.015 if not detailed.is_empty() else 0.04
	for index: int in ctrl.size():
		var before := ctrl[maxi(0, index - 1)]
		var after := ctrl[mini(ctrl.size() - 1, index + 1)]
		var tangent := (after - before) / 6.0
		xz_curve.add_point(ctrl[index], -tangent, tangent)

	var total_len := maxf(xz_curve.get_baked_length(), 0.01)
	var sample_count := maxi(16, ceili(total_len / 0.030)) if not detailed.is_empty() else clampi(ceili(total_len / 0.10), 16, 84)
	var is_ship := leg.mode == Planner.SHIP
	var path := Curve3D.new()
	path.bake_interval = 0.025
	var sea_y := _sampler.get_sea_level() + 0.014 if (_sampler != null and _sampler.ready) else 0.014

	var sampled: Array[Vector3] = []
	for i: int in range(sample_count + 1):
		var t := float(i) / float(sample_count)
		var p := xz_curve.sample_baked(total_len * t, true)
		if _sampler != null and _sampler.ready:
			if is_ship:
				var port_ease := smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.84, 1.0, t))
				var end_y := _sampler.sample_surface_height(p.x, p.z)
				p.y = lerpf(end_y, sea_y, port_ease)
				p.y = maxf(p.y, sea_y)
			else:
				p.y = _sampler.sample_surface_height(p.x, p.z) + 0.004
		else:
			p.y = lerpf(start.y, finish.y, t) + sin(PI * t) * 0.12
		sampled.append(p)

	# Light 3-tap vertical smoothing on interior land samples to glide gracefully across ridges without losing contact.
	if not is_ship and _sampler != null and _sampler.ready and sampled.size() >= 3:
		var raw_y: PackedFloat32Array = PackedFloat32Array()
		raw_y.resize(sampled.size())
		for i: int in sampled.size():
			raw_y[i] = sampled[i].y
		for i: int in range(1, sampled.size() - 1):
			var avg_y := raw_y[i - 1] * 0.22 + raw_y[i] * 0.56 + raw_y[i + 1] * 0.22
			sampled[i].y = maxf(raw_y[i], avg_y)

	for i: int in sampled.size():
		var before := sampled[maxi(0, i - 1)]
		var after := sampled[mini(sampled.size() - 1, i + 1)]
		var tangent := (after - before) / 6.0
		path.add_point(sampled[i], -tangent, tangent)
	return path


func _build_curve_ribbon(path: Curve3D, half_width: float, y_offset: float, is_ship: bool = false) -> ArrayMesh:
	var length := path.get_baked_length()
	var steps := maxi(16, ceili(length / 0.050))
	var pts: Array[Vector3] = []
	var base_clearance := 0.018 if is_ship else 0.025
	for i: int in range(steps + 1):
		var d := length * float(i) / float(steps)
		var pt := path.sample_baked(d, true)
		if _sampler != null and _sampler.ready and not is_ship:
			var surface_y := _sampler.sample_surface_height(pt.x, pt.z)
			pt.y = maxf(pt.y, surface_y)
		pts.append(pt + Vector3(0.0, base_clearance + y_offset, 0.0))
	return _build_polyline_ribbon(pts, half_width, not is_ship, base_clearance + y_offset)


func _build_detailed_ribbon(path: Curve3D, half_width: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := path.get_baked_length()
	var steps := maxi(16, ceili(length / DETAILED_ROAD_STEP))
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, Registry.TERRAIN_LAYER)
	var previous := PackedVector3Array()
	for step: int in range(steps + 1):
		var fraction := float(step) / steps
		var at := fraction * length
		var center := path.sample_baked(at, false)
		var tangent := path.sample_baked(minf(at + 0.012, length), false) - path.sample_baked(maxf(0.0, at - 0.012), false)
		var across := Vector3(tangent.z, 0.0, -tangent.x).normalized()
		var width := half_width * lerpf(0.40, 1.0, smoothstep(0.0, 0.050, minf(at, length - at)))
		var row := PackedVector3Array()
		for side: int in [-1, 0, 1]:
			var point := center + across * width * side
			query.from = Vector3(point.x, 3.0, point.z)
			query.to = Vector3(point.x, -0.5, point.z)
			var hit := space.intersect_ray(query)
			# Both branches sample the same triangles. The sampler also covers
			# a scene being restored before the physics server has synced.
			var ground := _sampler.sample_surface_height(point.x, point.z)
			if not hit.is_empty():
				var contact: Vector3 = hit["position"]
				ground = maxf(_sampler.get_sea_level(), contact.y)
			point.y = ground + DETAILED_ROAD_LIFT
			row.append(point)
		if step > 0:
			for side: int in range(2):
				_add_road_quad(surface, previous, row, side, at, length / steps, length)
		previous = row
	return surface.commit()


func _add_road_quad(surface: SurfaceTool, previous: PackedVector3Array, row: PackedVector3Array,
	side: int, at: float, step_length: float, length: float) -> void:
	for index: int in [0, 2, 3, 0, 3, 1]:
		var current := index >= 2
		var column := side + (index % 2)
		var distance := at if current else at - step_length
		surface.set_uv(Vector2(distance, column * 0.5))
		surface.set_uv2(Vector2(minf(distance, length - distance), 0.0))
		surface.add_vertex(row[column] if current else previous[column])


func _build_polyline_ribbon(pts: Array[Vector3], half_width: float, conform_edges: bool = false, edge_clearance: float = 0.032) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	if pts.size() < 2:
		return surface.commit()
	var dist := 0.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_u := 0.0
	var use_sampler := conform_edges and _sampler != null and _sampler.ready
	for i: int in pts.size():
		var p := pts[i]
		if i > 0:
			dist += pts[i - 1].distance_to(p)
		var before := pts[maxi(0, i - 1)]
		var after := pts[mini(pts.size() - 1, i + 1)]
		var tangent := (after - before)
		tangent.y = 0.0
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		var left_pt := p - right * half_width
		var right_pt := p + right * half_width
		if use_sampler:
			var left_y := _sampler.sample_surface_height(left_pt.x, left_pt.z) + edge_clearance
			var right_y := _sampler.sample_surface_height(right_pt.x, right_pt.z) + edge_clearance
			left_pt.y = maxf(p.y, left_y)
			right_pt.y = maxf(p.y, right_y)
		if i > 0:
			surface.set_uv(Vector2(prev_u, 0.0))
			surface.add_vertex(prev_l)
			surface.set_uv(Vector2(dist, 0.0))
			surface.add_vertex(left_pt)
			surface.set_uv(Vector2(dist, 1.0))
			surface.add_vertex(right_pt)

			surface.set_uv(Vector2(prev_u, 0.0))
			surface.add_vertex(prev_l)
			surface.set_uv(Vector2(dist, 1.0))
			surface.add_vertex(right_pt)
			surface.set_uv(Vector2(prev_u, 1.0))
			surface.add_vertex(prev_r)
		prev_l = left_pt
		prev_r = right_pt
		prev_u = dist
	return surface.commit()


func _build_fallback_pawn() -> Node3D:
	var root := Node3D.new()
	var gold := _material(GOLD_HALO, 0.60, 0.34)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.11
	cyl.height = 0.24
	var m := _mesh(root, cyl, gold)
	m.position.y = 0.12
	return root


func _mesh(parent: Node3D, geometry: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = geometry
	result.material_override = material
	if material is StandardMaterial3D and (material as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _light(color: Color, opacity: float, priority: int = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, opacity)
	material.render_priority = priority
	return material
