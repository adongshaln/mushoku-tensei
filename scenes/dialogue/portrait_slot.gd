extends Control

const Art := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")

var _image: TextureRect
var _caption: Label
var _actor: Dictionary = {}
var _key := ""
var _emotion := ""
var _active := false
var _art_tween: Tween
var _focus_tween: Tween
var _captions_visible := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image = TextureRect.new()
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_image)
	_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_image.offset_bottom = -52
	_caption = Label.new()
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.add_theme_font_size_override("font_size", 20)
	_caption.add_theme_color_override("font_color", Kit.PAPER)
	_caption.add_theme_stylebox_override("normal", Kit.style(Color("#312924e8"), 10, 7))
	add_child(_caption)
	_caption.anchor_left = 0.16
	_caption.anchor_right = 0.84
	_caption.anchor_top = 1.0
	_caption.anchor_bottom = 1.0
	_caption.offset_top = -47.0
	_caption.offset_bottom = -7.0
	pivot_offset_ratio = Vector2(0.5, 1.0)
	resized.connect(queue_redraw)
	hide()


func show_portrait(id: String, emotion: String, actor: Dictionary) -> void:
	var key := id + "_" + emotion
	var texture := Art.load_texture("res://assets/portraits/%s.png" % key)
	if key == _key and texture == _image.texture:
		return
	_key = key
	_actor = actor
	_emotion = emotion
	_image.texture = texture
	_image.offset_bottom = 0 if _image.texture != null else -52
	_caption.text = "%s   ·   %s" % [actor.get("name", id), actor.get("expressions", {}).get(emotion, emotion)]
	_caption.visible = _captions_visible and _image.texture == null
	show()
	queue_redraw()
	if _art_tween != null:
		_art_tween.kill()
	self_modulate.a = 0.32
	_image.self_modulate.a = 0.32
	_art_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_art_tween.tween_property(self, "self_modulate:a", 1.0, 0.24)
	_art_tween.tween_property(_image, "self_modulate:a", 1.0, 0.24)


func set_active(active: bool) -> void:
	if _focus_tween != null and _active == active:
		return
	_active = active
	if _focus_tween != null:
		_focus_tween.kill()
	_focus_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_focus_tween.tween_property(self, "modulate", Color.WHITE if active else Color("#c8bbb1"), 0.23)
	_focus_tween.tween_property(self, "scale", Vector2.ONE * (1.03 if active else 1.0), 0.23)


func set_captions_visible(visible_state: bool) -> void:
	_captions_visible = visible_state
	_caption.visible = visible_state and _image.texture == null


func _draw() -> void:
	if _actor.is_empty() or _image.texture != null:
		return
	var factor := minf(size.x / 330.0, (size.y - 53.0) / 480.0)
	if factor <= 0.0:
		return
	draw_set_transform(Vector2((size.x - 330 * factor) * 0.5, size.y - 49 - 480 * factor), 0.0, Vector2.ONE * factor)
	var hair := Color.html(str(_actor.get("accent", "#66899a")))
	var cloak := Color.html(str(_actor.get("coat", "#beaa89")))
	var ink := Color("#40372f")
	var skin := Color("#e6c8a9")
	var tall := str(_actor.get("build", "")) != "child"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e8d8b5d9")
	style.border_color = Color("#e9c992a0")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 103
	style.corner_radius_top_right = 103
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	draw_style_box(style, Rect2(31, 39, 268, 432))
	draw_arc(Vector2(165, 167), 105, PI, TAU, 34, Color("#a387617e"), 1.4, true)
	draw_arc(Vector2(165, 167), 99, PI, TAU, 34, Color("#c4a47d82"), 1.0, true)
	var head_y := 163.0 if tall else 198.0
	var hair_style := str(_actor.get("hair", "short"))
	if hair_style == "braid" or hair_style == "long":
		_shape([
			Vector2(121, head_y - 16), Vector2(209, head_y - 31), Vector2(245, head_y + 51),
			Vector2(259, head_y + 152), Vector2(279, head_y + 220), Vector2(210, head_y + 204),
			Vector2(159, head_y + 153), Vector2(89, head_y + 191), Vector2(100, head_y + 84)
		], hair.darkened(0.36))
	_shape([
		Vector2(35, 470), Vector2(43, head_y + 200), Vector2(81, head_y + 141), Vector2(128, head_y + 111),
		Vector2(202, head_y + 112), Vector2(248, head_y + 145), Vector2(287, head_y + 199), Vector2(296, 470)
	], ink)
	_shape([
		Vector2(42, 468), Vector2(51, head_y + 199), Vector2(89, head_y + 146), Vector2(142, head_y + 117),
		Vector2(190, head_y + 117), Vector2(239, head_y + 145), Vector2(279, head_y + 199), Vector2(289, 468)
	], cloak)
	_shape([
		Vector2(160, head_y + 158), Vector2(226, head_y + 137), Vector2(279, head_y + 198),
		Vector2(289, 469), Vector2(201, 469)
	], cloak.darkened(0.19))
	_shape([
		Vector2(105, head_y + 132), Vector2(132, head_y + 104), Vector2(197, head_y + 104),
		Vector2(225, head_y + 128), Vector2(184, head_y + 169), Vector2(163, head_y + 180)
	], ink)
	_shape([
		Vector2(132, head_y + 87), Vector2(198, head_y + 87), Vector2(196, head_y + 124),
		Vector2(165, head_y + 147), Vector2(135, head_y + 120)
	], skin.darkened(0.14))
	_shape([
		Vector2(88, head_y + 9), Vector2(105, head_y - 34), Vector2(150, head_y - 65), Vector2(199, head_y - 54),
		Vector2(234, head_y - 28), Vector2(242, head_y + 27), Vector2(224, head_y + 84), Vector2(198, head_y + 108),
		Vector2(128, head_y + 107), Vector2(99, head_y + 81)
	], hair.darkened(0.53))
	_shape([
		Vector2(106, head_y + 10), Vector2(123, head_y - 24), Vector2(166, head_y - 41),
		Vector2(207, head_y - 19), Vector2(229, head_y + 25), Vector2(220, head_y + 72),
		Vector2(202, head_y + 99), Vector2(164, head_y + 113), Vector2(129, head_y + 92), Vector2(111, head_y + 62)
	], skin)
	_shape([
		Vector2(93, head_y + 69), Vector2(88, head_y + 3), Vector2(106, head_y - 35),
		Vector2(127, head_y - 56), Vector2(145, head_y - 61), Vector2(158, head_y - 59),
		Vector2(194, head_y - 62), Vector2(229, head_y - 42), Vector2(243, head_y - 8),
		Vector2(238, head_y + 55), Vector2(212, head_y + 19), Vector2(204, head_y - 3),
		Vector2(173, head_y + 18), Vector2(175, head_y - 4), Vector2(141, head_y + 23),
		Vector2(146, head_y + 7), Vector2(111, head_y + 54), Vector2(106, head_y + 90)
	], hair)
	draw_polyline([Vector2(110, head_y - 2), Vector2(129, head_y - 31), Vector2(167, head_y - 44), Vector2(200, head_y - 38)], hair.lightened(0.22), 3.5, true)
	var softened := _emotion in ["gentle", "smile", "calm"]
	var eyelid := 3.0 if softened else -1.0
	draw_polyline([Vector2(124, head_y + 49), Vector2(137, head_y + 46 + eyelid), Vector2(151, head_y + 50)], ink, 2.9, true)
	draw_polyline([Vector2(180, head_y + 50), Vector2(192, head_y + 46 + eyelid), Vector2(207, head_y + 49)], ink, 2.9, true)
	draw_polyline([Vector2(163, head_y + 60), Vector2(159, head_y + 73), Vector2(166, head_y + 75)], Color("#9d785f"), 1.25, true)
	draw_polyline([Vector2(153, head_y + 88), Vector2(165, head_y + (91 if softened else 86)), Vector2(176, head_y + 87)], Color("#775849"), 1.65, true)
	if hair_style == "braid":
		for knot: int in range(5):
			var at := Vector2(218 - 4 * knot, head_y + 101 + 19 * knot)
			_shape([at + Vector2(-10, 0), at + Vector2(13, -4), at + Vector2(19, 13), at + Vector2(1, 26), at + Vector2(-8, 17)], hair.lerp(hair.darkened(0.3), knot / 8.0))
	if _actor.get("accessory") == "mark":
		draw_circle(Vector2(169, head_y + 26), 5.0, Color("#9e614b"), true, -1, true)
	var trim := hair.darkened(0.15)
	draw_polyline([Vector2(72, 466), Vector2(91, head_y + 222), Vector2(128, head_y + 171)], trim, 2.9, true)
	draw_polyline([Vector2(251, 466), Vector2(238, head_y + 231), Vector2(204, head_y + 172)], trim, 2.9, true)
	_shape([Vector2(165, head_y + 177), Vector2(176, head_y + 192), Vector2(165, head_y + 209), Vector2(155, head_y + 192)], Color("#a78a5d") if _actor.get("accessory") == "pendant" else trim)


func _shape(points: PackedVector2Array, fill: Color) -> void:
	var outline := PackedVector2Array()
	for index: int in points.size():
		var vertex := points[index]
		var start := vertex.lerp(points[posmod(index - 1, points.size())], 0.19)
		var finish := vertex.lerp(points[(index + 1) % points.size()], 0.19)
		for step: int in 5:
			var weight := step / 4.0
			outline.append(start.lerp(vertex, weight).lerp(vertex.lerp(finish, weight), weight))
	draw_colored_polygon(outline, fill)

