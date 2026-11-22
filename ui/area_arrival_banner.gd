extends CanvasLayer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const Planner := preload("res://core/travel_planner.gd")
const BANNER_SHADER := preload("res://shaders/area_arrival_banner.gdshader")

const BAND_WIDTH := 800.0
const BAND_HEIGHT := 116.0
const TOP_ANCHOR_Y := 102.0
const HOLD_SECONDS := 2.80
const QUEUED_HOLD_SECONDS := 0.72
const GAP_SECONDS := 0.16


class ArrivalNotice extends RefCounted:
	var eyebrow: String
	var title: String
	var subtitle: String

	func _init(eyebrow_text: String, title_text: String, subtitle_text: String) -> void:
		eyebrow = eyebrow_text
		title = title_text
		subtitle = subtitle_text


class TopStarOrnament extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(22.0, 22.0)

	func _draw() -> void:
		var c := size * 0.5
		var r := 7.0
		draw_circle(c, r * 1.8, Color("#e4be7036"))
		var pts := PackedVector2Array()
		for i: int in 8:
			var reach := r if i % 2 == 0 else r * 0.30
			pts.append(c + Vector2.from_angle(TAU * float(i) / 8.0 - PI * 0.5) * reach)
		draw_colored_polygon(pts, Color("#f5d78c"))
		draw_circle(c, 1.8, Color("#fffaf0"))


var _queue: Array[ArrivalNotice] = []
var _playing := false
var _last_key := ""
var _band: ColorRect
var _mat: ShaderMaterial
var _star: TopStarOrnament
var _eyebrow: Label
var _title: Label
var _subtitle: Label
var _title_font: SystemFont
var _body_font: SystemFont
var _active_tween: Tween


func _ready() -> void:
	layer = 108
	_title_font = Kit.make_font(true)
	_body_font = Kit.make_font()

	_band = ColorRect.new()
	_band.color = Color.WHITE
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.custom_minimum_size = Vector2(BAND_WIDTH, BAND_HEIGHT)
	_mat = ShaderMaterial.new()
	_mat.shader = BANNER_SHADER
	_mat.set_shader_parameter("banner_size", Vector2(BAND_WIDTH, BAND_HEIGHT))
	_mat.set_shader_parameter("reveal_progress", 0.0)
	_band.material = _mat
	add_child(_band)
	_band.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_band.offset_left = -BAND_WIDTH * 0.5
	_band.offset_right = BAND_WIDTH * 0.5
	_band.offset_top = TOP_ANCHOR_Y
	_band.offset_bottom = TOP_ANCHOR_Y + BAND_HEIGHT
	_band.pivot_offset_ratio = Vector2(0.5, 0.5)
	_band.hide()

	_star = TopStarOrnament.new()
	_star.position = Vector2(BAND_WIDTH * 0.5 - 11.0, -11.0)
	_band.add_child(_star)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 3)
	_band.add_child(col)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 72.0
	col.offset_right = -72.0
	col.offset_top = 12.0
	col.offset_bottom = -10.0

	_eyebrow = Kit.create_label("", 15, Color("#e8c782"), _title_font)
	_eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_eyebrow.add_theme_color_override("font_shadow_color", Color("#080402cc"))
	_eyebrow.add_theme_constant_override("shadow_offset_y", 1)
	col.add_child(_eyebrow)

	_title = Kit.create_label("", 32, Color("#faf3e6"), _title_font)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_shadow_color", Color("#080402dc"))
	_title.add_theme_constant_override("shadow_offset_y", 2)
	col.add_child(_title)

	_subtitle = Kit.create_label("", 15, Color("#d4c5b0d8"), _body_font)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_shadow_color", Color("#080402b8"))
	_subtitle.add_theme_constant_override("shadow_offset_y", 1)
	col.add_child(_subtitle)


func enqueue_geo(continent: String, country: String, region: String, location: String, poetic_subtitle: String = "") -> void:
	var geo := Planner.format_geo_hierarchy(continent, country, region, location)
	geo["poetic_subtitle"] = poetic_subtitle
	enqueue_arrival(geo)


func enqueue_arrival(geo: Dictionary) -> void:
	var title_text := str(geo.get("title", "")).strip_edges()
	if title_text.is_empty():
		return
	var dash_line := str(geo.get("eyebrow_dash", "")).strip_edges()
	var eyebrow_text := ("已抵达 · " + dash_line) if not dash_line.is_empty() else "已抵达"
	var sub_text := str(geo.get("poetic_subtitle", "")).strip_edges()
	var key := eyebrow_text + "|" + title_text
	if key == _last_key and (_playing or not _queue.is_empty()):
		return
	_last_key = key
	# Keep queue crisp: if 2+ items already waiting, replace the tail so rapid crossings stay fresh.
	if _queue.size() >= 2:
		_queue[_queue.size() - 1] = ArrivalNotice.new(eyebrow_text, title_text, sub_text)
	else:
		_queue.append(ArrivalNotice.new(eyebrow_text, title_text, sub_text))
	if not _playing:
		_play_next()


func clear_banners() -> void:
	_queue.clear()
	_last_key = ""
	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_playing = false
	if _band != null:
		_band.hide()


func is_showing() -> bool:
	return _playing and _band != null and _band.visible


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		_last_key = ""
		return
	_playing = true
	var item: ArrivalNotice = _queue.pop_front()
	_eyebrow.text = item.eyebrow
	_title.text = item.title
	_subtitle.text = item.subtitle
	_subtitle.visible = not item.subtitle.is_empty()

	_set_y_shift(-14.0)
	_band.modulate.a = 0.0
	_band.scale = Vector2(0.985, 0.985)
	_mat.set_shader_parameter("reveal_progress", 0.0)
	_band.show()
	AudioManager.play_sfx("area_arrive")

	if _active_tween != null and _active_tween.is_valid():
		_active_tween.kill()
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(_band, "modulate:a", 1.0, 0.34).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_active_tween.tween_method(_set_y_shift, -14.0, 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_band, "scale", Vector2.ONE, 0.40).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_active_tween.tween_property(_mat, "shader_parameter/reveal_progress", 1.0, 0.44).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await _active_tween.finished

	var held := 0.0
	var target_hold := HOLD_SECONDS
	while held < target_hold and is_inside_tree():
		if not _queue.is_empty():
			target_hold = minf(target_hold, QUEUED_HOLD_SECONDS)
		var step := minf(0.10, target_hold - held)
		if step <= 0.0:
			break
		await get_tree().create_timer(step).timeout
		held += step

	if not is_inside_tree():
		return
	_active_tween = create_tween().set_parallel(true)
	_active_tween.tween_property(_band, "modulate:a", 0.0, 0.46).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_active_tween.tween_method(_set_y_shift, 0.0, -8.0, 0.46).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	await _active_tween.finished
	_band.hide()
	if not is_inside_tree():
		return
	if not _queue.is_empty():
		await get_tree().create_timer(GAP_SECONDS).timeout
	_play_next()


func _set_y_shift(offset: float) -> void:
	_band.offset_top = TOP_ANCHOR_Y + offset
	_band.offset_bottom = TOP_ANCHOR_Y + BAND_HEIGHT + offset
