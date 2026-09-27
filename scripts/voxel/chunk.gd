class_name Chunk
extends Node3D

# ============================================================
#	Density-based chunk
# ============================================================
#	Each chunk stores:
#	  - density: (H+1) x (V+1) x (H+1) float samples (0=air, 1=solid)
#	  - material: same shape, holds Blocks.* ids for coloring
#	Cells between adjacent samples are 1 world unit each.
#	Mesher.build_surface turns the density field into a smooth mesh.
# ============================================================

const SIZE_H := 16
const SIZE_V := 40

# Sample grid is one larger than cell grid, so (H+1) samples = H cells.
const SAMPLES_X := SIZE_H + 1
const SAMPLES_Y := SIZE_V + 1
const SAMPLES_Z := SIZE_H + 1

# Total sample count
const SAMPLE_COUNT := SAMPLES_X * SAMPLES_Y * SAMPLES_Z

# Terrain appearance tuning
const GRASS_SLOPE_CUTOFF := 0.55	 # normal.y below this → exposed rock
const SNOW_HEIGHT := 32.0			 # above this world-Y, snow covers grass
const SAND_HEIGHT := 22.5			 # below this world-Y, sand shores
const BEACH_BLEND_RANGE := 1.5		 # Y-range over which sand fades to grass
const STONE_BLEND_RANGE := 0.35		 # normal.y range over which grass fades to stone

# ============================================================
#	State
# ============================================================

var density: PackedFloat32Array
var material: PackedInt32Array

var mesh_instance: MeshInstance3D
var collision_body: StaticBody3D
var collision_shape: CollisionShape3D

var world_ref: Node = null	  # set by world.gd after add_child

# ============================================================
#	Setup
# ============================================================

func _init() -> void:
	density.resize(SAMPLE_COUNT)
	density.fill(0.0)
	material.resize(SAMPLE_COUNT)
	material.fill(Blocks.STONE)

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Mesh"

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mesh_instance.material_override = mat

	add_child(mesh_instance)

	collision_body = StaticBody3D.new()
	collision_body.name = "Collision"
	collision_shape = CollisionShape3D.new()
	collision_body.add_child(collision_shape)
	add_child(collision_body)


func set_world_ref(w: Node) -> void:
	world_ref = w


# ============================================================
#	Sample access
# ============================================================

func sample_index(sx: int, sy: int, sz: int) -> int:
	return sx + SAMPLES_X * (sy + SAMPLES_Y * sz)


func get_density_local(sx: int, sy: int, sz: int) -> float:
	if sx < 0 or sx >= SAMPLES_X or sy < 0 or sy >= SAMPLES_Y or sz < 0 or sz >= SAMPLES_Z:
		return 0.0
	return density[sample_index(sx, sy, sz)]


func set_density_local(sx: int, sy: int, sz: int, d: float) -> void:
	if sx < 0 or sx >= SAMPLES_X or sy < 0 or sy >= SAMPLES_Y or sz < 0 or sz >= SAMPLES_Z:
		return
	density[sample_index(sx, sy, sz)] = clampf(d, 0.0, 1.0)


func get_material_local(sx: int, sy: int, sz: int) -> int:
	if sx < 0 or sx >= SAMPLES_X or sy < 0 or sy >= SAMPLES_Y or sz < 0 or sz >= SAMPLES_Z:
		return Blocks.STONE
	return material[sample_index(sx, sy, sz)]


func set_material_local(sx: int, sy: int, sz: int, m: int) -> void:
	if sx < 0 or sx >= SAMPLES_X or sy < 0 or sy >= SAMPLES_Y or sz < 0 or sz >= SAMPLES_Z:
		return
	material[sample_index(sx, sy, sz)] = m


# ============================================================
#	World-space sampling (used by neighbors and by player edits)
# ============================================================

func world_to_local(wx: float, wy: float, wz: float) -> Vector3i:
	var origin := global_position
	return Vector3i(
		int(round(wx - origin.x)),
		int(round(wy - origin.y)),
		int(round(wz - origin.z)),
	)


func get_density_world(wx: int, wy: int, wz: int) -> float:
	var l := world_to_local(float(wx), float(wy), float(wz))
	if _local_in_bounds(l):
		return get_density_local(l.x, l.y, l.z)
	if world_ref != null and world_ref.has_method("get_density_at_world"):
		return world_ref.get_density_at_world(wx, wy, wz)
	return 0.0


func _local_in_bounds(l: Vector3i) -> bool:
	return (
		l.x >= 0 and l.x < SAMPLES_X and
		l.y >= 0 and l.y < SAMPLES_Y and
		l.z >= 0 and l.z < SAMPLES_Z
	)


# ============================================================
#	Mesh building
# ============================================================

func rebuild_mesh() -> void:
	var result: Dictionary = Mesher.build_surface(
		density, SAMPLES_X, SAMPLES_Y, SAMPLES_Z,
		Callable(self, "_vertex_color"),
	)

	var verts: PackedVector3Array = result["vertices"]
	if verts.size() == 0:
		mesh_instance.mesh = null
		collision_shape.shape = null
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = result["normals"]
	arrays[Mesh.ARRAY_INDEX] = result["indices"]
	arrays[Mesh.ARRAY_COLOR] = result["colors"]

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_instance.mesh = mesh

	_update_collision(mesh)


func _update_collision(mesh: Mesh) -> void:
	collision_shape.shape = null
	if mesh.get_surface_count() == 0:
		return
	var shape := mesh.create_trimesh_shape()
	if shape != null:
		collision_shape.shape = shape


# ============================================================
#	Vertex coloring — slope + height aware
# ============================================================

# Called by Mesher for each generated vertex. Returns a per-vertex
# color that produces smooth blends across terrain: grass on flat
# ground, stone on steep slopes, snow on peaks, sand on shores.
func _vertex_color(local_pos: Vector3, normal: Vector3) -> Color:
	# Get material from nearest sample for a base hue
	var sx := int(round(local_pos.x))
	var sy := int(round(local_pos.y))
	var sz := int(round(local_pos.z))
	var mat_id := get_material_local(sx, sy, sz)
	var base := Blocks.color_of(mat_id)

	# World Y for height-based effects
	var world_y := global_position.y + local_pos.y
	var slope := normal.y  # 1.0 = flat facing up, 0.0 = vertical, -1.0 = down

	# --- Slope-driven stone exposure ---
	# Rock shows through where slopes are steep, regardless of top material
	var stone_color := Blocks.color_of(Blocks.STONE)
	var dirt_color := Blocks.color_of(Blocks.DIRT)

	var stone_blend := 0.0
	if slope < GRASS_SLOPE_CUTOFF:
		stone_blend = clampf((GRASS_SLOPE_CUTOFF - slope) / STONE_BLEND_RANGE, 0.0, 1.0)

	# --- Height-driven snow ---
	var snow_color := Blocks.color_of(Blocks.SNOW)
	var snow_blend := 0.0
	if world_y > SNOW_HEIGHT:
		snow_blend = clampf((world_y - SNOW_HEIGHT) / 6.0, 0.0, 1.0)
	# Snow sticks best to flat surfaces
	snow_blend *= clampf(slope, 0.0, 1.0)

	# --- Height-driven sand on shores ---
	var sand_color := Blocks.color_of(Blocks.SAND)
	var sand_blend := 0.0
	if world_y < SAND_HEIGHT:
		sand_blend = clampf((SAND_HEIGHT - world_y) / BEACH_BLEND_RANGE, 0.0, 1.0)

	# --- Compose ---
	var col := base

	# Sand shore overrides lower terrain
	col = col.lerp(sand_color, sand_blend)

	# Snow on peaks (after sand so peaks stay white even above beaches)
	col = col.lerp(snow_color, snow_blend)

	# Stone shows on steep slopes
	col = col.lerp(stone_color, stone_blend)

	# Deep-down shading — darker with depth
	var depth := clampf((world_y - 4.0) / 30.0, 0.0, 1.0)
	var depth_darken := lerpf(0.75, 1.0, depth)
	col = Color(col.r * depth_darken, col.g * depth_darken, col.b * depth_darken)

	# Subtle per-vertex noise for organic look (very small)
	var n := sin(local_pos.x * 12.9898 + local_pos.y * 78.233 + local_pos.z * 37.719) * 0.5 + 0.5
	var jitter := lerpf(0.94, 1.06, n)
	col = Color(col.r * jitter, col.g * jitter, col.b * jitter)

	return col


# ============================================================
#	Player editing — smooth crater
# ============================================================

# Dig at a world position: drop density in a sphere, smooth falloff.
func dig_at_world(wx: float, wy: float, wz: float, radius: float, strength: float) -> void:
	_modify_sphere(wx, wy, wz, radius, -strength)
	rebuild_mesh()


# Place solid material at a world position: raise density in a sphere.
func place_at_world(wx: float, wy: float, wz: float, radius: float, mat_id: int) -> void:
	_modify_sphere(wx, wy, wz, radius, 1.0)
	# Also set the material in the sphere so new terrain colors correctly
	_set_material_sphere(wx, wy, wz, radius * 0.75, mat_id)
	rebuild_mesh()


func _modify_sphere(wx: float, wy: float, wz: float, radius: float, delta: float) -> void:
	var origin := global_position
	var local_c := Vector3(wx - origin.x, wy - origin.y, wz - origin.z)
	var r_sq := radius * radius

	var min_x := int(floor(local_c.x - radius)) - 1
	var max_x := int(ceil(local_c.x + radius)) + 1
	var min_y := int(floor(local_c.y - radius)) - 1
	var max_y := int(ceil(local_c.y + radius)) + 1
	var min_z := int(floor(local_c.z - radius)) - 1
	var max_z := int(ceil(local_c.z + radius)) + 1

	min_x = max(min_x, 0)
	min_y = max(min_y, 0)
	min_z = max(min_z, 0)
	max_x = min(max_x, SAMPLES_X - 1)
	max_y = min(max_y, SAMPLES_Y - 1)
	max_z = min(max_z, SAMPLES_Z - 1)

	for sz in range(min_z, max_z + 1):
		for sy in range(min_y, max_y + 1):
			for sx in range(min_x, max_x + 1):
				var p := Vector3(sx, sy, sz)
				var d_sq := p.distance_squared_to(local_c)
				if d_sq > r_sq:
					continue
				var falloff := 1.0 - sqrt(d_sq) / radius
				falloff = falloff * falloff
				var cur := get_density_local(sx, sy, sz)
				set_density_local(sx, sy, sz, cur + delta * falloff)


func _set_material_sphere(wx: float, wy: float, wz: float, radius: float, mat_id: int) -> void:
	var origin := global_position
	var local_c := Vector3(wx - origin.x, wy - origin.y, wz - origin.z)
	var r_sq := radius * radius

	for sz in SAMPLES_Z:
		for sy in SAMPLES_Y:
			for sx in SAMPLES_X:
				var p := Vector3(sx, sy, sz)
				if p.distance_squared_to(local_c) <= r_sq:
					set_material_local(sx, sy, sz, mat_id)