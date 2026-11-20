extends Control

const OUTLINE := preload("res://shaders/anime_outline.gdshader")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")

var definition: Dictionary
var region_id := ""
var mask: Image
var bounds: Rect2i
var anchor_local := Vector2.ZERO

var _shadow: TextureRect
var _side: TextureRect
var _lift: Control
var _body: TextureRect
var _paint: ShaderMaterial
var _star_label: Label
var _star: PanelContainer
var _hover := false
var _font: SystemFont


func configure(data: Dictionary, base_image: Image, base_size: Vector2, font: SystemFont) -> void:
	definition = data
	region_id = str(data["id"])
	_font = font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var polygon := PackedVector2Array()
	for point: Array in data["polygon"]:
		polygon.append(Vector2(float(point[0]), float(point[1])) * base_size)
	var override_path := "res://assets/maps/demon_continent/regions/%s.png" % region_id
	var region_image: Image
	if ResourceLoader.exists(override_path, "Texture2D"):
		var override_texture := load(override_path) as Texture2D
		region_image = override_texture.get_image()
		bounds = region_image.get_used_rect()
		mask = region_image.get_region(bounds)
		region_image = region_image.get_region(bounds)
		region_image.convert(Image.FORMAT_RGBA8)
	else:
		var used := Rect2(polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon:
			used = used.expand(point)
		bounds = Rect2i(used.grow(2.0)).intersection(Rect2i(Vector2i.ZERO, base_image.get_size()))
		var local_polygon := PackedVector2Array()
		for point: Vector2 in polygon:
			local_polygon.append(point - Vector2(bounds.position))
		mask = _scanline_mask(local_polygon, bounds.size)
		region_image = base_image.get_region(bounds)
		region_image.convert(Image.FORMAT_RGBA8)
		for y: int in bounds.size.y:
			for x: int in bounds.size.x:
				var alpha := mask.get_pixel(x, y).a
				var source := region_image.get_pixel(x, y)
				region_image.set_pixel(x, y, Color(source.r, source.g, source.b, alpha))
	size = Vector2(bounds.size)
	anchor_local = Vector2(float(data["anchor"][0]), float(data["anchor"][1])) * base_size - Vector2(bounds.position)

	var silhouette := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	for y: int in bounds.size.y:
		for x: int in bounds.size.x:
			silhouette.set_pixel(x, y, Color(1, 1, 1, mask.get_pixel(x, y).a))
	var silhouette_texture := ImageTexture.create_from_image(silhouette)

	_shadow = TextureRect.new()
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shadow.stretch_mode = TextureRect.STRETCH_SCALE
	_shadow.texture = silhouette_texture
	_shadow.modulate = Color("#2f2318", 0.35)
	_shadow.position = Vector2(6, 10)
	_shadow.size = size
	add_child(_shadow)

	_side = TextureRect.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_side.stretch_mode = TextureRect.STRETCH_SCALE
	_side.texture = silhouette_texture
	_side.modulate = Color("#5a4433")
	_side.position = Vector2(0, 5)
	_side.size = size
	add_child(_side)

	_lift = Control.new()
	_lift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lift)
	_lift.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_body = TextureRect.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_SCALE
	_body.texture = ImageTexture.create_from_image(region_image)
	_paint = ShaderMaterial.new()
	_paint.shader = OUTLINE
	_paint.set_shader_parameter("use_source_color", true)
	_body.material = _paint
	_lift.add_child(_body)
	_body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var nameplate := Kit.create_folio_panel(Kit.PAPER, 12, 5, 3)
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift.add_child(nameplate)
	nameplate.add_child(Kit.create_label(str(data["name"]), 21, Kit.INK, font))
	nameplate.position = anchor_local + Vector2(-60, -52)

	_star = Kit.create_badge("✦ 0", Kit.AMBER, font, 17)
	_star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lift.add_child(_star)
	_star_label = _star.get_child(0) as Label
	_star.position = anchor_local + Vector2(44, -16)
	_star.hide()
	set_status(Color("#8a6f4d"), 0)


func contains_point(local_point: Vector2) -> bool:
	if local_point.x < 0 or local_point.y < 0 or local_point.x >= size.x or local_point.y >= size.y:
		return false
	return mask.get_pixelv(Vector2i(local_point)).a > 0.1


func set_status(color: Color, state: int) -> void:
	_paint.set_shader_parameter("outline_color", color)
	_paint.set_shader_parameter("outline_state", state)


func set_hover(hover: bool, tilt: float = 0.0) -> void:
	if _hover == hover and not hover:
		return
	_hover = hover
	Motion.spring(_lift, "position:y", _lift.position.y, -12.0 if hover else 0.0, 0.34, 9.0, 7.0)
	Motion.spring(self, "scale", self.scale, Vector2.ONE * (1.038 if hover else 1.0), 0.3, 9.0, 7.0)
	Motion.spring(self, "rotation", self.rotation, tilt * 0.012 if hover else 0.0, 0.3, 9.0, 7.0)
	Motion.spring(_shadow, "position", _shadow.position, Vector2(10, 18) if hover else Vector2(6, 10), 0.34, 9.0, 7.0)
	Motion.spring(_shadow, "modulate:a", _shadow.modulate.a, 0.28 if hover else 0.35, 0.34, 9.0, 7.0)
	Motion.spring(_side, "position:y", _side.position.y, 12.0 if hover else 5.0, 0.34, 9.0, 7.0)


func press_feedback() -> void:
	Motion.spring(self, "scale", Vector2.ONE * 0.97, Vector2.ONE * (1.038 if _hover else 1.0), 0.3, 6.0, 12.0)
	AudioManager.play_sfx("ui_click")


func set_star_count(count: int) -> void:
	_star.visible = count > 0
	_star_label.text = "✦ %d" % count
	if count > 0:
		Motion.pop_badge(_star, 0.4)


static func _scanline_mask(polygon: PackedVector2Array, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y: int in size.y:
		var xs: Array[float] = []
		var py := float(y) + 0.5
		for i: int in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y <= py and b.y > py) or (b.y <= py and a.y > py):
				var t := (py - a.y) / (b.y - a.y)
				xs.append(a.x + t * (b.x - a.x))
		xs.sort()
		for k: int in range(0, xs.size() - 1, 2):
			var x0 := ceili(xs[k] - 0.5)
			var x1 := floori(xs[k + 1] - 0.5) + 1
			if x1 > x0:
				image.fill_rect(Rect2i(x0, y, x1 - x0, 1), Color.WHITE)
	return image

