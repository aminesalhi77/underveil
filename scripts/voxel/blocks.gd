class_name Blocks
extends RefCounted

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const WOOD := 4
const LEAVES := 5

const COLORS := {
	AIR: Color(0, 0, 0, 0),
	GRASS: Color(0.30, 0.55, 0.20),
	DIRT: Color(0.42, 0.28, 0.18),
	STONE: Color(0.45, 0.45, 0.48),
	WOOD: Color(0.35, 0.22, 0.12),
	LEAVES: Color(0.22, 0.42, 0.20),
}


static func is_solid(id: int) -> bool:
	return id != AIR


static func color_of(id: int) -> Color:
	return COLORS.get(id, Color.MAGENTA)