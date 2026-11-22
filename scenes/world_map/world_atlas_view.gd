extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const CLOTH := preload("res://shaders/world_atlas_fabric.gdshader")
const Planner := preload("res://core/travel_planner.gd")
const Encounter := preload("res://core/encounter_engine.gd")
const JourneyStage := preload("res://scenes/world_map/atlas_travel_stage.gd")
const JourneyJournal := preload("res://scenes/world_map/atlas_travel_journal.gd")
const EncounterOverlay := preload("res://scenes/world_map/atlas_encounter_overlay.gd")
const ArrivalBanner := preload("res://ui/area_arrival_banner.gd")
const TerrainSampler := preload("res://scenes/world_map/world_terrain_sampler.gd")
const ChunkRegistry := preload("res://scenes/world_map/chunks/world_chunk_registry.gd")
const BiomeScatter := preload("res://scenes/world_map/world_biome_scatter.gd")
const WeatherStage := preload("res://scenes/world_map/world_weather_stage.gd")
const HeroAssets := preload("res://scenes/world_map/world_hero_assets.gd")
const RELIEF_SHADER := preload("res://shaders/world_relief_terrain_v2.gdshader")
const OCEAN_SHADER := preload("res://shaders/world_relief_ocean_v2.gdshader")
const LIGHTHOUSE_BEAM_SHADER := preload("res://shaders/lighthouse_beam.gdshader")
const STUDIO_HDRI_PATH := "res://assets/textures/world_v2/diorama_studio_env.hdr"

const RELIEF_ASSET := "res://assets/3d/world_v2/world_relief_world.glb"
const MAP_ASSET := "res://assets/3d/world_map.glb"
const MAP_DATA := "res://data/maps/world_map_data.json"
const CABIN := "res://scenes/room/room_explorer.tscn"
const DRAWER_WIDTH := 496.0
const DRAWER_MARGIN := 40.0
const DRAG_DEAD_ZONE := 9.0
const LAYER_TERRAIN := 1 << 0
const LAYER_CITY_BASE := 1 << 1
const HOVER_TINT := Color("#E5B456")
const SELECT_TINT := Color("#78B6DC")
const CITY_LIFT := 0.048
const CITY_SCALE := 1.07
const CITY_GLOBAL_SCALE := 0.76
const CITY_STRAIT_PORT_SCALE := 0.70
const ATLAS_PITCH_DEG := 48.0
const FOLLOW_PITCH_DEG := 49.0
const FOLLOW_LOOK_AHEAD := 0.62
const MAJOR_LIGHTHOUSE_PORTS: Array[String] = ["city_wind_port", "city_zanto_port", "city_west_port", "city_east_port"]
const LIGHTHOUSE_LANTERN_FALLBACK := Vector3(0.42, 1.09, 0.02)

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
	var ground_y := 0.0
	var outer_radius := 0.18
	var hero_half_extents := Vector2.ZERO
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
var _sampler: TerrainSampler
var _relief_mat: ShaderMaterial
var _ocean_mat: ShaderMaterial
var _cities_root: Node3D
var _terrain_mesh: MeshInstance3D
var _ocean_mesh: MeshInstance3D
var _frame_mesh: MeshInstance3D
var _mesh_stats: Dictionary = {}
var _telemetry_frames := 0
var _telemetry_logged := false
var _last_hover_hit := Vector3.ZERO
var _atlas_blend := 1.0
var _winter_snow_push := 0.0
var _wetness_boost := 0.0
var _manual_season_override := false
var _night_glow := 0.0
var _shadow_focus_dist := 36.0
var _hdri_loaded := false
var _biome_scatter: BiomeScatter
var _weather_stage: WeatherStage
var _lighthouse_multimesh: MultiMeshInstance3D
var _lighthouse_beam_mat: ShaderMaterial
var _lighthouse_entries: Array[Dictionary] = []
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _world_env: Environment
var _studio_sky_mat: Material
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
var _waypoint_badge_layer: Control
var _waypoint_badges: Array[PanelContainer] = []

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

var _travel_bar: PanelContainer
var _travel_date_lbl: Label
var _travel_km_lbl: Label
var _travel_dest_lbl: Label
var _speed_btn: Button
var _stop_btn: Button

var _hub_modal_shade: ColorRect
var _hub_modal_center: CenterContainer
var _hub_modal_card: PanelContainer
var _hub_modal_title: Label
var _hub_modal_route: Label
var _hub_modal_note: Label
var _hub_modal_confirm: Button
var _pending_hub_transport := ""

var _planner := Planner.new()
var _encounter_engine := Encounter.new()
var _journey_stage: JourneyStage
var _arrival_banner: ArrivalBanner
var _encounter_overlay: EncounterOverlay
var _plan: Planner.Itinerary
var _manual_mode := false
var _manual_waypoints: Array[String] = []
var _traveling := false
var _travel_paused := false
var _stop_requested := false
var _travel_speed := 1.0
var _viewing_route := false
var _journey_rng := RandomNumberGenerator.new()
var _forced_encounter_pool := ""
var _crossing_continent_id := ""

var _status_date: Label
var _status_city: Label
var _status_transport: Label
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
var _follow_active := false
var _follow_focus := Vector3.ZERO
var _follow_distance := 7.2

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
	_arrival_banner = ArrivalBanner.new()
	add_child(_arrival_banner)
	_encounter_overlay = EncounterOverlay.new()
	_encounter_overlay.configure(_encounter_engine)
	add_child(_encounter_overlay)
	if not ResourceLoader.exists(RELIEF_ASSET, "PackedScene"):
		_show_asset_message()
		return
	var relief_packed := ResourceLoader.load(RELIEF_ASSET, "PackedScene") as PackedScene
	if relief_packed == null:
		_show_asset_message()
		return
	_sampler = TerrainSampler.new()
	if not _sampler.load_from_meta():
		_show_asset_message()
		return
	var relief_root := relief_packed.instantiate() as Node3D
	_stage.add_child(relief_root)
	_install_relief_world(relief_root, data["continents"])
	_sampler.chunks = ChunkRegistry.new()
	_sampler.chunks.mount(_stage, _relief_mat, _ocean_mat)
	if ResourceLoader.exists(MAP_ASSET, "PackedScene"):
		var legacy_packed := ResourceLoader.load(MAP_ASSET, "PackedScene") as PackedScene
		if legacy_packed != null:
			var legacy_root := legacy_packed.instantiate() as Node3D
			_mount_city_miniatures(legacy_root, data["continents"])
			legacy_root.free()
	_install_biome_scatter()
	_install_port_lighthouse_beams()
	_weather_stage = WeatherStage.new()
	_weather_stage.name = "WorldWeatherStage"
	_stage.add_child(_weather_stage)
	var migurd: Piece = _cities.get("city_migurd")
	var migurd_chunk := _sampler.chunks.city_chunk("city_migurd")
	var migurd_mist_strength := 0.34 if migurd_chunk != null else (0.55 if migurd != null and migurd.hero_half_extents != Vector2.ZERO else 1.0)
	_weather_stage.build(_sampler, migurd_mist_strength, migurd_chunk.atmosphere_root if migurd_chunk != null else null)
	_journey_stage = JourneyStage.new()
	_journey_stage.set_terrain_sampler(_sampler)
	for city_node: String in _cities:
		var city: Piece = _cities[city_node]
		if city.hero_half_extents != Vector2.ZERO:
			_journey_stage.set_hero_footprint(city_node, city.hero_half_extents)
		elif _sampler.chunks.city_chunk(city_node) != null:
			_journey_stage.set_hero_footprint(city_node, Vector2.ONE * city.outer_radius)
	_stage.add_child(_journey_stage)
	_journey_stage.build_chunk_roads(_sampler.get_all_city_positions())
	WorldBlackboard.world_time_changed.connect(_refresh_date)
	WorldBlackboard.state_changed.connect(_refresh_travel_state)
	WorldBlackboard.buffs_changed.connect(_refresh_status)
	WorldBlackboard.transport_changed.connect(_on_transport_changed)
	_refresh_date()
	_refresh_status()
	_restore_context(context.get("atlas", {}))


func _exit_tree() -> void:
	if WorldBlackboard.world_time_changed.is_connected(_refresh_date):
		WorldBlackboard.world_time_changed.disconnect(_refresh_date)
	if WorldBlackboard.state_changed.is_connected(_refresh_travel_state):
		WorldBlackboard.state_changed.disconnect(_refresh_travel_state)
	if WorldBlackboard.buffs_changed.is_connected(_refresh_status):
		WorldBlackboard.buffs_changed.disconnect(_refresh_status)
	if WorldBlackboard.transport_changed.is_connected(_on_transport_changed):
		WorldBlackboard.transport_changed.disconnect(_on_transport_changed)
	if _traveling:
		WorldBlackboard.finish_city_travel()


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
	_render.use_debanding = true
	_render.world_3d = World3D.new()
	_render.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	surface.add_child(_render)
	_stage = Node3D.new()
	_render.add_child(_stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#241A15")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_sky_contribution = 0.42
	environment.ambient_light_color = Color("#C8D6E8")
	environment.ambient_light_energy = 0.36
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	var sky := Sky.new()
	var hdri_tex: Texture2D = null
	if ResourceLoader.exists(STUDIO_HDRI_PATH):
		hdri_tex = ResourceLoader.load(STUDIO_HDRI_PATH) as Texture2D
	if hdri_tex != null:
		var pano := PanoramaSkyMaterial.new()
		pano.panorama = hdri_tex
		pano.energy_multiplier = 1.0
		sky.sky_material = pano
		sky.radiance_size = Sky.RADIANCE_SIZE_256
		_studio_sky_mat = pano
		_hdri_loaded = true
	else:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = Color("#6D8CA8")
		sky_material.sky_horizon_color = Color("#D6BEA0")
		sky_material.ground_horizon_color = Color("#624232")
		sky_material.ground_bottom_color = Color("#2C1E18")
		sky.sky_material = sky_material
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		_studio_sky_mat = sky_material
		_hdri_loaded = false
	environment.sky = sky

	# Blender-matched AgX Filmic Tonemapping + Museum Post-Processing
	environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	environment.tonemap_exposure = 0.98

	var is_mobile_gpu := OS.has_feature("mobile")
	if not is_mobile_gpu and RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.ssao_enabled = true
		environment.ssao_radius = 0.42
		environment.ssao_intensity = 1.22
		environment.ssao_power = 1.48
		environment.ssao_detail = 0.65
		environment.ssil_enabled = true
		environment.ssil_radius = 1.85
		environment.ssil_intensity = 0.42
		environment.ssil_sharpness = 0.94

	# High-threshold soft bloom strictly for lighthouse beams, night windows & demon crystal tips (never snowy ridges!)
	environment.glow_enabled = true
	environment.glow_normalized = true
	environment.glow_hdr_threshold = 1.12
	environment.glow_intensity = 0.36
	environment.glow_strength = 0.85
	environment.glow_bloom = 0.08
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.00
	environment.adjustment_contrast = 1.09
	environment.adjustment_saturation = 1.06

	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)
	_world_env = environment

	var table := MeshInstance3D.new()
	var tabletop := PlaneMesh.new()
	tabletop.size = Vector2(120.0, 120.0)
	table.mesh = tabletop
	table.position.y = -0.342
	var fabric := ShaderMaterial.new()
	fabric.shader = CLOTH
	table.material_override = fabric
	_stage.add_child(table)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-36, -48, 0)
	key.light_color = Color("#FFE7C6")
	key.light_energy = 1.12
	key.light_angular_distance = 1.8
	key.shadow_enabled = true
	key.shadow_bias = 0.015
	key.shadow_normal_bias = 0.11
	key.shadow_blur = 1.45
	key.shadow_opacity = 0.82
	key.directional_shadow_split_1 = 0.14
	key.directional_shadow_split_2 = 0.34
	key.directional_shadow_split_3 = 0.66
	key.directional_shadow_blend_splits = true
	key.directional_shadow_max_distance = 36.0
	_stage.add_child(key)
	_key_light = key
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-34, 142, 0)
	fill.light_color = Color("#A2C3EC")
	fill.light_energy = 0.34
	_stage.add_child(fill)
	_fill_light = fill

	_camera = Camera3D.new()
	_camera.fov = 34.0
	_camera.near = 0.15
	_camera.far = 125.0
	_camera.current = true
	_stage.add_child(_camera)
	_pose_camera()


func _install_relief_world(relief_root: Node3D, groups: Array) -> void:
	_terrain_mesh = relief_root.find_child("TerrainSurface", true, false) as MeshInstance3D
	_ocean_mesh = relief_root.find_child("OceanPlane", true, false) as MeshInstance3D
	_frame_mesh = relief_root.find_child("DioramaFrame", true, false) as MeshInstance3D

	if _terrain_mesh != null:
		_relief_mat = ShaderMaterial.new()
		_relief_mat.shader = RELIEF_SHADER
		_relief_mat.set_shader_parameter("heightmap_tex", _sampler.height_texture)
		_relief_mat.set_shader_parameter("min_height", _sampler.min_height)
		_relief_mat.set_shader_parameter("max_height", _sampler.max_height)
		_relief_mat.set_shader_parameter("biome_splat_a", _sampler.splat_a_texture)
		_relief_mat.set_shader_parameter("biome_splat_b", _sampler.splat_b_texture)
		_relief_mat.set_shader_parameter("region_id_map", _sampler.region_id_texture)
		if _sampler.ao_curvature_texture != null:
			_relief_mat.set_shader_parameter("ao_curvature_tex", _sampler.ao_curvature_texture)
		if _sampler.tile_albedo_array != null:
			_relief_mat.set_shader_parameter("tile_albedo_array", _sampler.tile_albedo_array)
		if _sampler.tile_normal_array != null:
			_relief_mat.set_shader_parameter("tile_normal_array", _sampler.tile_normal_array)
		_relief_mat.set_shader_parameter("sea_level", _sampler.get_sea_level())
		_relief_mat.set_shader_parameter("atlas_blend", _atlas_blend)
		_relief_mat.set_shader_parameter("winter_snow_push", _winter_snow_push)
		_relief_mat.set_shader_parameter("wetness_boost", _wetness_boost)
		_terrain_mesh.material_override = _relief_mat
		_terrain_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		var body := StaticBody3D.new()
		body.collision_layer = LAYER_TERRAIN
		body.collision_mask = 0
		var shape_node := CollisionShape3D.new()
		shape_node.shape = _terrain_mesh.mesh.create_trimesh_shape()
		_terrain_mesh.add_child(body)
		body.add_child(shape_node)
	else:
		push_error("WorldAtlasView: TerrainSurface node missing in %s" % RELIEF_ASSET)

	if _ocean_mesh != null:
		_ocean_mat = ShaderMaterial.new()
		_ocean_mat.shader = OCEAN_SHADER
		_ocean_mat.set_shader_parameter("heightmap_tex", _sampler.height_texture)
		_ocean_mat.set_shader_parameter("min_height", _sampler.min_height)
		_ocean_mat.set_shader_parameter("max_height", _sampler.max_height)
		_ocean_mat.set_shader_parameter("sea_level", _sampler.get_sea_level())
		_ocean_mat.set_shader_parameter("atlas_blend", _atlas_blend)
		_ocean_mesh.material_override = _ocean_mat
		_ocean_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if _frame_mesh != null:
		_frame_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_refine_diorama_frame_materials(_frame_mesh)

	_mesh_stats = _collect_mesh_stats()

	for config: Dictionary in groups:
		var group := Piece.new()
		group.details = config
		group.kind = PieceKind.CONTINENT
		group.continent_id = str(config["id"])
		_pieces[str(config["id"])] = group
		_continents.append(group)
		for region: Dictionary in config["regions"]:
			var plate := Piece.new()
			plate.details = region
			plate.kind = PieceKind.REGION
			plate.continent_id = str(config["id"])
			plate.region_id = str(region["id"])
			_pieces[str(region["id"])] = plate


func _mount_city_miniatures(legacy_root: Node3D, groups: Array) -> void:
	_cities_root = Node3D.new()
	_cities_root.name = "GroundedCities"
	_stage.add_child(_cities_root)
	for cont_idx: int in groups.size():
		var config: Dictionary = groups[cont_idx]
		var cont_id := str(config["id"])
		var cont_piece: Piece = _pieces[cont_id]
		var city_layer := LAYER_CITY_BASE << cont_idx
		for region: Dictionary in config["regions"]:
			var reg_id := str(region["id"])
			for data: Dictionary in region["cities"]:
				_mount_single_city(legacy_root, data, cont_piece, reg_id, city_layer)
				for site: Dictionary in data.get("sites", []):
					_mount_single_city(legacy_root, site, cont_piece, reg_id, city_layer)


func _mount_single_city(legacy_root: Node3D, details: Dictionary, cont_piece: Piece, reg_id: String, city_layer: int) -> Piece:
	var node_name := str(details["node"])
	var model := legacy_root.find_child(node_name, true, false) as MeshInstance3D
	if model == null:
		push_error("舆图缺少城池网格 %s" % node_name)
		return null
	var edge := model.get_node_or_null(str(details["ring"])) as MeshInstance3D
	var old_parent := model.get_parent()
	if old_parent != null:
		old_parent.remove_child(model)
	_clear_owner_recursive(model)
	var chunk := _sampler.chunks.city_chunk(node_name)
	var parent := _cities_root if chunk == null else chunk.assets_root
	parent.add_child(model)

	var grounded_pos: Vector3
	if _sampler.has_city_position(node_name):
		grounded_pos = _sampler.get_city_position(node_name)
	else:
		var px: Array = details["pixel"]
		var wx := (float(px[0]) - 836.0) * 0.01
		var wz := (float(px[1]) - 470.5) * 0.01
		grounded_pos = Vector3(wx, _sampler.sample_height(wx, wz), wz)

	var base_scale := float(details.get("model_scale", 0.24))
	var scale_mul := CITY_STRAIT_PORT_SCALE if (node_name == "city_wind_port" or node_name == "city_zanto_port") else CITY_GLOBAL_SCALE
	var model_scale := base_scale * scale_mul
	# Gently embed lower half of pedestal (local Y 0..0.088) into flat terrace so base reads as a sleek thin stone foundation!
	var hide_plinth := chunk != null and chunk.hide_legacy_plinth
	var pedestal_embed := (0.162 if hide_plinth else 0.088) * model_scale
	if hide_plinth:
		model.mesh = HeroAssets.without_legacy_plinth(model.mesh)
	model.position = Vector3(grounded_pos.x, grounded_pos.y - pedestal_embed, grounded_pos.z)
	model.rotation = Vector3.ZERO
	model.scale = Vector3.ONE * model_scale
	model.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var piece := Piece.new()
	piece.details = details
	piece.kind = PieceKind.CITY
	piece.model = model
	piece.rest = model.position
	piece.rest_scale = model.scale
	piece.ground_y = grounded_pos.y
	piece.outer_radius = 0.93 * model_scale
	piece.continent_id = str(cont_piece.details["id"])
	piece.region_id = reg_id
	piece.height = maxf(0.18, model.get_aabb().end.y * model_scale - pedestal_embed)
	if edge != null:
		edge.position.y = 0.168 if hide_plinth else 0.096
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
	_cities[node_name] = piece

	var outline := model.mesh.create_trimesh_shape()
	_add_collider(model, outline, piece, city_layer)
	if _mount_hero_city(model, piece, cont_piece, city_layer):
		if chunk != null:
			chunk.add_city_lamps(grounded_pos, piece.hero_half_extents)
	else:
		_harmonize_city_materials(model, cont_piece)
	return piece


func _mount_hero_city(legacy: MeshInstance3D, piece: Piece, group: Piece, city_layer: int) -> bool:
	var city_node := str(piece.details["node"])
	var packed := HeroAssets.load_city(city_node, str(piece.details["id"]))
	if packed == null:
		return false
	var hero := packed.instantiate() as Node3D
	if hero == null:
		return false
	hero.name = &"HeroMiniature"
	legacy.add_child(hero)
	# Cancel the inherited scale at rest. Hover lift and its small scale pulse
	# continue to use the same city node and selection rules as the legacy mesh.
	var legacy_scale := legacy.scale.x
	hero.scale = Vector3.ONE / legacy_scale
	hero.position.y = (piece.ground_y - piece.rest.y) / legacy_scale
	var bounds := HeroAssets.mesh_bounds(hero)
	if not bounds.has_volume():
		legacy.remove_child(hero)
		hero.queue_free()
		return false
	legacy.layers = 0
	legacy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.height = maxf(piece.height, bounds.end.y + piece.ground_y - piece.rest.y)
	piece.hero_half_extents = Vector2(bounds.size.x, bounds.size.z) * 0.5
	piece.outer_radius = maxf(piece.outer_radius, piece.hero_half_extents.length())
	for part: MeshInstance3D in HeroAssets.mesh_nodes(hero):
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_harmonize_city_materials(part, group, false)
	var hit_anchor := Node3D.new()
	hit_anchor.position = bounds.get_center()
	hero.add_child(hit_anchor)
	var hit_box := BoxShape3D.new()
	hit_box.size = bounds.size
	_add_collider(hit_anchor, hit_box, piece, city_layer)
	return true


func _harmonize_city_materials(mesh: MeshInstance3D, group: Piece, restyle: bool = true) -> void:
	# Re-grade miniature architecture surfaces to match Notia's warm porcelain-glaze & matte antique-gold craft!
	for index: int in mesh.mesh.get_surface_count():
		var original := mesh.mesh.surface_get_material(index) as StandardMaterial3D
		if original == null:
			continue
		var tint := group.materials.get(original) as StandardMaterial3D
		if tint == null:
			tint = original.duplicate() as StandardMaterial3D
			var mname := original.resource_name.to_lower() if restyle else ""
			if mname.contains("ivory") or mname.contains("porcelain"):
				tint.albedo_color = Color("#E6DAC6")
				tint.roughness = 0.54
				tint.metallic = 0.0
				tint.clearcoat_enabled = true
				tint.clearcoat = 0.16
				tint.clearcoat_roughness = 0.38
				tint.rim_enabled = true
				tint.rim = 0.16
				tint.rim_tint = 0.45
			elif mname.contains("limestone") or mname.contains("stone"):
				tint.albedo_color = Color("#A89A84")
				tint.roughness = 0.76
				tint.metallic = 0.0
				tint.rim_enabled = true
				tint.rim = 0.12
				tint.rim_tint = 0.42
			elif mname.contains("brass") or mname.contains("gold"):
				tint.albedo_color = Color("#C49A4C")
				tint.metallic = 0.84
				tint.roughness = 0.28
			elif mname.contains("seamist") or mname.contains("blue"):
				tint.albedo_color = Color("#4E7590")
				tint.roughness = 0.48
				tint.metallic = 0.03
				tint.clearcoat_enabled = true
				tint.clearcoat = 0.20
				tint.clearcoat_roughness = 0.34
				tint.rim_enabled = true
				tint.rim = 0.18
				tint.rim_tint = 0.48
			elif mname.contains("terracotta") or mname.contains("terra"):
				tint.albedo_color = Color("#A85D4C")
				tint.roughness = 0.54
				tint.metallic = 0.02
				tint.clearcoat_enabled = true
				tint.clearcoat = 0.16
				tint.clearcoat_roughness = 0.38
				tint.rim_enabled = true
				tint.rim = 0.16
				tint.rim_tint = 0.45
			elif mname.contains("door") or mname.contains("dark"):
				tint.albedo_color = Color("#4A3222")
				tint.roughness = 0.78
				tint.set_meta(&"is_city_window", true)
			elif mname.contains("lamp") or mname.contains("honey"):
				tint.albedo_color = Color("#F2B86B")
				tint.emission_enabled = true
				tint.emission = Color("#E89B42")
				tint.emission_energy_multiplier = 0.65
				tint.set_meta(&"is_lighthouse_glass", true)
			tint.set_meta(&"base_albedo", tint.albedo_color)
			tint.set_meta(&"base_emission_energy", tint.emission_energy_multiplier)
			group.materials[original] = tint
		mesh.set_surface_override_material(index, tint)


func _install_biome_scatter() -> void:
	if _sampler == null or not _sampler.ready:
		return
	var city_exclusions: Array[Dictionary] = []
	for node_name: String in _cities:
		var cp: Piece = _cities[node_name]
		city_exclusions.append({
			"id": node_name,
			"pos": Vector2(cp.rest.x, cp.rest.z),
			"radius": cp.outer_radius,
		})
	_biome_scatter = BiomeScatter.new()
	_biome_scatter.name = "BiomeScatter"
	_stage.add_child(_biome_scatter)
	_biome_scatter.build_scatter(_sampler, city_exclusions)
	var contacts := _biome_scatter.hero_contacts()
	for node_name: String in _cities:
		var city: Piece = _cities[node_name]
		if city.hero_half_extents != Vector2.ZERO:
			contacts.append(Vector3(city.rest.x, city.outer_radius * 1.24, city.rest.z))
	HeroAssets.apply_ground(_relief_mat, contacts)


func _install_port_lighthouse_beams() -> void:
	_lighthouse_entries.clear()
	var init_phases: Array[float] = [0.35, 1.15, 2.05, 2.85]
	for i: int in MAJOR_LIGHTHOUSE_PORTS.size():
		var cid: String = MAJOR_LIGHTHOUSE_PORTS[i]
		if not _cities.has(cid):
			continue
		var piece: Piece = _cities[cid]
		var lantern_local := _find_lantern_centroid(piece.model as MeshInstance3D)
		_lighthouse_entries.append({
			"city_id": cid,
			"piece": piece,
			"lantern_local": lantern_local,
			"speed": 0.55 if i % 2 == 0 else -0.48,
			"phase": init_phases[i % init_phases.size()],
		})
	if _lighthouse_entries.is_empty():
		return

	var cone_mesh := _build_lighthouse_cone_mesh(1.08, 0.19, 14)
	_lighthouse_beam_mat = ShaderMaterial.new()
	_lighthouse_beam_mat.shader = LIGHTHOUSE_BEAM_SHADER
	_lighthouse_beam_mat.set_shader_parameter("beam_color", Color("#FFC868"))
	_lighthouse_beam_mat.set_shader_parameter("beam_intensity", 0.24)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cone_mesh
	mm.instance_count = _lighthouse_entries.size()

	_lighthouse_multimesh = MultiMeshInstance3D.new()
	_lighthouse_multimesh.name = "PortLighthouseBeams"
	_lighthouse_multimesh.multimesh = mm
	_lighthouse_multimesh.material_override = _lighthouse_beam_mat
	_lighthouse_multimesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_lighthouse_multimesh)
	_update_lighthouse_transforms()


static func _find_lantern_centroid(mesh_inst: MeshInstance3D) -> Vector3:
	if mesh_inst == null or mesh_inst.mesh == null:
		return LIGHTHOUSE_LANTERN_FALLBACK
	for s: int in mesh_inst.mesh.get_surface_count():
		var mat := mesh_inst.mesh.surface_get_material(s)
		if mat == null:
			continue
		var mname := mat.resource_name.to_lower()
		if mname.contains("lamp") or mname.contains("honey"):
			var arrays := mesh_inst.mesh.surface_get_arrays(s)
			var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
			if verts is PackedVector3Array and not (verts as PackedVector3Array).is_empty():
				var va: PackedVector3Array = verts
				var acc := Vector3.ZERO
				for v: Vector3 in va:
					acc += v
				return acc / float(va.size())
	return LIGHTHOUSE_LANTERN_FALLBACK


static func _build_lighthouse_cone_mesh(length: float, end_radius: float, sides: int) -> ArrayMesh:
	# Dual-opposing volumetric Fresnel lighthouse lens cones along +Z & -Z, angled -5.0 deg toward harbor water
	var pitch_down := deg_to_rad(-5.0)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var start_r := 0.015
	var rings := 2
	for dir_yaw: float in [0.0, PI]:
		var beam_basis := Basis(Vector3.UP, dir_yaw) * Basis(Vector3.RIGHT, pitch_down)
		var base_vertex := verts.size()
		for r_i: int in range(rings + 1):
			var t := float(r_i) / float(rings)
			var z_dist := lerpf(0.02, length, t)
			var rad := lerpf(start_r, end_radius, t)
			for k: int in range(sides):
				var ang := TAU * float(k) / float(sides)
				var local_p := beam_basis * Vector3(cos(ang) * rad, sin(ang) * rad, z_dist)
				var local_n := (beam_basis * Vector3(cos(ang), sin(ang), 0.14)).normalized()
				verts.append(local_p)
				norms.append(local_n)
				uvs.append(Vector2(float(k) / float(sides), t))

		for r_i: int in range(rings):
			var r0 := base_vertex + r_i * sides
			var r1 := base_vertex + (r_i + 1) * sides
			for k: int in range(sides):
				var kn := (k + 1) % sides
				indices.append_array([r0 + k, r0 + kn, r1 + kn, r0 + k, r1 + kn, r1 + k])

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _update_lighthouse_transforms() -> void:
	if _lighthouse_multimesh == null or _lighthouse_multimesh.multimesh == null:
		return
	var mm := _lighthouse_multimesh.multimesh
	for i: int in _lighthouse_entries.size():
		var entry: Dictionary = _lighthouse_entries[i]
		var piece: Piece = entry["piece"]
		var lantern_local: Vector3 = entry["lantern_local"]
		var world_origin: Vector3 = piece.model.transform * lantern_local
		var yaw: float = float(entry["phase"]) + _time * float(entry["speed"])
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), world_origin))


func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for child: Node in node.get_children():
		_clear_owner_recursive(child)


func _count_mesh_geometry(mesh_inst: MeshInstance3D) -> Dictionary:
	if mesh_inst == null or mesh_inst.mesh == null:
		return {"verts": 0, "tris": 0}
	var m := mesh_inst.mesh
	var verts := 0
	var tris := 0
	for s: int in m.get_surface_count():
		var arrays := m.surface_get_arrays(s)
		var v_arr: Variant = arrays[Mesh.ARRAY_VERTEX]
		if v_arr is PackedVector3Array:
			verts += (v_arr as PackedVector3Array).size()
		var i_arr: Variant = arrays[Mesh.ARRAY_INDEX]
		if i_arr is PackedInt32Array and not (i_arr as PackedInt32Array).is_empty():
			tris += (i_arr as PackedInt32Array).size() / 3
		elif v_arr is PackedVector3Array:
			tris += (v_arr as PackedVector3Array).size() / 3
	return {"verts": verts, "tris": tris}


func _collect_mesh_stats() -> Dictionary:
	var t := _count_mesh_geometry(_terrain_mesh)
	var o := _count_mesh_geometry(_ocean_mesh)
	var f := _count_mesh_geometry(_frame_mesh)
	return {
		"terrain_verts": int(t["verts"]),
		"terrain_tris": int(t["tris"]),
		"ocean_verts": int(o["verts"]),
		"ocean_tris": int(o["tris"]),
		"frame_verts": int(f["verts"]),
		"frame_tris": int(f["tris"]),
		"total_verts": int(t["verts"]) + int(o["verts"]) + int(f["verts"]),
		"total_tris": int(t["tris"]) + int(o["tris"]) + int(f["tris"]),
	}


func _refine_diorama_frame_materials(frame: MeshInstance3D) -> void:
	if frame == null or frame.mesh == null:
		return
	var walnut := StandardMaterial3D.new()
	walnut.albedo_color = Color("#FFFFFF")
	if _sampler != null and _sampler.walnut_albedo_texture != null:
		walnut.albedo_texture = _sampler.walnut_albedo_texture
		walnut.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	else:
		walnut.albedo_color = Color("#2C1A10")
	if _sampler != null and _sampler.walnut_normal_texture != null:
		walnut.normal_enabled = true
		walnut.normal_texture = _sampler.walnut_normal_texture
		walnut.normal_scale = 0.48
	walnut.uv1_triplanar = true
	walnut.uv1_triplanar_sharpness = 4.0
	walnut.uv1_scale = Vector3(0.42, 0.42, 0.42)
	walnut.roughness = 0.42
	walnut.metallic = 0.02
	walnut.clearcoat_enabled = true
	walnut.clearcoat = 0.24
	walnut.clearcoat_roughness = 0.28

	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#CCA352")
	brass.metallic = 0.85
	brass.roughness = 0.28

	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color("#46311B")
	bronze.metallic = 0.74
	bronze.roughness = 0.44

	for s: int in frame.mesh.get_surface_count():
		var orig := frame.mesh.surface_get_material(s)
		var mname := orig.resource_name.to_lower() if orig != null else ""
		if mname.contains("brass") or mname.contains("gold"):
			frame.set_surface_override_material(s, brass)
		elif mname.contains("bronze"):
			frame.set_surface_override_material(s, bronze)
		elif mname.contains("walnut"):
			frame.set_surface_override_material(s, walnut)
		else:
			frame.set_surface_override_material(s, walnut if s == 0 else (brass if s == 1 else bronze))


func get_m1_telemetry() -> Dictionary:
	var out := _mesh_stats.duplicate(true)
	out["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	out["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	out["fps"] = float(Engine.get_frames_per_second())
	out["atlas_blend"] = _atlas_blend
	out["terrain_samplers"] = 7
	out["ocean_samplers"] = 1
	out["m2_tile_vram_mb"] = _sampler.get_m2_vram_mb() if _sampler != null else 0.0
	if _biome_scatter != null:
		var sc := _biome_scatter.get_scatter_telemetry()
		out["biome_multimeshes"] = int(sc.get("multimesh_count", 0))
		out["biome_instances"] = int(sc.get("total_instances", 0))
		out["biome_instanced_tris"] = int(sc.get("total_instanced_tris", 0))
		out["biome_vram_kb"] = float(sc.get("buffer_vram_kb", 0.0))
		out["biome_migurd_props"] = int(sc.get("migurd_basin_props", 0))
		out["hero_cliffs"] = int(sc.get("hero_cliffs", 0))
		out["biome_species"] = sc.get("species", {})
	out["lighthouse_beams"] = _lighthouse_entries.size()
	out["renderer_method"] = str(RenderingServer.get_current_rendering_method())
	out["hdri_loaded"] = _hdri_loaded
	out["ao_baked"] = _sampler != null and _sampler.ao_curvature_texture != null
	out["shadow_focus_dist"] = _shadow_focus_dist
	out["winter_snow_push"] = _winter_snow_push
	out["wetness_boost"] = _wetness_boost
	out["weather"] = _weather_stage.get_weather_telemetry() if _weather_stage != null else {}
	return out


func get_biome_scatter() -> BiomeScatter:
	return _biome_scatter


func get_weather_stage() -> WeatherStage:
	return _weather_stage


func get_terrain_sampler() -> TerrainSampler:
	return _sampler


func set_season_climate(winter_snow: float, wetness: float) -> void:
	_manual_season_override = true
	_winter_snow_push = clampf(winter_snow, 0.0, 1.0)
	_wetness_boost = clampf(wetness, 0.0, 1.0)
	_sync_relief_shader_uniforms()


func clear_season_override() -> void:
	_manual_season_override = false
	_refresh_season_atmosphere()


func _sync_relief_shader_uniforms() -> void:
	if _relief_mat == null or _sampler == null or not _sampler.ready:
		return
	var hov_reg_idx := 0
	var hov_cont_idx := 0
	if _hovered != null:
		match _hovered.kind:
			PieceKind.CONTINENT:
				hov_cont_idx = _sampler.get_continent_index(str(_hovered.details["id"]))
			PieceKind.REGION:
				hov_reg_idx = _sampler.get_region_index(str(_hovered.details["id"]))
			PieceKind.CITY:
				hov_reg_idx = _sampler.get_region_index(_hovered.region_id)
	var sel_reg_idx := 0
	if _selected != null:
		if _selected.kind == PieceKind.REGION:
			sel_reg_idx = _sampler.get_region_index(str(_selected.details["id"]))
		elif _selected.kind == PieceKind.CITY:
			sel_reg_idx = _sampler.get_region_index(_selected.region_id)
	var act_cont_idx := _sampler.get_continent_index(str(_active.details["id"])) if _active != null else 0
	var cross_cont_idx := _sampler.get_continent_index(_crossing_continent_id) if not _crossing_continent_id.is_empty() else 0

	_relief_mat.set_shader_parameter("atlas_blend", _atlas_blend)
	_relief_mat.set_shader_parameter("hovered_region_idx", hov_reg_idx)
	_relief_mat.set_shader_parameter("selected_region_idx", sel_reg_idx)
	_relief_mat.set_shader_parameter("hovered_continent_idx", hov_cont_idx)
	_relief_mat.set_shader_parameter("active_continent_idx", act_cont_idx)
	_relief_mat.set_shader_parameter("crossing_continent_idx", cross_cont_idx)
	_relief_mat.set_shader_parameter("hover_pulse", sin(_time * 4.0) * 0.5 + 0.5)
	_relief_mat.set_shader_parameter("winter_snow_push", _winter_snow_push)
	_relief_mat.set_shader_parameter("wetness_boost", _wetness_boost)
	_relief_mat.set_shader_parameter("rain_cloud_boost", _wetness_boost)
	if _sampler.chunks != null:
		_sampler.chunks.sync_materials(_relief_mat)
	if _ocean_mat != null:
		_ocean_mat.set_shader_parameter("atlas_blend", _atlas_blend)
		_ocean_mat.set_shader_parameter("rain_cloud_boost", _wetness_boost)
	if _biome_scatter != null:
		_biome_scatter.sync_shader_uniforms(_atlas_blend, act_cont_idx, cross_cont_idx, _night_glow, _winter_snow_push, _wetness_boost)


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


func _add_collider(parent: Node3D, outline: Shape3D, piece: Piece, mask: int) -> void:
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
	if _follow_active and _journey_stage != null:
		var look_ahead := 0.14 if _travel_paused else FOLLOW_LOOK_AHEAD
		var pawn_pos := _journey_stage.get_pawn_world_position()
		var desired := Vector3(pawn_pos.x, 0.0, pawn_pos.z) + _journey_stage.get_pawn_forward_xz() * look_ahead
		var smooth := 1.0 - exp(-delta * 5.2)
		_follow_focus = _follow_focus.lerp(desired, smooth)
		_center = _center.lerp(_follow_focus, smooth)
		_pan = _pan.lerp(Vector3.ZERO, smooth)
		_distance = lerpf(_distance, _follow_distance, 1.0 - exp(-delta * 4.4))
		_camera_pitch = lerpf(_camera_pitch, deg_to_rad(FOLLOW_PITCH_DEG), 1.0 - exp(-delta * 4.4))
		_aim_height = lerpf(_aim_height, pawn_pos.y + 0.12, smooth)
		_drawer_shift = lerpf(_drawer_shift, 0.0, 1.0 - exp(-delta * 6.5))

	_pose_camera()
	_update_dynamic_shadow_focus()
	var target_blend := smoothstep(5.4, 15.8, _distance)
	_atlas_blend = lerpf(_atlas_blend, target_blend, 1.0 - exp(-delta * 6.5))
	_sync_relief_shader_uniforms()
	_update_lighthouse_transforms()
	if _weather_stage != null:
		var slot: int = int(WorldBlackboard.get_world_time().get("slot", 0))
		_weather_stage.update_atmosphere(delta, _distance, slot, _winter_snow_push, _wetness_boost)
	var fade := 1.0 - exp(-delta * 12.0)
	for piece: Piece in _pieces.values():
		if piece.rim == null or piece.rim_mesh == null:
			continue
		var breath := 0.87 + sin(_time * 4.1) * 0.10 if piece == _hovered and piece != _selected else 1.0
		piece.rim_opacity = lerpf(piece.rim_opacity, piece.rim_target * breath, fade)
		piece.rim.albedo_color = piece.rim.albedo_color.lerp(Color(piece.rim_tint, piece.rim_opacity), fade)
		piece.rim_mesh.visible = piece.rim.albedo_color.a > 0.012
	for group: Piece in _continents:
		var cid := str(group.details["id"])
		var bright := _active == null or group == _active or (not _crossing_continent_id.is_empty() and cid == _crossing_continent_id)
		var target := 1.0 if bright else 0.68
		if absf(group.shade - target) < 0.001:
			continue
		group.shade = lerpf(group.shade, target, fade)
		for original: StandardMaterial3D in group.materials:
			var tint := group.materials[original]
			var base: Color = tint.get_meta(&"base_albedo", original.albedo_color)
			var base_em: float = float(tint.get_meta(&"base_emission_energy", original.emission_energy_multiplier))
			tint.albedo_color = Color(base.r * group.shade, base.g * group.shade, base.b * group.shade, base.a)
			tint.emission_energy_multiplier = base_em * group.shade
	if _nameplate.visible and _hovered != null:
		_place_nameplate()
	_update_waypoint_badges()
	if not _traveling and _journey_stage != null and _cities.has(WorldBlackboard.current_city_id):
		_journey_stage.park(_city_seat(WorldBlackboard.current_city_id, true))
	if not _telemetry_logged:
		_telemetry_frames += 1
		if _time >= 1.5 and _telemetry_frames >= 60:
			_telemetry_logged = true
			var stats := get_m1_telemetry()
			print("[WorldAtlas M4 Telemetry] Renderer=%s | Relief=%d tris | Biome=%d inst | DrawCalls=%d | FPS=%.1f | HDRI=%s | AO=%s" % [
				str(stats.get("renderer_method", "")),
				int(stats.get("total_tris", 0)),
				int(stats.get("biome_instances", 0)),
				int(stats.get("draw_calls", 0)),
				float(stats.get("fps", 0.0)),
				str(stats.get("hdri_loaded", false)),
				str(stats.get("ao_baked", false)),
			])


func _physics_process(_delta: float) -> void:
	if _changing_view or _traveling or JournalUI.is_open() or _hub_modal_center.visible or _encounter_overlay.is_active():
		return
	if _pending_click:
		_pending_click = false
		var chosen := _pick_target(_click_at, true)
		if _manual_mode and chosen != null and chosen.kind == PieceKind.CITY:
			_append_manual_waypoint(str(chosen.details["node"]), chosen)
			return
		if _mode == ViewMode.WORLD and chosen != null and chosen.kind == PieceKind.CONTINENT:
			_change_view(chosen)
			return
		_select(chosen)
		if _changing_view:
			return
	var hit: Piece
	if _pointer_known and not _touch and not _held and not _is_hud(_cursor):
		hit = _pick_target(_cursor, _manual_mode)
	_set_hover(hit)


func _pick_target(point: Vector2, allow_world_city: bool = false) -> Piece:
	var hit := _pick(point, false, allow_world_city)
	if _hovered != null and hit != _hovered and (hit == null or hit.kind < _hovered.kind):
		if _pick(point, true, allow_world_city) == _hovered:
			return _hovered
	return hit


func _pick(point: Vector2, _rest := false, allow_world_city: bool = false) -> Piece:
	var screen := _view_point(point)
	var origin := _camera.project_ray_origin(screen)
	var target := origin + _camera.project_ray_normal(screen) * 100.0
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	var space := _render.world_3d.direct_space_state

	var city_mask := 0
	if _active == null or _manual_mode:
		for i: int in _continents.size():
			city_mask |= LAYER_CITY_BASE << i
	else:
		var act_idx := _continents.find(_active)
		if act_idx >= 0:
			city_mask = LAYER_CITY_BASE << act_idx

	if _mode == ViewMode.CONTINENT or allow_world_city:
		query.collision_mask = city_mask
		var city_hit := space.intersect_ray(query)
		if not city_hit.is_empty():
			var collider := city_hit.get("collider") as CollisionObject3D
			if collider != null:
				var piece: Piece = _pieces.get(str(collider.get_meta(&"atlas_piece")))
				if piece != null:
					_last_hover_hit = city_hit.get("position", piece.rest)
					if _mode == ViewMode.WORLD and (not allow_world_city or piece.kind != PieceKind.CITY):
						return _pieces.get(piece.continent_id, null)
					return piece

	if _sampler == null or not _sampler.ready:
		return null
	query.collision_mask = LAYER_TERRAIN
	var terrain_hit := space.intersect_ray(query)
	if _sampler.chunks != null and not _sampler.chunks.active.is_empty():
		query.collision_mask = ChunkRegistry.TERRAIN_LAYER
		var sculpt_hit := space.intersect_ray(query)
		if not sculpt_hit.is_empty():
			var macro_pos: Vector3 = terrain_hit.get("position", Vector3.INF)
			var sculpt_pos: Vector3 = sculpt_hit["position"]
			if terrain_hit.is_empty() or _sampler.chunks.at(Vector2(macro_pos.x, macro_pos.z)) != null \
					or origin.distance_squared_to(sculpt_pos) < origin.distance_squared_to(macro_pos):
				terrain_hit = sculpt_hit
	if terrain_hit.is_empty():
		return null
	var hit_pos: Vector3 = terrain_hit.get("position", Vector3.ZERO)
	_last_hover_hit = hit_pos
	var rid: String = _sampler.sample_region_id(hit_pos.x, hit_pos.z)
	var cid: String = _sampler.sample_continent_id(hit_pos.x, hit_pos.z)
	if rid.is_empty() or cid.is_empty():
		return null
	if _mode == ViewMode.WORLD:
		return _pieces.get(cid, null)
	if _active != null and not _manual_mode and cid != str(_active.details["id"]):
		return null
	return _pieces.get(rid, null)


func _view_point(point: Vector2) -> Vector2:
	return point * Vector2(_render.size) / size.max(Vector2.ONE)


func _set_hover(piece: Piece) -> void:
	if piece == _hovered:
		return
	var previous := _hovered
	var previous_support := _supporting_region
	_hovered = piece
	_supporting_region = null
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
		if _manual_mode:
			_set_manual_mode(false)
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


func _set_manual_mode(enabled: bool) -> void:
	if _traveling:
		return
	_manual_mode = enabled
	_journey_journal.set_manual_mode_silent(enabled)
	if enabled:
		_manual_waypoints.clear()
		if _selected != null and _selected.kind == PieceKind.CITY:
			var sid := str(_selected.details["node"])
			if sid != WorldBlackboard.current_city_id:
				_manual_waypoints.append(sid)
		_legend_label.text = "手动串点模式：依次点击地图城池串联途经点 · 点击右侧撤销或启程"
	else:
		_manual_waypoints.clear()
		_update_legend_default()
	_refresh_plan()
	_refresh_travel_page()


func _append_manual_waypoint(city_id: String, piece: Piece) -> void:
	if _traveling or city_id.is_empty():
		return
	var tail: String = WorldBlackboard.current_city_id if _manual_waypoints.is_empty() else str(_manual_waypoints.back())
	if city_id == tail:
		return
	_manual_waypoints.append(city_id)
	var previous := _selected
	_selected = piece
	_pose_piece(previous)
	_pose_piece(piece)
	_refresh_plan()
	_populate_journal(piece)
	if not _drawer.visible:
		_drawer.show()
		_drawer_motion = Motion.slide_drawer_in(_drawer, DRAWER_WIDTH + 50.0)
	AudioManager.play_sfx("ui_click")


func _undo_manual_waypoint() -> void:
	if _traveling or _manual_waypoints.is_empty():
		return
	_manual_waypoints.pop_back()
	AudioManager.play_sfx("ui_click")
	_refresh_plan()
	_refresh_travel_page()


func _clear_manual_waypoints() -> void:
	if _traveling:
		return
	_manual_waypoints.clear()
	AudioManager.play_sfx("ui_click")
	_refresh_plan()
	_refresh_travel_page()


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
	var local := _selected.rest + bounds.get_center() * _selected.rest_scale * CITY_SCALE
	local.y += CITY_LIFT
	var span := bounds.size * _selected.rest_scale * CITY_SCALE
	_city_distance = maxf(2.2, span[span.max_axis_index()] * 8.6)
	return (_selected.model as Node3D).get_parent_node_3d().to_global(local)


func _route_camera() -> Vector3:
	var route := _journey_stage.bounds
	var available := maxf(size.x - DRAWER_WIDTH - DRAWER_MARGIN, size.x * 0.50)
	var frustum := 2.0 * tan(deg_to_rad(_camera.fov) * 0.5)
	var horizontal := (route.size.x + 1.6) * size.y / available
	var vertical := route.size.z + 1.5
	_city_distance = maxf(3.8, maxf(horizontal, vertical) / frustum * 1.10)
	var focus := route.get_center()
	focus.y = maxf(0.18, route.get_center().y)
	return focus


func _pose_piece(piece: Piece) -> void:
	if piece == null or piece.model == null:
		return
	var chosen := piece == _selected
	var hover := piece == _hovered
	if piece.kind != PieceKind.CITY:
		return
	var lift := CITY_LIFT if chosen else (0.042 if hover else 0.0)
	var rescale := CITY_SCALE if chosen or hover else 1.0
	Motion.spring(piece.model, ^"position:y", piece.model.position.y, piece.rest.y + lift, 0.40, 7.6, 8.0)
	Motion.spring(piece.model, ^"scale", piece.model.scale, piece.rest_scale * rescale, 0.40, 8.4, 7.3)
	piece.rim_tint = SELECT_TINT if chosen else HOVER_TINT
	piece.rim_target = 0.97 if chosen else (0.84 if hover else 0.0)


func _place_nameplate() -> void:
	var anchor: Vector3
	if _hovered.kind == PieceKind.CITY and _hovered.model != null:
		anchor = _hovered.model.global_position + Vector3.UP * (_hovered.height + 0.14)
	else:
		anchor = _last_hover_hit + Vector3.UP * 0.22
	var screen := _camera.unproject_position(anchor) * size / Vector2(_render.size)
	_nameplate.position = (screen + Vector2(-_nameplate.size.x * 0.5, -54.0)).clamp(
		Vector2(18.0, 12.0), size - _nameplate.size - Vector2(18.0, 12.0))


func _update_waypoint_badges() -> void:
	if _journey_stage == null or _waypoint_badge_layer == null:
		return
	var anchors := _journey_stage.get_waypoint_anchors()
	while _waypoint_badges.size() < anchors.size():
		var pill := PanelContainer.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var box := Kit.style(Color("#1d140ee8"), 8, 2, 4, 1, Color("#f1cc7a"))
		box.set_corner_radius_all(12)
		pill.add_theme_stylebox_override("panel", box)
		var lbl := Kit.create_label("", 15, Color("#fff3d4"), _title_font)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.add_child(lbl)
		_waypoint_badge_layer.add_child(pill)
		_waypoint_badges.append(pill)
	for i: int in _waypoint_badges.size():
		var pill := _waypoint_badges[i]
		if i >= anchors.size() or _traveling:
			pill.hide()
			continue
		var entry: Dictionary = anchors[i]
		var world_pos: Vector3 = entry["world_pos"]
		if _camera.is_position_behind(world_pos):
			pill.hide()
			continue
		var lbl := pill.get_child(0) as Label
		lbl.text = str(entry["index"])
		pill.reset_size()
		var screen := _camera.unproject_position(world_pos) * size / Vector2(_render.size)
		pill.position = screen - Vector2(pill.size.x * 0.5, pill.size.y + 8.0)
		pill.show()


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
	_update_legend_default()
	for continent: Piece in _continents:
		_pose_piece(continent)
	var data: Dictionary = _world_camera if group == null else group.details["camera"]
	_apply_camera_data(data, fly)
	if fly:
		AudioManager.play_sfx("page_flip")


func _update_legend_default() -> void:
	if _legend_label == null:
		return
	_legend_label.text = "拖动平移 · 滚轮缩放 · 点击大陆或城池" if _active == null else "拖动平移 · 滚轮缩放 · 点击领地或城池"


func _apply_camera_data(data: Dictionary, fly: bool) -> void:
	var center: Array = data["center"]
	var zoom: Array = data["zoom"]
	var bounds: Array = data["pan"]
	_camera_limits = Vector2(float(zoom[0]), float(zoom[1]))
	_pan_bounds = Vector2(float(bounds[0]), float(bounds[1]))
	_home_distance = float(data["distance"])
	var target_pitch := deg_to_rad(ATLAS_PITCH_DEG)
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
	if JournalUI.handle_scene_input(event) or SceneTransition.is_busy() or _encounter_overlay.is_active():
		return
	if _hub_modal_center.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			_close_hub_confirm()
			get_viewport().set_input_as_handled()
		return
	if _traveling:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _manual_mode:
			_set_manual_mode(false)
		elif _mode == ViewMode.CONTINENT:
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
	var plane := Plane(Vector3.UP, 0.18)
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

	_waypoint_badge_layer = Control.new()
	_waypoint_badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_waypoint_badge_layer)
	_waypoint_badge_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var heading := Kit.create_smoked_hud_panel(22, 14, 10)
	_hud.add_child(heading)
	heading.position = Vector2(36, 28)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_theme_constant_override("separation", 12)
	heading.add_child(head_row)
	var compass_emblem := Kit.create_micro_icon("compass", 34.0, Kit.BRASS)
	compass_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_row.add_child(compass_emblem)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 2)
	head_row.add_child(page)
	_heading_label = Kit.create_label(title, 36, Kit.IVORY, _title_font)
	page.add_child(_heading_label)
	_heading_subtitle = Kit.create_label("三大陆沙盘舆图", 16, Kit.BRASS, _body_font)
	page.add_child(_heading_subtitle)
	_blocked.append(heading)

	_world_back = Kit.create_icon_button("compass", "← 返回世界总览", "dark_brass", _title_font, 19, Kit.BRASS)
	_world_back.pressed.connect(_change_view.bind(null))
	_hud.add_child(_world_back)
	_world_back.position = Vector2(36.0, 128.0)
	_world_back.custom_minimum_size = Vector2(216.0, 48.0)
	_world_back.hide()
	_blocked.append(_world_back)

	_build_world_name()
	var legend := Kit.create_smoked_hud_panel(16, 8, 6, Color("#18110cd6"))
	_hud.add_child(legend)
	legend.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	legend.offset_left = 36.0
	legend.offset_top = -74.0
	legend.offset_bottom = -30.0
	_legend_label = Kit.create_label("拖动平移 · 滚轮缩放 · 点击大陆或城池", 16, Color("#d8c6ae"), _body_font)
	legend.add_child(_legend_label)
	_blocked.append(legend)

	var menu := JournalUI.make_toolbar(_title_font)
	_hud.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	menu.offset_left = 36
	menu.offset_top = -134
	menu.offset_bottom = -84
	_blocked.append(menu)

	var tools := HBoxContainer.new()
	tools.alignment = BoxContainer.ALIGNMENT_END
	tools.add_theme_constant_override("separation", 10)
	_hud.add_child(tools)
	tools.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	tools.offset_left = -540.0
	tools.offset_right = -36.0
	tools.offset_top = -84.0
	tools.offset_bottom = -30.0
	var zoom_out := Kit.create_tactile_button("−", "medallion", _title_font, 24)
	var zoom_in := Kit.create_tactile_button("＋", "medallion", _title_font, 24)
	var reset := Kit.create_icon_button("compass", "重置视角", "dark_brass", _title_font, 18, Kit.BRASS)
	zoom_out.custom_minimum_size = Vector2(52.0, 52.0)
	zoom_in.custom_minimum_size = Vector2(52.0, 52.0)
	reset.custom_minimum_size.y = 52.0
	zoom_out.pressed.connect(_zoom.bind(1.15))
	zoom_in.pressed.connect(_zoom.bind(0.87))
	reset.pressed.connect(_reset_view)
	tools.add_child(zoom_out)
	tools.add_child(zoom_in)
	tools.add_child(reset)
	_cabin_back = Kit.create_icon_button("door", "返回木屋", "dark_brass", _title_font, 18, Kit.BRASS)
	_cabin_back.custom_minimum_size = Vector2(142.0, 52.0)
	_cabin_back.pressed.connect(_back)
	tools.add_child(_cabin_back)
	_blocked.append(tools)

	_nameplate = Kit.create_smoked_hud_panel(16, 7, 8)
	_nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_nameplate)
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_theme_constant_override("separation", 7)
	_nameplate.add_child(name_row)
	name_row.add_child(Kit.create_micro_icon("star", 15.0, Kit.BRASS))
	_name_label = Kit.create_label("", 22, Kit.IVORY, _title_font)
	name_row.add_child(_name_label)
	_nameplate.hide()

	_build_journal()
	_build_travel_status()
	_build_travel_bar()
	_build_hub_confirm_modal()


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
	_drawer_slot.offset_top = 108.0
	_drawer_slot.offset_bottom = 964.0
	_drawer = Kit.create_folio_panel(Kit.PAPER, 22, 20, 11)
	_drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	_drawer_slot.add_child(_drawer)
	_drawer_slot.resized.connect(_size_drawer)
	_drawer.minimum_size_changed.connect(_size_drawer, CONNECT_DEFERRED)
	_size_drawer()
	_blocked.append(_drawer)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	_drawer.add_child(page)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 9)
	page.add_child(heading)
	var ribbon := Kit.create_ribbon_header("舆图手账", _title_font, 21, Kit.WAX_GOLD)
	ribbon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ribbon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading.add_child(ribbon)
	var close := Kit.create_icon_button("close", "合上", "dark_brass", _title_font, 17, Kit.BRASS)
	close.custom_minimum_size = Vector2(96.0, 44.0)
	close.pressed.connect(_select.bind(null))
	heading.add_child(close)

	_drawer_title = Kit.create_label("", 38, Kit.INK, _title_font)
	page.add_child(_drawer_title)
	_drawer_subtitle = Kit.create_label("", 17, Kit.BLUE, _body_font)
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
	inset.add_theme_constant_override("margin_right", 10)
	_journal_scroll.add_child(inset)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(content)

	_description = Kit.create_label("", 18, Kit.MUTED, _body_font)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_constant_override("line_spacing", 4)
	content.add_child(_description)

	_tags = HFlowContainer.new()
	_tags.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tags.add_theme_constant_override("h_separation", 7)
	_tags.add_theme_constant_override("v_separation", 6)
	content.add_child(_tags)

	_journey_journal = JourneyJournal.new()
	content.add_child(_journey_journal)
	_journey_journal.configure(_title_font, _body_font)
	_journey_journal.options_changed.connect(_refresh_travel_state)
	_journey_journal.route_mode_changed.connect(_set_manual_mode)
	_journey_journal.waypoint_undo_requested.connect(_undo_manual_waypoint)
	_journey_journal.waypoint_clear_requested.connect(_clear_manual_waypoints)
	_journey_journal.hub_transfer_requested.connect(_open_hub_confirm)
	_journey_journal.manual_requested.connect(_perform_manual)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	page.add_child(actions)
	_route_button = Kit.create_tactile_button("查看全路线", "secondary", _title_font, 17)
	_route_button.custom_minimum_size = Vector2(118.0, 52.0)
	_route_button.pressed.connect(_toggle_route_view)
	actions.add_child(_route_button)
	_depart_button = Kit.create_tactile_button("启程前往", "primary", _title_font, 19)
	_depart_button.custom_minimum_size.y = 52.0
	_depart_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_depart_button.pressed.connect(_depart)
	actions.add_child(_depart_button)
	_drawer.hide()


func _build_travel_bar() -> void:
	# Minimal translucent floating travel control bar at bottom-center while moving.
	_travel_bar = Kit.create_smoked_hud_panel(20, 8, 10, Color("#17100be0"), Color("#e0b76a96"))
	_hud.add_child(_travel_bar)
	_travel_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_travel_bar.offset_left = -360.0
	_travel_bar.offset_right = 360.0
	_travel_bar.offset_top = -86.0
	_travel_bar.offset_bottom = -28.0
	_blocked.append(_travel_bar)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	_travel_bar.add_child(row)

	var ic := Kit.create_micro_icon("compass", 18.0, Kit.BRASS)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)

	_travel_date_lbl = Kit.create_label("", 17, Kit.IVORY, _title_font)
	row.add_child(_travel_date_lbl)

	row.add_child(Kit.create_micro_icon("star", 10.0, Kit.BRASS))
	_travel_dest_lbl = Kit.create_label("", 17, Color("#a5d4f0"), _title_font)
	row.add_child(_travel_dest_lbl)

	_travel_km_lbl = Kit.create_label("", 16, Kit.BRASS, _body_font)
	row.add_child(_travel_km_lbl)

	_speed_btn = Kit.create_tactile_button("1x 速率", "dark_brass", _title_font, 15)
	_speed_btn.custom_minimum_size = Vector2(88.0, 44.0)
	_speed_btn.pressed.connect(_toggle_travel_speed)
	row.add_child(_speed_btn)

	_stop_btn = Kit.create_tactile_button("原地驻停", "secondary", _title_font, 15)
	_stop_btn.custom_minimum_size = Vector2(102.0, 44.0)
	_stop_btn.pressed.connect(_request_stop_in_place)
	row.add_child(_stop_btn)
	_travel_bar.hide()


func _build_hub_confirm_modal() -> void:
	_hub_modal_shade = ColorRect.new()
	_hub_modal_shade.color = Color("#140d099e")
	_hub_modal_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(_hub_modal_shade)
	_hub_modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hub_modal_shade.hide()

	_hub_modal_center = CenterContainer.new()
	_hub_modal_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.add_child(_hub_modal_center)
	_hub_modal_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hub_modal_center.hide()
	_blocked.append(_hub_modal_center)

	_hub_modal_card = Kit.create_folio_panel(Kit.PAPER, 28, 22, 14)
	_hub_modal_card.custom_minimum_size = Vector2(520.0, 0.0)
	_hub_modal_card.pivot_offset_ratio = Vector2(0.5, 0.5)
	_hub_modal_center.add_child(_hub_modal_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_hub_modal_card.add_child(col)
	col.add_child(Kit.create_ribbon_header("枢纽交通换乘办理", _title_font, 20, Kit.SAPPHIRE))
	_hub_modal_title = Kit.create_label("", 28, Kit.INK, _title_font)
	col.add_child(_hub_modal_title)
	col.add_child(Kit.create_gold_divider(0.0, true, 6.0))
	_hub_modal_route = Kit.create_label("", 20, Kit.SAPPHIRE, _title_font)
	col.add_child(_hub_modal_route)
	_hub_modal_note = Kit.create_label("", 17, Kit.MUTED, _body_font)
	_hub_modal_note.custom_minimum_size.x = 460.0
	_hub_modal_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_hub_modal_note)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	col.add_child(btns)
	var cancel := Kit.create_tactile_button("暂不换乘", "subtle", _title_font, 17)
	cancel.custom_minimum_size = Vector2(126.0, 48.0)
	cancel.pressed.connect(_close_hub_confirm)
	btns.add_child(cancel)
	_hub_modal_confirm = Kit.create_tactile_button("确认办理换乘", "primary", _title_font, 18)
	_hub_modal_confirm.custom_minimum_size = Vector2(0.0, 48.0)
	_hub_modal_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hub_modal_confirm.pressed.connect(_confirm_hub_transfer)
	btns.add_child(_hub_modal_confirm)


func _open_hub_confirm(target_transport: String) -> void:
	if _traveling:
		return
	var city_id := WorldBlackboard.current_city_id
	var check := _planner.can_switch_transport_at(city_id, target_transport)
	if not bool(check["ok"]):
		StoryletScheduler.show_hint(str(check["reason"]))
		return
	_pending_hub_transport = target_transport
	var svc: Dictionary = check["service"]
	_hub_modal_title.text = "%s · %s" % [_planner.city_name(city_id), str(svc.get("label", Planner.transport_label(target_transport)))]
	_hub_modal_route.text = "%s  →  %s" % [Planner.transport_label(WorldBlackboard.current_transport), Planner.transport_label(target_transport)]
	_hub_modal_note.text = "%s\n（已预留港口/商行正式接待剧情接口，确认后立即切换 3D 旅途棋子形态。）" % str(svc.get("note", ""))
	_hub_modal_shade.show()
	_hub_modal_center.show()
	Motion.fade_in(_hub_modal_shade, 0.18)
	Motion.fade_in(_hub_modal_center, 0.22)
	Motion.spring(_hub_modal_card, ^"scale", Vector2(0.92, 0.92), Vector2.ONE, 0.34, 9.0, 7.5)
	AudioManager.play_sfx("page_flip")


func _close_hub_confirm() -> void:
	_pending_hub_transport = ""
	_hub_modal_shade.hide()
	_hub_modal_center.hide()


func _confirm_hub_transfer() -> void:
	if _pending_hub_transport.is_empty():
		return
	var target := _pending_hub_transport
	_close_hub_confirm()
	var result := _planner.request_hub_transport_switch(WorldBlackboard.current_city_id, target)
	AudioManager.play_sfx("stat_up" if bool(result["ok"]) else "ui_click")
	StoryletScheduler.show_hint(str(result.get("reason", "")))
	_refresh_travel_state()


func _on_transport_changed(_mode: String) -> void:
	_refresh_status()
	if not _traveling:
		_refresh_plan()
		_refresh_travel_page()


func _size_drawer() -> void:
	_drawer.size = _drawer_slot.size


func _populate_journal(piece: Piece) -> void:
	var details := piece.details
	var geo: Dictionary
	if piece.kind == PieceKind.CITY:
		geo = _planner.city_geo_formatted(str(details["node"]))
	else:
		geo = _planner.region_geo_formatted(str(details["id"]))
	_drawer_title.text = str(geo.get("title", details["name"]))
	var eyebrow := str(geo.get("eyebrow", ""))
	var poetic := str(geo.get("poetic_subtitle", details.get("subtitle", "")))
	_drawer_subtitle.text = (eyebrow + "\n" + poetic) if not eyebrow.is_empty() else poetic
	_description.text = str(details["description"])
	for child: Node in _tags.get_children():
		_tags.remove_child(child)
		child.queue_free()
	for tag: String in details["tags"]:
		_tags.add_child(Kit.create_chip(tag, _body_font, 16))
	_refresh_travel_page()
	_journal_scroll.set_deferred("scroll_vertical", 0)
	_size_drawer.call_deferred()


func _build_travel_status() -> void:
	var status := Kit.create_smoked_hud_panel(20, 10, 10)
	_hud.add_child(status)
	status.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	status.offset_left = -520.0
	status.offset_right = 520.0
	status.offset_top = 24.0
	status.offset_bottom = 76.0
	_blocked.append(status)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	status.add_child(row)
	var sun_ic := Kit.create_micro_icon("morning", 17.0, Kit.BRASS)
	sun_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(sun_ic)
	_status_date = Kit.create_label("", 17, Kit.IVORY, _title_font)
	row.add_child(_status_date)
	row.add_child(Kit.create_micro_icon("star", 10.0, Kit.BRASS))
	var city_ic := Kit.create_micro_icon("compass", 16.0, Color("#88c4e8"))
	city_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(city_ic)
	_status_city = Kit.create_label("", 17, Color("#a5d4f0"), _title_font)
	row.add_child(_status_city)
	_status_transport = Kit.create_label("", 15, Color("#f2d084"), _title_font)
	row.add_child(_status_transport)
	row.add_child(Kit.create_micro_icon("star", 10.0, Kit.BRASS))
	_status_supplies = Kit.create_label("", 16, Kit.BRASS, _body_font)
	row.add_child(_status_supplies)
	_status_badges = HBoxContainer.new()
	_status_badges.add_theme_constant_override("separation", 6)
	row.add_child(_status_badges)


func _update_dynamic_shadow_focus() -> void:
	if _key_light == null:
		return
	var focus_t := clampf((_distance - 3.2) / (19.6 - 3.2), 0.0, 1.0)
	_shadow_focus_dist = lerpf(10.5, 36.0, focus_t)
	_key_light.directional_shadow_max_distance = _shadow_focus_dist
	_key_light.shadow_bias = lerpf(0.006, 0.019, focus_t)
	_key_light.shadow_normal_bias = lerpf(0.045, 0.130, focus_t)
	var softness := 1.0
	if _sampler != null and _sampler.chunks != null:
		var focus := _center + _pan
		var chunk := _sampler.chunks.at(Vector2(focus.x, focus.z))
		if chunk != null:
			softness = lerpf(chunk.shadow_softness, 1.0, smoothstep(3.0, 5.5, _distance))
	_key_light.shadow_blur = lerpf(1.08, 1.55, focus_t) * softness


func _refresh_date() -> void:
	var dt := WorldBlackboard.date_text().replace("   ", " ")
	_status_date.text = dt
	if _travel_date_lbl != null:
		_travel_date_lbl.text = dt
	_refresh_time_atmosphere()
	_refresh_season_atmosphere()
	if _traveling and _time > _date_pulse:
		_date_pulse = _time + 0.13
		_status_date.pivot_offset_ratio = Vector2(0.5, 0.5)
		Motion.spring(_status_date, ^"scale", Vector2.ONE * 1.055, Vector2.ONE, 0.24, 8.0, 7.0)


func _refresh_season_atmosphere() -> void:
	if _manual_season_override:
		return
	var wt: Dictionary[String, int] = WorldBlackboard.get_world_time()
	var m: int = int(wt.get("month", 4))
	if WorldBlackboard.is_northern_winter(m):
		_winter_snow_push = 0.88 if (m == 12 or m == 1) else 0.70
	elif m == 3 or m == 10:
		_winter_snow_push = 0.24
	else:
		_winter_snow_push = 0.0

	if WorldBlackboard.is_milis_rainy_season(m):
		_wetness_boost = 0.86 if m == 7 else 0.72
	elif m == 5 or m == 9:
		_wetness_boost = 0.22
	else:
		_wetness_boost = 0.0
	_sync_relief_shader_uniforms()


func _refresh_time_atmosphere() -> void:
	var slot: int = int(WorldBlackboard.get_world_time().get("slot", 0))
	var win_albedo := Color("#4A3222")
	var win_em_energy := 0.0
	var lamp_em_energy := 0.65
	var beam_intensity := 0.22
	var key_rot := Vector3(-36.0, -48.0, 0.0)
	var key_col := Color("#FFE7C6")
	var key_energy := 1.18
	var fill_col := Color("#A2C3EC")
	var fill_energy := 0.30
	var amb_col := Color("#C8D6E8")
	var amb_energy := 0.36
	var sky_mult := 0.84

	match slot:
		1:  # 下午
			win_albedo = Color("#6E4826")
			win_em_energy = 0.12
			lamp_em_energy = 0.95
			beam_intensity = 0.30
			key_rot = Vector3(-31.0, -24.0, 0.0)
			key_col = Color("#FFDCAC")
			key_energy = 1.14
			sky_mult = 0.82
			_night_glow = 0.06
		2:  # 傍晚（橘金长影）
			win_albedo = Color("#B87634")
			win_em_energy = 2.25
			lamp_em_energy = 2.95
			beam_intensity = 1.02
			key_rot = Vector3(-30.0, -65.0, 0.0)
			key_col = Color("#F59E52")
			key_energy = 1.02
			fill_col = Color("#7C98CE")
			fill_energy = 0.28
			amb_col = Color("#8E9ECA")
			amb_energy = 0.32
			sky_mult = 0.56
			_night_glow = 0.52
		3:  # 深夜（幽蓝月光 + 万家灯火与灯塔）
			win_albedo = Color("#D28B3E")
			win_em_energy = 3.45
			lamp_em_energy = 3.85
			beam_intensity = 1.38
			key_rot = Vector3(-36.0, 48.0, 0.0)
			key_col = Color("#9CB6E2")
			key_energy = 0.74
			fill_col = Color("#5E7BB0")
			fill_energy = 0.26
			amb_col = Color("#6A84B2")
			amb_energy = 0.28
			sky_mult = 0.32
			_night_glow = 0.90
		_:  # 上午
			_night_glow = 0.0

	if _key_light != null:
		_key_light.rotation_degrees = key_rot
		_key_light.light_color = key_col
		_key_light.light_energy = key_energy
	if _fill_light != null:
		_fill_light.light_color = fill_col
		_fill_light.light_energy = fill_energy
	if _world_env != null:
		_world_env.ambient_light_color = amb_col
		_world_env.ambient_light_energy = amb_energy
	if _studio_sky_mat is PanoramaSkyMaterial:
		(_studio_sky_mat as PanoramaSkyMaterial).energy_multiplier = sky_mult
	if _lighthouse_beam_mat != null:
		_lighthouse_beam_mat.set_shader_parameter("beam_intensity", beam_intensity)
	if _sampler != null and _sampler.chunks != null:
		for chunk in _sampler.chunks.active:
			chunk.set_night_glow(_night_glow)

	for group: Piece in _continents:
		for original: StandardMaterial3D in group.materials:
			var tint := group.materials[original]
			if bool(tint.get_meta(&"is_city_window", false)):
				tint.emission_enabled = win_em_energy > 0.01
				tint.emission = Color("#FFB84C")
				tint.set_meta(&"base_albedo", win_albedo)
				tint.set_meta(&"base_emission_energy", win_em_energy)
				tint.albedo_color = Color(win_albedo.r * group.shade, win_albedo.g * group.shade, win_albedo.b * group.shade, win_albedo.a)
				tint.emission_energy_multiplier = win_em_energy * group.shade
			elif bool(tint.get_meta(&"is_lighthouse_glass", false)):
				tint.emission_enabled = true
				tint.emission = Color("#F8AB48")
				tint.set_meta(&"base_emission_energy", lamp_em_energy)
				tint.emission_energy_multiplier = lamp_em_energy * group.shade


func _refresh_status() -> void:
	var city_id := WorldBlackboard.current_city_id
	if _traveling:
		_status_city.text = "赶路中 · " + _planner.city_name(city_id)
	else:
		_status_city.text = _planner.city_name(city_id)
	_status_transport.text = "[%s]" % Planner.transport_label(WorldBlackboard.current_transport)
	_status_supplies.text = "干粮 %d  ·  %s" % [
		WorldBlackboard.get_total_rations(), WorldBlackboard.format_currency(WorldBlackboard.currency_copper)
	]
	var statuses := WorldBlackboard.active_statuses()
	var buffs := PackedStringArray()
	for s: Dictionary in statuses:
		buffs.append(str(s.get("name", "")))
	if buffs != _last_buffs:
		_last_buffs = buffs
		for child: Node in _status_badges.get_children():
			_status_badges.remove_child(child)
			child.queue_free()
		for s: Dictionary in statuses:
			var pol := WorldBlackboard.status_polarity(s)
			_status_badges.add_child(Kit.create_status_badge(str(s.get("name", s.get("id", ""))), pol >= 0, _body_font, 14))
	_cabin_back.visible = _mode == ViewMode.WORLD and city_id == WorldBlackboard.HOME_CITY and not _traveling


func _refresh_travel_state() -> void:
	_refresh_status()
	if not _traveling:
		_refresh_plan()
		_refresh_travel_page()


func _refresh_plan() -> void:
	var plan: Planner.Itinerary
	if _manual_mode:
		if not _manual_waypoints.is_empty():
			plan = _planner.plan_manual_waypoints(WorldBlackboard.current_city_id, _manual_waypoints,
				WorldBlackboard.current_transport, _journey_journal.posture, WorldBlackboard.get_world_time())
	elif _selected != null and _selected.kind == PieceKind.CITY:
		plan = _planner.plan(WorldBlackboard.current_city_id, str(_selected.details["node"]),
			WorldBlackboard.current_transport, _journey_journal.posture, WorldBlackboard.get_world_time())

	_plan = plan
	if _journey_stage != null:
		var centers: Dictionary[String, Vector3] = {}
		var radii: Dictionary[String, float] = {}
		if plan != null:
			for city_id: String in plan.path_cities:
				if _cities.has(city_id):
					var cp: Piece = _cities[city_id]
					centers[city_id] = Vector3(cp.rest.x, cp.ground_y, cp.rest.z)
					radii[city_id] = cp.outer_radius
		_journey_stage.set_itinerary(plan, centers, radii)
		if not _traveling:
			_journey_stage.set_travel_mode(WorldBlackboard.current_transport, false)


func _refresh_travel_page() -> void:
	if _manual_mode or _plan != null:
		var route_str := ""
		if _plan != null:
			var names := PackedStringArray()
			for city_id: String in _plan.path_cities:
				var label := _planner.city_name(city_id)
				if _plan.requires_hub_transfer and city_id == _plan.transfer_hub_id:
					label += " [换乘枢纽]"
				names.append(label)
			route_str = " → ".join(names)

		var wp_chain := ""
		if not _manual_waypoints.is_empty():
			var wp_names := PackedStringArray([_planner.city_name(WorldBlackboard.current_city_id)])
			for i: int in _manual_waypoints.size():
				wp_names.append("%d.%s" % [i + 1, _planner.city_name(_manual_waypoints[i])])
			wp_chain = " → ".join(wp_names)

		_journey_journal.present_plan(_plan, route_str, wp_chain, _manual_waypoints.size(), _traveling)
		if _plan == null:
			_route_button.hide()
			_depart_button.hide()
			return
		_route_button.show()
		_route_button.text = "城池特写" if _viewing_route else "查看全路线"
		_route_button.disabled = _traveling
		_depart_button.show()

		# Hub-transfer constraint button UX:
		if _plan.requires_hub_transfer and _plan.actionable_legs.is_empty():
			var hub_name := _planner.city_name(_plan.transfer_hub_id)
			var verb := Planner.transport_verb(_plan.required_next_transport)
			_depart_button.disabled = _traveling
			_depart_button.text = "在【%s】办理%s手续" % [hub_name, verb]
			return

		var req_fare := _plan.actionable_fare if _plan.requires_hub_transfer else _plan.fare
		var req_ship := _plan.actionable_ship_fare if _plan.requires_hub_transfer else _plan.ship_fare
		var req_rations := _plan.actionable_ration_cost if _plan.requires_hub_transfer else _plan.ration_cost
		var affordable := WorldBlackboard.can_afford(req_fare)
		_depart_button.disabled = _traveling or not affordable
		if _traveling:
			_depart_button.text = "旅途进行中"
		elif not affordable:
			_depart_button.text = "船票不足 · 暂无法启程" if not WorldBlackboard.can_afford(req_ship) else "车马费用不足"
		elif _plan.requires_hub_transfer:
			var hub_name := _planner.city_name(_plan.transfer_hub_id)
			var verb := Planner.transport_verb(_plan.required_next_transport)
			_depart_button.text = "先前往【%s】（抵港后%s）" % [hub_name, verb]
		elif req_rations > WorldBlackboard.get_total_rations():
			_depart_button.text = "强行启程 · 干粮不足"
		else:
			_depart_button.text = "扬帆启程" if WorldBlackboard.current_transport == Planner.SHIP else "启程前往"
		return

	_route_button.hide()
	_depart_button.hide()
	if _selected != null and _selected.kind == PieceKind.CITY and str(_selected.details["node"]) == WorldBlackboard.current_city_id:
		var cid := WorldBlackboard.current_city_id
		_journey_journal.present_local_hub(
			_planner.city_name(cid),
			_planner.get_hub_services(cid),
			StoryletScheduler.get_available_storylets(cid),
			_traveling
		)
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


func _toggle_travel_speed() -> void:
	_travel_speed = 2.0 if _travel_speed < 1.5 else 1.0
	_speed_btn.text = "2x 速率" if _travel_speed > 1.5 else "1x 速率"
	AudioManager.play_sfx("ui_click")


func _request_stop_in_place() -> void:
	if not _traveling or _stop_requested:
		return
	_stop_requested = true
	_stop_btn.disabled = true
	_stop_btn.text = "正在驻停…"
	AudioManager.play_sfx("ui_click")


func _city_seat(city_id: String, _follow_plate: bool) -> Vector3:
	var city := _cities[city_id]
	var center_xz := Vector3(city.rest.x, 0.0, city.rest.z)
	if _sampler != null and _sampler.ready:
		if WorldBlackboard.current_transport == Planner.SHIP:
			# Park sailing ship gracefully in the clearest open harbor water adjacent to the port pier!
			var best_water := center_xz + Vector3(city.outer_radius + 0.24, 0.0, 0.14)
			var lowest_h := 99.0
			var probe_r := city.outer_radius + 0.26
			for k: int in range(12):
				var ang := TAU * float(k) / 12.0
				var cand := center_xz + Vector3(cos(ang) * probe_r, 0.0, sin(ang) * probe_r)
				var ch := _sampler.sample_height(cand.x, cand.z)
				if ch < lowest_h:
					lowest_h = ch
					best_water = cand
			var ship_y := maxf(_sampler.get_sea_level() + 0.014, _sampler.sample_surface_height(best_water.x, best_water.z) + 0.004)
			return Vector3(best_water.x, ship_y, best_water.z)
		# Park land pawns neatly right outside the city stone rim on dry level ground!
		if city.hero_half_extents != Vector2.ZERO:
			for peer_name: String in HeroAssets.CITY_MODELS:
				if peer_name == city_id or not _cities.has(peer_name):
					continue
				var peer: Piece = _cities[peer_name]
				var approach := Vector2(peer.rest.x - center_xz.x, peer.rest.z - center_xz.z).normalized()
				var offset := JourneyStage.footprint_exit(city.hero_half_extents, approach) + 0.106
				var seat_point := center_xz + Vector3(approach.x, 0.0, approach.y) * offset
				var ground := _sampler.sample_height(seat_point.x, seat_point.z)
				if ground > _sampler.get_sea_level() + 0.055:
					return Vector3(seat_point.x, ground + 0.004, seat_point.z)
		var rim_r := city.outer_radius + 0.115
		var pref_angles: Array[float] = [0.42, 0.95, 1.55, 2.25, -0.35, 3.0]
		for ang: float in pref_angles:
			var cand := center_xz + Vector3(cos(ang) * rim_r, 0.0, sin(ang) * rim_r)
			var h := _sampler.sample_height(cand.x, cand.z)
			if h > _sampler.get_sea_level() + 0.055:
				return Vector3(cand.x, h + 0.004, cand.z)
		var fallback := center_xz + Vector3(rim_r, 0.0, 0.08)
		return Vector3(fallback.x, _sampler.sample_surface_height(fallback.x, fallback.z) + 0.004, fallback.z)
	return Vector3(city.rest.x + 0.24, city.ground_y + 0.006, city.rest.z + 0.10)


func _depart() -> void:
	if _traveling or _changing_view or _plan == null:
		return
	_refresh_plan()
	var trip := _plan
	if trip == null:
		_refresh_travel_page()
		return

	# If already standing at the required transfer hub, open the hub transfer modal directly (never teleport!).
	if trip.requires_hub_transfer and trip.actionable_legs.is_empty():
		_open_hub_confirm(trip.required_next_transport)
		return

	var exec_legs := trip.actionable_legs
	var exec_cities := trip.actionable_cities
	if exec_legs.is_empty():
		return
	var destination := exec_cities.back() as String
	var exec_days := trip.actionable_days if trip.requires_hub_transfer else trip.total_days
	var exec_rations := trip.actionable_ration_cost if trip.requires_hub_transfer else trip.ration_cost
	var exec_fare := trip.actionable_fare if trip.requires_hub_transfer else trip.fare
	var exec_km := trip.actionable_km if trip.requires_hub_transfer else trip.total_km

	if not WorldBlackboard.begin_city_travel(destination, exec_days, exec_rations, exec_fare):
		_refresh_travel_page()
		return

	_traveling = true
	_travel_paused = false
	_stop_requested = false
	_pointer_known = false
	_held = false
	_dragging = false
	_pending_click = false
	_set_hover(null)
	StoryletScheduler.dismiss_toast()

	# Close drawer smoothly and switch camera directly into close-mid pawn-follow mode (NEVER zoom out to world overview!).
	Motion.cancel(self, ^"_center")
	Motion.cancel(self, ^"_pan")
	Motion.cancel(self, ^"_distance")
	Motion.cancel(self, ^"_camera_pitch")
	Motion.cancel(self, ^"_aim_height")
	Motion.cancel(self, ^"_drawer_shift")
	if _drawer.visible:
		_drawer_motion = Motion.slide_drawer_out(_drawer, DRAWER_WIDTH + 50.0, 0.28)
		_drawer_motion.finished.connect(_drawer.hide)

	var start_pos := _city_seat(exec_cities[0], false)
	_journey_stage.set_waypoints_visible(false)
	_journey_stage.park(start_pos)
	_journey_stage.begin_trail(start_pos)
	_follow_focus = _center + _pan
	_follow_distance = clampf(_distance, 5.8, 8.2) if _mode == ViewMode.CONTINENT else 7.4
	_follow_active = true

	_speed_btn.text = "2x 速率" if _travel_speed > 1.5 else "1x 速率"
	_stop_btn.disabled = false
	_stop_btn.text = "原地驻停"
	_travel_dest_lbl.text = "前往 " + _planner.city_name(destination)
	_travel_km_lbl.text = "剩余 %d km" % exec_km
	_travel_bar.show()
	Motion.fade_in(_travel_bar, 0.24)
	_refresh_status()

	var raw_days := 0.0
	var weights := 0.0
	for leg: Planner.Leg in exec_legs:
		raw_days += leg.days
		weights += sqrt(float(leg.km))
	var base_animation := clampf(2.0 + float(exec_km) / 1450.0, 2.0, 4.6)

	var elapsed_days := 0.0
	var walked_km := 0.0
	var current_region := _planner.city_region_id(exec_cities[0])
	var dock_city := destination
	var encountered_once := false

	for index: int in exec_legs.size():
		var leg := exec_legs[index]
		var leg_duration := base_animation * sqrt(float(leg.km)) / maxf(weights, 0.001)
		var leg_days := leg.days * float(exec_days) / maxf(raw_days, 0.0001)
		var dest_info := _planner.get_city_info(leg.to_city)
		var dest_region := _planner.city_region_id(leg.to_city)
		var dest_continent := _planner.city_continent_id(leg.to_city)
		_crossing_continent_id = dest_continent

		var sound := "travel_wave" if leg.mode == Planner.SHIP else "travel_step"
		_journey_stage.set_travel_mode(leg.mode, true)
		_journey_stage.follow(index, 0.0, true)
		AudioManager.play_sfx(sound)

		var encounter: Dictionary = {}
		if not encountered_once:
			encounter = _encounter_engine.roll_leg_encounter(leg, dest_info, _journey_journal.posture, _journey_rng, _forced_encounter_pool)
			if not encounter.is_empty():
				encountered_once = true
		var enc_trigger := float(encounter.get("trigger_progress", 0.52)) if not encounter.is_empty() else -1.0
		var enc_fired := false
		var region_banner_fired := dest_region == current_region

		var progress := 0.0
		while progress < 1.0:
			var dt := get_process_delta_time()
			progress = minf(1.0, progress + (dt * _travel_speed) / maxf(leg_duration, 0.25))
			_journey_stage.follow(index, progress, false)
			var cur_days := elapsed_days + leg_days * progress
			WorldBlackboard.advance_city_travel(floori(cur_days + 0.000001))
			var rem_km := maxi(0, roundi(float(exec_km) - (walked_km + float(leg.km) * progress)))
			_travel_km_lbl.text = "剩余 %d km" % rem_km

			# Trigger cinematic region border banner when crossing into a new region on intermediate legs.
			if not region_banner_fired and progress >= 0.56:
				region_banner_fired = true
				current_region = dest_region
				if index < exec_legs.size() - 1:
					_arrival_banner.enqueue_arrival(_planner.region_geo_formatted(dest_region))

			# Trigger en-route or gate checkpoint encounter card, pausing cleanly in place!
			if enc_trigger > 0.0 and not enc_fired and progress >= enc_trigger:
				enc_fired = true
				_travel_paused = true
				_journey_stage.set_paused(true)
				_travel_bar.hide()
				await _encounter_overlay.present_encounter(encounter)
				_travel_paused = false
				_journey_stage.set_paused(false)
				if not _stop_requested:
					_travel_bar.show()
					AudioManager.play_sfx(sound)

			if _stop_requested:
				dock_city = leg.to_city if progress >= 0.48 else leg.from_city
				elapsed_days = cur_days
				break
			await get_tree().process_frame

		if _stop_requested:
			break
		walked_km += float(leg.km)
		elapsed_days += leg_days
		current_region = dest_region
		# Announce intermediate or final city arrival!
		_arrival_banner.enqueue_arrival(_planner.city_geo_formatted(leg.to_city))

	_travel_bar.hide()
	_follow_active = false
	_crossing_continent_id = ""
	var result: Dictionary
	if _stop_requested:
		var ratio := clampf(elapsed_days / maxf(float(exec_days), 1.0), 0.0, 1.0)
		var settled_days := maxi(0, roundi(elapsed_days))
		var settled_rations := roundi(float(exec_rations) * ratio)
		var settled_fare := roundi(float(exec_fare) * ratio)
		result = WorldBlackboard.finish_city_travel_at(dock_city, settled_days, settled_rations, settled_fare)
	else:
		result = WorldBlackboard.finish_city_travel()

	var arrived_city := str(result.get("city_id", destination))
	_journey_stage.set_waypoints_visible(true)
	_journey_stage.park(_city_seat(arrived_city, true))
	_journey_stage.fade_out_trail(1.6)
	_traveling = false
	_stop_requested = false
	_viewing_route = false
	_manual_mode = false
	_manual_waypoints.clear()
	_journey_journal.set_manual_mode_silent(false)
	_update_legend_default()

	# Keep camera cleanly in the arrived continent's close-mid view (NEVER pull back to max world overview!).
	var arrived_piece: Piece = _cities.get(arrived_city)
	if arrived_piece != null:
		var arrived_cont: Piece = _pieces.get(arrived_piece.continent_id)
		if arrived_cont != null:
			_active = arrived_cont
			_mode = ViewMode.CONTINENT
			_world_back.show()
			_heading_label.text = str(arrived_cont.details["name"])
			_heading_subtitle.text = str(arrived_cont.details["subtitle"])
			var cam_data: Dictionary = arrived_cont.details["camera"]
			var zoom_arr: Array = cam_data["zoom"]
			var pan_arr: Array = cam_data["pan"]
			var cont_center_arr: Array = cam_data["center"]
			var world_focus := _center + _pan
			_center = Vector3(float(cont_center_arr[0]), 0.0, float(cont_center_arr[1]))
			_pan = world_focus - _center
			_camera_limits = Vector2(float(zoom_arr[0]), float(zoom_arr[1]))
			_pan_bounds = Vector2(float(pan_arr[0]), float(pan_arr[1]))
			_home_distance = float(cam_data["distance"])
			_continent_pan = _clamp_pan(_pan)
			_continent_distance = clampf(_follow_distance, _camera_limits.x, _camera_limits.y)
			for c: Piece in _continents:
				_pose_piece(c)
		_selected = null
		_select(arrived_piece)

	_refresh_travel_state()
	if bool(result.get("stopped_early", false)):
		StoryletScheduler.show_hint("已在【%s】原地驻停，可随时休整或重新规划路线。" % _planner.city_name(arrived_city))
	elif bool(result.get("fatigue", false)):
		StoryletScheduler.show_hint("干粮不足，诺缇雅陷入了旅途疲惫。")
	elif trip.requires_hub_transfer and arrived_city == trip.transfer_hub_id:
		StoryletScheduler.show_hint("已抵达枢纽【%s】，可在右侧手账办理%s手续。" % [
			_planner.city_name(arrived_city), Planner.transport_verb(trip.required_next_transport)
		])
	StoryletScheduler.check_arrival(arrived_city)


func _show_asset_message() -> void:
	var empty := Kit.create_folio_panel(Kit.PAPER, 24, 18, 8)
	_hud.add_child(empty)
	empty.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	empty.add_child(Kit.create_label("舆图资产暂未载入", 24, Kit.INK, _title_font))
