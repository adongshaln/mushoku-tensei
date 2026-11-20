extends CanvasLayer

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const BANNER_SHADER := preload("res://shaders/center_fade_banner.gdshader")
const BAND_WIDTH := 760.0
const BAND_HEIGHT := 104.0
const VERTICAL_ANCHOR := 0.42
const HOLD_SECONDS := 1.85
const GAP_SECONDS := 0.15
const POSITIVE := Color("#3a75a0")
const NEGATIVE := Color("#b84d42")

class Notice:
	var narrative: String
	var delta_text: String
	var positive: bool

	func _init(text: String, delta_label: String, is_positive: bool) -> void:
		narrative = text
		delta_text = delta_label
		positive = is_positive


var _queue: Array[Notice] = []
var _playing := false
var _band: ColorRect
var _material: ShaderMaterial
var _narrative: Label
var _delta: Label
var _title_font: SystemFont


func _ready() -> void:
	layer = 110
	_title_font = Kit.make_font(true)
	_band = ColorRect.new()
	_band.color = Color.WHITE
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_band.custom_minimum_size = Vector2(BAND_WIDTH, BAND_HEIGHT)
	_material = ShaderMaterial.new()
	_material.shader = BANNER_SHADER
	_material.set_shader_parameter("banner_size", Vector2(BAND_WIDTH, BAND_HEIGHT))
	_material.set_shader_parameter("reveal_progress", 0.0)
	_band.material = _material
	add_child(_band)
	_band.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_band.anchor_top = VERTICAL_ANCHOR
	_band.anchor_bottom = VERTICAL_ANCHOR
	_band.offset_left = -BAND_WIDTH * 0.5
	_band.offset_right = BAND_WIDTH * 0.5
	_band.offset_top = -BAND_HEIGHT * 0.5
	_band.offset_bottom = BAND_HEIGHT * 0.5
	_band.pivot_offset_ratio = Vector2(0.5, 0.5)
	_band.hide()

	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 6)
	_band.add_child(page)
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 70
	page.offset_right = -70
	page.offset_top = 16
	page.offset_bottom = -16
	_narrative = Kit.create_label("", 22, Kit.INK, _title_font)
	_narrative.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_narrative.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_narrative.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_narrative)
	_delta = Kit.create_label("", 28, POSITIVE, _title_font)
	_delta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_delta.add_theme_constant_override("outline_size", 3)
	_delta.add_theme_color_override("font_outline_color", Color(0.231, 0.180, 0.145, 0.30))
	var delta_font := Kit.make_font(true)
	delta_font.font_weight = 700
	_delta.add_theme_font_override("font", delta_font)
	_delta.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_delta.pivot_offset_ratio = Vector2(0.5, 0.5)
	page.add_child(_delta)

	for star_y: float in [-8.0, BAND_HEIGHT - 8.0]:
		var star := Kit.create_label("✦", 16, Color(0.788, 0.541, 0.231, 0.95), _title_font)
		star.position = Vector2(BAND_WIDTH * 0.5 - 8.0, star_y)
		_band.add_child(star)

	WorldBlackboard.stat_changed.connect(_on_stat_changed)


func enqueue_stat_change(narrative_text: String, stat_delta_text: String, is_positive: bool = true) -> void:
	_queue.append(Notice.new(narrative_text, stat_delta_text, is_positive))
	if not _playing:
		_play_next()


func _on_stat_changed(stat_key: String, delta: int, _new_value: int, reason_text: String) -> void:
	var stat_name: String = WorldBlackboard.stat_label(stat_key)
	enqueue_stat_change(reason_text, "%s %+d" % [stat_name, delta], delta > 0)


func _play_next() -> void:
	if _queue.is_empty():
		_playing = false
		return
	_playing = true
	var item: Notice = _queue.pop_front()
	_narrative.text = item.narrative
	_delta.text = item.delta_text
	_delta.add_theme_color_override("font_color", POSITIVE if item.positive else NEGATIVE)
	_set_vertical_offset(10.0)
	_band.scale = Vector2.ONE
	_band.modulate.a = 0.0
	_delta.scale = Vector2.ONE * 0.84
	_delta.modulate.a = 0.0
	_material.set_shader_parameter("reveal_progress", 0.0)
	_band.show()

	var entrance := create_tween().set_parallel(true)
	entrance.tween_property(_band, "modulate:a", 1.0, 0.30).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	entrance.tween_method(_set_vertical_offset, 10.0, 0.0, 0.38).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	entrance.tween_property(_material, "shader_parameter/reveal_progress", 1.0, 0.38).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	var pop := create_tween()
	pop.tween_property(_delta, "modulate:a", 1.0, 0.10).set_delay(0.12)
	pop.tween_callback(func() -> void:
		Motion.spring(_delta, "scale", Vector2.ONE * 0.84, Vector2.ONE, 0.34, 5.0, 16.0)
		AudioManager.play_sfx("stat_up" if item.positive else "stat_down")).set_delay(0.12)
	await entrance.finished
	await get_tree().create_timer(HOLD_SECONDS).timeout
	var exit := create_tween().set_parallel(true)
	exit.tween_property(_band, "modulate:a", 0.0, 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	exit.tween_method(_set_vertical_offset, 0.0, -14.0, 0.58).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	exit.tween_property(_band, "scale", Vector2.ONE * 0.96, 0.58).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await exit.finished
	_band.hide()
	await get_tree().create_timer(GAP_SECONDS).timeout
	_play_next()


func _set_vertical_offset(offset: float) -> void:
	_band.offset_top = offset - BAND_HEIGHT * 0.5
	_band.offset_bottom = offset + BAND_HEIGHT * 0.5
