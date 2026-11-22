extends Node3D

# CustomProps is an identity-transform child of AssetsRoot.
var _sample_surface: Callable
var _collider: StaticBody3D


func configure(sample_surface: Callable, collider: StaticBody3D) -> void:
	_sample_surface = sample_surface
	_collider = collider


func snap_node_to_terrain(
	node: Node3D, world_xz: Vector2, y_offset: float = 0.0, align_normal_strength: float = 0.0
) -> bool:
	if node == null or not _sample_surface.is_valid():
		return false
	var hit: Vector4 = _sample_surface.call(world_xz)
	if not is_finite(hit.w):
		return false
	if is_instance_valid(_collider) and is_inside_tree():
		var query := PhysicsRayQueryParameters3D.create(Vector3(world_xz.x, 3.0, world_xz.y),
			Vector3(world_xz.x, -0.5, world_xz.y), _collider.collision_layer)
		var contact := get_world_3d().direct_space_state.intersect_ray(query)
		if not contact.is_empty() and contact["collider"] == _collider:
			var point: Vector3 = contact["position"]
			var normal: Vector3 = contact["normal"]
			hit = Vector4(normal.x, normal.y, normal.z, point.y)
	if node.get_parent() == null:
		add_child(node)
	elif node.get_parent() != self:
		node.reparent(self, true)
	node.global_position = Vector3(world_xz.x, hit.w + y_offset, world_xz.y)
	if align_normal_strength <= 0.0 or node.global_basis.y.is_zero_approx():
		return true
	var up := Vector3(hit.x, hit.y, hit.z)
	var basis := node.global_basis
	var correction := Quaternion.IDENTITY.slerp(Quaternion(basis.y.normalized(), up),
		clampf(align_normal_strength, 0.0, 1.0))
	node.global_basis = Basis(correction) * basis
	return true
