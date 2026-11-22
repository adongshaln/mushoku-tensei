extends SubViewportContainer

const D20Stage := preload("res://ui/d20_3d_stage.gd")

static var _scene_cache: Dictionary[String, PackedScene] = {}

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _tilt_holder: Node3D
var _current_path := ""
var _interactive := true
var _dragging := false
var _last_mouse := Vector2.ZERO
var _yaw := -0.24
var _pitch := 0.08
var _yaw_velocity := 0.0
var _spin_speed := 0.52
var _idle_resume := 0.0
var _clock := 0.0
var _base_camera_size := 1.34
var _flip_tween: Tween


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP if _interactive else Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.world_3d = World3D.new()
	add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#F5E8D5")
	env.ambient_light_energy = 0.48
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.sky = D20Stage.reflection_sky()
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = _base_camera_size
	_camera.position = Vector3(0.0, 0.0, 4.5)
	_viewport.add_child(_camera)

	_add_light(Color("#FFE7C4"), Vector3(-34.0, -28.0, 0.0), 1.18, 0.42)
	_add_light(Color("#A8D2FA"), Vector3(14.0, 148.0, 0.0), 0.80, 0.36)
	_add_light(Color("#FFD59A"), Vector3(38.0, 18.0, 0.0), 0.42, 0.24)

	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_tilt_holder = Node3D.new()
	_pivot.add_child(_tilt_holder)


func configure(interactive: bool = true, spin_speed: float = 0.52, camera_size: float = 1.34) -> void:
	_interactive = interactive
	_spin_speed = spin_speed
	_base_camera_size = camera_size
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	if _camera != null:
		_camera.size = camera_size


func set_model(glb_path: String, tilt_z_deg: float = 0.0, camera_size: float = -1.0) -> bool:
	if _pivot == null:
		return false
	if camera_size > 0.0:
		_base_camera_size = camera_size
		_camera.size = camera_size
	if glb_path == _current_path and _tilt_holder.get_child_count() > 0:
		_tilt_holder.rotation_degrees = Vector3(0.0, 0.0, tilt_z_deg)
		return true
	_current_path = glb_path
	for child: Node in _tilt_holder.get_children():
		_tilt_holder.remove_child(child)
		child.queue_free()
	if glb_path.is_empty():
		return false
	var packed := _load_cached(glb_path)
	if packed == null:
		return false
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return false
	var wrapper := Node3D.new()
	wrapper.add_child(inst)
	var bounds := _compute_aabb(inst)
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if extent > 0.0001:
		var scale_factor := 1.0 / extent
		inst.scale = Vector3.ONE * scale_factor
		inst.position = -bounds.get_center() * scale_factor
	_tilt_holder.add_child(wrapper)
	_tilt_holder.rotation_degrees = Vector3(0.0, 0.0, tilt_z_deg)
	_yaw = -0.24
	_pitch = 0.08
	_yaw_velocity = 0.0
	_idle_resume = 0.0
	_apply_pose()
	return true


func flip_side() -> void:
	if _flip_tween != null:
		_flip_tween.kill()
	_idle_resume = 2.6
	_yaw_velocity = 0.0
	var target := _yaw + PI
	_flip_tween = create_tween()
	_flip_tween.tween_property(self, "_yaw", target, 0.48).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _gui_input(event: InputEvent) -> void:
	if not _interactive:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mb.double_click:
					flip_side()
				else:
					_dragging = true
					_last_mouse = mb.position
					_yaw_velocity = 0.0
					if _flip_tween != null:
						_flip_tween.kill()
			else:
				_dragging = false
				_idle_resume = 2.2
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var delta_pos := mm.position - _last_mouse
		_last_mouse = mm.position
		_yaw += delta_pos.x * 0.015
		_pitch = clampf(_pitch + delta_pos.y * 0.012, -0.95, 0.95)
		_yaw_velocity = delta_pos.x * 0.14
		_apply_pose()
		accept_event()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _pivot == null:
		return
	_clock += delta
	if not _dragging:
		if absf(_yaw_velocity) > 0.02:
			_yaw += _yaw_velocity * delta
			_yaw_velocity *= exp(-delta * 4.5)
		elif _idle_resume > 0.0:
			_idle_resume = maxf(0.0, _idle_resume - delta)
		else:
			_yaw += _spin_speed * delta
			_pitch = lerpf(_pitch, 0.08, 1.0 - exp(-delta * 2.5))
	_apply_pose()


func _apply_pose() -> void:
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_pivot.position.y = sin(_clock * 2.0) * 0.018


func _add_light(tint: Color, angle: Vector3, energy: float, specular: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angle
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = specular
	_viewport.add_child(light)


static func _load_cached(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	if not ResourceLoader.exists(path, "PackedScene"):
		return null
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed != null:
		_scene_cache[path] = packed
	return packed


static func _compute_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var has_box := false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		var box := mi.transform * mi.get_aabb()
		if not has_box:
			result = box
			has_box = true
		else:
			result = result.merge(box)
	return result
