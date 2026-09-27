class_name TreeBuilder
extends Node3D

# ============================================================
#	Tree factory
# ============================================================
#	Builds realistic-looking trees from Godot primitives:
#	  - Trunk: tapered cylinder, occasionally curved
#	  - Branches: 0–6 tapered cylinders, angled upward
#	  - Foliage: 3–8 overlapping low-poly spheres with jitter
#	  - Palm fronds: elongated flattened cones fanning outward
#	  - Dead trees: bare trunk + a few broken branch stubs
#
#	Materials are cached at the class level so 500 trees share the
#	same 4 material instances — critical for draw call budget.
# ============================================================

enum Kind {
	OAK,
	PINE,
	PALM,
	DEAD,
}

static var _mat_bark_oak: StandardMaterial3D
static var _mat_bark_pine: StandardMaterial3D
static var _mat_bark_palm: StandardMaterial3D
static var _mat_bark_dead: StandardMaterial3D
static var _mat_leaf_broad: StandardMaterial3D
static var _mat_leaf_pine: StandardMaterial3D
static var _mat_leaf_palm: StandardMaterial3D


static func _ensure_materials() -> void:
	if _mat_bark_oak != null:
		return

	_mat_bark_oak = StandardMaterial3D.new()
	_mat_bark_oak.albedo_color = Color(0.32, 0.22, 0.13)
	_mat_bark_oak.roughness = 0.95
	_mat_bark_oak.metallic = 0.0

	_mat_bark_pine = StandardMaterial3D.new()
	_mat_bark_pine.albedo_color = Color(0.26, 0.17, 0.11)
	_mat_bark_pine.roughness = 0.95
	_mat_bark_pine.metallic = 0.0

	_mat_bark_palm = StandardMaterial3D.new()
	_mat_bark_palm.albedo_color = Color(0.42, 0.34, 0.20)
	_mat_bark_palm.roughness = 0.9
	_mat_bark_palm.metallic = 0.0

	_mat_bark_dead = StandardMaterial3D.new()
	_mat_bark_dead.albedo_color = Color(0.30, 0.28, 0.24)
	_mat_bark_dead.roughness = 0.98
	_mat_bark_dead.metallic = 0.0

	_mat_leaf_broad = StandardMaterial3D.new()
	_mat_leaf_broad.albedo_color = Color(0.20, 0.42, 0.16)
	_mat_leaf_broad.roughness = 0.88
	_mat_leaf_broad.metallic = 0.0
	_mat_leaf_broad.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_leaf_pine = StandardMaterial3D.new()
	_mat_leaf_pine.albedo_color = Color(0.14, 0.32, 0.14)
	_mat_leaf_pine.roughness = 0.9
	_mat_leaf_pine.metallic = 0.0
	_mat_leaf_pine.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_leaf_palm = StandardMaterial3D.new()
	_mat_leaf_palm.albedo_color = Color(0.28, 0.48, 0.20)
	_mat_leaf_palm.roughness = 0.85
	_mat_leaf_palm.metallic = 0.0
	_mat_leaf_palm.cull_mode = BaseMaterial3D.CULL_DISABLED


static func create(kind: int, rng: RandomNumberGenerator) -> Node3D:
	_ensure_materials()
	var tree := Node3D.new()
	tree.name = "Tree"
	match kind:
		Kind.OAK:
			_make_oak(tree, rng)
		Kind.PINE:
			_make_pine(tree, rng)
		Kind.PALM:
			_make_palm(tree, rng)
		Kind.DEAD:
			_make_dead(tree, rng)
	return tree


# ============================================================
#	Oak
# ============================================================

static func _make_oak(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var trunk_h := rng.randf_range(3.2, 4.8)
	var trunk_r_bot := rng.randf_range(0.28, 0.38)
	var trunk_r_top := trunk_r_bot * rng.randf_range(0.55, 0.7)

	_add_tapered_cylinder(
		parent,
		Vector3.ZERO,
		trunk_h,
		trunk_r_bot, trunk_r_top,
		_mat_bark_oak,
		rng.randf_range(0.0, TAU),
	)

	var branch_count := rng.randi_range(2, 4)
	for i in branch_count:
		var angle := (float(i) / float(branch_count)) * TAU + rng.randf_range(-0.4, 0.4)
		var branch_len := rng.randf_range(1.2, 2.2)
		var base_h := trunk_h * rng.randf_range(0.55, 0.9)
		var tilt := rng.randf_range(0.4, 0.9)
		_add_branch(
			parent,
			Vector3(0, base_h, 0),
			angle, tilt, branch_len,
			trunk_r_top * 0.55,
			trunk_r_top * 0.25,
			_mat_bark_oak,
		)

	var cluster_count := rng.randi_range(5, 8)
	var center_y := trunk_h + rng.randf_range(0.2, 0.7)
	var spread := rng.randf_range(1.6, 2.4)

	for i in cluster_count:
		var angle := rng.randf() * TAU
		var radius := rng.randf() * spread
		var cx := cos(angle) * radius
		var cz := sin(angle) * radius
		var cy := center_y + rng.randf_range(-0.5, 0.8)
		var sz := rng.randf_range(0.9, 1.4)
		_add_leaf_blob(
			parent,
			Vector3(cx, cy, cz),
			Vector3(sz, sz * rng.randf_range(0.7, 0.95), sz),
			_mat_leaf_broad,
			rng,
		)


# ============================================================
#	Pine
# ============================================================

static func _make_pine(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var trunk_h := rng.randf_range(5.5, 8.5)
	var trunk_r := rng.randf_range(0.20, 0.28)

	_add_tapered_cylinder(
		parent,
		Vector3.ZERO,
		trunk_h,
		trunk_r, trunk_r * 0.55,
		_mat_bark_pine,
		rng.randf_range(0.0, TAU),
	)

	var layer_count := rng.randi_range(4, 6)
	var layer_start := trunk_h * 0.28
	var layer_end := trunk_h
	for i in layer_count:
		var t := float(i) / float(layer_count - 1)
		var y := lerpf(layer_start, layer_end, t)
		var r := lerpf(1.9, 0.5, t) * rng.randf_range(0.9, 1.1)
		var h := lerpf(1.8, 0.9, t)
		_add_cone(
			parent,
			Vector3(0, y + h * 0.4, 0),
			r, h,
			_mat_leaf_pine,
			rng.randf_range(0.0, TAU),
		)


# ============================================================
#	Palm
# ============================================================

static func _make_palm(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var trunk_h := rng.randf_range(4.5, 6.5)
	var trunk_r := rng.randf_range(0.16, 0.22)
	var curve := rng.randf_range(-0.3, 0.3)
	var curve_axis := rng.randf_range(0.0, TAU)

	var segments := 6
	var seg_h := trunk_h / float(segments)
	var prev_pos := Vector3.ZERO
	var prev_r := trunk_r
	for i in segments:
		var t := float(i) / float(segments)
		var bend := curve * t * t
		var offset := Vector3(cos(curve_axis) * bend, 0, sin(curve_axis) * bend)
		var next_pos := Vector3(offset.x, (float(i) + 1.0) * seg_h, offset.z)
		var next_r := lerpf(trunk_r, trunk_r * 0.6, t + 1.0 / float(segments))
		_add_cylinder_between(parent, prev_pos, next_pos, prev_r, next_r, _mat_bark_palm)
		prev_pos = next_pos
		prev_r = next_r

	var frond_count := rng.randi_range(7, 10)
	for i in frond_count:
		var a := (float(i) / float(frond_count)) * TAU + rng.randf_range(-0.15, 0.15)
		var tilt := rng.randf_range(0.55, 0.95)
		var length := rng.randf_range(1.8, 2.6)
		_add_frond(parent, prev_pos, a, tilt, length, _mat_leaf_palm, rng)

	if rng.randf() < 0.35:
		for i in rng.randi_range(1, 3):
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.20, 0.30)
			var nut := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = r
			sph.height = r * 2.0
			nut.mesh = sph
			var nut_mat := StandardMaterial3D.new()
			nut_mat.albedo_color = Color(0.36, 0.24, 0.14)
			nut_mat.roughness = 0.9
			nut.material_override = nut_mat
			nut.position = prev_pos + Vector3(cos(a) * 0.3, -0.15, sin(a) * 0.3)
			parent.add_child(nut)


# ============================================================
#	Dead
# ============================================================

static func _make_dead(parent: Node3D, rng: RandomNumberGenerator) -> void:
	var trunk_h := rng.randf_range(3.0, 5.0)
	var trunk_r := rng.randf_range(0.22, 0.32)

	_add_tapered_cylinder(
		parent,
		Vector3.ZERO,
		trunk_h,
		trunk_r, trunk_r * 0.4,
		_mat_bark_dead,
		rng.randf_range(0.0, TAU),
	)

	var stub_count := rng.randi_range(1, 4)
	for i in stub_count:
		var angle := rng.randf() * TAU
		var base_h := trunk_h * rng.randf_range(0.4, 0.9)
		var stub_len := rng.randf_range(0.5, 1.3)
		var tilt := rng.randf_range(0.8, 1.4)
		_add_branch(
			parent,
			Vector3(0, base_h, 0),
			angle, tilt, stub_len,
			trunk_r * 0.5, trunk_r * 0.2,
			_mat_bark_dead,
		)


# ============================================================
#	Primitives
# ============================================================

static func _add_tapered_cylinder(
	parent: Node3D,
	base: Vector3,
	height: float,
	radius_bottom: float,
	radius_top: float,
	mat: Material,
	rot_y: float,
) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius_bottom
	mesh.top_radius = radius_top
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.cap_bottom = true
	mesh.cap_top = true

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = base + Vector3(0, height * 0.5, 0)
	mi.rotation.y = rot_y
	parent.add_child(mi)


static func _add_cylinder_between(
	parent: Node3D,
	from: Vector3,
	to: Vector3,
	r_from: float,
	r_to: float,
	mat: Material,
) -> void:
	var diff := to - from
	var length := diff.length()
	if length < 0.001:
		return

	var mesh := CylinderMesh.new()
	mesh.bottom_radius = r_from
	mesh.top_radius = r_to
	mesh.height = length
	mesh.radial_segments = 8
	mesh.rings = 2
	mesh.cap_bottom = true
	mesh.cap_top = true

	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = (from + to) * 0.5

	var up := Vector3.UP
	var dir := diff.normalized()
	var axis := up.cross(dir)
	var angle := up.angle_to(dir)
	if axis.length_squared() > 0.0001:
		mi.rotate(axis.normalized(), angle)

	parent.add_child(mi)


static func _add_branch(
	parent: Node3D,
	base: Vector3,
	angle_y: float,
	tilt: float,
	length: float,
	r_from: float,
	r_to: float,
	mat: Material,
) -> void:
	var dir := Vector3(
		cos(angle_y) * sin(tilt),
		cos(tilt),
		sin(angle_y) * sin(tilt),
	)
	var tip := base + dir * length
	_add_cylinder_between(parent, base, tip, r_from, r_to, mat)


static func _add_leaf_blob(
	parent: Node3D,
	pos: Vector3,
	scale: Vector3,
	mat: Material,
	rng: RandomNumberGenerator,
) -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	mi.mesh = sphere
	mi.material_override = mat
	mi.position = pos
	mi.scale = scale
	mi.rotation.y = rng.randf() * TAU
	mi.rotation.x = rng.randf_range(-0.2, 0.2)
	parent.add_child(mi)


static func _add_cone(
	parent: Node3D,
	pos: Vector3,
	radius: float,
	height: float,
	mat: Material,
	rot_y: float,
) -> void:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.bottom_radius = radius
	cone.top_radius = 0.001
	cone.height = height
	cone.radial_segments = 10
	cone.rings = 1
	cone.cap_bottom = true
	cone.cap_top = false
	mi.mesh = cone
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	parent.add_child(mi)


static func _add_frond(
	parent: Node3D,
	origin: Vector3,
	angle_y: float,
	tilt: float,
	length: float,
	mat: Material,
	rng: RandomNumberGenerator,
) -> void:
	var mi := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.bottom_radius = 0.16
	cone.top_radius = 0.02
	cone.height = length
	cone.radial_segments = 6
	cone.rings = 1
	cone.cap_bottom = false
	cone.cap_top = false
	mi.mesh = cone
	mi.material_override = mat

	var half := length * 0.5
	var dir := Vector3(
		cos(angle_y) * sin(tilt),
		cos(tilt),
		sin(angle_y) * sin(tilt),
	)
	mi.position = origin + dir * half

	var axis := Vector3.UP.cross(dir)
	var angle := Vector3.UP.angle_to(dir)
	if axis.length_squared() > 0.0001:
		mi.rotate(axis.normalized(), angle)
	mi.scale = Vector3(1.0, 1.0, 0.55)

	parent.add_child(mi)