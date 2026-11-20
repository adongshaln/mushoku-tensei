extends CanvasLayer

var _context: Dictionary = {}
var _busy := false
var _shade: ColorRect


func _ready() -> void:
	layer = 90
	_shade = ColorRect.new()
	_shade.color = Color("#29231e")
	_shade.modulate.a = 0.0
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()


func is_busy() -> bool:
	return _busy


func take_context() -> Dictionary:
	var context := _context
	_context = {}
	return context


func change_to(scene_path: String, context: Dictionary = {}, before_swap: Callable = Callable()) -> bool:
	if _busy or not ResourceLoader.exists(scene_path, "PackedScene"):
		return false
	_busy = true
	_swap_scene.call_deferred(scene_path, context.duplicate(true), before_swap)
	return true


func _swap_scene(scene_path: String, context: Dictionary, before_swap: Callable) -> void:
	_shade.show()
	await _fade(1.0)
	if before_swap.is_valid():
		before_swap.call()
	_context = context
	AudioManager.stop_voice()
	var result := get_tree().change_scene_to_file(scene_path)
	if result == OK:
		await get_tree().scene_changed
	else:
		_context.clear()
	await _fade(0.0)
	_shade.hide()
	_busy = false


func _fade(opacity: float) -> void:
	var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	fade.tween_property(_shade, "modulate:a", opacity, 0.24)
	await fade.finished
