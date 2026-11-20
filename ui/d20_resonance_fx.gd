extends Control

const Kit := preload("res://ui/ui_theme_kit.gd")


class Flight extends RefCounted:
	var start: Vector2
	var bend: Vector2
	var end: Vector2
	var color: Color
	var progress: float

	func point(weight: float) -> Vector2:
		return start.lerp(bend, weight).lerp(bend.lerp(end, weight), weight)


class Burst extends RefCounted:
	var center: Vector2
	var positive: bool
	var clutch: bool
	var critical: bool
	var elapsed := 0.0
	var duration: float


var _flights: Array[Flight] = []
var _bursts: Array[Burst] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)


func follow(flight: Flight) -> void:
	_flights.append(flight)
	queue_redraw()


func end_flight(flight: Flight) -> void:
	_flights.erase(flight)
	queue_redraw()


func impact(center: Vector2, positive: bool, clutch: bool = false, critical: bool = false) -> void:
	var burst := Burst.new()
	burst.center = center
	burst.positive = positive
	burst.clutch = clutch
	burst.critical = critical
	burst.duration = 0.61 if critical else (0.44 if clutch else 0.31)
	_bursts.append(burst)
	set_process(true)
	queue_redraw()


func clear() -> void:
	_flights.clear()
	_bursts.clear()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	for index: int in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[index]
		burst.elapsed += delta
		if burst.elapsed >= burst.duration:
			_bursts.remove_at(index)
	if _bursts.is_empty():
		set_process(false)
	queue_redraw()


func _draw() -> void:
	for flight: Flight in _flights:
		_draw_trail(flight)
	for burst: Burst in _bursts:
		_draw_burst(burst)


func _draw_trail(flight: Flight) -> void:
	var head := flight.progress
	var tail := maxf(0.0, head - 0.27)
	var fade := 1.0 - smoothstep(0.80, 1.0, head) * 0.45
	for segment: int in 11:
		var weight := float(segment + 1) / 11.0
		var a := flight.point(lerpf(tail, head, float(segment) / 11.0))
		var b := flight.point(lerpf(tail, head, weight))
		draw_line(a, b, Color(flight.color, 0.15 * fade * weight), lerpf(2.0, 13.0, weight), true)
		draw_line(a, b, Color(flight.color, 0.79 * fade * weight), lerpf(0.8, 3.4, weight), true)
	var light := smoothstep(0.47, 0.89, head) * fade
	var center := flight.point(head)
	draw_circle(center, 11.0, Color(flight.color, light * 0.13), true, -1.0, true)
	draw_circle(center, 5.0, Color(flight.color, light * 0.31), true, -1.0, true)
	draw_circle(center, 2.6, Color(flight.color.lightened(0.3), light * 0.9), true, -1.0, true)


func _draw_burst(burst: Burst) -> void:
	var t := clampf(burst.elapsed / burst.duration, 0.0, 1.0)
	var ease := 1.0 - pow(1.0 - t, 2.8)
	var alpha := (1.0 - t) * (0.42 if burst.positive else 0.30)
	var color := Kit.MODIFIER_WARM_LIGHT if burst.positive else Kit.MODIFIER_COLD_LIGHT
	var reach := 173.0 if burst.critical else (128.0 if burst.clutch else 89.0)
	var radius := lerpf(23.0, reach, ease)
	draw_arc(burst.center, radius, 0, TAU, 64, Color(color, alpha * 0.25), 10.0, true)
	draw_arc(burst.center, radius, 0, TAU, 64, Color(color, alpha), 2.0, true)
	if burst.clutch or burst.critical or not burst.positive:
		draw_arc(burst.center, radius * 0.82, 0, TAU, 64, Color(color, alpha * 0.45), 1.3, true)
	if not burst.positive:
		return
	var sparks := 8 if burst.clutch or burst.critical else 5
	for index: int in sparks:
		var angle := TAU * float(index) / sparks + 0.17
		var offset := Vector2.from_angle(angle) * radius * (0.73 + 0.07 * (index % 3))
		var length := (6.7 if burst.clutch else 4.5) * (1.0 - t * 0.75)
		var tip := Vector2.from_angle(angle) * length
		var side := tip.orthogonal() * 0.35
		var at := burst.center + offset
		draw_colored_polygon(PackedVector2Array([at + tip, at + side, at - tip, at - side]), Color(color, alpha * 1.65))
