extends RefCounted

const META_TWEENS := &"_uimotion_tweens"


static func attach_button_feel(button: BaseButton, hover_scale := 1.03, press_scale := 0.95, pivot_bottom := false) -> void:
	button.pivot_offset_ratio = Vector2(0.5, 1.0 if pivot_bottom else 0.5)
	button.mouse_entered.connect(func() -> void:
		if not button.disabled:
			_scale_to(button, hover_scale, 0.2, Tween.TRANS_BACK, Tween.EASE_OUT))
	button.mouse_exited.connect(func() -> void:
		_scale_to(button, 1.0, 0.24, Tween.TRANS_QUINT, Tween.EASE_OUT))
	button.button_down.connect(func() -> void:
		if not button.disabled:
			_scale_to(button, press_scale, 0.09, Tween.TRANS_QUINT, Tween.EASE_OUT))
	button.button_up.connect(func() -> void:
		if button.disabled:
			return
		var target := hover_scale if button.is_hovered() else 1.0
		spring(button, "scale", button.scale, Vector2.ONE * target, 0.38, 8.5, 10.0))


static func slide_drawer_in(node: Control, from_x: float, duration := 0.44) -> Tween:
	node.position.x = from_x
	return spring(node, "position:x", from_x, 0.0, duration, 9.0, 7.0)


static func slide_drawer_out(node: Control, to_x: float, duration := 0.26) -> Tween:
	var tween := _fresh(node, ^"position:x")
	tween.tween_property(node, "position:x", to_x, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	return tween


static func pop_badge(node: Control, duration := 0.44) -> Tween:
	_center_pivot(node)
	node.scale = Vector2.ONE * 0.55
	return spring(node, "scale", Vector2.ONE * 0.55, Vector2.ONE, duration, 8.0, 9.0)


static func animate_number_tick(label: Label, from_val: int, to_val: int, duration := 0.3) -> Tween:
	_center_pivot(label)
	var tween := _fresh(label, ^"scale")
	var apply := func(weight: float) -> void:
		var eased := 1.0 - pow(1.0 - weight, 3.0)
		label.text = str(roundi(lerpf(float(from_val), float(to_val), eased)))
	tween.tween_method(apply, 0.0, 1.0, duration)
	tween.parallel().tween_property(label, "scale", Vector2.ONE * 1.22, duration * 0.45).from(Vector2.ONE).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "scale", Vector2.ONE, duration * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


static func stamp_impact(node: Control, duration := 0.5) -> Tween:
	_center_pivot(node)
	var tween := _fresh(node, ^"scale")
	node.scale = Vector2.ONE * 1.85
	node.modulate.a = 0.0
	tween.tween_property(node, "modulate:a", 1.0, 0.07)
	tween.parallel().tween_property(node, "scale", Vector2.ONE * 1.02, 0.15).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.tween_property(node, "scale", Vector2.ONE * 0.965, 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "scale", Vector2.ONE, maxf(0.12, duration - 0.29)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween


static func fade_in(node: CanvasItem, duration := 0.25) -> Tween:
	node.modulate.a = 0.0
	return fade_alpha(node, 1.0, duration)


static func fade_alpha(node: CanvasItem, opacity: float, duration: float) -> Tween:
	var tween := _fresh(node, ^"modulate:a")
	tween.tween_property(node, "modulate:a", opacity, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	return tween


static func spring(node: Node, property: NodePath, from: Variant, to: Variant, duration := 0.42, damping := 9.0, freq := 7.0) -> Tween:
	var tween := _fresh(node, property)
	var ease := func(weight: float) -> float:
		if weight >= 1.0:
			return 1.0
		return 1.0 - exp(-damping * weight) * cos(freq * weight)
	tween.tween_property(node, property, to, duration).from(from).set_custom_interpolator(ease)
	return tween


static func cancel(node: Node, property: NodePath) -> void:
	if not node.has_meta(META_TWEENS):
		return
	var tracks: Dictionary[NodePath, Tween] = node.get_meta(META_TWEENS)
	var tween: Tween = tracks.get(property)
	if tween != null and tween.is_valid():
		tween.kill()
	tracks.erase(property)


static func _scale_to(node: Control, target: float, duration: float, trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	var tween := _fresh(node, ^"scale")
	tween.tween_property(node, "scale", Vector2.ONE * target, duration).set_trans(trans).set_ease(ease_type)


static func _fresh(node: Node, property: NodePath) -> Tween:
	cancel(node, property)
	if not node.has_meta(META_TWEENS):
		var tracks: Dictionary[NodePath, Tween] = {}
		node.set_meta(META_TWEENS, tracks)
	var tracks: Dictionary[NodePath, Tween] = node.get_meta(META_TWEENS)
	var tween := node.create_tween()
	tracks[property] = tween
	return tween


static func _center_pivot(node: Control) -> void:
	node.pivot_offset = Vector2.ZERO
	node.pivot_offset_ratio = Vector2(0.5, 0.5)
