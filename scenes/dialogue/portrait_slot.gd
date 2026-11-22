extends Control

const Art := preload("res://core/placeholder_art_factory.gd")
const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const BUST_FEATHER := preload("res://shaders/bust_feather.gdshader")

var actor_id := ""
var _image: TextureRect
var _bust_mat: ShaderMaterial
var _caption: Label
var _actor: Dictionary = {}
var _key := ""
var _emotion := ""
var _active := false
var _side_bust := false
var _stage_standing := false
var _focus_mode := ""
var _art_tween: Tween
var _tint_tween: Tween
var _bust_hide_tween: Tween
var _captions_visible := true
var _breath_clock := 0.0
var _base_image_y := 0.0


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
	_caption.add_theme_font_size_override("font_size", 17)
	_caption.add_theme_color_override("font_color", Kit.IVORY)
	var cap_box := Kit.style(Color("#1c140ee8"), 12, 5, 4, 1, Color("#c89b5288"))
	cap_box.set_corner_radius_all(8)
	_caption.add_theme_stylebox_override("normal", cap_box)
	add_child(_caption)
	_caption.anchor_left = 0.16
	_caption.anchor_right = 0.84
	_caption.anchor_top = 0.74
	_caption.anchor_bottom = 0.74
	_caption.offset_top = -42.0
	_caption.offset_bottom = -4.0

	pivot_offset_ratio = Vector2(0.5, 1.0)
	resized.connect(queue_redraw)
	if _side_bust:
		_apply_side_bust_setup()
	elif _stage_standing:
		_apply_stage_standing_setup()
	hide()


func configure_side_bust() -> void:
	_side_bust = true
	if _image != null:
		_apply_side_bust_setup()


func configure_stage_standing() -> void:
	_stage_standing = true
	if _image != null:
		_apply_stage_standing_setup()


func _apply_stage_standing_setup() -> void:
	if _bust_mat == null:
		_bust_mat = ShaderMaterial.new()
		_bust_mat.shader = BUST_FEATHER
	_bust_mat.set_shader_parameter("uv_y_min", 0.0)
	_bust_mat.set_shader_parameter("uv_y_max", 1.0)
	_bust_mat.set_shader_parameter("bottom_fade_start", 0.90)
	_bust_mat.set_shader_parameter("bottom_fade_end", 1.0)
	_bust_mat.set_shader_parameter("rim_tint", Color(0.08, 0.055, 0.04, 0.05))
	_image.material = _bust_mat
	_image.offset_bottom = 0
	pivot_offset_ratio = Vector2(0.5, 0.88)


func _apply_side_bust_setup() -> void:
	if _bust_mat == null:
		_bust_mat = ShaderMaterial.new()
		_bust_mat.shader = BUST_FEATHER
	_bust_mat.set_shader_parameter("bottom_fade_start", 0.66)
	_bust_mat.set_shader_parameter("bottom_fade_end", 0.97)
	_image.material = _bust_mat
	_image.offset_bottom = 0
	_caption.hide()
	pivot_offset_ratio = Vector2(0.5, 0.88)


func has_portrait_art(id: String, emotion: String = "") -> bool:
	if id.is_empty():
		return false
	if not emotion.is_empty() and Art.load_texture("res://assets/portraits/%s_%s.png" % [id, emotion]) != null:
		return true
	return Art.load_texture("res://assets/portraits/%s.png" % id) != null


func is_showing_actor(id: String) -> bool:
	return visible and not id.is_empty() and actor_id == id


func _process(delta: float) -> void:
	if not visible or _side_bust or _image == null:
		return
	if _active:
		_breath_clock += delta
		var target_y := _base_image_y + sin(_breath_clock * 2.0) * 2.2
		_image.position.y = lerpf(_image.position.y, target_y, 1.0 - exp(-delta * 10.0))
	else:
		_image.position.y = lerpf(_image.position.y, _base_image_y, 1.0 - exp(-delta * 8.5))


func show_portrait(id: String, emotion: String, actor: Dictionary) -> void:
	var key := id + "_" + emotion
	var raw_texture := Art.load_texture("res://assets/portraits/%s.png" % key)
	if raw_texture == null:
		raw_texture = Art.load_texture("res://assets/portraits/%s.png" % id)
	var same_actor := key == _key and visible
	actor_id = id
	_key = key
	_actor = actor
	_emotion = emotion

	if _side_bust:
		if _bust_hide_tween != null and _bust_hide_tween.is_valid():
			_bust_hide_tween.kill()
		if raw_texture == null:
			hide_side_bust(true)
			return
		_apply_side_bust_texture(raw_texture, actor)
		show()
		queue_redraw()
		if not same_actor or modulate.a < 0.92:
			_play_bust_entrance()
		return

	if visible and raw_texture != null and raw_texture == _image.texture:
		_caption.text = "%s  ·  %s" % [actor.get("name", id), actor.get("expressions", {}).get(emotion, emotion)]
		_caption.visible = false
		return
	if same_actor and raw_texture == _image.texture:
		return
	_image.texture = raw_texture
	_image.flip_h = false
	_image.offset_bottom = 0 if _image.texture != null else -52
	_caption.text = "%s  ·  %s" % [actor.get("name", id), actor.get("expressions", {}).get(emotion, emotion)]
	_caption.visible = _captions_visible and _image.texture == null
	show()
	queue_redraw()
	if _art_tween != null and _art_tween.is_valid():
		_art_tween.kill()
	self_modulate.a = 0.35
	_image.self_modulate.a = 0.35
	_art_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_art_tween.tween_property(self, "self_modulate:a", 1.0, 0.24)
	_art_tween.tween_property(_image, "self_modulate:a", 1.0, 0.24)


func _apply_side_bust_texture(raw_texture: Texture2D, actor: Dictionary) -> void:
	if raw_texture == null:
		_image.texture = null
		_image.flip_h = false
		return
	var crop_ratio := clampf(float(actor.get("bust_crop", 0.72)), 0.50, 1.0)
	var tex_size := raw_texture.get_size()
	var atlas := AtlasTexture.new()
	atlas.atlas = raw_texture
	atlas.region = Rect2(0.0, 0.0, tex_size.x, tex_size.y * crop_ratio)
	_image.texture = atlas
	_image.flip_h = bool(actor.get("bust_flip", false))
	_image.offset_bottom = 0
	_caption.hide()
	if _bust_mat != null:
		_bust_mat.set_shader_parameter("uv_y_min", 0.0)
		_bust_mat.set_shader_parameter("uv_y_max", crop_ratio)
		var accent := Color.html(str(actor.get("accent", "#cfa259")))
		_bust_mat.set_shader_parameter("rim_tint", Color(accent.r, accent.g, accent.b, 0.14))


func _play_bust_entrance() -> void:
	Motion.cancel(self, ^"modulate:a")
	Motion.cancel(_image, ^"position:x")
	modulate.a = 0.0
	Motion.fade_alpha(self, 0.94, 0.24)
	Motion.spring(_image, ^"position:x", -14.0, 0.0, 0.34, 9.5, 7.0)


func hide_side_bust(instant: bool = false) -> void:
	if not _side_bust:
		return
	if _bust_hide_tween != null and _bust_hide_tween.is_valid():
		_bust_hide_tween.kill()
	Motion.cancel(self, ^"modulate:a")
	Motion.cancel(_image, ^"position:x")
	if instant or not visible:
		modulate.a = 0.0
		hide()
		return
	_bust_hide_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_bust_hide_tween.tween_property(self, "modulate:a", 0.0, 0.16)
	_bust_hide_tween.tween_callback(hide)


func set_active(active: bool, ambient_level: bool = false, instant: bool = false) -> void:
	if _side_bust:
		return
	var next_mode := "active" if active else ("ambient" if ambient_level else "dim")
	var target_tint := Color.WHITE if active else (Color(0.82, 0.79, 0.77, 1.0) if ambient_level else Color(0.68, 0.65, 0.63, 1.0))
	var target_scale := Vector2.ONE * (1.032 if active else (0.985 if ambient_level else 0.968))
	var target_y := -10.0 if active else 0.0
	_active = active
	_base_image_y = target_y
	z_index = 4 if active else 1

	if instant:
		_focus_mode = next_mode
		Motion.cancel(self, ^"scale")
		if _tint_tween != null and _tint_tween.is_valid():
			_tint_tween.kill()
		scale = target_scale
		modulate = target_tint
		if _image != null:
			_image.position.y = target_y
		return

	if _focus_mode == next_mode:
		return
	_focus_mode = next_mode
	Motion.spring(self, ^"scale", scale, target_scale, 0.38, 9.0, 7.0)
	if _tint_tween != null and _tint_tween.is_valid():
		_tint_tween.kill()
	_tint_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_tint_tween.tween_property(self, "modulate", target_tint, 0.24)


func set_captions_visible(visible_state: bool) -> void:
	_captions_visible = visible_state
	_caption.visible = (not _side_bust) and visible_state and _image.texture == null


func _draw() -> void:
	if _actor.is_empty() or _image.texture != null:
		return
	if _side_bust:
		_draw_side_bust_fallback()
		return
	var usable_h := size.y * 0.77
	var factor := minf(size.x / 330.0, usable_h / 480.0)
	if factor <= 0.0:
		return
	draw_set_transform(Vector2((size.x - 330.0 * factor) * 0.5, usable_h - 472.0 * factor), 0.0, Vector2.ONE * factor)
	_draw_arch_silhouette(false)


func _draw_side_bust_fallback() -> void:
	var usable_w := size.x * 0.86
	var usable_h := size.y * 0.84
	var factor := minf(usable_w / 280.0, usable_h / 320.0)
	if factor <= 0.0:
		return
	draw_set_transform(Vector2((size.x - 280.0 * factor) * 0.5, size.y - 318.0 * factor), 0.0, Vector2.ONE * factor)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#1e150fd8")
	style.border_color = Color("#d8ae6288")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 104
	style.corner_radius_top_right = 104
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	draw_style_box(style, Rect2(14, 16, 252, 294))
	draw_set_transform(Vector2((size.x - 280.0 * factor) * 0.5 - 25.0 * factor, size.y - 318.0 * factor - 20.0 * factor), 0.0, Vector2.ONE * factor)
	_draw_bust_head(170.0)


func _draw_arch_silhouette(compact: bool) -> void:
	var hair := Color.html(str(_actor.get("accent", "#66899a")))
	var cloak := Color.html(str(_actor.get("coat", "#beaa89")))
	var ink := Color("#30261f")
	var tall := str(_actor.get("build", "")) != "child"
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#211812d9")
	style.border_color = Color("#cfa35cb8")
	style.set_border_width_all(2)
	style.corner_radius_top_left = 108
	style.corner_radius_top_right = 108
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	draw_style_box(style, Rect2(31, 39, 268, 432))
	draw_arc(Vector2(165, 167), 102, PI, TAU, 34, Color("#d8ae6278"), 1.3, true)
	var head_y := 163.0 if tall else 198.0
	var hair_style := str(_actor.get("hair", "short"))
	if hair_style == "braid" or hair_style == "long":
		_shape([
			Vector2(121, head_y - 16), Vector2(209, head_y - 31), Vector2(245, head_y + 51),
			Vector2(259, head_y + 152), Vector2(279, head_y + 220), Vector2(210, head_y + 204),
			Vector2(159, head_y + 153), Vector2(89, head_y + 191), Vector2(100, head_y + 84)
		], hair.darkened(0.36))
	if not compact:
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
	_draw_bust_head(head_y)


func _draw_bust_head(head_y: float) -> void:
	var hair := Color.html(str(_actor.get("accent", "#66899a")))
	var cloak := Color.html(str(_actor.get("coat", "#beaa89")))
	var ink := Color("#30261f")
	var skin := Color("#e4c5a5")
	if _side_bust:
		_shape([
			Vector2(48, 326), Vector2(58, head_y + 128), Vector2(102, head_y + 98),
			Vector2(228, head_y + 98), Vector2(272, head_y + 128), Vector2(282, 326)
		], cloak)
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
	var softened := _emotion in ["gentle", "smile", "calm"]
	var eyelid := 3.0 if softened else -1.0
	draw_polyline([Vector2(124, head_y + 49), Vector2(137, head_y + 46 + eyelid), Vector2(151, head_y + 50)], ink, 2.9, true)
	draw_polyline([Vector2(180, head_y + 50), Vector2(192, head_y + 46 + eyelid), Vector2(207, head_y + 49)], ink, 2.9, true)
	draw_polyline([Vector2(163, head_y + 60), Vector2(159, head_y + 73), Vector2(166, head_y + 75)], Color("#9d785f"), 1.25, true)
	draw_polyline([Vector2(153, head_y + 88), Vector2(165, head_y + (91 if softened else 86)), Vector2(176, head_y + 87)], Color("#775849"), 1.65, true)
	if _actor.get("accessory") == "mark":
		draw_circle(Vector2(169, head_y + 26), 5.5, Color("#b84539"), true, -1, true)


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
