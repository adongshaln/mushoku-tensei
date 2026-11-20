extends TextureRect

const OUTLINE := preload("res://shaders/anime_outline.gdshader")
const PAD := 5

var definition: Dictionary
var source_bounds: Rect2
var _region_uv: Rect2
var _hit_mask: BitMap
var _paint: ShaderMaterial
var _placeholder: bool


func configure(data: Dictionary, alpha_mask: Image, cutoff: float, is_placeholder: bool) -> void:
	definition = data
	_placeholder = is_placeholder
	var used := alpha_mask.get_used_rect()
	var full := Rect2i(Vector2i.ZERO, alpha_mask.get_size())
	source_bounds = Rect2(Vector2(used.position) / Vector2(full.size), Vector2(used.size) / Vector2(full.size))
	var region := used.grow(PAD).intersection(full)
	_region_uv = Rect2(Vector2(region.position) / Vector2(full.size), Vector2(region.size) / Vector2(full.size))
	var mask := alpha_mask.get_region(region)
	_hit_mask = BitMap.new()
	_hit_mask.create_from_image_alpha(mask, cutoff)
	texture = ImageTexture.create_from_image(mask)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	_paint = ShaderMaterial.new()
	_paint.shader = OUTLINE
	material = _paint
	_paint.set_shader_parameter("show_placeholder", _placeholder)
	_paint.set_shader_parameter("placeholder_color", Color.html(str(data.get("placeholder_color", "997353"))))
	set_highlight(0)


func fit_to(size_in_stage: Vector2) -> void:
	position = _region_uv.position * size_in_stage
	size = _region_uv.size * size_in_stage


func contains(stage_point: Vector2) -> bool:
	if not get_rect().has_point(stage_point):
		return false
	var uv := (stage_point - position) / size
	var mask_size := _hit_mask.get_size()
	var pixel := Vector2i((uv * Vector2(mask_size)).floor())
	return _hit_mask.get_bitv(pixel.min(mask_size - Vector2i.ONE))


func set_highlight(state: int) -> void:
	visible = _placeholder or state > 0
	_paint.set_shader_parameter("outline_state", state)
	_paint.set_shader_parameter("outline_color", Color("#f9d38f") if state == 2 else Color("#c2e2ee"))
