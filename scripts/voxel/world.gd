class_name World
extends Node3D

const CHUNKS_X := 5
const CHUNKS_Z := 5

var chunks: Dictionary = {}
var noise: FastNoiseLite


func _ready() -> void:
	noise = FastNoiseLite.new()
	noise.seed = 12345
	noise.frequency = 0.04
	noise.fractal_octaves = 4
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	_generate()


func _generate() -> void:
	for cz in CHUNKS_Z:
		for cx in CHUNKS_X:
			_generate_chunk(cx, cz)


func _generate_chunk(cx: int, cz: int) -> void:
	var chunk := Chunk.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	chunk.position = Vector3(cx * Chunk.SIZE, 0, cz * Chunk.SIZE)
	add_child(chunk)

	for lz in Chunk.SIZE:
		for lx in Chunk.SIZE:
			var wx := cx * Chunk.SIZE + lx
			var wz := cz * Chunk.SIZE + lz
			var n := noise.get_noise_2d(float(wx), float(wz))
			var h := int(n * 6.0 + 12.0)
			for ly in Chunk.SIZE:
				var id := 0
				if ly > h:
					id = Blocks.AIR
				elif ly == h:
					id = Blocks.GRASS
				elif ly > h - 4:
					id = Blocks.DIRT
				else:
					id = Blocks.STONE
				chunk.set_voxel(lx, ly, lz, id)

	chunk.rebuild_mesh()
	chunks[Vector2i(cx, cz)] = chunk


func get_voxel_world(wx: int, wy: int, wz: int) -> int:
	var cx := int(floor(float(wx) / float(Chunk.SIZE)))
	var cz := int(floor(float(wz) / float(Chunk.SIZE)))
	var chunk: Chunk = chunks.get(Vector2i(cx, cz))
	if chunk == null:
		return 0
	var lx := wx - cx * Chunk.SIZE
	var lz := wz - cz * Chunk.SIZE
	if wy < 0 or wy >= Chunk.SIZE:
		return 0
	return chunk.get_voxel(lx, wy, lz)