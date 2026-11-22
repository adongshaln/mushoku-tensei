extends RefCounted

const Kit := preload("res://ui/ui_theme_kit.gd")
const Motion := preload("res://ui/ui_motion.gd")
const CHOICE_RIBBON := preload("res://shaders/dialogue_choice_ribbon.gdshader")

const GOLD_WARM := Color("#e4be70")
const GOLD_BRIGHT := Color("#f6d78e")
const IVORY_SOFT := Color("#f7efe1")
const PARCHMENT_MUTED := Color("#d8cab8")


static func accent_color_for(pid: String, actor: Dictionary) -> Color:
	match pid:
		"ruijerd":
			return Color("#4fc48b")
		"eris":
			return Color("#e25d54")
		"rudeus":
			return Color("#d9995a")
		"notia":
			return Color("#6bc0d8")
		"roin":
			return Color("#7ca8c4")
		"":
			return GOLD_WARM
		_:
			var base := Color.html(str(actor.get("accent", "#e4be70")))
			return base.lightened(0.24) if base.get_luminance() < 0.42 else base


static func make_empty_style() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func clear_button_chrome(button: Button) -> void:
	var empty := make_empty_style()
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


class SpeakerDiamond extends Control:
	var _tone := GOLD_WARM

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(20.0, 20.0)

	func set_tone(tone: Color) -> void:
		_tone = tone
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.36
		draw_circle(c, r * 2.15, Color(_tone, 0.14))
		draw_circle(c, r * 1.42, Color(_tone, 0.28))
		var pts := PackedVector2Array([
			Vector2(c.x, c.y - r), Vector2(c.x + r * 0.88, c.y),
			Vector2(c.x, c.y + r), Vector2(c.x - r * 0.88, c.y)
		])
		draw_colored_polygon(pts, _tone)
		var ring := PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
		draw_polyline(ring, Color(GOLD_BRIGHT, 0.72), 1.1, true)
		draw_circle(c + Vector2(-r * 0.16, -r * 0.20), r * 0.22, Color(1.0, 0.98, 0.92, 0.82))


class GoldHairline extends Control:
	var _tone := GOLD_WARM
	var _accent := GOLD_WARM
	var _left_weighted := true
	var _max_alpha := 0.74

	func setup(left_weighted: bool = true, max_alpha: float = 0.74, height_px: float = 8.0) -> void:
		_left_weighted = left_weighted
		_max_alpha = max_alpha
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0.0, height_px)
		resized.connect(queue_redraw)
		queue_redraw()

	func set_accent(accent: Color) -> void:
		_accent = accent
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		if w <= 2.0:
			return
		var y := size.y * 0.5
		var segs := 44
		for i: int in segs:
			var t0 := float(i) / float(segs)
			var t1 := float(i + 1) / float(segs)
			var tm := (t0 + t1) * 0.5
			var env := 0.0
			if _left_weighted:
				var lead := smoothstep(0.0, 0.035, tm)
				var tail := 1.0 - smoothstep(0.28, 1.0, tm)
				env = lead * pow(tail, 1.15)
			else:
				env = sin(tm * PI)
				env = pow(maxf(env, 0.0), 1.35)
			var col := _accent.lerp(_tone, smoothstep(0.0, 0.22, tm))
			var alpha := env * _max_alpha
			if alpha > 0.005:
				draw_line(Vector2(w * t0, y), Vector2(w * t1, y), Color(col, alpha), 1.35, true)


class ContinueDiamond extends Control:
	var _phase := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(20.0, 20.0)

	func _process(delta: float) -> void:
		if not visible:
			return
		_phase += delta * 3.2
		queue_redraw()

	func _draw() -> void:
		var wave := 0.5 + 0.5 * sin(_phase)
		var c := size * 0.5 + Vector2(0.0, sin(_phase * 0.85) * 1.6)
		var r := 5.2 + wave * 0.9
		var a := 0.55 + wave * 0.40
		draw_circle(c, r * 2.0, Color(GOLD_WARM, 0.14 * a))
		var pts := PackedVector2Array([
			Vector2(c.x, c.y - r), Vector2(c.x + r * 0.85, c.y),
			Vector2(c.x, c.y + r), Vector2(c.x - r * 0.85, c.y)
		])
		draw_colored_polygon(pts, Color(GOLD_BRIGHT, a))
		draw_circle(c, r * 0.30, Color(1.0, 0.98, 0.92, a * 0.9))


class DialogueGlyph extends Control:
	var _kind := "star"
	var _tone := IVORY_SOFT
	var _dot_color := Color(0, 0, 0, 0)

	func setup(kind: String, px: float, tone: Color) -> void:
		_kind = kind
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px, px)
		queue_redraw()

	func set_tone(tone: Color) -> void:
		_tone = tone
		queue_redraw()

	func set_dot(dot_color: Color) -> void:
		_dot_color = dot_color
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := s * 0.42
		match _kind:
			"voice":
				draw_colored_polygon([
					Vector2(c.x - r * 0.85, c.y - r * 0.28), Vector2(c.x - r * 0.36, c.y - r * 0.28),
					Vector2(c.x + r * 0.04, c.y - r * 0.68), Vector2(c.x + r * 0.04, c.y + r * 0.68),
					Vector2(c.x - r * 0.36, c.y + r * 0.28), Vector2(c.x - r * 0.85, c.y + r * 0.28)
				], _tone)
				draw_arc(Vector2(c.x + r * 0.12, c.y), r * 0.42, -0.85, 0.85, 12, _tone, 1.5, true)
				draw_arc(Vector2(c.x + r * 0.12, c.y), r * 0.76, -0.78, 0.78, 12, _tone, 1.4, true)
			"log":
				draw_line(Vector2(c.x - r * 0.75, c.y - r * 0.52), Vector2(c.x + r * 0.75, c.y - r * 0.52), _tone, 1.6, true)
				draw_line(Vector2(c.x - r * 0.75, c.y), Vector2(c.x + r * 0.75, c.y), _tone, 1.6, true)
				draw_line(Vector2(c.x - r * 0.75, c.y + r * 0.52), Vector2(c.x + r * 0.38, c.y + r * 0.52), _tone, 1.6, true)
			"auto":
				draw_colored_polygon([
					Vector2(c.x - r * 0.36, c.y - r * 0.50),
					Vector2(c.x + r * 0.58, c.y),
					Vector2(c.x - r * 0.36, c.y + r * 0.50)
				], _tone)
				draw_arc(c, r * 0.88, -2.5, 2.2, 18, Color(_tone, 0.72), 1.4, true)
			"skip":
				for dx: float in [-r * 0.42, r * 0.16]:
					draw_polyline([
						Vector2(c.x + dx - r * 0.28, c.y - r * 0.54),
						Vector2(c.x + dx + r * 0.28, c.y),
						Vector2(c.x + dx - r * 0.28, c.y + r * 0.54)
					], _tone, 1.7, true)
			"hide":
				var rim := PackedVector2Array()
				for i: int in 25:
					var ang := TAU * float(i) / 24.0
					rim.append(c + Vector2(cos(ang) * r * 0.90, sin(ang) * r * 0.50))
				draw_polyline(rim, _tone, 1.5, true)
				draw_circle(c, r * 0.22, _tone)
				draw_line(c + Vector2(-r * 0.68, r * 0.62), c + Vector2(r * 0.68, -r * 0.62), _tone, 1.5, true)
			"d20":
				var hex := PackedVector2Array()
				for i: int in 7:
					var ang := TAU * float(i) / 6.0 - PI * 0.5
					hex.append(c + Vector2.from_angle(ang) * r * 0.90)
				draw_polyline(hex, _tone, 1.55, true)
				var tri := PackedVector2Array([
					c + Vector2(0.0, -r * 0.50), c + Vector2(r * 0.46, r * 0.30),
					c + Vector2(-r * 0.46, r * 0.30), c + Vector2(0.0, -r * 0.50)
				])
				draw_polyline(tri, Color(_tone, 0.82), 1.25, true)
			"book":
				draw_polyline([
					Vector2(c.x, c.y - r * 0.54), Vector2(c.x - r * 0.80, c.y - r * 0.68),
					Vector2(c.x - r * 0.80, c.y + r * 0.52), Vector2(c.x, c.y + r * 0.68),
					Vector2(c.x + r * 0.80, c.y + r * 0.52), Vector2(c.x + r * 0.80, c.y - r * 0.68),
					Vector2(c.x, c.y - r * 0.54), Vector2(c.x, c.y + r * 0.68)
				], _tone, 1.55, true)
			"quill":
				draw_colored_polygon([
					Vector2(c.x + r * 0.72, c.y - r * 0.76), Vector2(c.x + r * 0.38, c.y + r * 0.08),
					Vector2(c.x - r * 0.34, c.y + r * 0.42), Vector2(c.x - r * 0.14, c.y - r * 0.28)
				], _tone)
				draw_line(Vector2(c.x + r * 0.56, c.y - r * 0.56), Vector2(c.x - r * 0.72, c.y + r * 0.76), Color(_tone, 0.92), 1.55, true)
			"check":
				draw_polyline([
					c + Vector2(-r * 0.62, r * 0.02),
					c + Vector2(-r * 0.12, r * 0.52),
					c + Vector2(r * 0.68, -r * 0.48)
				], _tone, 1.9, true)
			"diamond":
				var pts := PackedVector2Array([
					Vector2(c.x, c.y - r * 0.72), Vector2(c.x + r * 0.64, c.y),
					Vector2(c.x, c.y + r * 0.72), Vector2(c.x - r * 0.64, c.y)
				])
				draw_colored_polygon(pts, _tone)
			"gear":
				draw_arc(c, r * 0.52, 0.0, TAU, 20, _tone, 1.7, true)
				draw_circle(c, r * 0.20, _tone)
				for i: int in 8:
					var dir := Vector2.from_angle(TAU * float(i) / 8.0)
					draw_line(c + dir * r * 0.60, c + dir * r * 0.92, _tone, 1.9, true)
			_:
				var star := PackedVector2Array()
				for i: int in 8:
					var reach := r * (0.94 if i % 2 == 0 else 0.30)
					star.append(c + Vector2.from_angle(TAU * float(i) / 8.0 - PI * 0.5) * reach)
				draw_colored_polygon(star, _tone)
		if _dot_color.a > 0.01:
			var dp := Vector2(size.x - 3.5, 3.5)
			draw_circle(dp, 4.4, Color(_dot_color, 0.28))
			draw_circle(dp, 2.7, _dot_color)


class GhostActionButton extends Button:
	var _glyph: DialogueGlyph
	var _caption: Label
	var _rest_alpha := 0.56
	var _rest_tone := PARCHMENT_MUTED
	var _active_tone := GOLD_BRIGHT
	var _underline_mix := 0.0
	var _hover_tween: Tween
	var _show_underline := true

	func setup(icon_kind: String, label_text: String, font: Font, font_size: int = 16, icon_px: float = 15.0, rest_alpha: float = 0.56, show_underline: bool = true) -> void:
		var empty := StyleBoxEmpty.new()
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, empty)
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_rest_alpha = rest_alpha
		_show_underline = show_underline
		custom_minimum_size = Vector2(44.0 if label_text.is_empty() else 78.0, 44.0)

		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		add_child(row)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		if not icon_kind.is_empty():
			_glyph = DialogueGlyph.new()
			_glyph.setup(icon_kind, icon_px, _rest_tone)
			_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(_glyph)

		if not label_text.is_empty():
			_caption = Kit.create_label(label_text, font_size, _rest_tone, font)
			_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			_caption.add_theme_color_override("font_shadow_color", Color("#090503b8"))
			_caption.add_theme_constant_override("shadow_offset_y", 1)
			row.add_child(_caption)

		Motion.attach_button_feel(self, 1.04, 0.94)
		mouse_entered.connect(_sync_visual.bind(false))
		mouse_exited.connect(_sync_visual.bind(false))
		toggled.connect(func(_pressed: bool) -> void: _sync_visual(false))
		_sync_visual(true)

	func set_indicator_dot(dot_color: Color) -> void:
		if _glyph != null:
			_glyph.set_dot(dot_color)

	func set_soft_disabled(state: bool) -> void:
		disabled = state
		_sync_visual(true)

	func refresh_visual() -> void:
		_sync_visual(false)

	func _sync_visual(instant: bool) -> void:
		var highlighted := (not disabled) and (is_hovered() or (toggle_mode and button_pressed))
		var target_alpha := 0.34 if disabled else (1.0 if highlighted else _rest_alpha)
		var target_tone := _active_tone if highlighted else _rest_tone
		var target_line := 1.0 if (highlighted and _show_underline) else 0.0
		if _glyph != null:
			_glyph.set_tone(target_tone)
		if _caption != null:
			_caption.add_theme_color_override("font_color", target_tone)
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		if instant or not is_inside_tree():
			modulate.a = target_alpha
			_underline_mix = target_line
			queue_redraw()
			return
		_hover_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_property(self, "modulate:a", target_alpha, 0.18)
		_hover_tween.tween_method(func(v: float) -> void:
			_underline_mix = v
			queue_redraw(), _underline_mix, target_line, 0.20)

	func _draw() -> void:
		if _underline_mix <= 0.01:
			return
		var y := size.y - 5.0
		var half := size.x * 0.34 * _underline_mix
		var cx := size.x * 0.5
		draw_line(Vector2(cx - half, y), Vector2(cx + half, y), Color(GOLD_BRIGHT, 0.78 * _underline_mix), 1.4, true)


class ChoiceRibbon extends Button:
	var _bg_rect: ColorRect
	var _mat: ShaderMaterial
	var _content: MarginContainer
	var _glyph: DialogueGlyph
	var _title_lbl: Label
	var _hover_tween: Tween
	var _hover_mix := 0.0

	func setup(text_str: String, is_check: bool, check_meta: Array[Dictionary], title_font: Font, body_font: Font) -> void:
		var empty := StyleBoxEmpty.new()
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(state, empty)
		flat = true
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		custom_minimum_size = Vector2(820.0, 88.0 if is_check else 66.0)

		_bg_rect = ColorRect.new()
		_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_mat = ShaderMaterial.new()
		_mat.shader = CHOICE_RIBBON
		_mat.set_shader_parameter("hover_mix", 0.0)
		_mat.set_shader_parameter("rect_size", custom_minimum_size)
		_bg_rect.material = _mat
		add_child(_bg_rect)
		_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		_content = MarginContainer.new()
		_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_content.add_theme_constant_override("margin_left", 68)
		_content.add_theme_constant_override("margin_right", 68)
		_content.add_theme_constant_override("margin_top", 10)
		_content.add_theme_constant_override("margin_bottom", 10)
		add_child(_content)
		_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 5)
		_content.add_child(col)

		var top := HBoxContainer.new()
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_theme_constant_override("separation", 12)
		col.add_child(top)

		_glyph = DialogueGlyph.new()
		_glyph.setup("d20" if is_check else "star", 20.0 if is_check else 15.0, GOLD_WARM)
		_glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(_glyph)

		_title_lbl = Kit.create_label(text_str, 24, IVORY_SOFT, title_font)
		_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_title_lbl.add_theme_color_override("font_shadow_color", Color("#080402cc"))
		_title_lbl.add_theme_constant_override("shadow_offset_y", 1)
		top.add_child(_title_lbl)

		if is_check and not check_meta.is_empty():
			var meta := HBoxContainer.new()
			meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
			meta.add_theme_constant_override("separation", 10)
			var spacer := Control.new()
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			spacer.custom_minimum_size = Vector2(22.0, 1.0)
			meta.add_child(spacer)
			for i: int in check_meta.size():
				if i > 0:
					var dot := Kit.create_label("·", 15, Color(GOLD_WARM, 0.55), body_font)
					meta.add_child(dot)
				var entry: Dictionary = check_meta[i]
				var tag := Kit.create_label(str(entry["text"]), 15, entry["color"] as Color, title_font if i < 2 else body_font)
				tag.add_theme_color_override("font_shadow_color", Color("#080402b8"))
				tag.add_theme_constant_override("shadow_offset_y", 1)
				meta.add_child(tag)
			col.add_child(meta)

		resized.connect(func() -> void:
			if _mat != null:
				_mat.set_shader_parameter("rect_size", size))
		mouse_entered.connect(_set_hovered.bind(true))
		mouse_exited.connect(_set_hovered.bind(false))
		button_down.connect(func() -> void:
			Motion.spring(self, ^"scale", scale, Vector2.ONE * 0.985, 0.14, 11.0, 8.0))
		button_up.connect(func() -> void:
			Motion.spring(self, ^"scale", scale, Vector2.ONE, 0.30, 9.0, 8.0))
		pivot_offset_ratio = Vector2(0.5, 0.5)

	func _set_hovered(hovered: bool) -> void:
		if hovered:
			AudioManager.play_sfx("ui_hover")
		var target := 1.0 if hovered else 0.0
		_title_lbl.add_theme_color_override("font_color", Color("#fff8e8") if hovered else IVORY_SOFT)
		_glyph.set_tone(GOLD_BRIGHT if hovered else GOLD_WARM)
		if _hover_tween != null and _hover_tween.is_valid():
			_hover_tween.kill()
		_hover_tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		_hover_tween.tween_method(func(v: float) -> void:
			_hover_mix = v
			if _mat != null:
				_mat.set_shader_parameter("hover_mix", v), _hover_mix, target, 0.20)
		Motion.spring(_content, ^"position:x", _content.position.x, 8.0 if hovered else 0.0, 0.34, 9.5, 7.5)
