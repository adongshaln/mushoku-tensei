class_name WorldWeatherStage
extends Node3D

const CLOUD_SHADER := preload("res://shaders/world_cloud_wisp.gdshader")
const MIST_SHADER := preload("res://shaders/basin_mist.gdshader")
const TerrainSampler := preload("res://scenes/world_map/world_terrain_sampler.gd")

const SNOW_COUNT := 140
const RAIN_COUNT := 120

var _clouds_root: Node3D
var _cloud_entries: Array[Dictionary] = []
var _mist_root: Node3D
var _mist_entries: Array[Dictionary] = []

var _snow_mm_inst: MultiMeshInstance3D
var _snow_mat: StandardMaterial3D
var _snow_items: Array[Dictionary] = []

var _rain_mm_inst: MultiMeshInstance3D
var _rain_mat: StandardMaterial3D
var _rain_items: Array[Dictionary] = []

var _clock := 0.0
var _winter_level := 0.0
var _rain_level := 0.0


func build(sampler: TerrainSampler, migurd_mist_strength: float = 1.0, mist_parent: Node3D = null) -> void:
	clear()
	_clouds_root = Node3D.new()
	_clouds_root.name = "HighAltitudeCloudWisps"
	add_child(_clouds_root)

	# 7 stylized high-altitude translucent watercolor cloud wisps gently drifting across seas & margins
	var cloud_specs: Array[Dictionary] = [
		{"pos": Vector3(-5.8, 1.82, -2.6), "size": Vector2(2.6, 1.35), "speed": Vector2(0.085, 0.025), "seed": 1.1, "base_alpha": 0.19},
		{"pos": Vector3(-1.4, 1.76, 1.3), "size": Vector2(3.1, 1.55), "speed": Vector2(0.068, 0.018), "seed": 2.4, "base_alpha": 0.17},
		{"pos": Vector3(2.8, 1.88, -1.9), "size": Vector2(2.8, 1.40), "speed": Vector2(0.075, -0.020), "seed": 3.7, "base_alpha": 0.18},
		{"pos": Vector3(5.4, 1.78, 2.2), "size": Vector2(2.4, 1.25), "speed": Vector2(0.062, 0.028), "seed": 5.0, "base_alpha": 0.16},
		{"pos": Vector3(-4.2, 1.92, 2.8), "size": Vector2(2.9, 1.50), "speed": Vector2(0.070, 0.015), "seed": 6.3, "base_alpha": 0.15},
		{"pos": Vector3(0.8, 1.85, -3.4), "size": Vector2(2.5, 1.20), "speed": Vector2(0.090, 0.022), "seed": 7.8, "base_alpha": 0.16},
		{"pos": Vector3(6.2, 1.74, -0.2), "size": Vector2(2.2, 1.18), "speed": Vector2(0.078, -0.014), "seed": 9.2, "base_alpha": 0.16},
	]
	for spec: Dictionary in cloud_specs:
		var qm := PlaneMesh.new()
		qm.size = spec["size"] as Vector2
		var mat := ShaderMaterial.new()
		mat.shader = CLOUD_SHADER
		mat.set_shader_parameter("seed_offset", float(spec["seed"]))
		mat.set_shader_parameter("opacity", float(spec["base_alpha"]))
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = spec["pos"] as Vector3
		_clouds_root.add_child(mi)
		_cloud_entries.append({
			"node": mi,
			"mat": mat,
			"home": spec["pos"] as Vector3,
			"speed": spec["speed"] as Vector2,
			"base_alpha": float(spec["base_alpha"]),
		})

	# Soft atmospheric basin mist nestled tightly around Migurd Village hollow (stays strictly off the wooden diorama frame!)
	_mist_root = Node3D.new()
	_mist_root.name = "MigurdBasinMist"
	var basin_atmosphere := self if mist_parent == null else mist_parent
	basin_atmosphere.add_child(_mist_root)
	if sampler != null and sampler.ready and sampler.has_city_position("city_migurd"):
		var mig := sampler.get_city_position("city_migurd")
		var mist_specs: Array[Dictionary] = [
			{"offset": Vector3(-0.08, 0.036, 0.14), "size": Vector2(0.86, 0.72), "phase": 0.2, "rot_speed": 0.035, "alpha": 0.14},
			{"offset": Vector3(-0.22, 0.064, 0.20), "size": Vector2(1.06, 0.84), "phase": 1.9, "rot_speed": -0.026, "alpha": 0.11},
		]
		for mspec: Dictionary in mist_specs:
			var mq := PlaneMesh.new()
			mq.size = mspec["size"] as Vector2
			var mmat := ShaderMaterial.new()
			mmat.shader = MIST_SHADER
			mmat.set_shader_parameter("drift_phase", float(mspec["phase"]))
			var opacity := float(mspec["alpha"]) * migurd_mist_strength
			mmat.set_shader_parameter("opacity", opacity)
			var mmi := MeshInstance3D.new()
			mmi.mesh = mq
			mmi.material_override = mmat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mpos := mig + (mspec["offset"] as Vector3)
			mpos.z = clampf(mpos.z, -3.96, 3.96)
			mpos.x = clampf(mpos.x, -7.65, 7.65)
			mmi.position = mpos
			_mist_root.add_child(mmi)
			_mist_entries.append({
				"node": mmi,
				"mat": mmat,
				"rot_speed": float(mspec["rot_speed"]),
				"base_alpha": opacity,
			})

	_build_seasonal_particles()


func _build_seasonal_particles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4180409

	# 1. Northern Winter Falling Snow Motes (MultiMesh, zero shadow pass, visible only in Winter)
	var snow_mesh := SphereMesh.new()
	snow_mesh.radius = 0.011
	snow_mesh.height = 0.020
	snow_mesh.radial_segments = 5
	snow_mesh.rings = 2
	_snow_mat = StandardMaterial3D.new()
	_snow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_snow_mat.albedo_color = Color(0.96, 0.96, 0.99, 0.72)
	_snow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_snow_mat.disable_receive_shadows = true

	var snow_mm := MultiMesh.new()
	snow_mm.transform_format = MultiMesh.TRANSFORM_3D
	snow_mm.mesh = snow_mesh
	snow_mm.instance_count = SNOW_COUNT
	_snow_mm_inst = MultiMeshInstance3D.new()
	_snow_mm_inst.name = "WinterSnowParticles"
	_snow_mm_inst.multimesh = snow_mm
	_snow_mm_inst.material_override = _snow_mat
	_snow_mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_snow_mm_inst.visible = false
	add_child(_snow_mm_inst)

	_snow_items.clear()
	for i: int in range(SNOW_COUNT):
		var sx := rng.randf_range(-7.3, -0.3)
		var sz := rng.randf_range(-4.1, -0.45)
		var sy := rng.randf_range(0.18, 1.55)
		var scale_f := rng.randf_range(0.75, 1.35)
		_snow_items.append({
			"x": sx,
			"y": sy,
			"z": sz,
			"speed": rng.randf_range(0.14, 0.28),
			"phase": rng.randf_range(0.0, TAU),
			"scale": scale_f,
		})
		snow_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale_f), Vector3(sx, sy, sz)))

	# 2. Milis Summer Rainy Season Fine Rain Streaks (MultiMesh, visible only in Rainy Months 6..8)
	var rain_mesh := CylinderMesh.new()
	rain_mesh.top_radius = 0.0032
	rain_mesh.bottom_radius = 0.0032
	rain_mesh.height = 0.16
	rain_mesh.radial_segments = 4
	rain_mesh.rings = 1
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.albedo_color = Color(0.84, 0.91, 0.98, 0.66)
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.disable_receive_shadows = true

	var rain_mm := MultiMesh.new()
	rain_mm.transform_format = MultiMesh.TRANSFORM_3D
	rain_mm.mesh = rain_mesh
	rain_mm.instance_count = RAIN_COUNT
	_rain_mm_inst = MultiMeshInstance3D.new()
	_rain_mm_inst.name = "MilisRainParticles"
	_rain_mm_inst.multimesh = rain_mm
	_rain_mm_inst.material_override = _rain_mat
	_rain_mm_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain_mm_inst.visible = false
	add_child(_rain_mm_inst)

	_rain_items.clear()
	var rain_tilt := Basis.from_euler(Vector3(0.0, 0.0, 0.14))
	for i: int in range(RAIN_COUNT):
		var rx := rng.randf_range(1.4, 6.7)
		var rz := rng.randf_range(0.35, 3.85)
		var ry := rng.randf_range(0.16, 1.50)
		_rain_items.append({
			"x": rx,
			"y": ry,
			"z": rz,
			"speed": rng.randf_range(1.15, 1.65),
			"basis": rain_tilt,
		})
		rain_mm.set_instance_transform(i, Transform3D(rain_tilt, Vector3(rx, ry, rz)))


func update_atmosphere(delta: float, cam_distance: float, time_slot: int, winter_push: float, wetness_push: float) -> void:
	_clock += delta
	_winter_level = clampf(winter_push, 0.0, 1.0)
	_rain_level = clampf(wetness_push, 0.0, 1.0)

	# Fade high-altitude clouds out cleanly when zooming close so camera & clicks stay 100% clear
	var zoom_fade := smoothstep(4.6, 11.8, cam_distance)
	var cloud_tint := Color("#FAF6EC")
	match time_slot:
		1:
			cloud_tint = Color("#FFEAD0")
		2:
			cloud_tint = Color("#F4BD94")
		3:
			cloud_tint = Color("#8EA3CB")

	for entry: Dictionary in _cloud_entries:
		var mi: MeshInstance3D = entry["node"]
		var mat: ShaderMaterial = entry["mat"]
		var home: Vector3 = entry["home"]
		var spd: Vector2 = entry["speed"]
		var wx := wrapf(home.x + _clock * spd.x, -8.5, 8.5)
		var wz := wrapf(home.z + _clock * spd.y, -4.7, 4.7)
		mi.position = Vector3(wx, home.y, wz)
		var rain_tint := cloud_tint.lerp(Color("#B2C2D4"), _rain_level * 0.45)
		mat.set_shader_parameter("cloud_tint", rain_tint)
		var op := float(entry["base_alpha"]) * zoom_fade * (1.0 + _rain_level * 0.35)
		mat.set_shader_parameter("opacity", op)
		mi.visible = op > 0.01

	# Migurd Basin mist gently swirls in Demon Continent hollow (subtle ochre-ivory veil)
	var mist_tint := Color("#DEC9B0")
	if time_slot == 2:
		mist_tint = Color("#E5B588")
	elif time_slot == 3:
		mist_tint = Color("#8D9EC2")
	var mist_zoom := lerpf(1.0, 0.55, zoom_fade)
	for mentry: Dictionary in _mist_entries:
		var mmi: MeshInstance3D = mentry["node"]
		var mmat: ShaderMaterial = mentry["mat"]
		mmi.rotation.y += float(mentry["rot_speed"]) * delta
		mmat.set_shader_parameter("mist_color", mist_tint)
		mmat.set_shader_parameter("opacity", float(mentry["base_alpha"]) * mist_zoom)

	# Northern Winter Snowflakes
	var show_snow := _winter_level > 0.14
	_snow_mm_inst.visible = show_snow
	if show_snow and _snow_mm_inst.multimesh != null:
		_snow_mat.albedo_color = Color(0.96, 0.96, 0.99, clampf(0.88 * _winter_level, 0.0, 0.88))
		var smm := _snow_mm_inst.multimesh
		for i: int in _snow_items.size():
			var it: Dictionary = _snow_items[i]
			var ny := float(it["y"]) - float(it["speed"]) * delta
			if ny < 0.14:
				ny = 1.55
			it["y"] = ny
			var sway_x := float(it["x"]) + sin(_clock * 1.4 + float(it["phase"])) * 0.09
			var sway_z := float(it["z"]) + cos(_clock * 1.1 + float(it["phase"])) * 0.06
			smm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * float(it["scale"])), Vector3(sway_x, ny, sway_z)))

	# Milis Summer Monsoon Rain
	var show_rain := _rain_level > 0.14
	_rain_mm_inst.visible = show_rain
	if show_rain and _rain_mm_inst.multimesh != null:
		_rain_mat.albedo_color = Color(0.80, 0.89, 0.96, clampf(0.58 * _rain_level, 0.0, 0.62))
		var rmm := _rain_mm_inst.multimesh
		for i: int in _rain_items.size():
			var rit: Dictionary = _rain_items[i]
			var ny := float(rit["y"]) - float(rit["speed"]) * delta
			if ny < 0.12:
				ny = 1.50
			rit["y"] = ny
			rmm.set_instance_transform(i, Transform3D(rit["basis"] as Basis, Vector3(float(rit["x"]), ny, float(rit["z"]))))


func clear() -> void:
	for child: Node in get_children():
		child.queue_free()
	_cloud_entries.clear()
	_mist_entries.clear()
	_snow_items.clear()
	_rain_items.clear()


func get_weather_telemetry() -> Dictionary:
	return {
		"cloud_wisps": _cloud_entries.size(),
		"migurd_mist_layers": _mist_entries.size(),
		"snow_active": _snow_mm_inst != null and _snow_mm_inst.visible,
		"rain_active": _rain_mm_inst != null and _rain_mm_inst.visible,
	}
