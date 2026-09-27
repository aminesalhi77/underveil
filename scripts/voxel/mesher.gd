class_name Mesher
extends RefCounted

# ============================================================
#	Surface Nets isosurface extraction
# ============================================================
#	Takes a 3D density field (0=air, 1=solid, 0.5=surface).
#	Produces a smooth triangulated mesh with interpolated vertices.
# ============================================================

const ISO := 0.5
const EPSILON := 0.0001

const CORNERS := [
	Vector3i(0, 0, 0),
	Vector3i(1, 0, 0),
	Vector3i(1, 0, 1),
	Vector3i(0, 0, 1),
	Vector3i(0, 1, 0),
	Vector3i(1, 1, 0),
	Vector3i(1, 1, 1),
	Vector3i(0, 1, 1),
]

const EDGES := [
	[0, 1], [1, 2], [2, 3], [3, 0],
	[4, 5], [5, 6], [6, 7], [7, 4],
	[0, 4], [1, 5], [2, 6], [3, 7],
]


# ============================================================
#	Public API
# ============================================================

static func build_surface(
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	color_fn: Callable,
) -> Dictionary:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()

	var cell_v: Dictionary = {}

	for z in range(sz - 1):
		for y in range(sy - 1):
			for x in range(sx - 1):
				var key := Vector3i(x, y, z)
				var cell: Dictionary = _cell_vertex(density, sx, sy, sz, x, y, z)
				if cell.is_empty():
					continue
				var pos: Vector3 = cell["pos"]
				var normal: Vector3 = cell["normal"]
				cell_v[key] = vertices.size()
				vertices.append(pos)
				var col: Color = color_fn.call(pos, normal)
				colors.append(col)

	for z in range(1, sz - 1):
		for y in range(1, sy - 1):
			for x in range(1, sx - 1):
				_emit_quad_along_x(cell_v, indices, density, sx, sy, sz, x, y, z)
				_emit_quad_along_y(cell_v, indices, density, sx, sy, sz, x, y, z)
				_emit_quad_along_z(cell_v, indices, density, sx, sy, sz, x, y, z)

	var normals := _compute_normals(vertices, indices)

	return {
		"vertices": vertices,
		"normals": normals,
		"indices": indices,
		"colors": colors,
	}


# ============================================================
#	Cell vertex
# ============================================================

static func _cell_vertex(
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> Dictionary:
	var samples := PackedFloat32Array()
	samples.resize(8)
	var min_v := 999.0
	var max_v := -999.0

	for i in 8:
		var c: Vector3i = CORNERS[i]
		var v := _sample(density, sx, sy, sz, x + c.x, y + c.y, z + c.z)
		samples[i] = v
		if v < min_v: min_v = v
		if v > max_v: max_v = v

	if min_v > ISO or max_v < ISO:
		return {}

	var sum := Vector3.ZERO
	var count := 0
	for e in EDGES:
		var a: int = e[0]
		var b: int = e[1]
		var va: float = samples[a]
		var vb: float = samples[b]
		if (va < ISO and vb >= ISO) or (va >= ISO and vb < ISO):
			var t := (ISO - va) / (vb - va)
			var pa := Vector3(CORNERS[a])
			var pb := Vector3(CORNERS[b])
			sum += pa.lerp(pb, t)
			count += 1

	if count == 0:
		return {}

	var local := sum / float(count)
	var normal := _gradient(density, sx, sy, sz, x, y, z)

	return {
		"pos": Vector3(x, y, z) + local,
		"normal": normal,
	}


static func _sample(
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> float:
	if x < 0 or x >= sx or y < 0 or y >= sy or z < 0 or z >= sz:
		return 0.0
	return density[x + sx * (y + sy * z)]


static func _gradient(
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> Vector3:
	var dx := _sample(density, sx, sy, sz, x + 1, y, z) - _sample(density, sx, sy, sz, x, y, z)
	var dy := _sample(density, sx, sy, sz, x, y + 1, z) - _sample(density, sx, sy, sz, x, y, z)
	var dz := _sample(density, sx, sy, sz, x, y, z + 1) - _sample(density, sx, sy, sz, x, y, z)
	var g := Vector3(dx, dy, dz)
	if g.length_squared() > EPSILON:
		return -g.normalized()
	return Vector3.UP


# ============================================================
#	Quad emission
# ============================================================

static func _emit_quad_along_x(
	cell_v: Dictionary, indices: PackedInt32Array,
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> void:
	var v0 := _sample(density, sx, sy, sz, x, y, z)
	var v1 := _sample(density, sx, sy, sz, x + 1, y, z)
	if (v0 < ISO) == (v1 < ISO):
		return

	var c_a := Vector3i(x, y, z)
	var c_b := Vector3i(x, y - 1, z)
	var c_c := Vector3i(x, y - 1, z - 1)
	var c_d := Vector3i(x, y, z - 1)

	if not _has_all(cell_v, [c_a, c_b, c_c, c_d]):
		return

	var ia: int = cell_v[c_a]
	var ib: int = cell_v[c_b]
	var ic: int = cell_v[c_c]
	var id: int = cell_v[c_d]

	if v0 < ISO:
		indices.append_array([ia, ib, ic, ia, ic, id])
	else:
		indices.append_array([ia, ic, ib, ia, id, ic])


static func _emit_quad_along_y(
	cell_v: Dictionary, indices: PackedInt32Array,
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> void:
	var v0 := _sample(density, sx, sy, sz, x, y, z)
	var v1 := _sample(density, sx, sy, sz, x, y + 1, z)
	if (v0 < ISO) == (v1 < ISO):
		return

	var c_a := Vector3i(x, y, z)
	var c_b := Vector3i(x - 1, y, z)
	var c_c := Vector3i(x - 1, y, z - 1)
	var c_d := Vector3i(x, y, z - 1)

	if not _has_all(cell_v, [c_a, c_b, c_c, c_d]):
		return

	var ia: int = cell_v[c_a]
	var ib: int = cell_v[c_b]
	var ic: int = cell_v[c_c]
	var id: int = cell_v[c_d]

	if v0 < ISO:
		indices.append_array([ia, ic, ib, ia, id, ic])
	else:
		indices.append_array([ia, ib, ic, ia, ic, id])


static func _emit_quad_along_z(
	cell_v: Dictionary, indices: PackedInt32Array,
	density: PackedFloat32Array,
	sx: int, sy: int, sz: int,
	x: int, y: int, z: int,
) -> void:
	var v0 := _sample(density, sx, sy, sz, x, y, z)
	var v1 := _sample(density, sx, sy, sz, x, y, z + 1)
	if (v0 < ISO) == (v1 < ISO):
		return

	var c_a := Vector3i(x, y, z)
	var c_b := Vector3i(x - 1, y, z)
	var c_c := Vector3i(x - 1, y - 1, z)
	var c_d := Vector3i(x, y - 1, z)

	if not _has_all(cell_v, [c_a, c_b, c_c, c_d]):
		return

	var ia: int = cell_v[c_a]
	var ib: int = cell_v[c_b]
	var ic: int = cell_v[c_c]
	var id: int = cell_v[c_d]

	if v0 < ISO:
		indices.append_array([ia, ib, ic, ia, ic, id])
	else:
		indices.append_array([ia, ic, ib, ia, id, ic])


static func _has_all(cell_v: Dictionary, keys: Array) -> bool:
	for k in keys:
		if not cell_v.has(k):
			return false
	return true


# ============================================================
#	Normals
# ============================================================

static func _compute_normals(
	vertices: PackedVector3Array,
	indices: PackedInt32Array,
) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for i in vertices.size():
		normals[i] = Vector3.ZERO

	var count := indices.size() / 3
	for t in count:
		var i0 := indices[t * 3]
		var i1 := indices[t * 3 + 1]
		var i2 := indices[t * 3 + 2]
		var a := vertices[i0]
		var b := vertices[i1]
		var c := vertices[i2]
		var n := (b - a).cross(c - a)
		normals[i0] += n
		normals[i1] += n
		normals[i2] += n

	for i in normals.size():
		var n := normals[i]
		if n.length_squared() > EPSILON:
			normals[i] = n.normalized()
		else:
			normals[i] = Vector3.UP

	return normals