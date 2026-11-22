class_name WorldBiomeScatter
extends Node3D

const TerrainSampler := preload("res://scenes/world_map/world_terrain_sampler.gd")
const HeroAssets := preload("res://scenes/world_map/world_hero_assets.gd")
const PROP_SHADER := preload("res://shaders/world_biome_prop.gdshader")

const ROUTES_PATH := "res://data/maps/world_routes.json"
const SCATTER_SEED := 4180301

const SPECIES_ORDER: Array[String] = [
	"broadleaf",
	"meadow",
	"pine_snow",
	"demon_deadwood",
	"demon_crystal",
	"rock_cluster",
]

const SPECIES_PATHS: Dictionary[String, String] = {
	"broadleaf": "res://assets/3d/world_v2/props/prop_tree_broadleaf.glb",
	"meadow": "res://assets/3d/world_v2/props/prop_tree_meadow.glb",
	"pine_snow": "res://assets/3d/world_v2/props/prop_tree_pine_snow.glb",
	"demon_deadwood": "res://assets/3d/world_v2/props/prop_demon_deadwood.glb",
	"demon_crystal": "res://assets/3d/world_v2/props/prop_demon_crystal.glb",
	"rock_cluster": "res://assets/3d/world_v2/props/prop_rock_cluster.glb",
}

const SPECIES_BASE_SCALE: Dictionary[String, float] = {
	"broadleaf": 0.098,
	"meadow": 0.096,
	"pine_snow": 0.106,
	"demon_deadwood": 0.098,
	"demon_crystal": 0.088,
	"rock_cluster": 0.084,
}

const SPECIES_WIND: Dictionary[String, float] = {
	"broadleaf": 0.036,
	"meadow": 0.034,
	"pine_snow": 0.026,
	"demon_deadwood": 0.014,
	"demon_crystal": 0.0,
	"rock_cluster": 0.0,
}

const SPECIES_EMISSION: Dictionary[String, float] = {
	"broadleaf": 0.0,
	"meadow": 0.0,
	"pine_snow": 0.0,
	"demon_deadwood": 0.0,
	"demon_crystal": 0.62,
	"rock_cluster": 0.0,
}

# Strict non-clipping clearance thresholds
const SHORE_HEIGHT_MIN := 0.056
const FOOTPRINT_WATER_MIN := 0.028
const CITY_CLEAR_PAD := 0.24
const ROAD_SPLAT_MAX := 0.14
const ROUTE_CORRIDOR_CLEAR := 0.205
const FRAME_SAFE_X := 8.04
const FRAME_SAFE_Z := 4.38
const SPATIAL_CELL := 0.125
const HERO_ROUTE_CLEAR := 0.17
# X, Z, footprint scale, yaw in degrees. The feet are sampled against the
# relief at runtime, including the tight northern shelf and basin rim.
const HERO_CLIFFS: Array[Vector4] = [
	Vector4(6.296, -3.850, 0.155, -55.0),
	Vector4(6.292, -4.016, 0.149, -22.0),
	Vector4(7.006, -4.038, 0.145, 42.0),
	Vector4(5.988, -3.972, 0.139, -78.0),
	Vector4(6.154, -4.102, 0.155, 26.0),
	Vector4(6.782, -3.418, 0.139, 108.0),
	Vector4(5.890, -3.764, 0.220, 4.0),
	Vector4(6.156, -3.723, 0.146, 68.0),
	Vector4(6.484, -3.116, 0.235, -120.0),
	Vector4(6.586, -3.280, 0.195, -134.0),
	Vector4(5.728, -3.852, 0.155, -12.0),
	Vector4(6.684, -3.136, 0.149, 96.0),
	Vector4(5.998, -4.146, 0.145, 41.0),
	Vector4(5.555, -3.952, 0.186, 58.0),
	Vector4(5.830, -4.132, 0.173, -37.0),
	Vector4(6.373, -2.974, 0.207, 27.0),
	Vector4(6.730, -3.145, 0.151, 117.0),
]

var _multimeshes: Dictionary[String, MultiMeshInstance3D] = {}
var _materials: Dictionary[String, ShaderMaterial] = {}
var _species_stats: Dictionary[String, Dictionary] = {}
var _route_polylines: Array[PackedVector2Array] = []
var _spawn_records: Array[Dictionary] = []
var _total_instances: int = 0
var _total_instanced_tris: int = 0
var _buffer_vram_bytes: int = 0
var _migurd_basin_props: int = 0
var _hero_cliff_root: Node3D
var _cliff_footprints: Array[Vector3] = []


func build_scatter(sampler: TerrainSampler, city_exclusions: Array[Dictionary]) -> void:
	clear_scatter()
	if sampler == null or not sampler.ready:
		return

	_route_polylines = _load_land_route_polylines(sampler)
	var sculpted_northeast := sampler.chunks != null and sampler.chunks.city_chunk("city_migurd") != null
	if not sculpted_northeast:
		_build_hero_cliffs(sampler, city_exclusions)
	var meshes: Dictionary[String, Mesh] = _load_prop_meshes()
	if meshes.is_empty():
		return

	var buckets: Dictionary[String, Array] = {}
	for sid: String in SPECIES_ORDER:
		buckets[sid] = []

	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var occupied: Dictionary[Vector2i, Array] = {}

	# Pass A: Curated Migurd Basin Diorama Accent Ring (weathered stones, green-ore crystals & sparse scrub)
	if not sculpted_northeast:
		_migurd_basin_props = _scatter_migurd_basin_ring(sampler, city_exclusions, occupied, buckets, rng)

	# Pass B: Deterministic Stratified Jittered Scatter across all three continents
	var step_x := 0.052
	var step_z := 0.052
	var nx := int(floor((FRAME_SAFE_X * 2.0) / step_x))
	var nz := int(floor((FRAME_SAFE_Z * 2.0) / step_z))
	var sea := sampler.get_sea_level()

	for gz: int in range(nz):
		for gx: int in range(nx):
			var wx := -FRAME_SAFE_X + (float(gx) + 0.16 + rng.randf() * 0.68) * step_x
			var wz := -FRAME_SAFE_Z + (float(gz) + 0.16 + rng.randf() * 0.68) * step_z
			if absf(wx) > FRAME_SAFE_X or absf(wz) > FRAME_SAFE_Z:
				continue

			var h := sampler.sample_height(wx, wz)
			if h <= sea + SHORE_HEIGHT_MIN:
				continue

			var splat_b := sampler.sample_splat_b(wx, wz)
			if splat_b.b > ROAD_SPLAT_MAX:
				continue

			if not _passes_exclusion_zones(sampler, wx, wz, city_exclusions, sea):
				continue

			var slope := sampler.sample_slope(wx, wz)
			if slope > 0.88:
				continue

			var splat_a := sampler.sample_splat_a(wx, wz)
			var clump_a := _clump_noise(wx * 0.85, wz * 0.85)
			var clump_b := _clump_noise(wx * 1.45 + 17.3, wz * 1.45 - 9.1)

			var chosen_species := ""
			var min_gap := 0.080

			# Tree-first priority on rolling hills (never let rocks swallow fertile plains!)
			if slope <= 0.64:
				# 1. Demon Continent crystal pockets (restrained mineral clusters on rifts)
				if splat_a.r > 0.40 and splat_b.a > 0.20 and clump_b > 0.50 and rng.randf() < 0.34:
					chosen_species = "demon_crystal"
					min_gap = 0.115
				# 2. Northern Tundra & high alpine shoulders -> snow-capped pines
				elif (splat_a.a > 0.22 or (h > 0.38 and splat_a.r < 0.32 and splat_a.g < 0.42)) and slope <= 0.68:
					var density_snow := clampf(splat_a.a * 1.35 + (h - 0.35) * 0.9, 0.0, 1.0)
					if clump_a > 0.36 and rng.randf() < lerpf(0.48, 0.84, density_snow):
						chosen_species = "pine_snow"
						min_gap = 0.070
				# 3. Milis Great Forest -> dense sculpted broadleaf canopy seas with scenic clearings
				elif splat_a.g > 0.34 and splat_b.g < 0.46:
					var density_g := clampf((splat_a.g - 0.30) * 1.55, 0.0, 1.0)
					if clump_a > 0.34 and rng.randf() < lerpf(0.58, 0.90, density_g):
						chosen_species = "broadleaf"
						min_gap = 0.062
				# 4. Central Continent meadows & plains -> graceful airy meadow tree & shrub groves
				elif splat_a.b > 0.36 and splat_b.g < 0.44 and slope <= 0.58:
					if clump_a > 0.41 and rng.randf() < 0.78:
						chosen_species = "meadow"
						min_gap = 0.072
				# 5. Demon Continent ochre wastes -> sparse weathered gnarled deadwood & scrub
				elif splat_a.r > 0.38 and splat_b.g < 0.44 and slope <= 0.62:
					if clump_a > 0.42 and rng.randf() < 0.42:
						chosen_species = "demon_deadwood"
						min_gap = 0.088

			# 6. Genuine rocky foothills, mountain crags, coastal bluffs & Demon mineral outcrops ONLY (zero rocks in open plains!)
			if chosen_species.is_empty():
				var rocky_foothill := (splat_b.r > 0.42) or (slope >= 0.46 and slope <= 0.86)
				var coastal_bluff := (splat_b.g > 0.24 and slope >= 0.30 and slope <= 0.78)
				var demon_outcrop := (splat_a.r > 0.48 and clump_b > 0.52 and slope >= 0.18 and slope <= 0.82)
				if (rocky_foothill or coastal_bluff or demon_outcrop) and clump_b > 0.40:
					if rng.randf() < (0.34 if demon_outcrop else 0.28):
						chosen_species = "rock_cluster"
						min_gap = 0.098

			if chosen_species.is_empty():
				continue
			if sampler.chunks != null and sampler.chunks.excludes_scatter(Vector2(wx, wz), chosen_species == "demon_deadwood"):
				continue
			if _obscures_hero_detail(chosen_species, Vector2(wx, wz)):
				continue
			if not _claim_spatial_cell(occupied, wx, wz, min_gap):
				continue

			_append_instance_record(buckets, sampler, rng, chosen_species, wx, h, wz, slope, splat_a)

	# Build the 6 hardware MultiMeshInstance3D nodes
	_assemble_multimeshes(buckets, meshes)


func _build_hero_cliffs(sampler: TerrainSampler, city_exclusions: Array[Dictionary]) -> void:
	var packed := HeroAssets.load_optional(HeroAssets.CLIFF_MODEL)
	if packed == null:
		return
	_hero_cliff_root = Node3D.new()
	_hero_cliff_root.name = &"NortheastHeroCliffs"
	add_child(_hero_cliff_root)
	var sample := packed.instantiate() as Node3D
	if sample == null:
		return
	_hero_cliff_root.add_child(sample)
	var bounds := HeroAssets.mesh_bounds(sample)
	sample.free()
	if not bounds.has_volume():
		return
	for index: int in HERO_CLIFFS.size():
		var config: Vector4 = HERO_CLIFFS[index]
		var position_xz := Vector2(config.x, config.y)
		var stretch := Vector3(1.03 + 0.16 * sin(index * 2.3), 1.08 + 0.29 * cos(index * 1.7),
			0.92 + 0.13 * cos(index * 2.1)) * config.z
		var radius := Vector2(bounds.size.x * stretch.x, bounds.size.z * stretch.z).length() * 0.5
		if _distance_to_land_routes(config.x, config.y) < HERO_ROUTE_CLEAR + radius:
			continue
		var overlaps_city := false
		for city: Dictionary in city_exclusions:
			var city_pos: Vector2 = city["pos"]
			if position_xz.distance_to(city_pos) < float(city["radius"]) + radius + 0.012:
				overlaps_city = true
				break
		if overlaps_city:
			continue
		var height := sampler.sample_height(config.x, config.y)
		var footing := height
		for i: int in range(8):
			var foot := position_xz + Vector2.from_angle(float(i) * TAU / 8.0) * radius * 0.60
			footing = minf(footing, sampler.sample_height(foot.x, foot.y))
		if footing <= sampler.get_sea_level() + 0.020:
			continue
		var cliff := packed.instantiate() as Node3D
		if cliff == null:
			continue
		if index % 4 == 1 or index % 4 == 2:
			stretch.x = -stretch.x
		var pose := Basis(Vector3.UP, deg_to_rad(config.w)).scaled_local(stretch)
		var embedded_y := height - minf(0.068, (height - footing) * 0.56) - 0.016
		cliff.transform = Transform3D(pose, Vector3(config.x, embedded_y, config.y))
		_hero_cliff_root.add_child(cliff)
		_cliff_footprints.append(Vector3(config.x, radius, config.y))


func hero_contacts() -> Array[Vector3]:
	return _cliff_footprints.duplicate()


func _obscures_hero_detail(species: String, position_xz: Vector2) -> bool:
	if _cliff_footprints.is_empty():
		return false
	# Reserve an unobstructed view across the two hero settlements, but leave
	# the rest of the continent's deterministic scatter alone.
	if species == "demon_deadwood" and Rect2(5.67, -4.27, 1.55, 1.35).has_point(position_xz):
		return true
	for footprint: Vector3 in _cliff_footprints:
		if position_xz.distance_to(Vector2(footprint.x, footprint.z)) < footprint.y + 0.03:
			return true
	return false


func _scatter_migurd_basin_ring(
	sampler: TerrainSampler,
	city_exclusions: Array[Dictionary],
	occupied: Dictionary[Vector2i, Array],
	buckets: Dictionary[String, Array],
	rng: RandomNumberGenerator
) -> int:
	if not sampler.has_city_position("city_migurd"):
		return 0
	var mig_center := sampler.get_city_position("city_migurd")
	var mig_r := 0.18
	for ex: Dictionary in city_exclusions:
		if str(ex.get("id", "")) == "city_migurd":
			mig_r = float(ex.get("radius", 0.18))
			break

	var sea := sampler.get_sea_level()
	var ring_min := mig_r + CITY_CLEAR_PAD + 0.015
	var ring_max := ring_min + 0.66
	var placed := 0
	var palette: Array[String] = ["rock_cluster", "demon_deadwood", "demon_crystal", "rock_cluster", "demon_deadwood"]

	for attempt: int in range(260):
		if placed >= 26:
			break
		var ang := TAU * (float(attempt) / 48.0) + rng.randf_range(-0.14, 0.14)
		var dist := lerpf(ring_min, ring_max, rng.randf())
		var wx := mig_center.x + cos(ang) * dist
		var wz := mig_center.z + sin(ang) * dist
		if absf(wx) > FRAME_SAFE_X or absf(wz) > FRAME_SAFE_Z:
			continue
		var h := sampler.sample_height(wx, wz)
		if h <= sea + SHORE_HEIGHT_MIN:
			continue
		if sampler.sample_splat_b(wx, wz).b > ROAD_SPLAT_MAX:
			continue
		if not _passes_exclusion_zones(sampler, wx, wz, city_exclusions, sea):
			continue
		var slope := sampler.sample_slope(wx, wz)
		if slope > 1.05:
			continue
		var sid: String = palette[attempt % palette.size()]
		if sid == "demon_deadwood" and slope > 0.66:
			sid = "demon_crystal" if attempt % 3 == 0 else "rock_cluster"
		if _obscures_hero_detail(sid, Vector2(wx, wz)):
			continue
		if not _claim_spatial_cell(occupied, wx, wz, 0.088):
			continue
		_append_instance_record(buckets, sampler, rng, sid, wx, h, wz, slope, sampler.sample_splat_a(wx, wz))
		placed += 1
	return placed


func _append_instance_record(
	buckets: Dictionary[String, Array],
	sampler: TerrainSampler,
	rng: RandomNumberGenerator,
	species_id: String,
	wx: float,
	wy: float,
	wz: float,
	slope: float,
	splat_a: Color
) -> void:
	var base_scale: float = float(SPECIES_BASE_SCALE.get(species_id, 0.11))
	var var_scale := rng.randf_range(0.74, 1.14) if species_id == "rock_cluster" else rng.randf_range(0.76, 1.32)
	var final_scale := base_scale * var_scale
	var yaw := rng.randf_range(0.0, TAU)

	var rot_basis := Basis(Vector3.UP, yaw)
	var embed := 0.015 + slope * 0.036
	if species_id == "rock_cluster":
		# Conform rock clusters partially to slope and embed firmly so bottoms never float
		var nrm := sampler.sample_normal(wx, wz)
		var slope_quat := Quaternion(Vector3.UP, nrm).slerp(Quaternion.IDENTITY, 0.58)
		rot_basis = Basis(slope_quat) * rot_basis
		embed = maxf(0.024, slope * 0.052)
	else:
		var tilt_x := rng.randf_range(-0.075, 0.075)
		var tilt_z := rng.randf_range(-0.075, 0.075)
		rot_basis = rot_basis * Basis.from_euler(Vector3(tilt_x, 0.0, tilt_z))
		if species_id == "demon_crystal":
			embed = maxf(0.020, slope * 0.044)

	var xform := Transform3D(rot_basis.scaled(Vector3.ONE * final_scale), Vector3(wx, wy - embed, wz))
	var inst_col := _pick_instance_color(species_id, splat_a, rng)
	var cont_idx := sampler.sample_continent_index(wx, wz)
	var warmth := rng.randf_range(0.08, 0.92)
	var custom := Color(warmth, var_scale, float(cont_idx), rng.randf())

	(buckets[species_id] as Array).append({
		"xform": xform,
		"color": inst_col,
		"custom": custom,
		"species": species_id,
		"pos": Vector3(wx, wy, wz),
	})
	_spawn_records.append({
		"species": species_id,
		"x": wx,
		"y": wy,
		"z": wz,
		"slope": slope,
	})


func _pick_instance_color(species_id: String, splat_a: Color, rng: RandomNumberGenerator) -> Color:
	var val := rng.randf_range(0.88, 1.00)
	if species_id == "rock_cluster":
		# Regional stone tinting matching continent strata
		var demon_stone := Color("#B07E5F")
		var milis_stone := Color("#7E979B")
		var central_stone := Color("#C47D64")
		var frost_stone := Color("#ABB5BF")
		var total_w := maxf(splat_a.r + splat_a.g + splat_a.b + splat_a.a, 0.001)
		var mix_c := (
			demon_stone * splat_a.r
			+ milis_stone * splat_a.g
			+ central_stone * splat_a.b
			+ frost_stone * splat_a.a
		) / total_w
		return Color(clampf(mix_c.r * val, 0.0, 1.0), clampf(mix_c.g * val, 0.0, 1.0), clampf(mix_c.b * val, 0.0, 1.0), 1.0)
	if species_id == "demon_crystal":
		var g_shift := rng.randf_range(0.90, 1.00)
		return Color(0.90 * g_shift, g_shift, 0.96 * g_shift, 1.0)
	var warm_jit := rng.randf_range(-0.04, 0.04)
	return Color(clampf(val + warm_jit, 0.78, 1.0), clampf(val + warm_jit * 0.3, 0.78, 1.0), clampf(val - warm_jit, 0.78, 1.0), 1.0)


func _assemble_multimeshes(buckets: Dictionary[String, Array], meshes: Dictionary[String, Mesh]) -> void:
	_total_instances = 0
	_total_instanced_tris = 0
	_buffer_vram_bytes = 0
	_species_stats.clear()

	for sid: String in SPECIES_ORDER:
		var items: Array = buckets.get(sid, [])
		var mesh: Mesh = meshes.get(sid, null)
		if items.is_empty() or mesh == null:
			continue

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = items.size()

		for i: int in items.size():
			var rec: Dictionary = items[i]
			mm.set_instance_transform(i, rec["xform"] as Transform3D)
			mm.set_instance_color(i, rec["color"] as Color)
			mm.set_instance_custom_data(i, rec["custom"] as Color)

		var mat := ShaderMaterial.new()
		mat.shader = PROP_SHADER
		mat.set_shader_parameter("wind_strength", float(SPECIES_WIND.get(sid, 0.0)))
		mat.set_shader_parameter("emission_boost", float(SPECIES_EMISSION.get(sid, 0.0)))
		mat.set_shader_parameter("atlas_blend", 1.0)
		mat.set_shader_parameter("night_glow", 0.0)

		var mmi := MultiMeshInstance3D.new()
		mmi.name = "BiomeMultiMesh_" + sid
		mmi.multimesh = mm
		mmi.material_override = mat
		# Trees cast crisp miniature diorama shadows; tiny ground rocks/crystals skip shadow pass for lean Mobile Draw Calls
		var casts_sh: bool = (sid != "rock_cluster" and sid != "demon_crystal")
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_sh else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

		var tri_count := _count_mesh_tris(mesh)
		var inst_tris := tri_count * items.size()
		# Per-instance buffer: 12 floats xform + 4 floats color + 4 floats custom = 80 bytes/instance
		_buffer_vram_bytes += items.size() * 80
		_total_instances += items.size()
		_total_instanced_tris += inst_tris
		_multimeshes[sid] = mmi
		_materials[sid] = mat
		_species_stats[sid] = {
			"instances": items.size(),
			"mesh_tris": tri_count,
			"total_tris": inst_tris,
			"cast_shadow": casts_sh,
		}


func sync_shader_uniforms(atlas_blend: float, active_cont_idx: int, crossing_cont_idx: int, night_glow: float = 0.0, winter_snow: float = 0.0, wetness: float = 0.0) -> void:
	for sid: String in _materials:
		var mat: ShaderMaterial = _materials[sid]
		mat.set_shader_parameter("atlas_blend", atlas_blend)
		mat.set_shader_parameter("active_continent_idx", active_cont_idx)
		mat.set_shader_parameter("crossing_continent_idx", crossing_cont_idx)
		mat.set_shader_parameter("night_glow", night_glow)
		mat.set_shader_parameter("winter_snow_push", winter_snow)
		mat.set_shader_parameter("wetness_boost", wetness)


func clear_scatter() -> void:
	if is_instance_valid(_hero_cliff_root):
		_hero_cliff_root.queue_free()
	_hero_cliff_root = null
	_cliff_footprints.clear()
	for sid: String in _multimeshes:
		var mmi: MultiMeshInstance3D = _multimeshes[sid]
		if mmi != null and is_instance_valid(mmi):
			mmi.queue_free()
	_multimeshes.clear()
	_materials.clear()
	_species_stats.clear()
	_spawn_records.clear()
	_total_instances = 0
	_total_instanced_tris = 0
	_buffer_vram_bytes = 0
	_migurd_basin_props = 0


func get_scatter_telemetry() -> Dictionary:
	return {
		"multimesh_count": _multimeshes.size(),
		"total_instances": _total_instances,
		"total_instanced_tris": _total_instanced_tris,
		"buffer_vram_kb": float(_buffer_vram_bytes) / 1024.0,
		"migurd_basin_props": _migurd_basin_props,
		"hero_cliffs": _cliff_footprints.size(),
		"species": _species_stats.duplicate(true),
	}


func audit_clearances(sampler: TerrainSampler, city_exclusions: Array[Dictionary]) -> Dictionary:
	var water_hits := 0
	var city_hits := 0
	var road_hits := 0
	var route_hits := 0
	var sea := sampler.get_sea_level()
	for rec: Dictionary in _spawn_records:
		var wx := float(rec["x"])
		var wz := float(rec["z"])
		var h := sampler.sample_height(wx, wz)
		if h <= sea + SHORE_HEIGHT_MIN * 0.92:
			water_hits += 1
		for ex: Dictionary in city_exclusions:
			var cp: Vector2 = ex["pos"]
			var min_r := float(ex["radius"]) + CITY_CLEAR_PAD - 0.005
			if Vector2(wx, wz).distance_to(cp) < min_r:
				city_hits += 1
				break
		if sampler.sample_splat_b(wx, wz).b > ROAD_SPLAT_MAX + 0.02:
			road_hits += 1
		if _distance_to_land_routes(wx, wz) < ROUTE_CORRIDOR_CLEAR - 0.005:
			route_hits += 1
	return {
		"checked": _spawn_records.size(),
		"water_hits": water_hits,
		"city_hits": city_hits,
		"road_hits": road_hits,
		"route_hits": route_hits,
	}


func _passes_exclusion_zones(sampler: TerrainSampler, wx: float, wz: float, city_exclusions: Array[Dictionary], sea: float) -> bool:
	# 1. Four-corner shoreline check so branches/boulders never dip into shallow coastal water
	var foot_r := 0.055
	if sampler.sample_height(wx + foot_r, wz) <= sea + FOOTPRINT_WATER_MIN \
	or sampler.sample_height(wx - foot_r, wz) <= sea + FOOTPRINT_WATER_MIN \
	or sampler.sample_height(wx, wz + foot_r) <= sea + FOOTPRINT_WATER_MIN \
	or sampler.sample_height(wx, wz - foot_r) <= sea + FOOTPRINT_WATER_MIN:
		return false

	# 2. All 19 city/port safety perimeters
	var p2 := Vector2(wx, wz)
	for ex: Dictionary in city_exclusions:
		var cp: Vector2 = ex["pos"]
		var clear_r := float(ex["radius"]) + CITY_CLEAR_PAD
		if p2.distance_to(cp) < clear_r:
			return false

	# 3. Land travel corridor clearance along all polylines in world_routes.json
	if _distance_to_land_routes(wx, wz) < ROUTE_CORRIDOR_CLEAR:
		return false
	return true


func _distance_to_land_routes(wx: float, wz: float) -> float:
	var best := 1e9
	var p := Vector2(wx, wz)
	for poly: PackedVector2Array in _route_polylines:
		for i: int in range(poly.size() - 1):
			var d := _dist_point_segment(p, poly[i], poly[i + 1])
			if d < best:
				best = d
	return best


static func _dist_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom < 1e-8:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _claim_spatial_cell(occupied: Dictionary[Vector2i, Array], wx: float, wz: float, min_dist: float) -> bool:
	var cx := int(floor(wx / SPATIAL_CELL))
	var cz := int(floor(wz / SPATIAL_CELL))
	var md2 := min_dist * min_dist
	for dz: int in range(-1, 2):
		for dx: int in range(-1, 2):
			var key := Vector2i(cx + dx, cz + dz)
			if not occupied.has(key):
				continue
			for existing: Vector2 in (occupied[key] as Array):
				if existing.distance_squared_to(Vector2(wx, wz)) < md2:
					return false
	var home := Vector2i(cx, cz)
	if not occupied.has(home):
		occupied[home] = []
	(occupied[home] as Array).append(Vector2(wx, wz))
	return true


func _load_prop_meshes() -> Dictionary[String, Mesh]:
	var out: Dictionary[String, Mesh] = {}
	for sid: String in SPECIES_ORDER:
		var path: String = str(SPECIES_PATHS.get(sid, ""))
		if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
			push_error("WorldBiomeScatter: missing prop GLB %s" % path)
			continue
		var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		if inst == null:
			continue
		var mmi := inst as MeshInstance3D
		if mmi == null:
			mmi = inst.find_child("*", true, false) as MeshInstance3D
		if mmi != null and mmi.mesh != null:
			out[sid] = mmi.mesh
		inst.free()
	return out


func _load_land_route_polylines(sampler: TerrainSampler) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if not FileAccess.file_exists(ROUTES_PATH):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROUTES_PATH))
	if not (parsed is Dictionary):
		return out
	var routes: Array = (parsed as Dictionary).get("routes", [])
	for r_v: Variant in routes:
		if not (r_v is Dictionary):
			continue
		var route: Dictionary = r_v
		if str(route.get("mode", "land")) == "ship":
			continue
		var f_id := str(route.get("from", ""))
		var t_id := str(route.get("to", ""))
		if not sampler.has_city_position(f_id) or not sampler.has_city_position(t_id):
			continue
		var pf := sampler.get_city_position(f_id)
		var pt := sampler.get_city_position(t_id)
		var pts := PackedVector2Array()
		pts.append(Vector2(pf.x, pf.z))
		var vias: Array = route.get("via", [])
		for vp_v: Variant in vias:
			if vp_v is Array and (vp_v as Array).size() >= 2:
				var va: Array = vp_v
				pts.append(Vector2((float(va[0]) - 836.0) * 0.01, (float(va[1]) - 470.5) * 0.01))
		pts.append(Vector2(pt.x, pt.z))
		out.append(pts)
	return out


static func _count_mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var total := 0
	for s: int in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if idx is PackedInt32Array and not (idx as PackedInt32Array).is_empty():
			total += (idx as PackedInt32Array).size() / 3
		elif verts is PackedVector3Array:
			total += (verts as PackedVector3Array).size() / 3
	return total


static func _hash2d(ix: int, iz: int) -> float:
	var n := sin(float(ix) * 127.1 + float(iz) * 311.7) * 43758.5453123
	return n - floor(n)


static func _vnoise(x: float, z: float) -> float:
	var ix := int(floor(x))
	var iz := int(floor(z))
	var fx := x - float(ix)
	var fz := z - float(iz)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uz := fz * fz * (3.0 - 2.0 * fz)
	var a := _hash2d(ix, iz)
	var b := _hash2d(ix + 1, iz)
	var c := _hash2d(ix, iz + 1)
	var d := _hash2d(ix + 1, iz + 1)
	return lerpf(lerpf(a, b, ux), lerpf(c, d, ux), uz)


static func _clump_noise(x: float, z: float) -> float:
	return _vnoise(x, z) * 0.65 + _vnoise(x * 2.13 + 5.7, z * 2.13 - 3.4) * 0.35
