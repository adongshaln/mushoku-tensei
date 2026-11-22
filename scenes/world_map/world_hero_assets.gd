extends RefCounted

const CITY_MODELS: Dictionary[String, String] = {
	"city_migurd": "res://assets/3d/world_v2/heroes/hero_migurd_village.glb",
	"city_rikarisu": "res://assets/3d/world_v2/heroes/hero_rikarisu_town.glb",
}
const CLIFF_MODEL := "res://assets/3d/world_v2/heroes/kit_demon_cliff_a.glb"
const SOIL_PALETTE := "res://assets/textures/world_v2/hero_ground_palette.json"
const SOIL_PATCH := Rect2(5.16, -4.49, 2.46, 1.97)
const CONTACT_SIZE := 192
const CITY_MODEL_DIR := "res://assets/3d/world_v2/heroes"


static func load_optional(path: String) -> PackedScene:
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return null
	return ResourceLoader.load(path, "PackedScene") as PackedScene


static func load_city(city_node: String, city_id: String) -> PackedScene:
	var standard := load_optional("%s/hero_%s.glb" % [CITY_MODEL_DIR, city_id])
	return standard if standard != null else load_optional(CITY_MODELS.get(city_node, ""))


static func without_legacy_plinth(source: Mesh) -> Mesh:
	var trimmed := ArrayMesh.new()
	for surface: int in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var stone := source.surface_get_material(surface)
		if stone != null and stone.resource_name in ["Aged brass footing", "Warm cut limestone"]:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var indices := PackedInt32Array()
			for face: int in range(0, original.size(), 3):
				var a := original[face]
				var b := original[face + 1]
				var c := original[face + 2]
				if maxf(vertices[a].y, maxf(vertices[b].y, vertices[c].y)) <= 0.17501:
					continue
				indices.append(a)
				indices.append(b)
				indices.append(c)
			if indices.is_empty():
				continue
			arrays[Mesh.ARRAY_INDEX] = indices
		trimmed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		trimmed.surface_set_material(trimmed.get_surface_count() - 1, stone)
	return trimmed


static func mesh_bounds(model: Node3D) -> AABB:
	var bounds := AABB()
	var inverse := model.global_transform.affine_inverse()
	for mesh: MeshInstance3D in mesh_nodes(model):
		var part: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		bounds = part if not bounds.has_volume() else bounds.merge(part)
	return bounds


static func mesh_nodes(model: Node3D) -> Array[MeshInstance3D]:
	var parts: Array[MeshInstance3D] = []
	var own := model as MeshInstance3D
	if own != null and own.mesh != null:
		parts.append(own)
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.mesh != null:
			parts.append(part)
	return parts


static func apply_ground(material: ShaderMaterial, contacts: Array[Vector3]) -> void:
	if material == null or contacts.is_empty() or not FileAccess.file_exists(SOIL_PALETTE):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOIL_PALETTE))
	if not parsed is Dictionary:
		return
	var palette: Dictionary = parsed
	var rock: Array = palette.get("kit_demon_cliff_a", {}).get("skirt_rgb", [])
	var sand: Array = palette.get("hero_migurd_village", {}).get("skirt_rgb", [])
	if rock.size() != 3 or sand.size() != 3:
		return
	var pixels := PackedByteArray()
	pixels.resize(CONTACT_SIZE * CONTACT_SIZE)
	for stamp: Vector3 in contacts:
		var center := Vector2(stamp.x, stamp.z)
		var radius := stamp.y
		var low := (center - Vector2.ONE * radius - SOIL_PATCH.position) / SOIL_PATCH.size * CONTACT_SIZE
		var high := (center + Vector2.ONE * radius - SOIL_PATCH.position) / SOIL_PATCH.size * CONTACT_SIZE
		for y: int in range(maxi(0, floori(low.y)), mini(CONTACT_SIZE, ceili(high.y))):
			for x: int in range(maxi(0, floori(low.x)), mini(CONTACT_SIZE, ceili(high.x))):
				var sample_position := SOIL_PATCH.position + (Vector2(x, y) + Vector2(0.5, 0.5)) / CONTACT_SIZE * SOIL_PATCH.size
				var falloff := 1.0 - smoothstep(0.32, 1.0, center.distance_to(sample_position) / radius)
				var index := y * CONTACT_SIZE + x
				pixels[index] = maxi(pixels[index], roundi(falloff * 255.0))
	var image := Image.create_from_data(CONTACT_SIZE, CONTACT_SIZE, false, Image.FORMAT_R8, pixels)
	material.set_shader_parameter("hero_ground_contact", ImageTexture.create_from_image(image))
	material.set_shader_parameter("hero_ground_rect", Vector4(SOIL_PATCH.position.x, SOIL_PATCH.position.y, SOIL_PATCH.size.x, SOIL_PATCH.size.y))
	material.set_shader_parameter("hero_rock_color", Color(float(rock[0]), float(rock[1]), float(rock[2])))
	material.set_shader_parameter("hero_sand_color", Color(float(sand[0]), float(sand[1]), float(sand[2])))
	material.set_shader_parameter("hero_ground_enabled", true)
