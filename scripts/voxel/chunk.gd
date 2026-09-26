class_name Chunk
extends Node3D

const SIZE := 16

var voxels: PackedInt32Array
var mesh_instance: MeshInstance3D
var collision: StaticBody3D


func _init() -> void:
	voxels.resize(SIZE * SIZE * SIZE)
	voxels.fill(0)
	mesh_instance = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.material_override = mat
	add_child(mesh_instance)


func idx(x: int, y: int, z: int) -> int:
	return x + SIZE * (y + SIZE * z)


func get_voxel(x: int, y: int, z: int) -> int:
	if x < 0 or x >= SIZE or y < 0 or y >= SIZE or z < 0 or z >= SIZE:
		return 0
	return voxels[idx(x, y, z)]


func set_voxel(x: int, y: int, z: int, id: int) -> void:
	if x < 0 or x >= SIZE or y < 0 or y >= SIZE or z < 0 or z >= SIZE:
		return
	voxels[idx(x, y, z)] = id


func rebuild_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for z in SIZE:
		for y in SIZE:
			for x in SIZE:
				var id := get_voxel(x, y, z)
				if id == 0:
					continue
				if not _is_solid(x, y + 1, z):
					_add_face(st, x, y, z, Vector3.UP, id)
				if not _is_solid(x, y - 1, z):
					_add_face(st, x, y, z, Vector3.DOWN, id)
				if not _is_solid(x + 1, y, z):
					_add_face(st, x, y, z, Vector3.RIGHT, id)
				if not _is_solid(x - 1, y, z):
					_add_face(st, x, y, z, Vector3.LEFT, id)
				if not _is_solid(x, y, z + 1):
					_add_face(st, x, y, z, Vector3.BACK, id)
				if not _is_solid(x, y, z - 1):
					_add_face(st, x, y, z, Vector3.FORWARD, id)

	st.generate_normals()
	var mesh := st.commit()
	mesh_instance.mesh = mesh
	_update_collision(mesh)


func _is_solid(x: int, y: int, z: int) -> bool:
	if x < 0 or x >= SIZE or y < 0 or y >= SIZE or z < 0 or z >= SIZE:
		return _neighbor_solid(x, y, z)
	return get_voxel(x, y, z) != 0


func _neighbor_solid(x: int, y: int, z: int) -> bool:
	var world := get_parent()
	if world == null or not world.has_method("get_voxel_world"):
		return false
	var wx := int(global_position.x) + x
	var wy := y
	var wz := int(global_position.z) + z
	return world.get_voxel_world(wx, wy, wz) != 0


func _add_face(st: SurfaceTool, x: int, y: int, z: int, dir: Vector3, id: int) -> void:
	var color := Blocks.color_of(id)
	var p := Vector3(x, y, z)
	var verts: Array[Vector3]

	if dir == Vector3.UP:
		verts = [p + Vector3(0,1,0), p + Vector3(0,1,1), p + Vector3(1,1,1), p + Vector3(1,1,0)]
	elif dir == Vector3.DOWN:
		verts = [p, p + Vector3(1,0,0), p + Vector3(1,0,1), p + Vector3(0,0,1)]
	elif dir == Vector3.RIGHT:
		verts = [p + Vector3(1,0,1), p + Vector3(1,0,0), p + Vector3(1,1,0), p + Vector3(1,1,1)]
	elif dir == Vector3.LEFT:
		verts = [p, p + Vector3(0,0,1), p + Vector3(0,1,1), p + Vector3(0,1,0)]
	elif dir == Vector3.BACK:
		verts = [p + Vector3(0,0,1), p + Vector3(1,0,1), p + Vector3(1,1,1), p + Vector3(0,1,1)]
	else:
		verts = [p, p + Vector3(0,1,0), p + Vector3(1,1,0), p + Vector3(1,0,0)]

	st.set_color(color)
	st.add_vertex(verts[0])
	st.add_vertex(verts[1])
	st.add_vertex(verts[2])
	st.add_vertex(verts[0])
	st.add_vertex(verts[2])
	st.add_vertex(verts[3])


func _update_collision(mesh: Mesh) -> void:
	if collision:
		collision.queue_free()
		collision = null
	if mesh.get_surface_count() == 0:
		return
	collision = StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	collision.add_child(shape)
	add_child(collision)