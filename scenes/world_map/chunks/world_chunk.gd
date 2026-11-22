extends Node3D

const HeroAssets := preload("res://scenes/world_map/world_hero_assets.gd")
const PropPlacer := preload("res://scenes/world_map/chunks/chunk_prop_placer.gd")
const PROP_MODELS: Dictionary[String, String] = {
	"cliff": "res://assets/3d/world_v2/heroes/kit_demon_cliff_a.glb",
	"crystal": "res://assets/3d/world_v2/props/prop_demon_crystal.glb",
}

var bounds: Rect2
var terrain_root: Node3D
var assets_root: Node3D
var atmosphere_root: Node3D
var custom_props: PropPlacer
var material: ShaderMaterial
var city_ids: PackedStringArray
var terrain_group: String
var hide_legacy_plinth := false
var shadow_softness := 1.0
var scatter_exclusion_margin: float
var _cells: Vector2i
var _heights: PackedFloat32Array
var _terrain_materials: Dictionary[String, Texture2D]
var _lamps: Array[OmniLight3D] = []


func build(config: Dictionary, macro_material: ShaderMaterial, terrain_layer: int) -> bool:
	var rect: Array = config.get("bounds", [])
	var cells: Array = config.get("grid_cells", [])
	if rect.size() != 4 or cells.size() != 2 or macro_material == null:
		return false
	bounds = Rect2(float(rect[0]), float(rect[1]), float(rect[2]) - float(rect[0]), float(rect[3]) - float(rect[1]))
	_cells = Vector2i(int(cells[0]), int(cells[1]))
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or _cells.x < 1 or _cells.y < 1:
		return false
	var model := HeroAssets.load_optional(str(config.get("terrain", "")))
	if model == null:
		return false
	for channel: String in ["albedo", "normal", "ao", "roughness"]:
		var path := "%s_%s.png" % [str(config.get("pbr_prefix", "")), channel]
		var image := load(path) as Texture2D if ResourceLoader.exists(path, "Texture2D") else null
		if image == null:
			return false
		_terrain_materials[channel] = image
	name = str(config["id"])
	var instance := model.instantiate() as Node3D
	if instance == null:
		return false
	terrain_root = Node3D.new()
	terrain_root.name = &"TerrainRoot"
	add_child(terrain_root)
	terrain_root.add_child(instance)
	var parts := HeroAssets.mesh_nodes(instance)
	if parts.size() != 1 or not _read_surface_grid(parts[0]):
		return false
	var mesh: MeshInstance3D = parts[0]
	var collider := StaticBody3D.new()
	collider.name = &"SculptedGround"
	collider.collision_layer = terrain_layer
	collider.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.shape = mesh.mesh.create_trimesh_shape()
	mesh.add_child(collider)
	collider.add_child(shape)

	material = macro_material.duplicate() as ShaderMaterial
	material.set_shader_parameter("sculpted_terrain", true)
	material.set_shader_parameter("sculpted_seam", float(config.get("seam_width", 0.35)))
	for channel: String in _terrain_materials:
		material.set_shader_parameter("sculpted_" + channel, _terrain_materials[channel])
	mesh.material_override = material

	assets_root = Node3D.new()
	assets_root.name = &"AssetsRoot"
	add_child(assets_root)
	custom_props = PropPlacer.new()
	custom_props.name = &"CustomProps"
	assets_root.add_child(custom_props)
	custom_props.configure(sample_surface, collider)
	atmosphere_root = Node3D.new()
	atmosphere_root.name = &"AtmosphereRoot"
	add_child(atmosphere_root)
	city_ids = PackedStringArray(config.get("cities", []))
	terrain_group = str(config.get("terrain_group", ""))
	hide_legacy_plinth = bool(config.get("hide_legacy_plinth", false))
	shadow_softness = clampf(float(config.get("shadow_softness", 1.0)), 0.5, 1.0)
	scatter_exclusion_margin = maxf(0.0, float(config.get("scatter_exclusion_margin", 0.0)))
	for prop: Dictionary in config.get("props", []):
		_place_prop(prop)
	return true


func _read_surface_grid(mesh: MeshInstance3D) -> bool:
	_heights.resize((_cells.x + 1) * (_cells.y + 1))
	_heights.fill(NAN)
	var inverse := global_transform.affine_inverse() * mesh.global_transform
	for surface: int in mesh.mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for local_point: Vector3 in vertices:
			var point := inverse * local_point
			var uv := (Vector2(point.x, point.z) - bounds.position) / bounds.size
			var cell := Vector2i(roundi(uv.x * _cells.x), roundi(uv.y * _cells.y))
			if cell.x < 0 or cell.x > _cells.x or cell.y < 0 or cell.y > _cells.y:
				return false
			_heights[cell.y * (_cells.x + 1) + cell.x] = point.y
	for value: float in _heights:
		if not is_finite(value):
			return false
	return true


func world_bounds_uniform() -> Vector4:
	return Vector4(bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y)


# GLB cells use the NW→SE diagonal. This is the exact triangle plane used
# by physics, including where a sample falls between mesh vertices.
func sample_surface(xz: Vector2) -> Vector4:
	const EDGE_EPSILON := 0.000001
	if xz.x < bounds.position.x - EDGE_EPSILON or xz.x > bounds.end.x + EDGE_EPSILON \
			or xz.y < bounds.position.y - EDGE_EPSILON or xz.y > bounds.end.y + EDGE_EPSILON:
		return Vector4(0.0, 1.0, 0.0, NAN)
	var uv := ((xz - bounds.position) / bounds.size).clamp(Vector2.ZERO, Vector2.ONE)
	var grid := uv * Vector2(_cells)
	var x := clampi(floori(grid.x), 0, _cells.x - 1)
	var z := clampi(floori(grid.y), 0, _cells.y - 1)
	var dx := grid.x - x
	var dz := grid.y - z
	var stride := _cells.x + 1
	var i := z * stride + x
	var a := _heights[i]
	var b := _heights[i + 1]
	var c := _heights[i + stride]
	var d := _heights[i + stride + 1]
	var dh := Vector2(d - c, c - a) if dz > dx else Vector2(b - a, d - b)
	var normal := Vector3(-dh.x * _cells.x / bounds.size.x, 1.0, -dh.y * _cells.y / bounds.size.y).normalized()
	var height := a + dh.dot(Vector2(dx, dz))
	return Vector4(normal.x, normal.y, normal.z, height)


func depth_image(resolution: int) -> Image:
	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	for z: int in resolution:
		for x: int in resolution:
			var xz := bounds.position + bounds.size * Vector2(x, z) / float(resolution - 1)
			heights[z * resolution + x] = sample_surface(xz).w
	return Image.create_from_data(resolution, resolution, false, Image.FORMAT_RF, heights.to_byte_array())


func add_city_lamps(center: Vector3, half_extents: Vector2) -> void:
	var extent := minf(half_extents.x, half_extents.y)
	for offset: Vector2 in [Vector2(-0.36, 0.60), Vector2(0.36, -0.40), Vector2(0.45, 0.65)]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#FFB760")
		lamp.omni_range = 0.102 + extent * 0.20
		lamp.omni_attenuation = 1.45
		lamp.light_energy = 0.0
		lamp.position = center + Vector3(offset.x * extent, extent * 0.34, offset.y * extent)
		atmosphere_root.add_child(lamp)
		_lamps.append(lamp)


func set_night_glow(strength: float) -> void:
	for lamp: OmniLight3D in _lamps:
		lamp.light_energy = strength * 0.11


func _place_prop(config: Dictionary) -> void:
	var xz: Array = config.get("xz", [])
	var size: Array = config.get("scale", [])
	if xz.size() != 2 or size.size() != 3:
		return
	var location := Vector2(float(xz[0]), float(xz[1]))
	if sample_surface(location).w < 0.045:
		return
	var packed := HeroAssets.load_optional(PROP_MODELS.get(str(config.get("kind", "")), ""))
	if packed == null:
		return
	var prop := packed.instantiate() as Node3D
	if prop == null:
		return
	prop.scale = Vector3(float(size[0]), float(size[1]), float(size[2]))
	prop.rotation_degrees.y = float(config.get("yaw", 0.0))
	custom_props.snap_node_to_terrain(prop, location, float(config.get("embed", -0.008)), 0.12)
	if str(config.get("kind", "")) == "crystal":
		for mesh: MeshInstance3D in HeroAssets.mesh_nodes(prop):
			for slot: int in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(slot) as StandardMaterial3D
				if source == null:
					continue
				var mineral := source.duplicate() as StandardMaterial3D
				mineral.vertex_color_use_as_albedo = true
				mineral.albedo_color = Color("#A3DAB5")
				mineral.emission_enabled = true
				mineral.emission = Color("#43B890")
				mineral.emission_energy_multiplier = 0.13
				mesh.set_surface_override_material(slot, mineral)
