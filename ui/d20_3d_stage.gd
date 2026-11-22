extends SubViewportContainer

signal settled
signal landed(strength: float)

const SKIN_PATH := "res://assets/3d/d20_skin.glb"
const FACES_PATH := "res://assets/3d/d20_faces.json"
const POLYHEDRAL_TABLES_PATH := "res://assets/3d/dice/dice_face_tables.json"
const DIE_SKINS: Dictionary[String, String] = {
	"d4": "res://assets/3d/dice/d4_skin.glb",
	"d6": "res://assets/3d/dice/d6_skin.glb",
	"d8": "res://assets/3d/dice/d8_skin.glb",
	"d10": "res://assets/3d/dice/d10_skin.glb",
	"d12": "res://assets/3d/dice/d12_skin.glb",
	"d20": "res://assets/3d/d20_skin.glb"
}
const DIE_SIDES: Dictionary[String, int] = {
	"d4": 4, "d6": 6, "d8": 8, "d10": 10, "d12": 12, "d20": 20
}
const DIE_SCALES: Dictionary[String, float] = {
	"d4": 1.15, "d6": 1.06, "d8": 0.90, "d10": 0.92, "d12": 0.96, "d20": 1.0
}
const DIE_FACE_DEPTHS: Dictionary[String, float] = {
	"d4": 0.34, "d6": 0.616, "d8": 0.577, "d10": 0.59, "d12": 0.75, "d20": 0.779
}
const KEY_ENERGY := 1.12
const KEY_HOVER_ENERGY := 1.22
const CERAMIC_FACE_Z := 0.779
const PHI := 1.61803398875
const RAW_VERTICES: Array[Vector3] = [
	Vector3(-1, PHI, 0), Vector3(1, PHI, 0), Vector3(-1, -PHI, 0), Vector3(1, -PHI, 0),
	Vector3(0, -1, PHI), Vector3(0, 1, PHI), Vector3(0, -1, -PHI), Vector3(0, 1, -PHI),
	Vector3(PHI, 0, -1), Vector3(PHI, 0, 1), Vector3(-PHI, 0, -1), Vector3(-PHI, 0, 1)
]
const FACES: Array[Vector3i] = [
	Vector3i(0, 11, 5), Vector3i(0, 5, 1), Vector3i(0, 1, 7), Vector3i(0, 7, 10), Vector3i(0, 10, 11),
	Vector3i(1, 5, 9), Vector3i(5, 11, 4), Vector3i(11, 10, 2), Vector3i(10, 7, 6), Vector3i(7, 1, 8),
	Vector3i(3, 9, 4), Vector3i(3, 4, 2), Vector3i(3, 2, 6), Vector3i(3, 6, 8), Vector3i(3, 8, 9),
	Vector3i(4, 9, 5), Vector3i(2, 4, 11), Vector3i(6, 2, 10), Vector3i(8, 6, 7), Vector3i(9, 8, 1)
]
const BOUNCE_MARKS: Array[float] = [0.60, 0.80, 0.93]
const BOUNCE_PITCH: Array[float] = [1.0, 1.16, 1.32]

enum Phase { IDLE, ROLLING, SETTLING, READY }

class Die extends Node3D:
	var phase: Phase = Phase.IDLE
	var target: Quaternion
	var spin: Vector3
	var roll_progress: float
	var motion: Tween

var _viewport: SubViewport
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _warm_pulse: DirectionalLight3D
var _cold_pulse: DirectionalLight3D
var _holder: Node3D
var _dice: Array[Die] = []
var _focus_die: Die
var _impact_die: Die
var _impact_origin: Transform3D
var _impact_tween: Tween
var _face_normals: Array[Vector3] = []
var _face_ups: Array[Vector3] = []
var _body_mesh: ArrayMesh
var _wire_mesh: ArrayMesh
var _skin: PackedScene
var _die_type := "d20"
var _phase := Phase.IDLE
var _idle_time := 0.0
var _hover_target := Vector2.ZERO
var _hover_current := Vector2.ZERO
var _settled_emitted := false
var _time_scale := 1.0
static var _studio_sky: Sky
static var _polyhedral_tables: Dictionary = {}
static var _skin_cache: Dictionary[String, PackedScene] = {}
static var _normal_cache: Dictionary[String, Array] = {}
static var _up_cache: Dictionary[String, Array] = {}


static func sides_for(die_type: String) -> int:
	return int(DIE_SIDES.get(die_type.to_lower(), 20))


static func reflection_sky() -> Sky:
	return _reflection_sky()


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.world_3d = World3D.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#F6EBDC")
	environment.ambient_light_energy = 0.43
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.sky = _reflection_sky()
	add_child(_viewport)
	var studio := WorldEnvironment.new()
	studio.environment = environment
	_viewport.add_child(studio)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 3.20
	_camera.position = Vector3(0, 0, 6.2)
	_viewport.add_child(_camera)
	_key_light = _studio_light(Color("#FFE7C3"), Vector3(-36, -27, 0), KEY_ENERGY, 0.34)
	_studio_light(Color("#A4CFFA"), Vector3(9, 151, 0), 0.84, 0.38)
	_studio_light(Color("#FFD3A2"), Vector3(42, 9, 0), 0.25, 0.16)
	_warm_pulse = _studio_light(Color("#FFCB86"), Vector3(-26, 51, 0), 0.0, 0.44)
	_cold_pulse = _studio_light(Color("#AED3F1"), Vector3(14, -59, 0), 0.0, 0.44)
	_holder = Node3D.new()
	_viewport.add_child(_holder)


func _studio_light(tint: Color, angle: Vector3, energy: float, specular: float) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = angle
	light.light_color = tint
	light.light_energy = energy
	light.light_specular = specular
	_viewport.add_child(light)
	return light


func get_face_projection() -> Transform2D:
	if _focus_die == null:
		return Transform2D(0.0, size * 0.5)
	var die := _focus_die
	var basis := die.target.inverse()
	var depth := float(DIE_FACE_DEPTHS.get(_die_type, CERAMIC_FACE_Z)) if _skin != null else 0.812
	var center := die.to_global(basis * Vector3(0, 0, depth))
	var ratio := size / Vector2(_viewport.size)
	var projected := _camera.unproject_position(center)
	var right := _camera.unproject_position(die.to_global(basis * Vector3(1, 0, depth))) - projected
	var down := _camera.unproject_position(die.to_global(basis * Vector3(0, -1, depth))) - projected
	return Transform2D(right * ratio, down * ratio, projected * ratio)


func get_stage_texture() -> ViewportTexture:
	return _viewport.get_texture()


func set_time_scale(scale_val: float) -> void:
	_time_scale = clampf(scale_val, 0.5, 4.0)


func get_time_scale() -> float:
	return _time_scale


func play_modifier_impact(is_positive: bool, impact_dir: Vector2, is_clutch: bool = false) -> void:
	if _phase != Phase.READY or _focus_die == null:
		return
	clear_modifier_impact()
	_impact_die = _focus_die
	_impact_origin = _impact_die.transform
	var die := _impact_die
	var position_before := die.position
	var scale_before := die.scale
	var face := die.target
	var direction := impact_dir.normalized()
	var axis := Vector3(-direction.y, -direction.x, 0).normalized() if not direction.is_zero_approx() else Vector3.RIGHT
	var pulse := _warm_pulse if is_positive else _cold_pulse
	var energy := (0.57 if is_clutch else 0.39) if is_positive else (0.40 if is_clutch else 0.27)
	var tilt := deg_to_rad(5.0 if is_clutch else 4.0) if is_positive else deg_to_rad(1.8)
	var zoom := 0.05 if is_positive else -0.04
	var displacement := Vector3(direction.x * 0.028, 0.026, 0.02) if is_positive else Vector3(0, -0.058, -0.13)
	var frequency := 9.0 if is_positive else 17.0
	var kick := func(progress: float) -> void:
		var bounce := exp(-5.8 * progress) * cos(frequency * progress)
		die.quaternion = Quaternion(axis, tilt * bounce) * face
		die.position = position_before + displacement * bounce
		die.scale = scale_before * (1.0 + zoom * bounce)
		pulse.light_energy = energy * pow(1.0 - progress, 2.4)
	kick.call(0.0)
	_impact_tween = create_tween()
	_impact_tween.tween_method(kick, 0.0, 1.0, (0.33 if is_clutch else 0.27) / _time_scale)
	_impact_tween.tween_callback(_restore_impact)


func clear_modifier_impact() -> void:
	if _impact_tween != null:
		_impact_tween.kill()
		_impact_tween = null
	_restore_impact()


func _restore_impact() -> void:
	if is_instance_valid(_impact_die):
		_impact_die.transform = _impact_origin
	_impact_die = null
	_warm_pulse.light_energy = 0.0
	_cold_pulse.light_energy = 0.0


static func _reflection_sky() -> Sky:
	if _studio_sky != null:
		return _studio_sky
	const WIDTH := 256
	const HEIGHT := 128
	var panorama := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGBAH)
	var softbox := Vector3(-0.52, 0.66, 0.54).normalized()
	var strip := Vector3(0.68, 0.49, 0.55).normalized()
	var rim := Vector3(0.53, 0.18, -0.83).normalized()
	var bounce := Vector3(-0.17, -0.87, 0.46).normalized()
	for y: int in HEIGHT:
		var latitude := PI * (y + 0.5) / HEIGHT
		var radius := sin(latitude)
		var elevation := cos(latitude)
		for x: int in WIDTH:
			var azimuth := TAU * (x + 0.5) / WIDTH
			var ray := Vector3(sin(azimuth) * radius, elevation, cos(azimuth) * radius)
			var light := Color(0.091, 0.077, 0.064)
			light += Color(3.8, 2.72, 1.62) * pow(maxf(0.0, ray.dot(softbox)), 10.0)
			light += Color(7.6, 5.5, 3.15) * pow(maxf(0.0, ray.dot(strip)), 65.0)
			light += Color(1.40, 2.64, 4.85) * pow(maxf(0.0, ray.dot(rim)), 24.0)
			light += Color(0.83, 0.48, 0.26) * pow(maxf(0.0, ray.dot(bounce)), 6.0)
			panorama.set_pixel(x, y, Color(light.r, light.g, light.b, 1.0))
	var material := PanoramaSkyMaterial.new()
	material.panorama = ImageTexture.create_from_image(panorama)
	_studio_sky = Sky.new()
	_studio_sky.radiance_size = Sky.RADIANCE_SIZE_256
	_studio_sky.process_mode = Sky.PROCESS_MODE_QUALITY
	_studio_sky.sky_material = material
	return _studio_sky


func _load_skin(die_type: String = "d20") -> bool:
	var kind := die_type.to_lower() if DIE_SKINS.has(die_type.to_lower()) else "d20"
	if _skin_cache.has(kind) and _normal_cache.has(kind) and _up_cache.has(kind):
		_skin = _skin_cache[kind]
		_face_normals = _to_vec3_array(_normal_cache[kind])
		_face_ups = _to_vec3_array(_up_cache[kind])
		return true
	var skin_path := DIE_SKINS[kind]
	if not ResourceLoader.exists(skin_path, "PackedScene"):
		return false
	var sides := DIE_SIDES[kind]
	var normals: Array[Vector3] = []
	var ups: Array[Vector3] = []
	if kind == "d20":
		if not FileAccess.file_exists(FACES_PATH):
			return false
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FACES_PATH))
		if not parsed is Dictionary or parsed.size() != FACES.size():
			return false
		for face_index: int in FACES.size():
			var face: Variant = parsed.get(str(face_index + 1))
			if not face is Dictionary:
				return false
			var normal := _read_unit_vector(face.get("normal"))
			var up := _read_unit_vector(face.get("up"))
			if normal == Vector3.ZERO or up == Vector3.ZERO or absf(normal.dot(up)) > 0.0001:
				return false
			normals.append(normal)
			ups.append(up)
	else:
		var table := _load_polyhedral_table(kind)
		if table.is_empty():
			return false
		var is_d4_apex := str(table.get("reading_mode", "")) == "apex_top" and table.get("apex_views") is Dictionary
		for face_index: int in sides:
			var key := str(face_index + 1)
			var face_entry: Variant
			if is_d4_apex:
				var views: Variant = (table["apex_views"] as Dictionary).get(key)
				if not views is Array or (views as Array).is_empty():
					return false
				face_entry = (views as Array)[0]
			else:
				face_entry = table.get(key)
			if not face_entry is Dictionary:
				return false
			var normal := _read_unit_vector((face_entry as Dictionary).get("normal"))
			var up := _read_unit_vector((face_entry as Dictionary).get("up"))
			if normal == Vector3.ZERO or up == Vector3.ZERO or absf(normal.dot(up)) > 0.001:
				return false
			normals.append(normal)
			ups.append(up)
	var loaded := ResourceLoader.load(skin_path, "PackedScene") as PackedScene
	if loaded == null:
		return false
	_skin = loaded
	_face_normals = normals
	_face_ups = ups
	_skin_cache[kind] = loaded
	_normal_cache[kind] = normals.duplicate()
	_up_cache[kind] = ups.duplicate()
	return true


static func _load_polyhedral_table(kind: String) -> Dictionary:
	if _polyhedral_tables.is_empty() and FileAccess.file_exists(POLYHEDRAL_TABLES_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POLYHEDRAL_TABLES_PATH))
		if parsed is Dictionary:
			_polyhedral_tables = parsed
	var entry: Variant = _polyhedral_tables.get(kind)
	return entry if entry is Dictionary else {}


static func _to_vec3_array(raw: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for item: Variant in raw:
		if item is Vector3:
			result.append(item)
	return result


static func _read_unit_vector(values: Variant) -> Vector3:
	if not values is Array or values.size() != 3:
		return Vector3.ZERO
	for value: Variant in values:
		if not value is float and not value is int:
			return Vector3.ZERO
	var vector := Vector3(float(values[0]), float(values[1]), float(values[2]))
	if not vector.is_finite() or absf(vector.length_squared() - 1.0) > 0.001:
		return Vector3.ZERO
	return vector.normalized()


func _compute_faces(vertices: Array[Vector3]) -> void:
	for face: Vector3i in FACES:
		var a := vertices[face.x]
		var b := vertices[face.y]
		var c := vertices[face.z]
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(a + b + c) < 0.0:
			normal = -normal
		_face_normals.append(normal)
		var x_axis := Vector3.UP.cross(normal).normalized()
		_face_ups.append(normal.cross(x_axis))


func setup(rolls: Array[int], die_type: String = "d20") -> void:
	clear_modifier_impact()
	var resolved := die_type.to_lower() if DIE_SKINS.has(die_type.to_lower()) else "d20"
	_die_type = resolved
	_skin = null
	_face_normals.clear()
	_face_ups.clear()
	if not _load_skin(resolved):
		_die_type = "d20"
		if not _load_skin("d20"):
			_build_meshes()
	for die: Die in _dice:
		if die.motion != null:
			die.motion.kill()
		_holder.remove_child(die)
		die.queue_free()
	_dice.clear()
	_focus_die = null
	_settled_emitted = false
	_phase = Phase.IDLE
	_idle_time = 0.0
	_hover_target = Vector2.ZERO
	_hover_current = Vector2.ZERO
	var sides := maxi(1, _face_normals.size())
	var base_scale := float(DIE_SCALES.get(_die_type, 1.0))
	var two := rolls.size() > 1
	for index: int in rolls.size():
		var die := _build_die()
		_holder.add_child(die)
		die.position = Vector3(0 if not two else (-1.02 if index == 0 else 1.02), 0, 0)
		die.scale = Vector3.ONE * base_scale * (0.92 if two else 1.0)
		die.target = _face_quat(clampi(rolls[index], 1, sides) - 1)
		_dice.append(die)
	if not _dice.is_empty():
		_focus_die = _dice[0]


func toss() -> void:
	if _phase != Phase.IDLE:
		return
	_phase = Phase.ROLLING
	for index: int in _dice.size():
		var die := _dice[index]
		die.phase = Phase.ROLLING
		die.spin = Vector3(
			randf_range(6.0, 11.0) * (1.0 if randf() > 0.5 else -1.0),
			randf_range(7.0, 12.0) * (1.0 if randf() > 0.5 else -1.0),
			randf_range(4.0, 9.0) * (1.0 if randf() > 0.5 else -1.0)) * _time_scale
		die.motion = die.create_tween()
		var height := func(weight: float) -> void:
			die.position.y = _toss_height(weight)
			for mark: int in BOUNCE_MARKS.size():
				if die.roll_progress < BOUNCE_MARKS[mark] and weight >= BOUNCE_MARKS[mark]:
					AudioManager.play_sfx("dice_bounce", BOUNCE_PITCH[mark])
					if index == 0:
						landed.emit(0.46 - float(mark) * 0.11)
			die.roll_progress = weight
		die.motion.tween_method(height, 0.0, 1.0, 1.02 / _time_scale).set_delay((index * 0.09) / _time_scale)
		die.motion.tween_callback(_settle_die.bind(die))


func skip() -> void:
	if _phase != Phase.ROLLING:
		return
	for die: Die in _dice:
		if die.motion != null:
			die.motion.kill()
		die.position.y = 0.0
		die.quaternion = die.target
		die.phase = Phase.READY
	_finish_settle()


func converge(winner: int) -> Tween:
	_focus_die = _dice[winner]
	var tween := create_tween()
	for index: int in _dice.size():
		var die := _dice[index]
		if index == winner:
			tween.parallel().tween_property(die, "position:x", 0.0, 0.42 / _time_scale).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
		else:
			tween.parallel().tween_property(die, "scale", Vector3.ONE * 0.001, 0.3 / _time_scale).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(die, "position:y", -0.25, 0.3 / _time_scale).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		for index: int in _dice.size():
			if index != winner:
				_dice[index].hide())
	return tween


func set_hover(active: bool, tilt: Vector2) -> void:
	_hover_target = tilt if active else Vector2.ZERO


func _process(delta: float) -> void:
	_hover_current = _hover_current.lerp(_hover_target, 1.0 - exp(-delta * 8.0))
	var light_energy := KEY_HOVER_ENERGY if _hover_target != Vector2.ZERO else KEY_ENERGY
	_key_light.light_energy = lerpf(_key_light.light_energy, light_energy, 1.0 - exp(-delta * 6.0))
	if _phase == Phase.IDLE:
		_idle_time += delta
		var tilt := Quaternion(Vector3.UP, _hover_current.x * 0.22) * Quaternion(Vector3.RIGHT, -_hover_current.y * 0.16)
		for index: int in _dice.size():
			var die := _dice[index]
			var spin := Quaternion(Vector3(0.32, 1.0, 0.18).normalized(), _idle_time * 0.6 + index * 1.7)
			die.quaternion = tilt * spin
			die.position.y = sin(_idle_time * 1.4 + index * 2.1) * 0.05
	elif _phase == Phase.ROLLING:
		for die: Die in _dice:
			if die.phase != Phase.ROLLING:
				continue
			die.rotate_x(die.spin.x * delta)
			die.rotate_y(die.spin.y * delta)
			die.rotate_z(die.spin.z * delta)
			die.spin *= exp(-2.0 * delta)


func _toss_height(weight: float) -> float:
	if weight < 0.33:
		var rise := weight / 0.33
		return 0.55 * (1.0 - pow(1.0 - rise, 2.0))
	if weight < 0.60:
		var fall := (weight - 0.33) / 0.27
		return 0.55 * (1.0 - fall * fall)
	if weight < 0.80:
		return 0.24 * sin((weight - 0.60) / 0.20 * PI)
	if weight < 0.93:
		return 0.09 * sin((weight - 0.80) / 0.13 * PI)
	return 0.0


func _settle_die(die: Die) -> void:
	die.phase = Phase.SETTLING
	die.position.y = 0.0
	die.motion = die.create_tween()
	die.motion.tween_property(die, "quaternion", die.target, 0.46 / _time_scale).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	die.motion.tween_callback(func() -> void:
		die.phase = Phase.READY
		_finish_settle())


func _finish_settle() -> void:
	if _settled_emitted:
		return
	for die: Die in _dice:
		if die.phase != Phase.READY:
			return
	_settled_emitted = true
	_phase = Phase.READY
	settled.emit()


func _face_quat(face_index: int) -> Quaternion:
	var normal := _face_normals[face_index]
	var up := _face_ups[face_index]
	var face_basis := Basis(up.cross(normal), up, normal).orthonormalized()
	# The orthographic stage looks down -Z, with every numbered face parallel to the camera.
	return face_basis.transposed().get_rotation_quaternion()


func _build_meshes() -> void:
	var vertices: Array[Vector3] = []
	for vertex: Vector3 in RAW_VERTICES:
		vertices.append(vertex.normalized())
	_compute_faces(vertices)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face_index: int in FACES.size():
		var face := FACES[face_index]
		var normal := _face_normals[face_index]
		surface.set_normal(normal)
		surface.add_vertex(vertices[face.x])
		surface.set_normal(normal)
		surface.add_vertex(vertices[face.z])
		surface.set_normal(normal)
		surface.add_vertex(vertices[face.y])
	var ceramic := StandardMaterial3D.new()
	ceramic.albedo_color = Color("#3e709c")
	ceramic.roughness = 0.4
	ceramic.metallic_specular = 0.3
	surface.set_material(ceramic)
	_body_mesh = surface.commit()

	var edges := SurfaceTool.new()
	edges.begin(Mesh.PRIMITIVE_LINES)
	var seen: Dictionary[Vector2i, bool] = {}
	for face: Vector3i in FACES:
		for edge: Vector2i in [Vector2i(face.x, face.y), Vector2i(face.y, face.z), Vector2i(face.z, face.x)]:
			var key := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
			if seen.has(key):
				continue
			seen[key] = true
			edges.add_vertex(vertices[edge.x] * 1.004)
			edges.add_vertex(vertices[edge.y] * 1.004)
	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color("#d9b36a")
	edges.set_material(gold)
	_wire_mesh = edges.commit()


func _build_die() -> Die:
	var root := Die.new()
	if _skin != null:
		root.add_child(_skin.instantiate())
		return root
	var body := MeshInstance3D.new()
	body.mesh = _body_mesh
	root.add_child(body)
	var wire := MeshInstance3D.new()
	wire.mesh = _wire_mesh
	root.add_child(wire)

	for face_index: int in FACES.size():
		var normal := _face_normals[face_index]
		var label := Label3D.new()
		label.text = str(face_index + 1)
		label.font_size = 64
		label.pixel_size = 0.0055
		label.modulate = Color("#f3e6c8")
		label.outline_modulate = Color("#3b2e25")
		label.outline_size = 9
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = normal * 0.812
		var x_axis := Vector3.UP.cross(normal).normalized()
		label.basis = Basis(x_axis, _face_ups[face_index], normal)
		root.add_child(label)

	return root
