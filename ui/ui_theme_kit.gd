extends RefCounted

const PAPER := Color("#f5ede0")
const PAPER_DEEP := Color("#eadec9")
const INK := Color("#3b2e25")
const MUTED := Color("#6b5543")
const BLUE := Color("#4a7fa7")
const AMBER := Color("#c88a3b")
const GREEN := Color("#4e8c65")
const VERMILLION := Color("#b84d42")
const WASH := Color("#231912ea")
const BORDER := Color("#7a5c3e")
const SHADOW := Color("#170f0a78")
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

const ESPRESSO := Color("#1c1510e6")
const ESPRESSO_DEEP := Color("#140e0bf0")
const LEATHER := Color("#332217")
const LEATHER_RIM := Color("#9a7440")
const BRASS := Color("#e0b76a")
const IVORY := Color("#f7efe1")
const SAPPHIRE := Color("#3b6f96")
const WAX_GOLD := Color("#c68634")
const WAX_RED := Color("#9c3d34")

const PARCHMENT := preload("res://shaders/parchment_paper.gdshader")
const MODIFIER_FROST := preload("res://shaders/d20_frosted_chip.gdshader")
const BUTTON_SHEEN := preload("res://shaders/game_button_sheen.gdshader")
const SMOKED_GLASS := preload("res://shaders/smoked_hud_glass.gdshader")
const GRIMOIRE_SPREAD := preload("res://shaders/grimoire_book_spread.gdshader")
const CIRCLE_MASK := preload("res://shaders/circle_mask.gdshader")
const Motion := preload("res://ui/ui_motion.gd")


class MicroIcon extends Control:
	var _kind := ""
	var _tone := Color("#6b5543")

	func setup(kind: String, px: float, tone: Color) -> void:
		_kind = kind
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px, px)
		queue_redraw()

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
			"staff":
				draw_line(c + Vector2(-r * 0.75, r * 0.80), c + Vector2(r * 0.48, -r * 0.45), _tone, 2.6, true)
				draw_arc(c + Vector2(r * 0.58, -r * 0.58), r * 0.32, 0.0, TAU, 18, _tone, 2.0, true)
				_sparkle(c + Vector2(r * 0.58, -r * 0.58), r * 0.22, _tone.lightened(0.32))
			"cloak":
				draw_colored_polygon([
					Vector2(c.x, c.y - r * 0.88), Vector2(c.x + r * 0.42, c.y - r * 0.42),
					Vector2(c.x + r * 0.84, c.y + r * 0.78), Vector2(c.x, c.y + r * 0.56),
					Vector2(c.x - r * 0.84, c.y + r * 0.78), Vector2(c.x - r * 0.42, c.y - r * 0.42)
				], _tone)
				draw_circle(Vector2(c.x, c.y - r * 0.22), r * 0.15, _tone.lightened(0.45))
			"charm":
				draw_arc(Vector2(c.x, c.y - r * 0.55), r * 0.34, PI * 0.15, PI * 0.85, 14, _tone, 1.8, true)
				draw_colored_polygon([
					Vector2(c.x, c.y - r * 0.25), Vector2(c.x + r * 0.48, c.y + r * 0.28),
					Vector2(c.x, c.y + r * 0.88), Vector2(c.x - r * 0.48, c.y + r * 0.28)
				], _tone)
				draw_circle(Vector2(c.x, c.y + r * 0.28), r * 0.16, _tone.lightened(0.42))
			"crown":
				draw_colored_polygon([
					Vector2(c.x - r * 0.82, c.y + r * 0.58), Vector2(c.x - r * 0.90, c.y - r * 0.35),
					Vector2(c.x - r * 0.38, c.y + r * 0.08), Vector2(c.x, c.y - r * 0.65),
					Vector2(c.x + r * 0.38, c.y + r * 0.08), Vector2(c.x + r * 0.90, c.y - r * 0.35),
					Vector2(c.x + r * 0.82, c.y + r * 0.58)
				], _tone)
			"coin":
				draw_circle(c, r * 0.78, _tone)
				draw_arc(c, r * 0.55, 0.0, TAU, 22, _tone.lightened(0.38), 1.5, true)
				_sparkle(c, r * 0.30, _tone.lightened(0.45))
			"ration":
				var bread := PackedVector2Array()
				for i: int in 17:
					var t := float(i) / 16.0
					var ang := lerpf(PI, TAU, t)
					bread.append(Vector2(c.x + cos(ang) * r * 0.85, c.y + r * 0.25 + sin(ang) * r * 0.68))
				bread.append(Vector2(c.x + r * 0.85, c.y + r * 0.55))
				bread.append(Vector2(c.x - r * 0.85, c.y + r * 0.55))
				draw_colored_polygon(bread, _tone)
				draw_line(Vector2(c.x - r * 0.35, c.y - r * 0.15), Vector2(c.x - r * 0.12, c.y + r * 0.15), _tone.darkened(0.3), 1.8, true)
				draw_line(Vector2(c.x + r * 0.12, c.y - r * 0.15), Vector2(c.x + r * 0.35, c.y + r * 0.15), _tone.darkened(0.3), 1.8, true)
			"compass":
				draw_arc(c, r * 0.88, 0.0, TAU, 28, _tone, 2.0, true)
				draw_colored_polygon([
					Vector2(c.x, c.y - r * 0.76), Vector2(c.x + r * 0.26, c.y),
					Vector2(c.x, c.y + r * 0.14), Vector2(c.x - r * 0.26, c.y)
				], _tone.lightened(0.28))
				draw_colored_polygon([
					Vector2(c.x, c.y + r * 0.76), Vector2(c.x + r * 0.22, c.y),
					Vector2(c.x - r * 0.22, c.y)
				], _tone)
			"book":
				draw_polyline([
					Vector2(c.x, c.y - r * 0.58), Vector2(c.x - r * 0.85, c.y - r * 0.72),
					Vector2(c.x - r * 0.85, c.y + r * 0.56), Vector2(c.x, c.y + r * 0.72),
					Vector2(c.x + r * 0.85, c.y + r * 0.56), Vector2(c.x + r * 0.85, c.y - r * 0.72),
					Vector2(c.x, c.y - r * 0.58), Vector2(c.x, c.y + r * 0.72)
				], _tone, 2.1, true)
			"quill":
				draw_colored_polygon([
					Vector2(c.x + r * 0.78, c.y - r * 0.82), Vector2(c.x + r * 0.45, c.y + r * 0.08),
					Vector2(c.x - r * 0.35, c.y + r * 0.48), Vector2(c.x - r * 0.15, c.y - r * 0.28)
				], _tone)
				draw_line(Vector2(c.x + r * 0.62, c.y - r * 0.62), Vector2(c.x - r * 0.78, c.y + r * 0.82), _tone.lightened(0.25), 2.1, true)
			"door":
				draw_polyline([
					Vector2(c.x - r * 0.62, c.y + r * 0.78), Vector2(c.x - r * 0.62, c.y - r * 0.78),
					Vector2(c.x + r * 0.62, c.y - r * 0.78), Vector2(c.x + r * 0.62, c.y + r * 0.78)
				], _tone, 2.2, true)
				draw_line(Vector2(c.x - r * 0.82, c.y + r * 0.78), Vector2(c.x + r * 0.82, c.y + r * 0.78), _tone, 2.0, true)
				draw_circle(Vector2(c.x + r * 0.28, c.y + r * 0.05), r * 0.14, _tone)
			"foot":
				draw_line(Vector2(c.x - r * 0.55, c.y + r * 0.72), Vector2(c.x - r * 0.05, c.y - r * 0.10), _tone, 2.2, true)
				draw_line(Vector2(c.x + r * 0.55, c.y + r * 0.72), Vector2(c.x + r * 0.10, c.y - r * 0.10), _tone, 2.2, true)
				draw_circle(Vector2(c.x, c.y - r * 0.58), r * 0.24, _tone)
				draw_line(Vector2(c.x, c.y - r * 0.32), Vector2(c.x, c.y + r * 0.04), _tone, 2.2, true)
			"caravan":
				draw_arc(Vector2(c.x, c.y + r * 0.08), r * 0.68, PI, TAU, 16, _tone, 2.2, true)
				draw_line(Vector2(c.x - r * 0.76, c.y + r * 0.10), Vector2(c.x + r * 0.76, c.y + r * 0.10), _tone, 2.2, true)
				draw_circle(Vector2(c.x - r * 0.44, c.y + r * 0.52), r * 0.24, _tone)
				draw_circle(Vector2(c.x + r * 0.44, c.y + r * 0.52), r * 0.24, _tone)
			"ship":
				draw_colored_polygon([
					Vector2(c.x - r * 0.85, c.y + r * 0.22), Vector2(c.x + r * 0.85, c.y + r * 0.22),
					Vector2(c.x + r * 0.55, c.y + r * 0.70), Vector2(c.x - r * 0.55, c.y + r * 0.70)
				], _tone)
				draw_line(Vector2(c.x, c.y + r * 0.22), Vector2(c.x, c.y - r * 0.82), _tone, 2.0, true)
				draw_colored_polygon([
					Vector2(c.x + 1.0, c.y - r * 0.76), Vector2(c.x + r * 0.68, c.y + r * 0.04),
					Vector2(c.x + 1.0, c.y + r * 0.04)
				], _tone.lightened(0.24))
			"lock":
				draw_arc(Vector2(c.x, c.y - r * 0.22), r * 0.42, PI, TAU, 16, _tone, 2.2, true)
				var box := StyleBoxFlat.new()
				box.bg_color = _tone
				box.set_corner_radius_all(3)
				draw_style_box(box, Rect2(c.x - r * 0.62, c.y - r * 0.18, r * 1.24, r * 0.96))
				draw_circle(Vector2(c.x, c.y + r * 0.25), r * 0.14, _tone.darkened(0.45))
			"gear":
				draw_arc(c, r * 0.56, 0.0, TAU, 24, _tone, 2.2, true)
				draw_circle(c, r * 0.24, _tone)
				for i: int in 8:
					var dir := Vector2.from_angle(TAU * float(i) / 8.0)
					draw_line(c + dir * r * 0.64, c + dir * r * 0.96, _tone, 2.4, true)
			"sword":
				draw_line(c + Vector2(-r * 0.72, r * 0.72), c + Vector2(r * 0.74, -r * 0.74), _tone, 2.6, true)
				draw_line(c + Vector2(-r * 0.56, r * 0.14), c + Vector2(-r * 0.14, r * 0.56), _tone, 2.4, true)
			"scroll":
				draw_polyline([
					Vector2(c.x - r * 0.66, c.y - r * 0.64), Vector2(c.x + r * 0.66, c.y - r * 0.64),
					Vector2(c.x + r * 0.66, c.y + r * 0.64), Vector2(c.x - r * 0.66, c.y + r * 0.64),
					Vector2(c.x - r * 0.66, c.y - r * 0.64)
				], _tone, 2.0, true)
				draw_line(Vector2(c.x - r * 0.36, c.y - r * 0.22), Vector2(c.x + r * 0.36, c.y - r * 0.22), _tone, 1.8, true)
				draw_line(Vector2(c.x - r * 0.36, c.y + r * 0.16), Vector2(c.x + r * 0.26, c.y + r * 0.16), _tone, 1.8, true)
			"d20":
				var hex := PackedVector2Array()
				for i: int in 7:
					var ang := TAU * i / 6.0 - PI * 0.5
					hex.append(c + Vector2.from_angle(ang) * r * 0.88)
				draw_polyline(hex, _tone, 2.0, true)
				var tri := PackedVector2Array([
					c + Vector2(0.0, -r * 0.48), c + Vector2(r * 0.44, r * 0.28),
					c + Vector2(-r * 0.44, r * 0.28), c + Vector2(0.0, -r * 0.48)
				])
				draw_polyline(tri, _tone.lightened(0.25), 1.6, true)
			"close":
				draw_line(c + Vector2(-r * 0.58, -r * 0.58), c + Vector2(r * 0.58, r * 0.58), _tone, 2.2, true)
				draw_line(c + Vector2(r * 0.58, -r * 0.58), c + Vector2(-r * 0.58, r * 0.58), _tone, 2.2, true)
			_:
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
	var _tone := Color("#c88a3b")
	var _label: Label

	func setup(title: String, font: Font, font_size: int, tone: Color) -> void:
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(
			font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 62.0,
			float(font_size) + 16.0)
		_label = Label.new()
		_label.text = title
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label.add_theme_font_override("font", font)
		_label.add_theme_font_size_override("font_size", font_size)
		_label.add_theme_color_override("font_color", INK)
		add_child(_label)
		_label.position = Vector2(28, 5)
		resized.connect(queue_redraw)

	func _draw() -> void:
		var h := size.y
		var w := size.x
		# Sleek light-novel section header: diamond emblem + subtle gold rule underneath.
		var cy := h * 0.5
		var d := PackedVector2Array([
			Vector2(10.0, cy - 6.0), Vector2(16.0, cy), Vector2(10.0, cy + 6.0), Vector2(4.0, cy)
		])
		draw_colored_polygon(d, _tone)
		var y_line := h - 2.0
		var steps := 18
		for i: int in steps:
			var t0 := float(i) / steps
			var t1 := float(i + 1) / steps
			var alpha := (1.0 - t0 * t0) * 0.52
			draw_line(Vector2(w * t0, y_line), Vector2(w * t1, y_line), Color(_tone, alpha), 1.6, true)


class CornerMarks extends Control:
	var _tone := Color("#c88a3b")
	var _inset := 7.0
	var _length := 17.0

	func setup(tone: Color, inset := 7.0, length := 17.0) -> void:
		_tone = tone
		_inset = inset
		_length = length
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var inset := _inset
		var length := _length
		for corner: Array in [
			[Vector2(inset, inset), Vector2(1, 1)],
			[Vector2(size.x - inset, inset), Vector2(-1, 1)],
			[Vector2(inset, size.y - inset), Vector2(1, -1)],
			[Vector2(size.x - inset, size.y - inset), Vector2(-1, -1)]
		]:
			var at: Vector2 = corner[0]
			var dir: Vector2 = corner[1]
			draw_line(at, at + Vector2(dir.x * length, 0), _tone, 2.0, true)
			draw_line(at, at + Vector2(0, dir.y * length), _tone, 2.0, true)
			draw_circle(at + Vector2(dir.x * 4.5, dir.y * 4.5), 1.6, Color(_tone, 0.72))


class WaxSeal extends Control:
	var _tone := WAX_GOLD
	var _glyph := "star"
	var _cracked := false

	func setup(tone: Color = WAX_GOLD, glyph := "star", px := 42.0, cracked := false) -> void:
		_tone = tone
		_glyph = glyph
		_cracked = cracked
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(px, px)
		pivot_offset_ratio = Vector2(0.5, 0.5)
		queue_redraw()

	func _draw() -> void:
		var s := minf(size.x, size.y)
		var c := size * 0.5
		var r := s * 0.44
		# Soft drop shadow.
		draw_circle(c + Vector2(1.5, 2.5), r * 1.02, Color(0.08, 0.05, 0.03, 0.34))
		# Organic scalloped wax perimeter.
		var outer := PackedVector2Array()
		var pts := 36
		for i: int in pts:
			var ang := TAU * i / pts
			var wobble := 1.0 + 0.055 * sin(ang * 7.0 + 0.5) + 0.03 * cos(ang * 11.0)
			outer.append(c + Vector2.from_angle(ang) * r * wobble)
		draw_colored_polygon(outer, _tone.darkened(0.14))
		draw_circle(c, r * 0.80, _tone)
		draw_arc(c, r * 0.67, 0.0, TAU, 28, _tone.lightened(0.28), 1.6, true)
		draw_arc(c, r * 0.81, -PI * 0.85, -PI * 0.15, 16, Color(1.0, 0.96, 0.85, 0.32), 1.4, true)
		# Embossed center mark.
		var mark_col := _tone.lightened(0.46)
		if _glyph == "lock":
			draw_arc(Vector2(c.x, c.y - r * 0.12), r * 0.22, PI, TAU, 12, mark_col, 1.8, true)
			draw_rect(Rect2(c.x - r * 0.28, c.y - r * 0.10, r * 0.56, r * 0.44), mark_col)
		else:
			var star := PackedVector2Array()
			for i: int in 8:
				var reach := r * (0.40 if i % 2 == 0 else 0.15)
				star.append(c + Vector2.from_angle(TAU * i / 8.0 - PI * 0.5) * reach)
			draw_colored_polygon(star, mark_col)
		if _cracked:
			draw_polyline([
				c + Vector2(-r * 0.52, -r * 0.45), c + Vector2(-r * 0.05, -r * 0.06),
				c + Vector2(r * 0.14, r * 0.16), c + Vector2(r * 0.50, r * 0.52)
			], Color("#2b1c18"), 2.0, true)


class StatRadarChart extends Control:
	var _labels: Array[String] = []
	var _values: Array[float] = []
	var _font: Font

	func setup(labels: Array[String], values: Array[float], font: Font) -> void:
		_labels = labels
		_values = values
		_font = font
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var count := _labels.size()
		if count < 3:
			return
		var c := size * 0.5
		var max_r := minf(size.x, size.y) * 0.34
		# Concentric astronomical web polygons (3 rings).
		for ring: int in range(1, 4):
			var rr := max_r * float(ring) / 3.0
			var poly := PackedVector2Array()
			for i: int in count + 1:
				var ang := TAU * (i % count) / count - PI * 0.5
				poly.append(c + Vector2.from_angle(ang) * rr)
			draw_polyline(poly, Color(AMBER, 0.18 if ring < 3 else 0.42), 1.2 if ring < 3 else 1.6, true)
		# Radial spokes and labels.
		var data_poly := PackedVector2Array()
		for i: int in count:
			var ang := TAU * i / count - PI * 0.5
			var dir := Vector2.from_angle(ang)
			draw_line(c, c + dir * max_r, Color(AMBER, 0.24), 1.1, true)
			var norm := clampf(_values[i] / 18.0, 0.16, 1.0)
			data_poly.append(c + dir * (max_r * norm))
			if _font != null:
				var text := _labels[i]
				var tsize := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
				var pos := c + dir * (max_r + 22.0) - tsize * 0.5 + Vector2(0.0, tsize.y * 0.35)
				draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, INK)
		# Glowing stat silhouette polygon.
		draw_colored_polygon(data_poly, Color(BLUE, 0.26))
		var closed := data_poly.duplicate()
		closed.append(data_poly[0])
		draw_polyline(closed, Color(BLUE, 0.90), 2.2, true)
		for pt: Vector2 in data_poly:
			draw_circle(pt, 4.4, WAX_GOLD)
			draw_circle(pt, 2.2, IVORY)


class RankPipBar extends Control:
	var _filled := 0
	var _total := 3
	var _tone := WAX_GOLD

	func setup(filled: int, total: int, tone: Color = WAX_GOLD) -> void:
		_filled = clampi(filled, 0, total)
		_total = maxi(1, total)
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(float(_total) * 18.0 + 4.0, 18.0)
		queue_redraw()

	func _draw() -> void:
		var cy := size.y * 0.5
		for i: int in _total:
			var cx := 9.0 + float(i) * 18.0
			var r := 6.0
			var dia := PackedVector2Array([
				Vector2(cx, cy - r), Vector2(cx + r, cy), Vector2(cx, cy + r), Vector2(cx - r, cy)
			])
			if i < _filled:
				draw_colored_polygon(dia, _tone)
				draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), _tone.lightened(0.35), 1.2, true)
			else:
				draw_colored_polygon(dia, Color("#d4c3a7"))
				draw_polyline(PackedVector2Array([dia[0], dia[1], dia[2], dia[3], dia[0]]), Color("#9c8669"), 1.1, true)


class AstralWatermark extends Control:
	var _tone := Color("#e0b76a")
	var _angle := 0.0

	func setup(tone: Color = Color("#e0b76a")) -> void:
		_tone = tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * 0.045, TAU)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44
		draw_arc(c, r, 0.0, TAU, 64, Color(_tone, 0.16), 1.4, true)
		draw_arc(c, r * 0.84, 0.0, TAU, 64, Color(_tone, 0.11), 1.0, true)
		draw_arc(c, r * 0.52, 0.0, TAU, 48, Color(_tone, 0.10), 1.0, true)
		for i: int in 12:
			var ang := _angle + TAU * i / 12.0
			var inner := r * (0.74 if i % 3 == 0 else 0.84)
			var outer := r * (1.06 if i % 3 == 0 else 0.96)
			draw_line(c + Vector2.from_angle(ang) * inner, c + Vector2.from_angle(ang) * outer, Color(_tone, 0.22 if i % 3 == 0 else 0.12), 1.3, true)
		var star := PackedVector2Array()
		for i: int in 8:
			var ang := -_angle * 0.5 + TAU * i / 8.0
			var reach := r * (0.48 if i % 2 == 0 else 0.14)
			star.append(c + Vector2.from_angle(ang) * reach)
		star.append(star[0])
		draw_polyline(star, Color(_tone, 0.16), 1.2, true)


class PortraitMedallion extends Control:
	var _texture: Texture2D
	var _ring_tone := BRASS
	var _img: TextureRect
	var _ring_overlay: Control

	func setup(tex: Texture2D, diameter := 68.0, ring_tone: Color = BRASS) -> void:
		_texture = tex
		_ring_tone = ring_tone
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(diameter, diameter)
		_img = TextureRect.new()
		_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var mat := ShaderMaterial.new()
		mat.shader = CIRCLE_MASK
		_img.material = mat
		add_child(_img)
		_img.anchor_left = 0.07
		_img.anchor_top = 0.07
		_img.anchor_right = 0.93
		_img.anchor_bottom = 0.93
		_ring_overlay = Control.new()
		_ring_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ring_overlay.draw.connect(_draw_ring)
		add_child(_ring_overlay)
		_ring_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		set_portrait(tex)

	func set_portrait(tex: Texture2D) -> void:
		_texture = tex
		if _img != null:
			if tex != null:
				var sz := tex.get_size()
				var side := minf(sz.x, sz.y * 0.78)
				var crop := AtlasTexture.new()
				crop.atlas = tex
				crop.region = Rect2(Vector2((sz.x - side) * 0.5, sz.y * 0.02), Vector2(side, side)).intersection(Rect2(Vector2.ZERO, sz))
				_img.texture = crop
			else:
				_img.texture = null
		queue_redraw()
		if _ring_overlay != null:
			_ring_overlay.queue_redraw()

	func _draw() -> void:
		var d := minf(size.x, size.y)
		var c := size * 0.5
		var r := d * 0.45
		draw_circle(c + Vector2(0.0, 2.5), r + 3.5, Color(0.05, 0.03, 0.02, 0.58))
		draw_circle(c, r, Color("#2c2017"))

	func _draw_ring() -> void:
		var d := minf(size.x, size.y)
		var c := size * 0.5
		var r := d * 0.45
		_ring_overlay.draw_arc(c, r + 1.0, 0.0, TAU, 44, _ring_tone, 2.8, true)
		_ring_overlay.draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(0.08, 0.05, 0.03, 0.58), 1.4, true)
		_ring_overlay.draw_circle(c + Vector2(0.0, -r - 1.0), 3.0, _ring_tone.lightened(0.25))


static func make_font(titles := false) -> SystemFont:
	var font := SystemFont.new()
	if titles:
		font.font_names = PackedStringArray(["Songti SC", "STSong", "SimSun", "Noto Serif CJK SC", "Noto Serif SC"])
	else:
		font.font_names = PackedStringArray(["Hiragino Sans GB", "PingFang SC", "Microsoft YaHei", "Noto Sans CJK SC", "Noto Sans SC"])
	return font


static func style(fill: Color, margin_x: int, margin_y: int, shadow: int = 0, border_width: int = 2, border_color: Color = BORDER) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(6)
	box.shadow_color = SHADOW
	box.shadow_size = shadow
	if shadow > 0:
		box.shadow_offset = Vector2(2, 5)
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
	panel.add_theme_stylebox_override("panel", style(fill, margin_x, margin_y, shadow, 2, Color("#896844")))
	bind_paper(panel, paper_material(Vector2(320, 200), true))
	return panel


static func create_smoked_hud_panel(margin_x: int = 20, margin_y: int = 12, shadow: int = 10, fill: Color = ESPRESSO, border_col: Color = Color("#c89b5280")) -> PanelContainer:
	var panel := PanelContainer.new()
	var box := style(fill, margin_x, margin_y, shadow, 1, border_col)
	box.set_corner_radius_all(8)
	box.shadow_color = Color("#0b070496")
	box.shadow_offset = Vector2(0.0, 5.0)
	panel.add_theme_stylebox_override("panel", box)
	var mat := ShaderMaterial.new()
	mat.shader = SMOKED_GLASS
	mat.set_shader_parameter("panel_size", Vector2(320, 80))
	bind_paper(panel, mat)
	return panel


static func create_grimoire_book(dimensions: Vector2, spine_x: float = 0.295, show_spine: bool = true) -> Dictionary:
	# Outer dark walnut/leather hardcover binding with antique brass border.
	var binding := PanelContainer.new()
	var cover := style(LEATHER, 12, 12, 22, 2, LEATHER_RIM)
	cover.set_corner_radius_all(10)
	cover.shadow_color = Color("#090604c8")
	cover.shadow_offset = Vector2(0.0, 12.0)
	binding.add_theme_stylebox_override("panel", cover)
	binding.custom_minimum_size = dimensions
	binding.pivot_offset_ratio = Vector2(0.5, 0.5)

	# Inner open parchment spread with spine gutter shadow & double filigree ruling.
	var spread := PanelContainer.new()
	var page_box := style(PAPER, 34, 24, 4, 1, Color("#8b6a42"))
	page_box.set_corner_radius_all(5)
	page_box.shadow_color = Color("#120b0660")
	spread.add_theme_stylebox_override("panel", page_box)
	var mat := ShaderMaterial.new()
	mat.shader = GRIMOIRE_SPREAD
	mat.set_shader_parameter("panel_size", dimensions)
	mat.set_shader_parameter("spine_x", spine_x)
	mat.set_shader_parameter("show_spine", 1.0 if show_spine else 0.0)
	bind_paper(spread, mat)
	binding.add_child(spread)

	# Subtle antique brass corner flourishes mounted on leather binding.
	var corners := CornerMarks.new()
	corners.setup(Color(BRASS, 0.85), 5.0, 22.0)
	binding.add_child(corners)
	corners.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return {"binding": binding, "spread": spread, "material": mat}


static func create_ribbon_header(title: String, font: Font, font_size: int = 24, tone: Color = AMBER) -> RibbonHeader:
	var ribbon := RibbonHeader.new()
	ribbon.setup(title, font, font_size, tone)
	return ribbon


static func create_tactile_button(text: String, variant := "secondary", font: Font = null, font_size: int = 24, hover_scale := 1.03, press_scale := 0.95, pivot_bottom := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54.0
	if font != null:
		button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)

	if variant == "ghost_gold":
		var empty := StyleBoxEmpty.new()
		empty.content_margin_left = 22
		empty.content_margin_right = 22
		empty.content_margin_top = 10
		empty.content_margin_bottom = 10
		var hover_box := StyleBoxFlat.new()
		hover_box.bg_color = Color("#e0b76a22")
		hover_box.border_color = Color("#e0b76a88")
		hover_box.border_width_left = 3
		hover_box.border_width_top = 1
		hover_box.border_width_bottom = 1
		hover_box.set_corner_radius_all(4)
		hover_box.content_margin_left = 22
		hover_box.content_margin_right = 22
		hover_box.content_margin_top = 10
		hover_box.content_margin_bottom = 10
		var press_box := hover_box.duplicate() as StyleBoxFlat
		press_box.bg_color = Color("#e0b76a38")
		button.add_theme_stylebox_override("normal", empty)
		button.add_theme_stylebox_override("hover", hover_box)
		button.add_theme_stylebox_override("pressed", press_box)
		button.add_theme_stylebox_override("hover_pressed", press_box)
		button.add_theme_stylebox_override("focus", hover_box)
		button.add_theme_color_override("font_color", Color("#eee2ce"))
		button.add_theme_color_override("font_hover_color", Color("#fff4dc"))
		button.add_theme_color_override("font_focus_color", Color("#fff4dc"))
		button.add_theme_color_override("font_pressed_color", BRASS)
		button.add_theme_color_override("font_shadow_color", Color("#140d09c4"))
		button.add_theme_constant_override("shadow_offset_y", 2)
		Motion.attach_button_feel(button, 1.025, 0.97, false)
		AudioManager.bind_ui(button)
		return button

	var base: Color
	var hover: Color
	var pressed: Color
	var border_col := BORDER
	var hover_border := Color("#c89b52")
	var text_color := INK
	var radius := 7
	var sheen_tint := Color(1.0, 0.90, 0.66, 0.44)
	match variant:
		"primary":
			base = SAPPHIRE
			hover = SAPPHIRE.lightened(0.09)
			pressed = SAPPHIRE.darkened(0.16)
			border_col = Color("#8eb8d6aa")
			hover_border = BRASS
			text_color = IVORY
		"accent":
			base = WAX_GOLD
			hover = WAX_GOLD.lightened(0.10)
			pressed = WAX_GOLD.darkened(0.16)
			border_col = Color("#f3d28ecc")
			hover_border = Color("#ffebc0")
			text_color = IVORY
		"dark_brass":
			base = Color("#211812eb")
			hover = Color("#2f2218f4")
			pressed = Color("#18110df2")
			border_col = Color("#b88d4b96")
			hover_border = BRASS
			text_color = IVORY
			radius = 8
		"medallion":
			base = Color("#241912ef")
			hover = Color("#34251af6")
			pressed = Color("#19110df5")
			border_col = Color("#cfa35cb8")
			hover_border = Color("#f4d490")
			text_color = IVORY
			radius = 24
		"subtle":
			base = Color("#e7dcc7")
			hover = PAPER
			pressed = PAPER_DEEP
			border_col = Color("#9b806088")
			hover_border = Color("#8b6a42")
			text_color = MUTED
		_:
			base = Color("#ede0ca")
			hover = Color("#f7efe2")
			pressed = Color("#dfd0b4")
			border_col = Color("#8a6a44b0")
			hover_border = WAX_GOLD
			text_color = INK

	var s_norm := style(base, 18, 8, 4, 1 if variant in ["dark_brass", "medallion"] else 2, border_col)
	var s_hov := style(hover, 18, 8, 6, 1 if variant in ["dark_brass", "medallion"] else 2, hover_border)
	var s_prs := style(pressed, 18, 8, 1, 1 if variant in ["dark_brass", "medallion"] else 2, border_col)
	var s_dis := style(Color("#cfc2ad") if variant not in ["dark_brass", "medallion"] else Color("#1c151099"), 18, 8, 0, 1, Color("#8a745c66"))
	for box: StyleBoxFlat in [s_norm, s_hov, s_prs, s_dis]:
		box.set_corner_radius_all(radius)
	button.add_theme_stylebox_override("normal", s_norm)
	button.add_theme_stylebox_override("hover", s_hov)
	button.add_theme_stylebox_override("pressed", s_prs)
	button.add_theme_stylebox_override("hover_pressed", s_prs)
	button.add_theme_stylebox_override("disabled", s_dis)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(radius)
	focus.border_color = BRASS
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", text_color)
	button.add_theme_color_override("font_hover_color", Color("#fff8eb") if variant in ["primary", "accent", "dark_brass", "medallion"] else INK)
	button.add_theme_color_override("font_focus_color", text_color)
	button.add_theme_color_override("font_pressed_color", IVORY if variant in ["primary", "accent", "dark_brass", "medallion"] else INK)
	button.add_theme_color_override("font_hover_pressed_color", IVORY if variant in ["primary", "accent", "dark_brass", "medallion"] else INK)
	button.add_theme_color_override("font_disabled_color", Color("#8a7968"))

	var sheen := ShaderMaterial.new()
	sheen.shader = BUTTON_SHEEN
	sheen.set_shader_parameter("sheen_color", sheen_tint)
	bind_paper(button, sheen)
	button.mouse_entered.connect(func() -> void:
		if button.disabled:
			return
		var tw := button.create_tween().set_parallel(true)
		tw.tween_method(func(v: float) -> void: sheen.set_shader_parameter("hover_amount", v), 0.0, 1.0, 0.18)
		tw.tween_method(func(v: float) -> void: sheen.set_shader_parameter("sheen_progress", v), -0.45, 1.45, 0.52).set_trans(Tween.TRANS_SINE))
	button.mouse_exited.connect(func() -> void:
		var tw := button.create_tween()
		tw.tween_method(func(v: float) -> void: sheen.set_shader_parameter("hover_amount", v), 1.0, 0.0, 0.22))

	Motion.attach_button_feel(button, hover_scale, press_scale, pivot_bottom)
	AudioManager.bind_ui(button)
	return button


static func create_icon_button(icon_kind: String, label_text: String, variant := "dark_brass", font: Font = null, font_size: int = 18, icon_tone: Color = BRASS) -> Button:
	var btn := create_tactile_button("", variant, font, font_size)
	btn.custom_minimum_size.y = 48.0
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	btn.add_child(pad)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	pad.add_child(row)
	var ic := create_micro_icon(icon_kind, 20.0, icon_tone)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	if not label_text.is_empty():
		var col := IVORY if variant in ["dark_brass", "medallion", "primary", "accent"] else INK
		var lbl := create_label(label_text, font_size, col, font)
		lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lbl)
		var est_w := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if font != null else float(label_text.length() * font_size)
		btn.custom_minimum_size.x = maxf(btn.custom_minimum_size.x, est_w + 62.0)
	else:
		btn.custom_minimum_size = Vector2(48.0, 48.0)
	return btn


static func create_micro_icon(kind: String, px: float = 22.0, tone: Color = MUTED) -> MicroIcon:
	var icon := MicroIcon.new()
	icon.setup(kind, px, tone)
	return icon


static func create_badge(text: String, tone: Color = BLUE, font: Font = null, font_size: int = 18) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := style(tone, 11, 4, 0, 1, tone.lightened(0.18))
	box.set_corner_radius_all(8)
	badge.add_theme_stylebox_override("panel", box)
	var label := create_label(text, font_size, IVORY, font)
	badge.add_child(label)
	return badge


static func create_chip(text: String, font: Font = null, font_size: int = 21) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := style(PAPER_DEEP, 12, 6, 1, 1, Color("#9a7952"))
	box.set_corner_radius_all(7)
	chip.add_theme_stylebox_override("panel", box)
	bind_paper(chip, paper_material(Vector2(160, 40), false))
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


static func create_meter(fill: Color, track: Color = Color("#3a2b20"), height: float = 10.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	var background := StyleBoxFlat.new()
	background.bg_color = track
	background.border_color = Color("#70553b88")
	background.set_border_width_all(1)
	background.set_corner_radius_all(5)
	var foreground := StyleBoxFlat.new()
	foreground.bg_color = fill
	foreground.border_color = fill.lightened(0.28)
	foreground.border_width_top = 1
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
	bar.custom_minimum_size.x = 8.0
	var track := style(Color("#dfd0b6"), 0, 0, 0, 0)
	track.set_corner_radius_all(4)
	var grabber := style(Color("#b6966b"), 0, 0, 0, 0)
	grabber.set_corner_radius_all(4)
	var active := style(WAX_GOLD, 0, 0, 0, 0)
	active.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_pressed", active)
	bar.add_theme_stylebox_override("grabber_highlight", active)


static func create_gold_divider(width: float = 0.0, with_star: bool = false, height: float = 14.0) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(width, height)
	if width <= 0.0:
		holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.50, 0.82, 1.0])
	gradient.colors = PackedColorArray([
		Color("#b88a4b00"), Color("#c9995a55"), Color("#d69f4fe8"), Color("#c9995a55"), Color("#b88a4b00")
	])
	var rule := GradientTexture1D.new()
	rule.gradient = gradient
	rule.width = 256
	var line := TextureRect.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.texture = rule
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	holder.add_child(line)
	line.anchor_left = 0.0
	line.anchor_right = 1.0
	line.anchor_top = 0.5
	line.anchor_bottom = 0.5
	line.offset_top = -1.0
	line.offset_bottom = 1.0
	if with_star:
		var star := create_micro_icon("star", 13.0, BRASS)
		holder.add_child(star)
		star.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		star.offset_left = -6.5
		star.offset_right = 6.5
		star.offset_top = -6.5
		star.offset_bottom = 6.5
	return holder


static func create_status_badge(text: String, positive: bool, font: Font = null, font_size: int = 16) -> PanelContainer:
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glass := MODIFIER_WARM_GLASS if positive else MODIFIER_COLD_GLASS
	var rim := MODIFIER_WARM_RIM if positive else MODIFIER_COLD_RIM
	var box := style(glass, 11, 4, 2, 1, Color(rim, 0.90))
	box.set_corner_radius_all(8)
	box.shadow_color = Color("#1a110b70")
	box.shadow_offset = Vector2(0.0, 2.0)
	badge.add_theme_stylebox_override("panel", box)
	var frost := ShaderMaterial.new()
	frost.shader = MODIFIER_FROST
	frost.set_shader_parameter("sheen_tone", rim)
	bind_paper(badge, frost)
	var label := create_label(text, font_size, MODIFIER_WARM_VALUE if positive else MODIFIER_COLD_VALUE, font)
	badge.add_child(label)
	return badge


static func create_gold_tab_button(text: String, font: Font, font_size: int = 23) -> Button:
	var button := Button.new()
	button.text = text
	button.toggle_mode = true
	button.custom_minimum_size.y = 50.0
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", font_size)
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 14
	empty.content_margin_right = 14
	empty.content_margin_top = 6
	empty.content_margin_bottom = 10
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color("#c88a3b18")
	hover_box.set_corner_radius_all(6)
	hover_box.content_margin_left = 14
	hover_box.content_margin_right = 14
	hover_box.content_margin_top = 6
	hover_box.content_margin_bottom = 10
	var active_box := StyleBoxFlat.new()
	active_box.bg_color = Color("#c88a3b20")
	active_box.set_corner_radius_all(6)
	active_box.content_margin_left = 14
	active_box.content_margin_right = 14
	active_box.content_margin_top = 6
	active_box.content_margin_bottom = 10
	var focus_box := StyleBoxFlat.new()
	focus_box.draw_center = false
	focus_box.set_border_width_all(2)
	focus_box.set_corner_radius_all(6)
	focus_box.border_color = Color("#c88a3b88")
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", hover_box)
	button.add_theme_stylebox_override("pressed", active_box)
	button.add_theme_stylebox_override("hover_pressed", active_box)
	button.add_theme_stylebox_override("focus", focus_box)
	button.add_theme_color_override("font_color", MUTED)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_focus_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)
	var underline := create_gold_divider(0.0, true, 10.0)
	button.add_child(underline)
	underline.anchor_left = 0.05
	underline.anchor_right = 0.95
	underline.anchor_top = 1.0
	underline.anchor_bottom = 1.0
	underline.offset_top = -9.0
	underline.offset_bottom = 1.0
	underline.modulate.a = 0.0
	button.set_meta(&"gold_underline", underline)
	Motion.attach_button_feel(button, 1.02, 0.97, false)
	AudioManager.bind_ui(button)
	return button
