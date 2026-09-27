class_name World
extends Node3D

# ============================================================
#	Density-based voxel world
# ============================================================
#	Generates terrain as a smooth density field sampled from noise.
#	Surface is extracted via Mesher (Surface Nets) — no visible cubes.
#	Trees are real 3D meshes batched into MultiMeshInstance3D.
# ============================================================

const CHUNKS_X := 5
const CHUNKS_Z := 5
const WORLD_W := CHUNKS_X * Chunk.SIZE_H
const WORLD_D := CHUNKS_Z * Chunk.SIZE_H
const MAX_Y := Chunk.SIZE_V

const SURFACE_BAND := 1.6
const CAVE_THRESHOLD := 0.15
const CAVE_STRENGTH := 2.5
const CAVE_MIN_DEPTH := 2.0

var chunks: Dictionary = {}
var tree_multimeshes: Array = []

var temp_noise: FastNoiseLite
var humid_noise: FastNoiseLite
var height_noise: FastNoiseLite
var ridge_noise: FastNoiseLite
var cave_noise: FastNoiseLite
var detail_noise: FastNoiseLite

var tree_rng := RandomNumberGenerator.new()


# ============================================================
#	Boot
# ============================================================

func _ready() -> void:
	_setup_noise()
	tree_rng.seed = 7331

	var t0 := Time.get_ticks_msec()
	print("[World] creating chunks...")
	_create_chunk_nodes()

	var t1 := Time.get_ticks_msec()
	print("[World] chunk nodes in %d ms" % (t1 - t0))

	print("[World] filling density fields...")
	_fill_all_density()
	var t2 := Time.get_ticks_msec()
	print("[World] density in %d ms" % (t2 - t1))

	print("[World] meshing terrain...")
	_mesh_all_chunks()
	var t3 := Time.get_ticks_msec()
	print("[World] meshing in %d ms" % (t3 - t2))

	print("[World] placing trees...")
	_place_trees()
	var t4 := Time.get_ticks_msec()
	print("[World] trees in %d ms" % (t4 - t3))

	print("[World] total %d ms" % (t4 - t0))


# ============================================================
#	Noise
# ============================================================

func _setup_noise() -> void:
	temp_noise = FastNoiseLite.new()
	temp_noise.seed = 1111
	temp_noise.frequency = 0.006
	temp_noise.fractal_octaves = 2
	temp_noise.fractal_gain = 0.5

	humid_noise = FastNoiseLite.new()
	humid_noise.seed = 2222
	humid_noise.frequency = 0.007
	humid_noise.fractal_octaves = 2
	humid_noise.fractal_gain = 0.5

	height_noise = FastNoiseLite.new()
	height_noise.seed = 3333
	height_noise.frequency = 0.014
	height_noise.fractal_octaves = 4
	height_noise.fractal_lacunarity = 2.0
	height_noise.fractal_gain = 0.5

	ridge_noise = FastNoiseLite.new()
	ridge_noise.seed = 4444
	ridge_noise.frequency = 0.011
	ridge_noise.fractal_octaves = 3

	detail_noise = FastNoiseLite.new()
	detail_noise.seed = 5555
	detail_noise.frequency = 0.10
	detail_noise.fractal_octaves = 2

	cave_noise = FastNoiseLite.new()
	cave_noise.seed = 6666
	cave_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	cave_noise.frequency = 0.055
	cave_noise.fractal_octaves = 2
	cave_noise.fractal_gain = 0.55


# ============================================================
#	Chunk nodes
# ============================================================

func _create_chunk_nodes() -> void:
	for cz in CHUNKS_Z:
		for cx in CHUNKS_X:
			var c := Chunk.new()
			c.name = "Chunk_%d_%d" % [cx, cz]
			c.position = Vector3(cx * Chunk.SIZE_H, 0, cz * Chunk.SIZE_H)
			add_child(c)
			c.set_world_ref(self)
			chunks[Vector2i(cx, cz)] = c


# ============================================================
#	Density filling
# ============================================================

func _fill_all_density() -> void:
	for cz in CHUNKS_Z:
		for cx in CHUNKS_X:
			_fill_chunk(cx, cz)


func _fill_chunk(cx: int, cz: int) -> void:
	var chunk: Chunk = chunks[Vector2i(cx, cz)]
	var origin_x := cx * Chunk.SIZE_H
	var origin_z := cz * Chunk.SIZE_H

	for sz in Chunk.SAMPLES_Z:
		for sx in Chunk.SAMPLES_X:
			var wx := origin_x + sx
			var wz := origin_z + sz
			var biome := _biome_at_with_height(wx, wz)
			var surf_y := _surface_y(wx, wz, biome)

			for sy in Chunk.SAMPLES_Y:
				var wy := sy
				var d := _compute_density(wx, wy, wz, surf_y)
				chunk.set_density_local(sx, sy, sz, d)
				var mat := _material_for(wy, surf_y, biome)
				chunk.set_material_local(sx, sy, sz, mat)


# ============================================================
#	Biome + surface
# ============================================================

func _biome_at(wx: int, wz: int) -> int:
	# Mountains selected by ridge noise before climate pick
	var ridge_raw := ridge_noise.get_noise_2d(float(wx), float(wz))
	var mountain_mask: float = 1.0 - absf(ridge_raw)
	if mountain_mask > 0.72:
		return Biomes.Type.MOUNTAINS

	var temp := temp_noise.get_noise_2d(float(wx), float(wz))
	var humid := humid_noise.get_noise_2d(float(wx), float(wz))
	return Biomes.pick(temp, humid)


func _biome_at_with_height(wx: int, wz: int) -> int:
	var b := _biome_at(wx, wz)
	var sy := _surface_y_raw(wx, wz, b)
	return Biomes.override_for_height(b, sy)


func _surface_y(wx: int, wz: int, biome: int) -> float:
	return _surface_y_raw(wx, wz, biome)


func _surface_y_raw(wx: int, wz: int, biome: int) -> float:
	var h := height_noise.get_noise_2d(float(wx), float(wz)) * 0.5 + 0.5
	var ridge_raw := ridge_noise.get_noise_2d(float(wx), float(wz))
	var ridge: float = 1.0 - absf(ridge_raw)
	var detail := detail_noise.get_noise_2d(float(wx), float(wz)) * 0.5 + 0.5

	var base := Biomes.base_height(biome)
	var amp := Biomes.amplitude(biome)
	var ridge_amt := Biomes.ridge_amount(biome)
	var detail_mul := Biomes.detail_freq(biome)

	var y: float = base + h * amp + ridge * ridge_amt + detail * detail_mul
	return clampf(y, 3.0, float(MAX_Y - 4))


# ============================================================
#	Density
# ============================================================

func _compute_density(wx: int, wy: int, wz: int, surface_y: float) -> float:
	var d := 0.5 + (surface_y - float(wy)) / SURFACE_BAND

	if float(wy) < surface_y - CAVE_MIN_DEPTH:
		var c := cave_noise.get_noise_3d(float(wx), float(wy), float(wz))
		var carve := absf(c) - CAVE_THRESHOLD
		if carve > 0.0:
			var depth_factor := clampf((surface_y - float(wy)) / 12.0, 0.0, 1.0)
			d -= carve * CAVE_STRENGTH * depth_factor

	return clampf(d, 0.0, 1.0)


# ============================================================
#	Material (for coloring)
# ============================================================

func _material_for(wy: int, surface_y: float, biome: int) -> int:
	if float(wy) > surface_y + 0.5:
		return Blocks.AIR
	if float(wy) > surface_y - 2.0:
		return _surface_block_for(biome)
	if float(wy) > surface_y - 5.0:
		return _subsurface_block_for(biome)
	return Blocks.STONE


func _surface_block_for(biome: int) -> int:
	match biome:
		Biomes.Type.DESERT, Biomes.Type.BEACH:
			return Blocks.SAND
		Biomes.Type.TUNDRA:
			return Blocks.SNOW
		Biomes.Type.MOUNTAINS:
			return Blocks.STONE
		_:
			return Blocks.GRASS


func _subsurface_block_for(biome: int) -> int:
	match biome:
		Biomes.Type.DESERT, Biomes.Type.BEACH:
			return Blocks.SAND
		Biomes.Type.MOUNTAINS:
			return Blocks.STONE
		_:
			return Blocks.DIRT


# ============================================================
#	Cross-chunk density lookup
# ============================================================

func get_density_at_world(wx: int, wy: int, wz: int) -> float:
	if wy < 0 or wy >= Chunk.SAMPLES_Y:
		return 0.0
	var cx := wx >> 4
	var cz := wz >> 4
	if cx < 0 or cx >= CHUNKS_X or cz < 0 or cz >= CHUNKS_Z:
		return 0.0
	var chunk: Chunk = chunks.get(Vector2i(cx, cz))
	if chunk == null:
		return 0.0
	var lx := wx - cx * Chunk.SIZE_H
	var lz := wz - cz * Chunk.SIZE_H
	return chunk.get_density_local(lx, wy, lz)


# ============================================================
#	Meshing
# ============================================================

func _mesh_all_chunks() -> void:
	for cz in CHUNKS_Z:
		for cx in CHUNKS_X:
			var chunk: Chunk = chunks[Vector2i(cx, cz)]
			chunk.rebuild_mesh()


# ============================================================
#	Trees
# ============================================================

func _place_trees() -> void:
	var kinds: Array = [
		TreeBuilder.Kind.OAK,
		TreeBuilder.Kind.PINE,
		TreeBuilder.Kind.PALM,
		TreeBuilder.Kind.DEAD,
	]

	var prototypes: Dictionary = {}
	for k in kinds:
		var proto: Node3D = TreeBuilder.create(k, tree_rng)
		var baked: ArrayMesh = _bake_tree_to_mesh(proto)
		proto.queue_free()
		prototypes[k] = baked

	var placements: Dictionary = {}
	for k in kinds:
		placements[k] = []

	for wz in WORLD_D:
		for wx in WORLD_W:
			var biome := _biome_at_with_height(wx, wz)
			var density := Biomes.tree_density(biome)
			if density <= 0.0:
				continue
			if tree_rng.randf() > density:
				continue

			var sy := _surface_y(wx, wz, biome)
			var iy := int(round(sy))
			if iy < 3 or iy > MAX_Y - 12:
				continue

			var surface_mat := _surface_block_for(biome)
			if surface_mat == Blocks.STONE:
				continue

			var kind := Biomes.tree_kind(biome)
			var pos := Vector3(float(wx) + 0.5, sy + 0.2, float(wz) + 0.5)
			var rot := Basis.IDENTITY.rotated(Vector3.UP, tree_rng.randf() * TAU)
			var s := tree_rng.randf_range(0.85, 1.15)
			var scl := Basis.IDENTITY.scaled(Vector3(s, s, s))
			var t := Transform3D(rot * scl, pos)
			placements[kind].append(t)

	for k in kinds:
		var tfs: Array = placements[k]
		if tfs.size() == 0:
			continue
		_create_multimesh(k, prototypes[k], tfs)


func _create_multimesh(kind: int, mesh: Mesh, transforms: Array) -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees_%d" % kind
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	tree_multimeshes.append(mmi)
	print("[World] %d trees of kind %d" % [transforms.size(), kind])


# ============================================================
#	Tree mesh baking
# ============================================================

func _bake_tree_to_mesh(tree: Node3D) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bake_node_recursive(st, tree, Transform3D.IDENTITY)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	if m == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_color(Color.RED)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-0.5, 0, -0.5))
		st.add_vertex(Vector3(0.5, 0, -0.5))
		st.add_vertex(Vector3(0.5, 0, 0.5))
		st.generate_normals()
		m = st.commit()
	return m


func _bake_node_recursive(st: SurfaceTool, node: Node, parent_xform: Transform3D) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform

	if node is MeshInstance3D:
		_bake_mesh_instance(st, node as MeshInstance3D, xform)

	for child in node.get_children():
		_bake_node_recursive(st, child, xform)


func _bake_mesh_instance(st: SurfaceTool, mi: MeshInstance3D, xform: Transform3D) -> void:
	if mi.mesh == null:
		return
	var mesh := mi.mesh

	var color := Color(1, 1, 1)
	if mi.material_override is StandardMaterial3D:
		color = (mi.material_override as StandardMaterial3D).albedo_color

	for surf_i in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surf_i)
		if arrays.size() == 0:
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var norms: PackedVector3Array = PackedVector3Array()
		if arrays.size() > Mesh.ARRAY_NORMAL and arrays[Mesh.ARRAY_NORMAL] != null:
			norms = arrays[Mesh.ARRAY_NORMAL]

		var xf_basis := xform.basis
		var xf_origin := xform.origin

		if idx.size() > 0:
			for i in idx:
				var v := verts[i]
				var world_v := xf_basis * v + xf_origin
				var n := Vector3.UP
				if i < norms.size():
					n = (xf_basis * norms[i]).normalized()
				st.set_color(color)
				st.set_normal(n)
				st.add_vertex(world_v)
		else:
			for i in verts.size():
				var v := verts[i]
				var world_v := xf_basis * v + xf_origin
				var n := Vector3.UP
				if i < norms.size():
					n = (xf_basis * norms[i]).normalized()
				st.set_color(color)
				st.set_normal(n)
				st.add_vertex(world_v)


# ============================================================
#	Spawn
# ============================================================

func get_spawn_point() -> Vector3:
	@warning_ignore("integer_division")
	var cx := WORLD_W / 2
	@warning_ignore("integer_division")
	var cz := WORLD_D / 2

	for radius in range(0, 30, 2):
		for da in 8:
			var a := float(da) * TAU / 8.0
			var wx := cx + int(cos(a) * float(radius))
			var wz := cz + int(sin(a) * float(radius))
			if wx < 2 or wx > WORLD_W - 3 or wz < 2 or wz > WORLD_D - 3:
				continue
			var biome := _biome_at_with_height(wx, wz)
			if biome == Biomes.Type.MOUNTAINS:
				continue
			var sy := _surface_y(wx, wz, biome)
			if sy < 4.0 or sy > 34.0:
				continue
			return Vector3(float(wx) + 0.5, sy + 2.5, float(wz) + 0.5)

	return Vector3(float(cx) + 0.5, 30.0, float(cz) + 0.5)