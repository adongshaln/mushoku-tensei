extends RefCounted

const PAPER := Color("#f5ede0")
const PAPER_DEEP := Color("#eadec9")
const INK := Color("#3b2e25")
const MUTED := Color("#6b5543")
const BLUE := Color("#4a7fa7")
const AMBER := Color("#c88a3b")
const GREEN := Color("#4e8c65")
const VERMILLION := Color("#b84d42")
const WASH := Color("#342920ed")
const BORDER := Color("#7a5c3e")
const SHADOW := Color("#25191162")
const GOLD_LINE := Color("#d9b36a")
const MODIFIER_WARM_LIGHT := Color("#F7D89A")
const MODIFIER_COLD_LIGHT := Color("#A4C9DE")
const MODIFIER_WARM_GLASS := Color("#332418C7")
const MODIFIER_WARM_RIM := Color("#D8A652")
const MODIFIER_WARM_VALUE := Color("#F5C976")
const MODIFIER_COLD_GLASS := Color("#1B2735C7")
const MODIFIER_COLD_RIM := Color("#6C93B5")
const MODIFIER_COLD_VALUE := Color("#9CC8EC")
const MODIFIER_CATEGORY := Color("#B3A697")

const PARCHMENT := preload("res://shaders/parchment_paper.gdshader")
const MODIFIER_FROST := preload("res://shaders/d20_frosted_chip.gdshader")
const Motion := preload("res://ui/ui_motion.gd")


class MicroIcon extends Control:
	var _kind := ""
	var _tone := Color("#6b5543")

	func setup(kind: String, px: float, tone: Color) -> void:
		_kind = kind
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px, px)

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := s * 0.42
		match _kind:
			"morning":
				var horizon := c.y + r * 0.42
				_half_sun(Vector2(c.x, horizon), r * 0.62)
				draw_line(Vector2(c.x - r, horizon), Vector2(c.x + r, horizon), _tone, 2.0, true)
				for angle: float in [-2.35, -1.57, -0.79]:
					var dir := Vector2.from_angle(angle)
					draw_line(Vector2(c.x, horizon) + dir * r * 0.82, Vector2(c.x, horizon) + dir * r * 1.08, _tone, 2.0, true)
			"afternoon":
				draw_circle(c, r * 0.5, _tone)
				for i: int in 8:
					var dir := Vector2.from_angle(TAU * i / 8.0)
					draw_line(c + dir * r * 0.7, c + dir * r * 1.0, _tone, 2.0, true)
			"evening":
				var horizon := c.y + r * 0.18
				_half_sun(Vector2(c.x, horizon), r * 0.66)
				draw_line(Vector2(c.x - r, horizon), Vector2(c.x + r, horizon), _tone, 2.0, true)
				draw_polyline([Vector2(c.x - r * 0.3, horizon + r * 0.42), Vector2(c.x, horizon + r * 0.72), Vector2(c.x + r * 0.3, horizon + r * 0.42)], _tone, 2.0, true)
			"night":
				draw_arc(c, r * 0.6, 0.75, TAU - 0.75, 26, _tone, r * 0.42, true)
				draw_circle(Vector2(c.x + r * 0.62, c.y - r * 0.62), 1.8, _tone)
			"drop":
				var bulb := Vector2(c.x, c.y + r * 0.28)
				var points := PackedVector2Array([Vector2(c.x, c.y - r)])
				for deg: int in range(-55, 236, 16):
					points.append(bulb + Vector2.from_angle(deg_to_rad(deg)) * r * 0.6)
				draw_colored_polygon(points, _tone)
				draw_arc(bulb, r * 0.34, 2.2, 3.6, 12, _tone.lightened(0.4), 1.6, true)
			"bag":
				var body := StyleBoxFlat.new()
				body.bg_color = _tone
				body.set_corner_radius_all(4)
				draw_style_box(body, Rect2(c.x - r * 0.72, c.y - r * 0.3, r * 1.44, r * 1.12))
				draw_arc(Vector2(c.x, c.y - r * 0.3), r * 0.42, PI, TAU, 16, _tone, 2.4, true)
				draw_line(Vector2(c.x - r * 0.72, c.y + r * 0.06), Vector2(c.x + r * 0.72, c.y + r * 0.06), _tone.darkened(0.28), 1.6, true)
			"shield":
				draw_colored_polygon(_smooth([
					Vector2(c.x - r * 0.72, c.y - r * 0.78), Vector2(c.x + r * 0.72, c.y - r * 0.78),
					Vector2(c.x + r * 0.72, c.y + r * 0.12), Vector2(c.x, c.y + r * 0.92),
					Vector2(c.x - r * 0.72, c.y + r * 0.12)
				]), _tone)
				draw_polyline([Vector2(c.x - r * 0.36, c.y - r * 0.3), Vector2(c.x, c.y + r * 0.06), Vector2(c.x + r * 0.36, c.y - r * 0.3)], _tone.lightened(0.38), 1.8, true)
			"eye":
				var rim := PackedVector2Array()
				for i: int in 27:
					var angle := TAU * i / 26.0
					rim.append(c + Vector2(cos(angle) * r * 0.95, sin(angle) * r * 0.55))
				draw_polyline(rim, _tone, 2.2, true)
				draw_circle(c, r * 0.28, _tone)
				_sparkle(Vector2(c.x + r * 0.42, c.y - r * 0.42), r * 0.2, _tone.lightened(0.3))
			"voice":
				draw_colored_polygon([
					Vector2(c.x - r * 0.9, c.y - r * 0.3), Vector2(c.x - r * 0.4, c.y - r * 0.3),
					Vector2(c.x, c.y - r * 0.72), Vector2(c.x, c.y + r * 0.72),
					Vector2(c.x - r * 0.4, c.y + r * 0.3), Vector2(c.x - r * 0.9, c.y + r * 0.3)
				], _tone)
				draw_arc(Vector2(c.x + r * 0.08, c.y), r * 0.45, -0.9, 0.9, 14, _tone, 2.0, true)
				draw_arc(Vector2(c.x + r * 0.08, c.y), r * 0.78, -0.8, 0.8, 14, _tone, 2.0, true)
			"hp":
				draw_colored_polygon(_smooth([
					Vector2(c.x, c.y + r * 0.85), Vector2(c.x - r * 0.55, c.y + r * 0.35),
					Vector2(c.x - r * 0.95, c.y - r * 0.05), Vector2(c.x - r * 0.95, c.y - r * 0.45),
					Vector2(c.x - r * 0.65, c.y - r * 0.8), Vector2(c.x - r * 0.25, c.y - r * 0.8),
					Vector2(c.x, c.y - r * 0.5), Vector2(c.x + r * 0.25, c.y - r * 0.8),
					Vector2(c.x + r * 0.65, c.y - r * 0.8), Vector2(c.x + r * 0.95, c.y - r * 0.45),
					Vector2(c.x + r * 0.95, c.y - r * 0.05), Vector2(c.x + r * 0.55, c.y + r * 0.35)
				]), _tone)
			"star":
				_sparkle(c, r, _tone)

	func _half_sun(at: Vector2, radius: float) -> void:
		var points := PackedVector2Array()
		for i: int in 15:
			points.append(at + Vector2.from_angle(PI + PI * i / 14.0) * radius)
		draw_colored_polygon(points, _tone)

	func _sparkle(at: Vector2, radius: float, color: Color) -> void:
		var points := PackedVector2Array()
		for i: int in 8:
			var reach := radius if i % 2 == 0 else radius * 0.36
			points.append(at + Vector2.from_angle(TAU * i / 8.0 - PI * 0.5) * reach)
		draw_colored_polygon(points, color)

	func _smooth(vertices: PackedVector2Array) -> PackedVector2Array:
		var outline := PackedVector2Array()
		for index: int in vertices.size():
			var vertex := vertices[index]
			var start := vertex.lerp(vertices[posmod(index - 1, vertices.size())], 0.22)
			var finish := vertex.lerp(vertices[(index + 1) % vertices.size()], 0.22)
			for step: int in 4:
				var weight := step / 3.0
				outline.append(start.lerp(vertex, weight).lerp(vertex.lerp(finish, weight), weight))
		return outline


class RibbonHeader extends Control:
	var _tone := Color("#4a7fa7")
	var _label: Label

	func setup(title: String, font: Font, font_size: int, tone: Color) -> void:
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(
			font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 66.0,
			float(font_size) + 20.0)
		_label = Label.new()
		_label.text = title
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_override("font", font)
		_label.add_theme_font_size_override("font_size", font_size)
		_label.add_theme_color_override("font_color", Color("#3b2e25"))
		add_child(_label)
		_label.position = Vector2(36, 8)

	func _draw() -> void:
		var h := size.y
		var w := size.x
		var shape := PackedVector2Array([
			Vector2(0, 3), Vector2(w - 13, 3), Vector2(w, 3), Vector2(w - 7, h * 0.5),
			Vector2(w, h - 3), Vector2(w - 13, h - 3), Vector2(0, h - 3)
		])
		draw_colored_polygon(shape, Color("#eadec9"))
		draw_polyline(shape, Color("#7a5c3e"), 1.6, true)
		var points := PackedVector2Array()
		for i: int in 8:
			var reach := 6.5 if i % 2 == 0 else 2.3
			points.append(Vector2(19, h * 0.5) + Vector2.from_angle(TAU * i / 8.0 - PI * 0.5) * reach)
		draw_colored_polygon(points, _tone)


class CornerMarks extends Control:
	var _tone := Color("#c88a3b")

	func setup(tone: Color) -> void:
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var inset := 7.0
		var length := 17.0
		for corner: Array in [
			[Vector2(inset, inset), Vector2(1, 1)],
			[Vector2(size.x - inset, inset), Vector2(-1, 1)],
			[Vector2(inset, size.y - inset), Vector2(1, -1)],
			[Vector2(size.x - inset, size.y - inset), Vector2(-1, -1)]
		]:
			var at: Vector2 = corner[0]
			var dir: Vector2 = corner[1]
			draw_line(at, at + Vector2(dir.x * length, 0), _tone, 2.2, true)
			draw_line(at, at + Vector2(0, dir.y * length), _tone, 2.2, true)


static func make_font(titles := false) -> SystemFont:
	var font := SystemFont.new()
	if titles:
		font.font_names = PackedStringArray(["Songti SC", "STSong", "SimSun", "Noto Serif CJK SC", "Noto Serif SC"])
	else:
		font.font_names = PackedStringArray(["PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC"])
	return font


static func style(fill: Color, margin_x: int, margin_y: int, shadow: int = 0, border_width: int = 2, border_color: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(5)
	box.shadow_color = SHADOW
	box.shadow_size = shadow
	if shadow > 0:
		box.shadow_offset = Vector2(3, 5)
	box.content_margin_left = margin_x
	box.content_margin_right = margin_x
	box.content_margin_top = margin_y
	box.content_margin_bottom = margin_y
	return box


static func paper_material(size: Vector2, with_inner_line := true) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = PARCHMENT
	material.set_shader_parameter("panel_size", size)
	material.set_shader_parameter("inner_line", 1.0 if with_inner_line else 0.0)
	return material


static func bind_paper(control: Control, material: ShaderMaterial) -> void:
	control.material = material
	var sync_size := func() -> void:
		material.set_shader_parameter("panel_size", control.size)
	control.resized.connect(sync_size)
	sync_size.call()


static func create_folio_panel(fill: Color = PAPER, margin_x: int = 24, margin_y: int = 18, shadow: int = 8) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(fill, margin_x, margin_y, shadow))
	bind_paper(panel, paper_material(Vector2(320, 200), true))
	return panel


static func create_ribbon_header(title: String, font: Font, font_size: int = 26, tone: Color = BLUE) -> RibbonHeader:
	var ribbon := RibbonHeader.new()
	ribbon.setup(title, font, font_size, tone)
	return ribbon


static func create_tactile_button(text: String, variant := "secondary", font: Font = null, font_size: int = 24, hover_scale := 1.03, press_scale := 0.95, pivot_bottom := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 58.0
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	var base: Color
	var hover: Color
	var pressed: Color
	var text_color := INK
	match variant:
		"primary":
			base = BLUE
			hover = BLUE.lightened(0.08)
			pressed = BLUE.darkened(0.16)
			text_color = PAPER
		"accent":
			base = AMBER
			hover = AMBER.lightened(0.08)
			pressed = AMBER.darkened(0.16)
			text_color = PAPER
		"subtle":
			base = Color("#e7dcc8")
			hover = PAPER
			pressed = PAPER_DEEP
			text_color = MUTED
		_:
			base = PAPER_DEEP
			hover = PAPER
			pressed = Color("#e0d3ba")
	button.add_theme_stylebox_override("normal", style(base, 18, 8, 3))
	button.add_theme_stylebox_override("hover", style(hover, 18, 8, 4))
	button.add_theme_stylebox_override("pressed", style(pressed, 18, 8, 1))
	button.add_theme_stylebox_override("hover_pressed", style(pressed, 18, 8, 1))
	button.add_theme_stylebox_override("disabled", style(Color("#ded2bd"), 18, 8, 0))
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(5)
	focus.border_color = Color("#f2c780")
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", text_color)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_pressed_color", PAPER if variant in ["primary", "accent"] else INK)
	button.add_theme_color_override("font_hover_pressed_color", PAPER if variant in ["primary", "accent"] else INK)
	button.add_theme_color_override("font_disabled_color", MUTED)
	bind_paper(button, paper_material(Vector2(180, 58), false))
	Motion.attach_button_feel(button, hover_scale, press_scale, pivot_bottom)
	AudioManager.bind_ui(button)
	return button


static func create_micro_icon(kind: String, px: float = 22.0, tone: Color = MUTED) -> MicroIcon:
	var icon := MicroIcon.new()
	icon.setup(kind, px, tone)
	return icon


static func create_badge(text: String, tone: Color = BLUE, font: Font = null, font_size: int = 18) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", style(tone, 11, 5, 0, 1, tone.darkened(0.22)))
	var label := create_label(text, font_size, PAPER, font)
	badge.add_child(label)
	return badge


static func create_chip(text: String, font: Font = null, font_size: int = 21) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override("panel", style(PAPER, 14, 8, 4))
	bind_paper(chip, paper_material(Vector2(160, 44), false))
	chip.add_child(create_label(text, font_size, INK, font))
	return chip


static func create_modifier_chip(title: String, value: int, category: String, font: Font, number_font: Font, width: float) -> PanelContainer:
	var warm := value > 0
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.pivot_offset_ratio = Vector2(0.5, 0.5)
	chip.custom_minimum_size = Vector2(width, 67.0)
	chip.add_theme_stylebox_override("panel", modifier_style(warm))
	var frost := ShaderMaterial.new()
	frost.shader = MODIFIER_FROST
	frost.set_shader_parameter("sheen_tone", MODIFIER_WARM_RIM if warm else MODIFIER_COLD_RIM)
	bind_paper(chip, frost)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	chip.add_child(row)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	names.add_theme_constant_override("separation", 0)
	row.add_child(names)
	var name_label := create_label(title, 20, Color("#F5EBDC"), font)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(name_label)
	var category_label := create_label(category, 14, MODIFIER_CATEGORY, font)
	category_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	names.add_child(category_label)
	var amount := create_label("%+d" % value, 31, MODIFIER_WARM_VALUE if warm else MODIFIER_COLD_VALUE, number_font)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	amount.custom_minimum_size.x = 43.0
	row.add_child(amount)
	return chip


static func modifier_style(positive: bool, awakened: bool = false) -> StyleBoxFlat:
	var glass := MODIFIER_WARM_GLASS if positive else MODIFIER_COLD_GLASS
	var border := MODIFIER_WARM_RIM if positive else MODIFIER_COLD_RIM
	var box := style(glass, 13, 8, 7, 1, Color(border, 0.86))
	box.set_corner_radius_all(9)
	box.shadow_color = Color("#150E0AC4")
	box.shadow_offset = Vector2(0.0, 4.0)
	if awakened:
		box.border_color = border.lightened(0.32)
		box.shadow_color = Color((MODIFIER_WARM_LIGHT if positive else MODIFIER_COLD_LIGHT), 0.36)
		box.shadow_offset = Vector2.ZERO
		box.shadow_size = 10
	return box


static func create_meter(fill: Color, track: Color = Color("#d9c7a9"), height: float = 10.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var background := StyleBoxFlat.new()
	background.bg_color = track
	background.set_corner_radius_all(4)
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", foreground)
	return bar


static func create_label(text: String, font_size: int, color: Color, font: Font = null) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	if font != null:
		label.add_theme_font_override("font", font)
	return label


static func style_scrollbar(bar: ScrollBar) -> void:
	bar.custom_minimum_size.x = 10.0
	var track := style(Color("#e5d9c2"), 0, 0, 0, 0)
	track.set_corner_radius_all(4)
	var grabber := style(PAPER_DEEP, 0, 0, 0, 1, BORDER)
	grabber.set_corner_radius_all(4)
	var active := style(AMBER, 0, 0, 0, 1, BORDER)
	active.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_pressed", active)
	bar.add_theme_stylebox_override("grabber_highlight", active)

