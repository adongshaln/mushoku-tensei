class_name WorldTerrainSampler
extends RefCounted

const META_PATH := "res://data/maps/world_relief_meta.json"
const ChunkRegistry := preload("res://scenes/world_map/chunks/world_chunk_registry.gd")
const TILE_DIR := "res://assets/textures/world_v2/tiles"
const BIOME_TILE_NAMES: Array[String] = [
	"tile_00_demon_wastes",
	"tile_01_milis_forest",
	"tile_02_central_meadow",
	"tile_03_north_frost",
	"tile_04_mountain_rock",
	"tile_05_coastal_sand",
	"tile_06_royal_road",
	"tile_07_demon_rift",
]

var ready: bool = false
var chunks: ChunkRegistry
var min_x: float = -8.36
var max_x: float = 8.36
var min_z: float = -4.705
var max_z: float = 4.705
var world_width: float = 16.72
var world_depth: float = 9.41
var min_height: float = -0.295
var max_height: float = 1.2
var sea_level: float = 0.0

var height_image: Image = null
var region_id_image: Image = null
var splat_a_image: Image = null
var splat_b_image: Image = null
var ao_curvature_image: Image = null

var height_texture: ImageTexture = null
var region_id_texture: ImageTexture = null
var splat_a_texture: ImageTexture = null
var splat_b_texture: ImageTexture = null
var ao_curvature_texture: ImageTexture = null

var tile_albedo_array: Texture2DArray = null
var tile_normal_array: Texture2DArray = null
var walnut_albedo_texture: ImageTexture = null
var walnut_normal_texture: ImageTexture = null
var m2_tile_vram_bytes: int = 0
var m2_tiles_ready: bool = false

var _height_w: int = 0
var _height_h: int = 0
var _region_w: int = 0
var _region_h: int = 0
var _splat_a_w: int = 0
var _splat_a_h: int = 0
var _splat_b_w: int = 0
var _splat_b_h: int = 0

var _index_to_region_id: Dictionary[int, String] = {}
var _region_id_to_index: Dictionary[String, int] = {}
var _index_to_continent_id: Dictionary[int, String] = {}
var _continent_id_to_index: Dictionary[String, int] = {}
var _city_positions: Dictionary[String, Vector3] = {}
var _region_to_continent_id: Dictionary[String, String] = {}


func load_from_meta(meta_path: String = META_PATH) -> bool:
	ready = false
	var raw: String = FileAccess.get_file_as_string(meta_path)
	if raw.is_empty():
		push_error("WorldTerrainSampler: missing metadata file %s" % meta_path)
		return false
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("WorldTerrainSampler: invalid JSON in %s" % meta_path)
		return false
	var meta: Dictionary = parsed

	var bounds: Dictionary = meta.get("world_bounds", {})
	min_x = float(bounds.get("min_x", -8.36))
	max_x = float(bounds.get("max_x", 8.36))
	min_z = float(bounds.get("min_z", -4.705))
	max_z = float(bounds.get("max_z", 4.705))
	world_width = maxf(max_x - min_x, 0.001)
	world_depth = maxf(max_z - min_z, 0.001)

	var hrange: Dictionary = meta.get("height_range", {})
	min_height = float(hrange.get("min_height", -0.295))
	max_height = float(hrange.get("max_height", 1.2))
	sea_level = float(hrange.get("sea_level", 0.0))

	_index_to_region_id.clear()
	_region_id_to_index.clear()
	_index_to_continent_id.clear()
	_continent_id_to_index.clear()
	_city_positions.clear()
	_region_to_continent_id.clear()

	var cont_dict: Dictionary = meta.get("continents", {})
	for cid_v: Variant in cont_dict.keys():
		var cid: String = str(cid_v)
		var cidx: int = int(cont_dict[cid_v])
		_continent_id_to_index[cid] = cidx
		_index_to_continent_id[cidx] = cid

	var regions: Array = meta.get("regions", [])
	for reg_v: Variant in regions:
		if not (reg_v is Dictionary):
			continue
		var reg: Dictionary = reg_v
		var ridx: int = int(reg.get("index", 0))
		var rid: String = str(reg.get("id", ""))
		var cid: String = str(reg.get("continent_id", ""))
		if ridx > 0 and not rid.is_empty():
			_index_to_region_id[ridx] = rid
			_region_id_to_index[rid] = ridx
			_region_to_continent_id[rid] = cid

	var cities: Dictionary = meta.get("cities", {})
	for node_v: Variant in cities.keys():
		var node_id: String = str(node_v)
		var entry_v: Variant = cities[node_v]
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = entry_v
		var pos_arr: Array = entry.get("position", [])
		if pos_arr.size() >= 3:
			_city_positions[node_id] = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))

	var maps: Dictionary = meta.get("control_maps", {})
	var h_path: String = str(maps.get("heightmap", "res://assets/textures/world_v2/world_heightmap.png"))
	var r_path: String = str(maps.get("region_id_map", "res://assets/textures/world_v2/world_region_id_map.png"))
	var a_path: String = str(maps.get("biome_splat_a", "res://assets/textures/world_v2/world_biome_splat_a.png"))
	var b_path: String = str(maps.get("biome_splat_b", "res://assets/textures/world_v2/world_biome_splat_b.png"))
	var ao_path: String = str(maps.get("ao_curvature_map", "res://assets/textures/world_v2/world_ao_curvature.png"))

	height_image = _load_lossless_image(h_path)
	region_id_image = _load_lossless_image(r_path)
	splat_a_image = _load_lossless_image(a_path)
	splat_b_image = _load_lossless_image(b_path)
	ao_curvature_image = _load_lossless_image(ao_path)

	if height_image == null or region_id_image == null:
		push_error("WorldTerrainSampler: failed to load required heightmap or region_id_map.")
		return false

	_height_w = height_image.get_width()
	_height_h = height_image.get_height()
	_region_w = region_id_image.get_width()
	_region_h = region_id_image.get_height()

	# Build lossless GPU textures directly from uncompressed CPU Images (zero VRAM block corruption).
	height_texture = ImageTexture.create_from_image(height_image)
	region_id_texture = ImageTexture.create_from_image(region_id_image)
	if splat_a_image != null:
		_splat_a_w = splat_a_image.get_width()
		_splat_a_h = splat_a_image.get_height()
		splat_a_texture = ImageTexture.create_from_image(splat_a_image)
	if splat_b_image != null:
		_splat_b_w = splat_b_image.get_width()
		_splat_b_h = splat_b_image.get_height()
		splat_b_texture = ImageTexture.create_from_image(splat_b_image)
	if ao_curvature_image != null:
		ao_curvature_texture = ImageTexture.create_from_image(ao_curvature_image)

	m2_tiles_ready = _load_biome_tile_arrays()
	ready = _height_w > 1 and _height_h > 1 and _region_w > 1 and _region_h > 1
	return ready


func _load_biome_tile_arrays() -> bool:
	m2_tile_vram_bytes = 0
	var albedo_layers: Array[Image] = []
	var normal_layers: Array[Image] = []
	for tile_name: String in BIOME_TILE_NAMES:
		var alb_img: Image = _load_lossless_image("%s/%s_albedo.png" % [TILE_DIR, tile_name])
		var nrm_img: Image = _load_lossless_image("%s/%s_normal.png" % [TILE_DIR, tile_name])
		if alb_img == null or nrm_img == null:
			push_error("WorldTerrainSampler: missing M2 tile %s" % tile_name)
			return false
		if alb_img.get_format() != Image.FORMAT_RGBA8:
			alb_img.convert(Image.FORMAT_RGBA8)
		if nrm_img.get_format() != Image.FORMAT_RGBA8:
			nrm_img.convert(Image.FORMAT_RGBA8)
		alb_img.generate_mipmaps()
		nrm_img.generate_mipmaps()
		m2_tile_vram_bytes += alb_img.get_data().size() + nrm_img.get_data().size()
		albedo_layers.append(alb_img)
		normal_layers.append(nrm_img)

	tile_albedo_array = Texture2DArray.new()
	if tile_albedo_array.create_from_images(albedo_layers) != OK:
		push_error("WorldTerrainSampler: failed to build tile_albedo_array")
		return false
	tile_normal_array = Texture2DArray.new()
	if tile_normal_array.create_from_images(normal_layers) != OK:
		push_error("WorldTerrainSampler: failed to build tile_normal_array")
		return false

	var w_alb: Image = _load_lossless_image("%s/tile_walnut_frame_albedo.png" % TILE_DIR)
	if w_alb != null:
		if w_alb.get_format() != Image.FORMAT_RGBA8:
			w_alb.convert(Image.FORMAT_RGBA8)
		w_alb.generate_mipmaps()
		m2_tile_vram_bytes += w_alb.get_data().size()
		walnut_albedo_texture = ImageTexture.create_from_image(w_alb)
	var w_nrm: Image = _load_lossless_image("%s/tile_walnut_frame_normal.png" % TILE_DIR)
	if w_nrm != null:
		if w_nrm.get_format() != Image.FORMAT_RGBA8:
			w_nrm.convert(Image.FORMAT_RGBA8)
		w_nrm.generate_mipmaps()
		m2_tile_vram_bytes += w_nrm.get_data().size()
		walnut_normal_texture = ImageTexture.create_from_image(w_nrm)
	return true


func get_m2_vram_mb() -> float:
	return float(m2_tile_vram_bytes) / (1024.0 * 1024.0)


func world_to_uv(world_x: float, world_z: float) -> Vector2:
	var u: float = clampf((world_x - min_x) / world_width, 0.0, 1.0)
	var v: float = clampf((world_z - min_z) / world_depth, 0.0, 1.0)
	return Vector2(u, v)


func sample_height(world_x: float, world_z: float) -> float:
	if not ready or height_image == null:
		return sea_level
	if chunks != null:
		var world_xz := Vector2(world_x, world_z)
		var chunk := chunks.at(world_xz)
		if chunk != null:
			return chunk.sample_surface(world_xz).w
	var uv: Vector2 = world_to_uv(world_x, world_z)
	var fx: float = uv.x * float(_height_w - 1)
	var fy: float = uv.y * float(_height_h - 1)
	var x0: int = clampi(int(floor(fx)), 0, _height_w - 1)
	var y0: int = clampi(int(floor(fy)), 0, _height_h - 1)
	var x1: int = mini(x0 + 1, _height_w - 1)
	var y1: int = mini(y0 + 1, _height_h - 1)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var h00: float = height_image.get_pixel(x0, y0).r
	var h10: float = height_image.get_pixel(x1, y0).r
	var h01: float = height_image.get_pixel(x0, y1).r
	var h11: float = height_image.get_pixel(x1, y1).r
	var top: float = lerpf(h00, h10, tx)
	var bot: float = lerpf(h01, h11, tx)
	var norm_h: float = lerpf(top, bot, ty)
	return min_height + norm_h * (max_height - min_height)


func sample_surface_height(world_x: float, world_z: float) -> float:
	return maxf(sample_height(world_x, world_z), sea_level)


func sample_region_index(world_x: float, world_z: float) -> int:
	if not ready or region_id_image == null:
		return 0
	var uv: Vector2 = world_to_uv(world_x, world_z)
	var ix: int = clampi(int(round(uv.x * float(_region_w - 1))), 0, _region_w - 1)
	var iy: int = clampi(int(round(uv.y * float(_region_h - 1))), 0, _region_h - 1)
	var px: Color = region_id_image.get_pixel(ix, iy)
	return int(round(px.r * 255.0))


func sample_region_id(world_x: float, world_z: float) -> String:
	var idx: int = sample_region_index(world_x, world_z)
	return _index_to_region_id.get(idx, "")


func sample_continent_index(world_x: float, world_z: float) -> int:
	if not ready or region_id_image == null:
		return 0
	var uv: Vector2 = world_to_uv(world_x, world_z)
	var ix: int = clampi(int(round(uv.x * float(_region_w - 1))), 0, _region_w - 1)
	var iy: int = clampi(int(round(uv.y * float(_region_h - 1))), 0, _region_h - 1)
	var px: Color = region_id_image.get_pixel(ix, iy)
	return int(round(px.g * 255.0))


func sample_continent_id(world_x: float, world_z: float) -> String:
	var cidx: int = sample_continent_index(world_x, world_z)
	return _index_to_continent_id.get(cidx, "")


func get_region_index(region_id: String) -> int:
	return _region_id_to_index.get(region_id, 0)


func get_continent_index(continent_id: String) -> int:
	return _continent_id_to_index.get(continent_id, 0)


func get_region_continent_id(region_id: String) -> String:
	return _region_to_continent_id.get(region_id, "")


func get_city_position(city_id: String) -> Vector3:
	if _city_positions.has(city_id):
		var p: Vector3 = _city_positions[city_id]
		return Vector3(p.x, sample_height(p.x, p.z), p.z)
	return Vector3(0.0, sea_level, 0.0)


func has_city_position(city_id: String) -> bool:
	return _city_positions.has(city_id)


func get_sea_level() -> float:
	return sea_level


func get_all_city_positions() -> Dictionary[String, Vector3]:
	var out: Dictionary[String, Vector3] = {}
	for cid: String in _city_positions:
		var p: Vector3 = _city_positions[cid]
		out[cid] = Vector3(p.x, sample_height(p.x, p.z), p.z)
	return out


func sample_splat_a(world_x: float, world_z: float) -> Color:
	if not ready or splat_a_image == null or _splat_a_w <= 1 or _splat_a_h <= 1:
		return Color(0.0, 0.0, 0.0, 0.0)
	var uv: Vector2 = world_to_uv(world_x, world_z)
	var ix: int = clampi(int(round(uv.x * float(_splat_a_w - 1))), 0, _splat_a_w - 1)
	var iy: int = clampi(int(round(uv.y * float(_splat_a_h - 1))), 0, _splat_a_h - 1)
	return splat_a_image.get_pixel(ix, iy)


func sample_splat_b(world_x: float, world_z: float) -> Color:
	if not ready or splat_b_image == null or _splat_b_w <= 1 or _splat_b_h <= 1:
		return Color(0.0, 0.0, 0.0, 0.0)
	var uv: Vector2 = world_to_uv(world_x, world_z)
	var ix: int = clampi(int(round(uv.x * float(_splat_b_w - 1))), 0, _splat_b_w - 1)
	var iy: int = clampi(int(round(uv.y * float(_splat_b_h - 1))), 0, _splat_b_h - 1)
	return splat_b_image.get_pixel(ix, iy)


func sample_normal(world_x: float, world_z: float) -> Vector3:
	if not ready or height_image == null:
		return Vector3.UP
	var eps := 0.045
	var dhdx: float = (sample_height(world_x + eps, world_z) - sample_height(world_x - eps, world_z)) / (2.0 * eps)
	var dhdz: float = (sample_height(world_x, world_z + eps) - sample_height(world_x, world_z - eps)) / (2.0 * eps)
	return Vector3(-dhdx, 1.0, -dhdz).normalized()


func sample_slope(world_x: float, world_z: float) -> float:
	if not ready or height_image == null:
		return 0.0
	var eps := 0.045
	var dhdx: float = (sample_height(world_x + eps, world_z) - sample_height(world_x - eps, world_z)) / (2.0 * eps)
	var dhdz: float = (sample_height(world_x, world_z + eps) - sample_height(world_x, world_z - eps)) / (2.0 * eps)
	return sqrt(dhdx * dhdx + dhdz * dhdz)


func _load_lossless_image(res_path: String) -> Image:
	if FileAccess.file_exists(res_path):
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(res_path)
		if not bytes.is_empty():
			var img := Image.new()
			if img.load_png_from_buffer(bytes) == OK:
				return img
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			var tex_img: Image = (res as Texture2D).get_image()
			if tex_img != null:
				if tex_img.is_compressed():
					tex_img.decompress()
				return tex_img
	return null
