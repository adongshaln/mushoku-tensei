extends Control

const Motion := preload("res://ui/ui_motion.gd")
const GOLD := Color("#DBB071")
const RADIUS := 226.0

var _halo: GradientTexture2D
var _angle := 0.0
var _glow := 0.0
var _light := GOLD


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset_ratio = Vector2(0.5, 0.5)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.46, 1.0])
	gradient.colors = PackedColorArray([Color("#A872423D"), Color("#9B673424"), Color("#8E543100")])
	_halo = GradientTexture2D.new()
	_halo.gradient = gradient
	_halo.fill = GradientTexture2D.FILL_RADIAL
	_halo.fill_from = Vector2(0.5, 0.5)
	_halo.fill_to = Vector2(1.0, 0.5)
	_halo.width = 128
	_halo.height = 128


func pulse(strength: float, warm: bool = true) -> void:
	_light = GOLD if warm else Color("#A4C9DE")
	_glow = maxf(_glow, strength)
	Motion.spring(self, ^"scale", Vector2.ONE * (1.0 + 0.056 * strength), Vector2.ONE, 0.40, 6.2, 8.5)


func reset() -> void:
	Motion.cancel(self, ^"scale")
	scale = Vector2.ONE
	_glow = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_angle = fposmod(_angle + delta * 0.043, TAU)
	_glow = move_toward(_glow, 0.0, delta * 2.1)
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var halo_size := Vector2.ONE * 605.0
	draw_texture_rect(_halo, Rect2(center - halo_size * 0.5, halo_size), false)
	draw_arc(center, RADIUS, 0.0, TAU, 128, Color(GOLD, 0.32), 1.45, true)
	draw_arc(center, RADIUS - 17.0, 0.0, TAU, 128, Color(GOLD, 0.23), 1.0, true)
	for index: int in 48:
		var angle := _angle + TAU * float(index) / 48.0
		var radial := Vector2.from_angle(angle)
		var long_mark := index % 4 == 0
		var tick_start := RADIUS - (13.0 if long_mark else 7.5)
		draw_line(center + radial * tick_start, center + radial * (RADIUS - 3.0), Color(GOLD, 0.33 if long_mark else 0.21), 1.0, true)
		if index % 12 == 0:
			var at := center + radial * (RADIUS + 8.0)
			var tip := radial * 6.0
			var side := radial.orthogonal() * 2.9
			draw_colored_polygon(PackedVector2Array([at + tip, at + side, at - tip, at - side]), Color(GOLD, 0.55))
	if _glow > 0.0:
		var sweep := _angle + (1.0 - _glow) * 2.8
		for index: int in 10:
			var angle := sweep + float(index) * 0.13
			var opacity := _glow * float(index + 1) / 10.0
			draw_arc(center, RADIUS, angle, angle + 0.14, 6, Color(_light, opacity * 0.58), 2.0, true)
