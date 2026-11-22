extends CanvasLayer

const INK_SHADER := preload("res://shaders/ink_transition.gdshader")

var _context: Dictionary = {}
var _busy := false
var _shade: ColorRect
var _material: ShaderMaterial


func _ready() -> void:
	layer = 90
	_shade = ColorRect.new()
	_shade.color = Color.WHITE
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_material = ShaderMaterial.new()
	_material.shader = INK_SHADER
	_material.set_shader_parameter("progress", 0.0)
	_shade.material = _material
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
	await _wash(0.0, 1.0, 0.28)
	if before_swap.is_valid():
		before_swap.call()
	_context = context
	AudioManager.stop_voice()
	StoryletScheduler.dismiss_toast()
	var result := get_tree().change_scene_to_file(scene_path)
	if result == OK:
		await get_tree().scene_changed
	else:
		_context.clear()
	await _wash(1.0, 0.0, 0.30)
	_shade.hide()
	_busy = false


func _wash(from_p: float, to_p: float, duration: float) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_method(func(v: float) -> void:
		_material.set_shader_parameter("progress", v), from_p, to_p, duration)
	await tw.finished
