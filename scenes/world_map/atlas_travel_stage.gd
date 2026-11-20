extends Node3D

const Planner := preload("res://core/travel_planner.gd")
const LAND := Color("#FFD481")
const SEA := Color("#8ED8F2")
const LAND_INK := Color("#844822")
const SEA_INK := Color("#254B62")
const BLUE := Color("#467C9D")
const GOLD := Color("#CA9A54")

var _routes: Node3D
var _pawn: Node3D
var _body: Node3D
var _halo: MeshInstance3D
var _paths: Array[Curve3D] = []
var _beads: Array[MeshInstance3D] = []
var _clock := 0.0
var _moving := false
var bounds: AABB


func _ready() -> void:
	_routes = Node3D.new()
	add_child(_routes)
	_pawn = Node3D.new()
	add_child(_pawn)
	_body = Node3D.new()
	_pawn.add_child(_body)

	var gold := _material(GOLD, 0.60, 0.34)
	var blue := _material(BLUE, 0.12, 0.38)
	var ivory := _material(Color("#F6E3C4"), 0.06, 0.30)
	var shade := _material(Color("#263D54"), 0.10, 0.48)
	_lathe(_pawn, [Vector2(0.095, 0.00), Vector2(0.111, 0.015), Vector2(0.110, 0.031),
		Vector2(0.090, 0.049)], gold)
	_lathe(_pawn, [Vector2(0.095, 0.025), Vector2(0.099, 0.039), Vector2(0.084, 0.055)], blue)
	_lathe(_body, [Vector2(0.069, 0.047), Vector2(0.076, 0.069), Vector2(0.061, 0.100),
		Vector2(0.025, 0.19), Vector2(0.051, 0.212), Vector2(0.027, 0.244)], ivory)
	_lathe(_body, [Vector2(0.071, 0.068), Vector2(0.073, 0.082), Vector2(0.057, 0.112),
		Vector2(0.045, 0.145), Vector2(0.045, 0.167)], blue, Vector3(0, 0, -0.009))
	_sphere(_body, Vector3(0, 0.265, -0.005), Vector3(0.090, 0.098, 0.088), blue)
	_sphere(_body, Vector3(0, 0.260, 0.029), Vector3(0.063, 0.063, 0.027), shade)
	_sphere(_body, Vector3(0, 0.258, 0.040), Vector3(0.046, 0.045, 0.016), ivory)
	_lathe(_body, [Vector2(0.034, 0.219), Vector2(0.057, 0.226),
		Vector2(0.047, 0.237), Vector2(0.035, 0.243)], gold)
	_sphere(_body, Vector3(0, 0.207, 0.054), Vector3(0.029, 0.032, 0.017), gold)
	var torus := TorusMesh.new()
	torus.inner_radius = 0.114
	torus.outer_radius = 0.126
	torus.rings = 32
	torus.ring_segments = 8
	_halo = _mesh(_pawn, torus, _light(Color("#93DFF2"), 0.61))
	_halo.position.y = 0.009


func _process(delta: float) -> void:
	_clock += delta
	_body.position.y = (0.005 if _moving else 0.009) * (0.5 + 0.5 * sin(_clock * 3.1))
	_halo.scale = Vector3.ONE * (1.0 + 0.07 * sin(_clock * 2.3))
	for index: int in _beads.size():
		var path := _paths[index]
		var progress := fposmod(_clock * 0.7 + index * 0.31, 1.0)
		_beads[index].position = path.sample_baked(path.get_baked_length() * progress, true)


func park(position_on_map: Vector3) -> void:
	_moving = false
	_pawn.position = position_on_map
	_pawn.rotation.y = 0.20


func follow(index: int, fraction: float) -> void:
	_moving = true
	var path := _paths[index]
	var offset := path.get_baked_length() * fraction
	var point := path.sample_baked(offset, true)
	var ahead := path.sample_baked(minf(path.get_baked_length(), offset + 0.06), true)
	_pawn.position = point
	if ahead.distance_squared_to(point) > 0.000001:
		_pawn.rotation.y = atan2(ahead.x - point.x, ahead.z - point.z)


func set_itinerary(plan: Planner.Itinerary, cities: Dictionary[String, Vector3]) -> void:
	for child: Node in _routes.get_children():
		_routes.remove_child(child)
		child.queue_free()
	_paths.clear()
	_beads.clear()
	bounds = AABB()
	if plan == null:
		return
	for leg: Planner.Leg in plan.legs:
		var path := _curve(leg, cities[leg.from_city], cities[leg.to_city])
		var coast := leg.mode == Planner.SHIP
		var tone := SEA if coast else LAND
		_paths.append(path)
		for point: Vector3 in path.get_baked_points():
			bounds = bounds.expand(point) if bounds.has_surface() else AABB(point, Vector3.ONE * 0.001)
		_mesh(_routes, _tube(path, 0.035, coast), _light(tone, 0.22))
		_mesh(_routes, _tube(path, 0.025 if coast else 0.023, coast), _light(SEA_INK if coast else LAND_INK, 0.74, 1))
		_mesh(_routes, _tube(path, 0.015 if coast else 0.013, coast), _light(tone, 0.98, 2))
		var bead := SphereMesh.new()
		bead.radius = 0.032
		bead.height = 0.064
		bead.radial_segments = 12
		bead.rings = 8
		_beads.append(_mesh(_routes, bead, _light(tone.lightened(0.37), 0.96, 3)))


func _curve(leg: Planner.Leg, start: Vector3, finish: Vector3) -> Curve3D:
	# Keep the low endpoints aligned with the pawn and raise the connecting arc above the silhouettes.
	var points: Array[Vector3] = [start]
	for pixel: Vector2 in leg.via:
		points.append(Vector3((pixel.x - 836.0) / 100.0, 0.0, (pixel.y - 470.5) / 100.0))
	if points.size() == 1:
		points.append((start + finish) * 0.5)
	points.append(finish)
	var path := Curve3D.new()
	path.bake_interval = 0.025
	var apex := clampf(start.distance_to(finish) * 0.11, 0.13, 0.56)
	if leg.mode == Planner.SHIP:
		apex += 0.13
	for index: int in range(1, points.size() - 1):
		var weight := float(index) / (points.size() - 1)
		points[index].y = lerpf(start.y, finish.y, weight) + sin(PI * weight) * apex
	for index: int in points.size():
		var before := points[maxi(0, index - 1)]
		var after := points[mini(points.size() - 1, index + 1)]
		var tangent := (after - before) / 6.0
		path.add_point(points[index], -tangent, tangent)
	return path


func _tube(path: Curve3D, radius: float, dashed: bool) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := path.get_baked_length()
	var start := 0.0
	while start < length:
		var finish := minf(length, start + 0.145) if dashed else length
		var segments := maxi(1, ceili((finish - start) / 0.070))
		var previous := _tube_ring(path, start, radius)
		for index: int in range(1, segments + 1):
			var ring := _tube_ring(path, lerpf(start, finish, float(index) / segments), radius)
			for side: int in ring.size():
				var next := (side + 1) % ring.size()
				for vertex: Vector3 in [previous[side], ring[side], ring[next], previous[side], ring[next], previous[next]]:
					surface.add_vertex(vertex)
			previous = ring
		start = finish + 0.085
	return surface.commit()


func _tube_ring(path: Curve3D, offset: float, radius: float) -> Array[Vector3]:
	var before := path.sample_baked(maxf(0.0, offset - 0.01), true)
	var after := path.sample_baked(minf(path.get_baked_length(), offset + 0.01), true)
	var tangent := (after - before).normalized()
	var right := tangent.cross(Vector3.UP).normalized()
	var up := right.cross(tangent).normalized()
	var center := path.sample_baked(offset, true)
	var points: Array[Vector3] = []
	for side: int in 6:
		var angle := TAU * side / 6.0
		points.append(center + (right * cos(angle) + up * sin(angle)) * radius)
	return points


func _lathe(parent: Node3D, profile: Array[Vector2], material: StandardMaterial3D, offset := Vector3.ZERO) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(profile.size() - 1):
		for side: int in 32:
			var a := _radial(profile[row], side)
			var b := _radial(profile[row], side + 1)
			var c := _radial(profile[row + 1], side)
			var d := _radial(profile[row + 1], side + 1)
			for vertex: Vector3 in [a, b, c, b, d, c]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	_mesh(parent, surface.commit(), material).position = offset


func _radial(profile: Vector2, side: int) -> Vector3:
	var angle := TAU * side / 32.0
	return Vector3(cos(angle) * profile.x, profile.y, sin(angle) * profile.x)


func _sphere(parent: Node3D, center: Vector3, proportions: Vector3, material: StandardMaterial3D) -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 20
	sphere.rings = 12
	sphere.radius = 0.5
	sphere.height = 1.0
	var part := _mesh(parent, sphere, material)
	part.position = center
	part.scale = proportions


func _mesh(parent: Node3D, geometry: Mesh, material: StandardMaterial3D) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.mesh = geometry
	result.material_override = material
	if material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
		result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(result)
	return result


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _light(color: Color, opacity: float, priority: int = 0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color, opacity)
	material.render_priority = priority
	return material
