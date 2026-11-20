extends Control

var _bursts: Array[Dictionary] = []


func impact(at: Vector2, element: String, seconds: float) -> void:
	var colors := {
		"water": Color("#9cdaea"), "ice": Color("#bbf0ed"), "earth": Color("#e2bd82"),
		"parry": Color("#ffe1a0"), "physical": Color("#f8c6a2")
	}
	_bursts.append({
		"at": at, "age": 0.0, "duration": seconds,
		"color": colors.get(element, Color("#f8eed2")), "kind": element
	})
	queue_redraw()


func clear() -> void:
	_bursts.clear()
	queue_redraw()


func _process(delta: float) -> void:
	if _bursts.is_empty():
		return
	for index: int in range(_bursts.size() - 1, -1, -1):
		var burst := _bursts[index]
		burst["age"] = float(burst["age"]) + delta
		if float(burst["age"]) >= float(burst["duration"]):
			_bursts.remove_at(index)
	queue_redraw()


func _draw() -> void:
	for burst: Dictionary in _bursts:
		var phase := float(burst["age"]) / float(burst["duration"])
		var at: Vector2 = burst["at"]
		var color: Color = burst["color"]
		color.a = (1.0 - phase) * 0.9
		var ring_color := color
		ring_color.a *= 0.55
		draw_arc(at, 15.0 + phase * 160.0, 0, TAU, 46, ring_color, 3.0, true)
		for i: int in range(11):
			var unit := Vector2.from_angle(TAU * i / 11.0 + 0.13)
			var reach := (26.0 + 120.0 * phase) * (0.75 + 0.11 * (i % 3))
			var tip := at + unit * reach
			var base := tip - unit * (17.0 + (i % 4) * 4)
			var across := unit.orthogonal() * (4.5 if burst["kind"] == "ice" else 2.5)
			draw_colored_polygon([tip, base - across, base + across], color)
		if burst["kind"] in ["physical", "parry"]:
			var offset := Vector2(69, -44) * (0.8 + phase)
			draw_line(at - offset, at + offset, color, 6.0 * (1.0 - phase), true)
