extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const CLOTH := preload("res://shaders/world_atlas_fabric.gdshader")
const Planner := preload("res://core/travel_planner.gd")
const JourneyStage := preload("res://scenes/world_map/atlas_travel_stage.gd")
const JourneyJournal := preload("res://scenes/world_map/atlas_travel_journal.gd")
const MAP_ASSET := "res://assets/3d/world_map.glb"
const MAP_DATA := "res://data/maps/world_map_data.json"
const CABIN := "res://scenes/room/room_explorer.tscn"
const DRAWER_WIDTH := 486.0
const DRAWER_MARGIN := 42.0
const DRAG_DEAD_ZONE := 9.0
const REGION_MASK := 0b111
const HOVER_TINT := Color("#F9BE6F")
const SELECT_TINT := Color("#85C6F2")
const CITY_LIFT := 0.122
const CITY_SCALE := 1.08


enum ViewMode { WORLD, CONTINENT }
enum PieceKind { CONTINENT, REGION, CITY }


class Piece extends RefCounted:
	var details: Dictionary
	var kind: PieceKind
	var model: Node3D
	var rim_mesh: MeshInstance3D
	var rim: StandardMaterial3D
	var rest: Vector3
	var rest_scale: Vector3
	var continent_id: String
	var region_id: String
	var height: float
	var materials: Dictionary[StandardMaterial3D, StandardMaterial3D] = {}
	var shade := 1.0
	var rim_tint := HOVER_TINT
	var rim_opacity := 0.0
	var rim_target := 0.0


var _return_scene := CABIN
var _title_font: SystemFont
var _body_font: SystemFont
var _render: SubViewport
var _stage: Node3D
var _camera: Camera3D
var _pieces: Dictionary[String, Piece] = {}
var _cities: Dictionary[String, Piece] = {}
var _continents: Array[Piece] = []
var _mode := ViewMode.WORLD
var _active: Piece
var _hovered: Piece
var _supporting_region: Piece
var _selected: Piece
var _changing_view := false
var _world_camera: Dictionary
var _atlas_title: String
var _world_back: Button
var _cabin_back: Button
var _heading_label: Label
var _heading_subtitle: Label
var _legend_label: Label
var _world_name: VBoxContainer
var _world_name_label: Label
var _hud: Control
var _blocked: Array[Control] = []
var _nameplate: PanelContainer
var _name_label: Label
var _drawer_slot: Control
var _drawer: PanelContainer
var _drawer_title: Label
var _drawer_subtitle: Label
var _description: Label
var _tags: HFlowContainer
var _journal_scroll: ScrollContainer
var _journey_journal: JourneyJournal
var _depart_button: Button
var _route_button: Button
var _planner := Planner.new()
var _journey_stage: JourneyStage
var _plan: Planner.Itinerary
var _traveling := false
var _viewing_route := false
var _journey_rng := RandomNumberGenerator.new()
var _status_date: Label
var _status_city: Label
var _status_supplies: Label
var _status_badges: HBoxContainer
var _last_buffs := PackedStringArray()
var _date_pulse := 0.0
var _drawer_motion: Tween
var _pan := Vector3.ZERO
var _center := Vector3.ZERO
var _distance: float
var _distance_target: float
var _home_distance: float
var _camera_limits: Vector2
var _pan_bounds: Vector2
var _camera_pitch: float
var _drawer_shift := 0.0
var _aim_height := 0.0
var _city_pan := Vector3.ZERO
var _city_distance: float
var _continent_pan := Vector3.ZERO
var _continent_distance: float
var _cursor := Vector2.ZERO
var _press_at := Vector2.ZERO
var _held := false
var _dragging := false
var _touch := false
var _pointer_known := false
var _pending_click := false
var _click_at := Vector2.ZERO
var _time := 0.0


func _ready() -> void:
	var context := SceneTransition.take_context()
	_return_scene = str(context.get("return_scene", CABIN))
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()
	var data := WorldBlackboard.read_config(MAP_DATA)
	_planner.configure(data)
	_journey_rng.randomize()
	_atlas_title = str(data.get("title", "人之世界"))
	_world_camera = data["world_camera"]
	_apply_camera_data(_world_camera, false)
	_build_stage()
	_build_hud(_atlas_title)
	if not ResourceLoader.exists(MAP_ASSET, "PackedScene"):
		_show_asset_message()
		return
	var packed := ResourceLoader.load(MAP_ASSET, "PackedScene") as PackedScene
	if packed == null:
		_show_asset_message()
		return
	var model := packed.instantiate() as Node3D
	_stage.add_child(model)
	_install_atlas(model, data["continents"])
	_journey_stage = JourneyStage.new()
	_stage.add_child(_journey_stage)
	WorldBlackboard.world_time_changed.connect(_refresh_date)
	WorldBlackboard.state_changed.connect(_refresh_travel_state)
	WorldBlackboard.buffs_changed.connect(_refresh_status)
	_refresh_date()
	_refresh_status()
	_restore_context(context.get("atlas", {}))


func get_save_context() -> Dictionary:
	var city_selected := _selected != null and _selected.kind == PieceKind.CITY
	var offset := _continent_pan if city_selected else _pan
	return {"atlas": {
		"continent": str(_active.details["id"]) if _active != null else "",
		"selected": str(_selected.details["id"]) if _selected != null else "",
		"route_overview": _viewing_route, "pan": [offset.x, offset.z],
		"distance": _continent_distance if city_selected else _distance_target
	}}


func _restore_context(data: Dictionary) -> void:
	if data.is_empty():
		return
	var group: Piece = _pieces.get(str(data.get("continent", "")))
	if group != null and group.kind == PieceKind.CONTINENT:
		_change_view(group, false)
	var pan: Variant = data.get("pan", [])
	if pan is Array and pan.size() == 2:
		_pan = _clamp_pan(Vector3(float(pan[0]), 0.0, float(pan[1])))
	_distance_target = clampf(float(data.get("distance", _home_distance)), _camera_limits.x, _camera_limits.y)
	_distance = _distance_target
	var selected: Piece = _pieces.get(str(data.get("selected", "")))
	if selected != null and selected.kind != PieceKind.CONTINENT:
		_select(selected)
		if _plan != null and _viewing_route != bool(data.get("route_overview", false)):
			_viewing_route = not _viewing_route
			_frame_selection(selected)
			_refresh_travel_page()


func get_dice_hud_items() -> Array[CanvasItem]:
	return [_hud]


func _build_stage() -> void:
	var surface := SubViewportContainer.new()
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.stretch = true
	add_child(surface)
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_render = SubViewport.new()
	_render.msaa_3d = Viewport.MSAA_4X
	_render.world_3d = World3D.new()
	_render.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	surface.add_child(_render)
	_stage = Node3D.new()
	_render.add_child(_stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#241A15")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#EEE9DC")
	environment.ambient_light_energy = 0.60
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#8199AC")
	sky_material.sky_horizon_color = Color("#D7BF9F")
	sky_material.ground_horizon_color = Color("#6A4430")
	sky_material.ground_bottom_color = Color("#302019")
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky = sky
	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)

	var table := MeshInstance3D.new()
	var tabletop := PlaneMesh.new()
	tabletop.size = Vector2(120.0, 120.0)
	table.mesh = tabletop
	table.position.y = -0.183
	var fabric := ShaderMaterial.new()
	fabric.shader = CLOTH
	table.material_override = fabric
	_stage.add_child(table)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-54, -32, 0)
	key.light_color = Color("#FFECD5")
	key.light_energy = 0.70
	key.light_angular_distance = 2.3
	key.shadow_enabled = true
	key.shadow_bias = 0.065
	key.shadow_normal_bias = 0.34
	key.shadow_blur = 2.35
	key.shadow_opacity = 0.85
	key.directional_shadow_max_distance = 42.0
	_stage.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-38, 138, 0)
	fill.light_color = Color("#C6DDF2")
	fill.light_energy = 0.26
	_stage.add_child(fill)

	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.near = 0.15
	_camera.far = 125.0
	_camera.current = true
	_stage.add_child(_camera)
	_pose_camera()


func _install_atlas(model: Node3D, groups: Array) -> void:
	for config: Dictionary in groups:
		var group := _install_piece(model, config, null, PieceKind.CONTINENT, "rim")
		if group == null:
			continue
		_continents.append(group)
		for region: Dictionary in config["regions"]:
			var plate := _install_piece(group.model, region, group, PieceKind.REGION, "rim")
			if plate == null:
				continue
			for data: Dictionary in region["cities"]:
				_install_piece(plate.model, data, plate, PieceKind.CITY, "ring")
				for site: Dictionary in data.get("sites", []):
					_install_piece(plate.model, site, plate, PieceKind.CITY, "ring")


func _install_piece(parent: Node3D, details: Dictionary, owner_piece: Piece, kind: PieceKind, rim_key: String) -> Piece:
	var model := parent.get_node_or_null(str(details["node"])) as Node3D
	var edge := model.get_node_or_null(str(details[rim_key])) as MeshInstance3D if model != null else null
	if model == null or edge == null:
		push_error("舆图缺少配置所指的网格 %s" % details["node"])
		return null
	var piece := Piece.new()
	piece.details = details
	piece.kind = kind
	piece.model = model
	piece.rest = model.position
	piece.rest_scale = model.scale
	piece.rim_mesh = edge
	piece.rim = StandardMaterial3D.new()
	piece.rim.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	piece.rim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	piece.rim.cull_mode = BaseMaterial3D.CULL_DISABLED
	piece.rim.albedo_color = Color(HOVER_TINT, 0.0)
	edge.material_override = piece.rim
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	edge.hide()
	_pieces[str(details["id"])] = piece
	if kind == PieceKind.CONTINENT:
		return piece
	piece.continent_id = str(owner_piece.details["id"]) if kind == PieceKind.REGION else owner_piece.continent_id
	if kind == PieceKind.CITY:
		piece.region_id = str(owner_piece.details["id"])
		_cities[str(details["node"])] = piece
	var mesh := model as MeshInstance3D
	piece.height = mesh.get_aabb().end.y
	var outline := mesh.mesh.create_trimesh_shape()
	# Queries address the active continent's bits, so distant geometry cannot block detail picking.
	var layer := 1 << (_continents.size() - 1) if kind == PieceKind.REGION else 1 << (_continents.size() + 2)
	_add_collider(mesh, outline, piece, layer)
	var seat := Node3D.new()
	mesh.get_parent().add_child(seat)
	seat.transform = mesh.transform
	if kind == PieceKind.REGION:
		seat.reparent(_stage)
	_add_collider(seat, outline, piece, layer << 6)
	_tintable_surfaces(mesh, _pieces[piece.continent_id])
	return piece


func _tintable_surfaces(mesh: MeshInstance3D, group: Piece) -> void:
	for index: int in mesh.mesh.get_surface_count():
		var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
		if original == null:
			continue
		var tint := group.materials.get(original) as StandardMaterial3D
		if tint == null:
			tint = original.duplicate() as StandardMaterial3D
			group.materials[original] = tint
		mesh.set_surface_override_material(index, tint)


func _add_collider(parent: Node3D, outline: ConcavePolygonShape3D, piece: Piece, mask: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = mask
	body.collision_mask = 0
	body.set_meta(&"atlas_piece", str(piece.details["id"]))
	var shape_node := CollisionShape3D.new()
	shape_node.shape = outline
	parent.add_child(body)
	body.add_child(shape_node)


func _pose_camera() -> void:
	var covered_width := DRAWER_WIDTH + DRAWER_MARGIN
	var half_view_height := _distance * tan(deg_to_rad(_camera.fov) * 0.5)
	var shift := half_view_height * _drawer_shift * covered_width / maxf(size.y, 1.0)
	var point := _center + _pan + Vector3(shift, _aim_height, 0.0)
	var arm := _distance + shift * 0.22
	_camera.position = point + Vector3(0.0, sin(_camera_pitch), cos(_camera_pitch)) * arm
	_camera.look_at(point, Vector3.UP)


func _process(delta: float) -> void:
	_time += delta
	_pose_camera()
	var fade := 1.0 - exp(-delta * 12.0)
	for piece: Piece in _pieces.values():
		var breath := 0.87 + sin(_time * 4.1) * 0.10 if piece == _hovered and piece != _selected else 1.0
		piece.rim_opacity = lerpf(piece.rim_opacity, piece.rim_target * breath, fade)
		piece.rim.albedo_color = piece.rim.albedo_color.lerp(Color(piece.rim_tint, piece.rim_opacity), fade)
		piece.rim_mesh.visible = piece.rim.albedo_color.a > 0.012
	for group: Piece in _continents:
		var target := 0.63 if _active != null and group != _active else 1.0
		if absf(group.shade - target) < 0.001:
			continue
		group.shade = lerpf(group.shade, target, fade)
		for original: StandardMaterial3D in group.materials:
			var base := original.albedo_color
			var tint := group.materials[original]
			tint.albedo_color = Color(base.r * group.shade, base.g * group.shade, base.b * group.shade, base.a)
			tint.emission_energy_multiplier = original.emission_energy_multiplier * group.shade
	if _nameplate.visible and _hovered != null:
		_place_nameplate()
	if not _traveling and _journey_stage != null and _cities.has(WorldBlackboard.current_city_id):
		_journey_stage.park(_city_seat(WorldBlackboard.current_city_id, true))


func _physics_process(_delta: float) -> void:
	if _changing_view or _traveling or JournalUI.is_open():
		return
	if _pending_click:
		_pending_click = false
		var chosen := _pick_target(_click_at, true)
		if _mode == ViewMode.WORLD and chosen != null and chosen.kind == PieceKind.CONTINENT:
			_change_view(chosen)
			return
		_select(chosen)
		if _changing_view:
			return
	var hit: Piece
	if _pointer_known and not _touch and not _held and not _is_hud(_cursor):
		hit = _pick_target(_cursor)
	_set_hover(hit)


func _pick_target(point: Vector2, allow_world_city: bool = false) -> Piece:
	var hit := _pick(point, false, allow_world_city)
	# A raised object can leave its own resting projection during a mouse hover.
	if _hovered != null and hit != _hovered and (hit == null or hit.kind < _hovered.kind):
		if _pick(point, true) == _hovered:
			return _hovered
	return hit


func _pick(point: Vector2, rest := false, allow_world_city: bool = false) -> Piece:
	var regions := REGION_MASK if _active == null else 1 << _continents.find(_active)
	if rest:
		regions <<= 6
	var screen := _view_point(point)
	var origin := _camera.project_ray_origin(screen)
	var target := origin + _camera.project_ray_normal(screen) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	var space := _render.world_3d.direct_space_state
	var hit: Dictionary
	if not rest or _mode == ViewMode.CONTINENT:
		query.collision_mask = regions << 3
		hit = space.intersect_ray(query)
	if hit.is_empty():
		query.collision_mask = regions
		hit = space.intersect_ray(query)
	var collider := hit.get("collider") as CollisionObject3D
	if collider == null:
		return null
	var piece: Piece = _pieces.get(str(collider.get_meta(&"atlas_piece")))
	if _mode == ViewMode.WORLD and (not allow_world_city or piece.kind != PieceKind.CITY):
		return _pieces[piece.continent_id]
	return piece


func _view_point(point: Vector2) -> Vector2:
	return point * Vector2(_render.size) / size.max(Vector2.ONE)


func _set_hover(piece: Piece) -> void:
	if piece == _hovered:
		return
	var previous := _hovered
	var previous_support := _supporting_region
	_hovered = piece
	_supporting_region = null
	# Keep a raised plate steady when the cursor passes from it onto its own sculpture.
	if piece != null and piece.kind == PieceKind.CITY:
		var seat: Piece = _pieces[piece.region_id]
		if seat == previous or seat == previous_support:
			_supporting_region = seat
	_pose_piece(previous)
	_pose_piece(piece)
	if previous_support != null and previous_support != piece and previous_support != previous:
		_pose_piece(previous_support)
	_world_name.hide()
	_nameplate.hide()
	if piece == null or piece == _selected:
		return
	if piece.kind == PieceKind.CONTINENT:
		_world_name_label.text = str(piece.details["name"])
		_world_name.show()
		Motion.fade_in(_world_name, 0.24)
	else:
		_name_label.text = str(piece.details["name"])
		_nameplate.reset_size()
		_place_nameplate()
		_nameplate.show()
		Motion.fade_in(_nameplate, 0.18)
	AudioManager.play_sfx("ui_hover")


func _select(piece: Piece) -> void:
	if _traveling or piece == _selected:
		return
	var previous := _selected
	_selected = piece
	_viewing_route = false
	_refresh_plan()
	if _plan != null:
		_viewing_route = piece.continent_id != _cities[WorldBlackboard.current_city_id].continent_id
	_pose_piece(previous)
	_pose_piece(piece)
	_nameplate.hide()
	_frame_selection(previous)
	if piece == null:
		if _drawer.visible:
			_drawer_motion = Motion.slide_drawer_out(_drawer, DRAWER_WIDTH + 50.0)
			_drawer_motion.finished.connect(_drawer.hide)
		return
	_populate_journal(piece)
	if not _drawer.visible:
		_drawer.show()
		_drawer_motion = Motion.slide_drawer_in(_drawer, DRAWER_WIDTH + 50.0)
	elif previous == null:
		_drawer_motion = Motion.slide_drawer_in(_drawer, _drawer.position.x)
	AudioManager.play_sfx("page_flip")


func _frame_selection(previous: Piece) -> void:
	var city := _selected != null and _selected.kind == PieceKind.CITY
	var was_city := previous != null and previous.kind == PieceKind.CITY
	var shift := 1.0 if city else (0.84 if _selected != null else 0.0)
	Motion.spring(self, ^"_drawer_shift", _drawer_shift, shift, 0.50, 8.4, 7.0)
	if not city and not was_city:
		return

	var height := 0.0
	var pan := _continent_pan
	if city:
		if not was_city:
			_continent_pan = _pan
			_continent_distance = _distance_target
		var focus := _route_camera() if _viewing_route and _plan != null else _city_camera()
		height = focus.y
		_city_pan = Vector3(focus.x, 0.0, focus.z) - _center
		pan = _city_pan
	_distance_target = _city_distance if city else _continent_distance
	_changing_view = true
	_pointer_known = false
	_set_hover(null)
	Motion.spring(self, ^"_aim_height", _aim_height, height, 0.62, 7.5, 5.5)
	Motion.spring(self, ^"_pan", _pan, pan, 0.62, 7.5, 5.5)
	var flight := Motion.spring(self, ^"_distance", _distance, _distance_target, 0.62, 7.5, 5.5)
	flight.finished.connect(func() -> void: _changing_view = false)


func _city_camera() -> Vector3:
	var bounds := (_selected.model as MeshInstance3D).get_aabb()
	var plate: Piece = _pieces[_selected.region_id]
	var local := plate.rest + _selected.rest + bounds.get_center() * _selected.rest_scale * CITY_SCALE
	local.y += CITY_LIFT
	# Frame miniature models of different sizes at a comparable scale.
	var span := bounds.size * _selected.rest_scale * CITY_SCALE
	_city_distance = span[span.max_axis_index()] * 8.8
	return plate.model.get_parent_node_3d().to_global(local)


func _route_camera() -> Vector3:
	var route := _journey_stage.bounds
	var available := maxf(size.x - DRAWER_WIDTH - DRAWER_MARGIN, size.x * 0.50)
	var frustum := 2.0 * tan(deg_to_rad(_camera.fov) * 0.5)
	var horizontal := (route.size.x + 1.6) * size.y / available
	var vertical := route.size.z + 1.5
	_city_distance = maxf(3.8, maxf(horizontal, vertical) / frustum * 1.10)
	var focus := route.get_center()
	focus.y = 0.18
	return focus


func _pose_piece(piece: Piece) -> void:
	if piece == null:
		return
	var chosen := piece == _selected
	var hover := piece == _hovered
	var lift := 0.0
	var tilt := Vector3.ZERO
	var rescale := 1.0
	match piece.kind:
		PieceKind.CONTINENT:
			lift = 0.32 if hover else (-0.063 if _active != null and piece != _active else 0.0)
		PieceKind.REGION:
			lift = 0.40 if chosen else (0.29 if hover or piece == _supporting_region else 0.0)
			tilt = Vector3(0.017, 0.0, -0.014) if (hover or piece == _supporting_region) and not chosen else Vector3.ZERO
		PieceKind.CITY:
			lift = CITY_LIFT if chosen else (0.094 if hover else 0.0)
			rescale = CITY_SCALE if chosen or hover else 1.0
	Motion.spring(piece.model, ^"position:y", piece.model.position.y, piece.rest.y + lift, 0.43, 7.2, 8.0)
	if piece.kind == PieceKind.REGION:
		Motion.spring(piece.model, ^"rotation", piece.model.rotation, tilt, 0.43, 8.2, 7.3)
	if piece.kind == PieceKind.CITY:
		Motion.spring(piece.model, ^"scale", piece.model.scale, piece.rest_scale * rescale, 0.40, 8.4, 7.3)
	piece.rim_tint = SELECT_TINT if chosen else HOVER_TINT
	piece.rim_target = 0.97 if chosen else (0.84 if hover else 0.0)


func _place_nameplate() -> void:
	var anchor := _hovered.model.to_global(Vector3.UP * _hovered.height) + Vector3.UP * 0.10
	var screen := _camera.unproject_position(anchor) * size / Vector2(_render.size)
	_nameplate.position = (screen + Vector2(-_nameplate.size.x * 0.5, -54.0)).clamp(
		Vector2(18.0, 12.0), size - _nameplate.size - Vector2(18.0, 12.0))


func _change_view(group: Piece, fly: bool = true) -> void:
	if _traveling:
		return
	_set_hover(null)
	_select(null)
	_active = group
	_mode = ViewMode.WORLD if group == null else ViewMode.CONTINENT
	_changing_view = fly
	_pending_click = false
	_pointer_known = false
	_held = false
	_dragging = false
	_world_back.visible = group != null
	_cabin_back.visible = group == null and WorldBlackboard.current_city_id == WorldBlackboard.HOME_CITY
	_heading_label.text = _atlas_title if group == null else str(group.details["name"])
	_heading_subtitle.text = "三大陆沙盘舆图" if group == null else str(group.details["subtitle"])
	_legend_label.text = "拖动平移 · 滚轮缩放 · 点击大陆或城池" if group == null else "拖动平移 · 滚轮缩放 · 点击领地或城池"
	for continent: Piece in _continents:
		_pose_piece(continent)
	var data: Dictionary = _world_camera if group == null else group.details["camera"]
	_apply_camera_data(data, fly)
	if fly:
		AudioManager.play_sfx("page_flip")


func _apply_camera_data(data: Dictionary, fly: bool) -> void:
	var center: Array = data["center"]
	var zoom: Array = data["zoom"]
	var bounds: Array = data["pan"]
	_camera_limits = Vector2(float(zoom[0]), float(zoom[1]))
	_pan_bounds = Vector2(float(bounds[0]), float(bounds[1]))
	_home_distance = float(data["distance"])
	var target_pitch := deg_to_rad(float(data["pitch"]))
	_distance_target = _home_distance
	var target := Vector3(float(center[0]), 0.0, float(center[1]))
	if not fly:
		_center = target
		_distance = _distance_target
		_camera_pitch = target_pitch
		return
	Motion.spring(self, ^"_camera_pitch", _camera_pitch, target_pitch, 0.62, 7.0, 5.6)
	Motion.spring(self, ^"_pan", _pan, Vector3.ZERO, 0.62, 7.0, 5.6)
	Motion.spring(self, ^"_center", _center, target, 0.62, 7.0, 5.6)
	var flight := Motion.spring(self, ^"_distance", _distance, _distance_target, 0.62, 7.0, 5.6)
	flight.finished.connect(func() -> void: _changing_view = false)


func _input(event: InputEvent) -> void:
	if JournalUI.handle_scene_input(event) or SceneTransition.is_busy() or _traveling:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _mode == ViewMode.CONTINENT:
			_change_view(null)
		elif _selected != null:
			_select(null)
		elif not _changing_view:
			_back()
		get_viewport().set_input_as_handled()
	elif _changing_view:
		return
	elif event is InputEventMouseButton:
		_pointer_button(event)
	elif event is InputEventMouseMotion:
		_pointer_motion(event)


func _pointer_button(event: InputEventMouseButton) -> void:
	_cursor = event.position
	_pointer_known = true
	_touch = event.device == InputEvent.DEVICE_ID_EMULATION
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _is_hud(event.position):
				return
			_held = true
			_dragging = false
			_press_at = event.position
			Motion.cancel(self, ^"_pan")
		elif _held:
			if _dragging:
				var bound := _clamp_pan(_pan)
				Motion.spring(self, ^"_pan", _pan, bound, 0.42, 8.0, 7.0)
			elif not _is_hud(event.position):
				_pending_click = true
				_click_at = event.position
			_held = false
			_dragging = false
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.pressed and not _is_hud(event.position):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.87)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.15)
			get_viewport().set_input_as_handled()


func _pointer_motion(event: InputEventMouseMotion) -> void:
	var previous := _cursor
	_cursor = event.position
	_pointer_known = true
	_touch = event.device == InputEvent.DEVICE_ID_EMULATION
	if not _held:
		return
	if not _dragging and _cursor.distance_to(_press_at) >= DRAG_DEAD_ZONE:
		_dragging = true
		previous = _press_at
	if _dragging:
		var desired := _pan + _table_point(previous) - _table_point(_cursor)
		var limited := _clamp_pan(desired)
		_pan = limited + (desired - limited) * 0.28
		get_viewport().set_input_as_handled()


func _table_point(point: Vector2) -> Vector3:
	var screen := _view_point(point)
	var plane := Plane(Vector3.UP, 0.0)
	var intersection: Variant = plane.intersects_ray(_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))
	return intersection if intersection is Vector3 else Vector3.ZERO


func _clamp_pan(pan: Vector3) -> Vector3:
	if _selected != null and _selected.kind == PieceKind.CITY:
		var radius := _distance_target * 0.24
		var span := Vector3(radius, 0.0, radius)
		return pan.clamp(_city_pan - span, _city_pan + span)
	var bounds := _pan_bounds * lerpf(1.0, 0.62, smoothstep(_camera_limits.x, _camera_limits.y, _distance_target))
	return Vector3(clampf(pan.x, -bounds.x, bounds.x), 0.0, clampf(pan.z, -bounds.y, bounds.y))


func _zoom(ratio: float) -> void:
	if _changing_view or _traveling:
		return
	var city := _selected != null and _selected.kind == PieceKind.CITY
	var limits := Vector2(0.72, 1.75) * _city_distance if city else _camera_limits
	_distance_target = clampf(_distance_target * ratio, limits.x, limits.y)
	Motion.spring(self, ^"_distance", _distance, _distance_target, 0.46, 8.8, 7.2)
	Motion.spring(self, ^"_pan", _pan, _clamp_pan(_pan), 0.46, 8.8, 7.2)


func _reset_view() -> void:
	if _changing_view or _traveling:
		return
	var city := _selected != null and _selected.kind == PieceKind.CITY
	_distance_target = _city_distance if city else _home_distance
	Motion.spring(self, ^"_distance", _distance, _distance_target, 0.48, 8.1, 7.4)
	Motion.spring(self, ^"_pan", _pan, _city_pan if city else Vector3.ZERO, 0.48, 8.1, 7.4)


func _back() -> void:
	if _traveling or WorldBlackboard.current_city_id != WorldBlackboard.HOME_CITY:
		return
	SceneTransition.change_to(_return_scene)


func _is_hud(point: Vector2) -> bool:
	for control: Control in _blocked:
		if control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return false


func _build_hud(title: String) -> void:
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var heading := Kit.create_folio_panel(Kit.PAPER, 26, 18, 8)
	_hud.add_child(heading)
	heading.position = Vector2(42, 35)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 2)
	heading.add_child(page)
	_heading_label = Kit.create_label(title, 44, Kit.INK, _title_font)
	page.add_child(_heading_label)
	_heading_subtitle = Kit.create_label("三大陆沙盘舆图", 19, Kit.BLUE, _body_font)
	page.add_child(_heading_subtitle)
	_blocked.append(heading)

	_world_back = Kit.create_tactile_button("← 返回世界总览", "secondary", _title_font, 23)
	_world_back.pressed.connect(_change_view.bind(null))
	_hud.add_child(_world_back)
	_world_back.position = Vector2(42.0, 174.0)
	_world_back.custom_minimum_size = Vector2(220.0, 48.0)
	_world_back.hide()
	_blocked.append(_world_back)

	_build_world_name()
	var legend := Kit.create_folio_panel(Kit.WASH, 17, 8, 4)
	_hud.add_child(legend)
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 42.0
	legend.offset_top = -83.0
	legend.offset_bottom = -36.0
	_legend_label = Kit.create_label("拖动平移 · 滚轮缩放 · 点击大陆或城池", 18, Kit.PAPER, _body_font)
	legend.add_child(_legend_label)
	_blocked.append(legend)
	var menu := JournalUI.make_toolbar(_title_font)
	_hud.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = 42
	menu.offset_top = -145
	menu.offset_bottom = -96
	_blocked.append(menu)
	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_END
	tools.add_theme_constant_override("separation", 10)
	_hud.add_child(tools)
	tools.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tools.offset_left = -530.0
	tools.offset_right = -42.0
	tools.offset_top = -94.0
	tools.offset_bottom = -36.0
	var zoom_out := Kit.create_tactile_button("−", "secondary", _title_font, 27)
	var zoom_in := Kit.create_tactile_button("＋", "secondary", _title_font, 27)
	var reset := Kit.create_tactile_button("重置视角", "secondary", _title_font, 22)
	zoom_out.custom_minimum_size.x = 60
	zoom_in.custom_minimum_size.x = 60
	zoom_out.pressed.connect(_zoom.bind(1.15))
	zoom_in.pressed.connect(_zoom.bind(0.87))
	reset.pressed.connect(_reset_view)
	tools.add_child(zoom_out)
	tools.add_child(zoom_in)
	tools.add_child(reset)
	_cabin_back = Kit.create_tactile_button("返回木屋", "secondary", _title_font, 23)
	_cabin_back.custom_minimum_size = Vector2(134.0, 48.0)
	_cabin_back.pressed.connect(_back)
	tools.add_child(_cabin_back)
	_blocked.append(tools)

	_nameplate = Kit.create_folio_panel(Kit.PAPER, 17, 7, 7)
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_nameplate)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 7)
	_nameplate.add_child(name_row)
	name_row.add_child(Kit.create_micro_icon("star", 16.0, Kit.AMBER))
	_name_label = Kit.create_label("", 24, Kit.INK, _title_font)
	name_row.add_child(_name_label)
	_nameplate.hide()
	_build_journal()
	_build_travel_status()


func _build_world_name() -> void:
	_world_name = VBoxContainer.new()
	_world_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_name.add_theme_constant_override("separation", 7)
	_hud.add_child(_world_name)
	_world_name.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_world_name.offset_left = -158.0
	_world_name.offset_right = 158.0
	_world_name.offset_top = 105.0
	_world_name_label = Kit.create_label("", 43, Color("#F7EAD0"), _title_font)
	_world_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_name_label.add_theme_color_override("font_shadow_color", Color("#211310"))
	_world_name_label.add_theme_constant_override("shadow_offset_y", 3)
	_world_name.add_child(_world_name_label)

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([Color("#D7AA6300"), Color("#EDBD72"), Color("#D7AA6300")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 316
	texture.height = 2
	var marker := TextureRect.new()
	marker.texture = texture
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_world_name.add_child(marker)
	_world_name.hide()


func _build_journal() -> void:
	_drawer_slot = Control.new()
	_drawer_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_drawer_slot)
	_drawer_slot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_drawer_slot.offset_left = -DRAWER_WIDTH - DRAWER_MARGIN
	_drawer_slot.offset_right = -DRAWER_MARGIN
	_drawer_slot.offset_top = 118.0
	_drawer_slot.offset_bottom = 958.0
	_drawer = Kit.create_folio_panel(Kit.PAPER, 23, 21, 11)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_slot.add_child(_drawer)
	_drawer_slot.resized.connect(_size_drawer)
	_drawer.minimum_size_changed.connect(_size_drawer, CONNECT_DEFERRED)
	_size_drawer()
	_blocked.append(_drawer)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_drawer.add_child(page)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 9)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("舆图手账", _title_font, 22, Kit.BLUE)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(ribbon)
	var close := Kit.create_tactile_button("合上", "subtle", _title_font, 21)
	close.custom_minimum_size = Vector2(79.0, 48.0)
	close.pressed.connect(_select.bind(null))
	heading.add_child(close)

	_drawer_title = Kit.create_label("", 42, Kit.INK, _title_font)
	page.add_child(_drawer_title)
	_drawer_subtitle = Kit.create_label("", 19, Kit.BLUE, _body_font)
	_drawer_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(_drawer_subtitle)
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_journal_scroll.custom_minimum_size.y = 180.0
	page.add_child(_journal_scroll)
	Kit.style_scrollbar(_journal_scroll.get_v_scroll_bar())
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_theme_constant_override("margin_right", 12)
	_journal_scroll.add_child(inset)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(content)
	_description = Kit.create_label("", 20, Kit.MUTED, _body_font)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_constant_override("line_spacing", 4)
	content.add_child(_description)
	content.add_child(Kit.create_label("相关地标", 22, Kit.INK, _title_font))
	_tags = HFlowContainer.new()
	_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags.add_theme_constant_override("h_separation", 8)
	_tags.add_theme_constant_override("v_separation", 8)
	content.add_child(_tags)
	_journey_journal = JourneyJournal.new()
	content.add_child(_journey_journal)
	_journey_journal.configure(_title_font, _body_font)
	_journey_journal.options_changed.connect(_refresh_travel_state)
	_journey_journal.manual_requested.connect(_perform_manual)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	page.add_child(actions)
	_route_button = Kit.create_tactile_button("查看全路线", "secondary", _title_font, 19)
	_route_button.custom_minimum_size = Vector2(128.0, 54.0)
	_route_button.pressed.connect(_toggle_route_view)
	actions.add_child(_route_button)
	_depart_button = Kit.create_tactile_button("启程前往", "primary", _title_font, 21)
	_depart_button.custom_minimum_size.y = 54
	_depart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depart_button.pressed.connect(_depart)
	actions.add_child(_depart_button)
	_drawer.hide()


func _size_drawer() -> void:
	_drawer.size = _drawer_slot.size


func _populate_journal(piece: Piece) -> void:
	var details := piece.details
	_drawer_title.text = str(details["name"])
	var context := str(_pieces[piece.continent_id].details["name"])
	if piece.kind == PieceKind.CITY:
		context += " / " + str(_pieces[piece.region_id].details["name"])
	var subtitle := str(details["subtitle"])
	var lead := str(_pieces[piece.region_id].details["name"]) if piece.kind == PieceKind.CITY else ""
	if not lead.is_empty():
		subtitle = subtitle.trim_prefix(lead + " · ")
	_drawer_subtitle.text = context + "\n" + subtitle
	_description.text = str(details["description"])
	for child: Node in _tags.get_children():
		_tags.remove_child(child)
		child.queue_free()
	for tag: String in details["tags"]:
		_tags.add_child(Kit.create_chip(tag, _body_font, 18))
	_refresh_travel_page()
	_journal_scroll.set_deferred("scroll_vertical", 0)
	_size_drawer.call_deferred()


func _build_travel_status() -> void:
	var status := Kit.create_folio_panel(Kit.PAPER, 15, 8, 5)
	_hud.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status.offset_left = -458.0
	status.offset_right = 458.0
	status.offset_top = 31.0
	status.offset_bottom = 83.0
	_blocked.append(status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	status.add_child(row)
	_status_date = Kit.create_label("", 20, Kit.INK, _title_font)
	row.add_child(_status_date)
	row.add_child(Kit.create_micro_icon("star", 12, Kit.AMBER))
	_status_city = Kit.create_label("", 20, Kit.BLUE, _title_font)
	row.add_child(_status_city)
	_status_supplies = Kit.create_label("", 19, Kit.INK, _body_font)
	row.add_child(_status_supplies)
	_status_badges = HBoxContainer.new()
	_status_badges.add_theme_constant_override("separation", 5)
	row.add_child(_status_badges)


func _refresh_date() -> void:
	_status_date.text = WorldBlackboard.date_text()
	if _traveling and _time > _date_pulse:
		_date_pulse = _time + 0.13
		_status_date.pivot_offset_ratio = Vector2(0.5, 0.5)
		Motion.spring(_status_date, ^"scale", Vector2.ONE * 1.055, Vector2.ONE, 0.24, 8.0, 7.0)


func _refresh_status() -> void:
	var city_id := WorldBlackboard.current_city_id
	if _traveling:
		_status_city.text = "赶路中 · " + _planner.city_name(city_id)
	else:
		_status_city.text = "所在 · " + _planner.city_name(city_id)
	_status_supplies.text = "干粮 %d    钱币 %s" % [
		WorldBlackboard.get_total_rations(), WorldBlackboard.format_currency(WorldBlackboard.currency_copper)
	]
	var buffs := WorldBlackboard.get_buff_names()
	if buffs != _last_buffs:
		_last_buffs = buffs
		for child: Node in _status_badges.get_children():
			_status_badges.remove_child(child)
			child.queue_free()
		for buff: String in buffs:
			var tone := Kit.VERMILLION if buff == WorldBlackboard.TRAVEL_FATIGUE_NAME else Kit.BLUE
			_status_badges.add_child(Kit.create_badge(buff, tone, _body_font, 16))
	_cabin_back.visible = _mode == ViewMode.WORLD and city_id == WorldBlackboard.HOME_CITY and not _traveling


func _refresh_travel_state() -> void:
	_refresh_status()
	if not _traveling:
		_refresh_plan()
		_refresh_travel_page()


func _refresh_plan() -> void:
	var plan: Planner.Itinerary
	if _selected != null and _selected.kind == PieceKind.CITY:
		plan = _planner.plan(WorldBlackboard.current_city_id, str(_selected.details["node"]),
			_journey_journal.transport, _journey_journal.posture, WorldBlackboard.get_world_time())
	var rebuild := (_plan == null) != (plan == null)
	if _plan != null and plan != null:
		rebuild = _plan.path_cities != plan.path_cities
	_plan = plan
	if rebuild:
		var anchors: Dictionary[String, Vector3] = {}
		if plan != null:
			for city_id: String in plan.path_cities:
				anchors[city_id] = _city_seat(city_id, false)
		_journey_stage.set_itinerary(plan, anchors)


func _refresh_travel_page() -> void:
	if _plan != null:
		var names := PackedStringArray()
		for city_id: String in _plan.path_cities:
			names.append(_planner.city_name(city_id))
		_journey_journal.present_plan(_plan, " → ".join(names), _traveling)
		_route_button.show()
		_route_button.text = "城池特写" if _viewing_route else "查看全路线"
		_route_button.disabled = _traveling
		_depart_button.show()
		var affordable := WorldBlackboard.can_afford(_plan.fare)
		_depart_button.disabled = _traveling or not affordable
		if _traveling:
			_depart_button.text = "旅途进行中"
		elif not affordable:
			_depart_button.text = "船票不足 · 暂无法启程" if not WorldBlackboard.can_afford(_plan.ship_fare) else "车马费用不足"
		else:
			_depart_button.text = "强行启程 · 干粮不足" if _plan.ration_cost > WorldBlackboard.get_total_rations() else "启程前往"
		return
	_route_button.hide()
	_depart_button.hide()
	if _selected != null and _selected.kind == PieceKind.CITY and str(_selected.details["node"]) == WorldBlackboard.current_city_id:
		_journey_journal.present_manual(StoryletScheduler.get_available_storylets(WorldBlackboard.current_city_id))
	else:
		_journey_journal.hide()


func _perform_manual(storylet_id: String) -> void:
	if _traveling or _selected == null or str(_selected.details["node"]) != WorldBlackboard.current_city_id:
		return
	await StoryletScheduler.execute_storylet(storylet_id, WorldBlackboard.current_city_id)
	_refresh_travel_page()


func _toggle_route_view() -> void:
	if _changing_view or _traveling or _plan == null:
		return
	_viewing_route = not _viewing_route
	_frame_selection(_selected)
	_refresh_travel_page()


func _city_seat(city_id: String, follow_plate: bool) -> Vector3:
	var city := _cities[city_id]
	var plate := _pieces[city.region_id]
	var offset := Vector3(0.14 + city.rest_scale.x * 0.61, 0.011, 0.115)
	if follow_plate:
		return city.model.global_position + offset
	return plate.rest + city.rest + offset


func _depart() -> void:
	if _traveling or _changing_view or _plan == null:
		return
	_refresh_plan()
	var trip := _plan
	if trip == null:
		_refresh_travel_page()
		return
	var destination := trip.path_cities.back() as String
	if not WorldBlackboard.begin_city_travel(destination, trip.total_days, trip.ration_cost, trip.fare):
		_refresh_travel_page()
		return
	_traveling = true
	_pointer_known = false
	_held = false
	_dragging = false
	_pending_click = false
	_set_hover(null)
	if not _viewing_route:
		_viewing_route = true
		_frame_selection(_selected)
	_refresh_status()
	_refresh_travel_page()
	var encounter := StoryletScheduler.pick_en_route(trip, _journey_journal.posture, _journey_rng)
	if _changing_view:
		await get_tree().create_timer(0.64).timeout
	var raw_days := 0.0
	var weights := 0.0
	for leg: Planner.Leg in trip.legs:
		raw_days += leg.days
		weights += sqrt(leg.km)
	var elapsed := 0.0
	var animation := clampf(1.2 + trip.total_km / 2700.0, 1.2, 3.0)
	for index: int in trip.legs.size():
		var leg := trip.legs[index]
		var duration := animation * sqrt(leg.km) / weights
		var days := leg.days * trip.total_days / raw_days
		var sound := "travel_wave" if leg.mode == Planner.SHIP else "travel_step"
		AudioManager.play_sfx(sound)
		if encounter != null and encounter.leg_index == index:
			await _animate_leg(index, Vector2(0.0, 0.5), elapsed, days, duration * 0.5)
			await StoryletScheduler.run_en_route(encounter, leg.to_city)
			AudioManager.play_sfx(sound)
			await _animate_leg(index, Vector2(0.5, 1.0), elapsed, days, duration * 0.5)
		else:
			await _animate_leg(index, Vector2(0.0, 1.0), elapsed, days, duration)
		elapsed += days
	var result := WorldBlackboard.finish_city_travel()
	_journey_stage.park(_city_seat(destination, true))
	_traveling = false
	_viewing_route = false
	_refresh_travel_state()
	_journal_scroll.set_deferred("scroll_vertical", 0)
	_frame_selection(_selected)
	if bool(result.get("fatigue", false)):
		StoryletScheduler.show_hint("干粮不足，诺缇雅陷入了旅途疲惫。")
	StoryletScheduler.check_arrival(destination)


func _animate_leg(index: int, limits: Vector2, elapsed: float, days: float, duration: float) -> void:
	var move := func(progress: float) -> void:
		_journey_stage.follow(index, progress)
		WorldBlackboard.advance_city_travel(floori(elapsed + days * progress + 0.000001))
	var tween := create_tween()
	tween.tween_method(move, limits.x, limits.y, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished


func _exit_tree() -> void:
	if _traveling:
		WorldBlackboard.finish_city_travel()


func _show_asset_message() -> void:
	var empty := Kit.create_folio_panel(Kit.PAPER, 24, 18, 8)
	_hud.add_child(empty)
	empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	empty.add_child(Kit.create_label("舆图资产暂未载入", 24, Kit.INK, _title_font))
