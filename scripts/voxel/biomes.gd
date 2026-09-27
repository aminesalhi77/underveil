class_name Biomes
extends RefCounted

# ============================================================
#	Biome system
# ============================================================
#	Each biome defines terrain shape, surface appearance, and
#	which trees grow on it.
# ============================================================

enum Type {
	PLAINS,
	FOREST,
	DESERT,
	MOUNTAINS,
	TUNDRA,
	SWAMP,
	BEACH,
}

# ------------------------------------------------------------
#	Terrain shape
# ------------------------------------------------------------

const BASE_HEIGHT := {
	Type.PLAINS: 22.0,
	Type.FOREST: 23.0,
	Type.DESERT: 20.0,
	Type.MOUNTAINS: 32.0,
	Type.TUNDRA: 22.0,
	Type.SWAMP: 19.0,
	Type.BEACH: 18.0,
}

const AMPLITUDE := {
	Type.PLAINS: 3.5,
	Type.FOREST: 4.5,
	Type.DESERT: 3.0,
	Type.MOUNTAINS: 26.0,
	Type.TUNDRA: 4.0,
	Type.SWAMP: 2.0,
	Type.BEACH: 1.2,
}

const RIDGE_AMOUNT := {
	Type.PLAINS: 0.0,
	Type.FOREST: 0.0,
	Type.DESERT: 0.0,
	Type.MOUNTAINS: 14.0,
	Type.TUNDRA: 1.5,
	Type.SWAMP: 0.0,
	Type.BEACH: 0.0,
}

const DETAIL_FREQ := {
	Type.PLAINS: 0.9,
	Type.FOREST: 1.0,
	Type.DESERT: 0.7,
	Type.MOUNTAINS: 1.6,
	Type.TUNDRA: 1.0,
	Type.SWAMP: 0.5,
	Type.BEACH: 0.6,
}

# ------------------------------------------------------------
#	Ground colors
# ------------------------------------------------------------

const SURFACE_COLOR := {
	Type.PLAINS: Color(0.34, 0.58, 0.24),
	Type.FOREST: Color(0.24, 0.46, 0.18),
	Type.DESERT: Color(0.86, 0.76, 0.50),
	Type.MOUNTAINS: Color(0.48, 0.46, 0.44),
	Type.TUNDRA: Color(0.88, 0.92, 0.96),
	Type.SWAMP: Color(0.28, 0.40, 0.22),
	Type.BEACH: Color(0.84, 0.78, 0.58),
}

const DEEP_COLOR := {
	Type.PLAINS: Color(0.30, 0.22, 0.14),
	Type.FOREST: Color(0.26, 0.18, 0.12),
	Type.DESERT: Color(0.55, 0.44, 0.28),
	Type.MOUNTAINS: Color(0.30, 0.28, 0.26),
	Type.TUNDRA: Color(0.40, 0.34, 0.28),
	Type.SWAMP: Color(0.22, 0.20, 0.14),
	Type.BEACH: Color(0.60, 0.52, 0.36),
}

const SLOPE_COLOR := Color(0.42, 0.38, 0.34)

const SNOW_Y := 40.0
const SNOW_COLOR := Color(0.94, 0.96, 1.00)

const SHORE_Y := 20.0
const SHORE_COLOR := Color(0.82, 0.76, 0.56)

# ------------------------------------------------------------
#	Trees
# ------------------------------------------------------------

const TREE_DENSITY := {
	Type.PLAINS: 0.010,
	Type.FOREST: 0.070,
	Type.DESERT: 0.004,
	Type.MOUNTAINS: 0.000,
	Type.TUNDRA: 0.014,
	Type.SWAMP: 0.030,
	Type.BEACH: 0.012,
}

# 0=OAK, 1=PINE, 2=PALM, 3=DEAD
const TREE_KIND := {
	Type.PLAINS: 0,
	Type.FOREST: 0,
	Type.DESERT: 3,
	Type.MOUNTAINS: 1,
	Type.TUNDRA: 1,
	Type.SWAMP: 0,
	Type.BEACH: 2,
}

# ============================================================
#	Biome selection
# ============================================================

static func pick(temp: float, humid: float) -> int:
	if temp < -0.35:
		return Type.TUNDRA
	if temp > 0.30 and humid < -0.15:
		return Type.DESERT
	if humid > 0.40 and temp > -0.10 and temp < 0.35:
		return Type.SWAMP
	if humid > 0.08:
		return Type.FOREST
	return Type.PLAINS


static func override_for_height(biome: int, surface_y: float) -> int:
	if surface_y > 38.0:
		return Type.MOUNTAINS
	return biome


# ============================================================
#	Convenience getters
# ============================================================

static func base_height(biome: int) -> float:
	return float(BASE_HEIGHT[biome])

static func amplitude(biome: int) -> float:
	return float(AMPLITUDE[biome])

static func ridge_amount(biome: int) -> float:
	return float(RIDGE_AMOUNT[biome])

static func detail_freq(biome: int) -> float:
	return float(DETAIL_FREQ[biome])

static func tree_density(biome: int) -> float:
	return float(TREE_DENSITY[biome])

static func tree_kind(biome: int) -> int:
	return int(TREE_KIND[biome])

static func surface_color(biome: int) -> Color:
	return SURFACE_COLOR[biome] as Color

static func deep_color(biome: int) -> Color:
	return DEEP_COLOR[biome] as Color


# ============================================================
#	Vertex-level color composition
# ============================================================
#	Called by chunk._vertex_color for each generated mesh vertex.
#	Explicit Color types everywhere because Dictionary lookups
#	return Variant.
# ============================================================

static func compose_vertex_color(
	biome: int,
	world_y: float,
	normal_y: float,
	depth_factor: float,
	seed_jitter: float,
) -> Color:
	var surface: Color = SURFACE_COLOR.get(biome, Color.WHITE) as Color
	var deep: Color = DEEP_COLOR.get(biome, Color.BLACK) as Color

	var col: Color = surface.lerp(deep, clampf(depth_factor, 0.0, 1.0))

	var slope_blend: float = 0.0
	if normal_y < 0.60:
		slope_blend = clampf((0.60 - normal_y) / 0.35, 0.0, 1.0)
	col = col.lerp(SLOPE_COLOR, slope_blend)

	if world_y < SHORE_Y:
		var shore_blend: float = clampf((SHORE_Y - world_y) / 2.5, 0.0, 1.0)
		shore_blend *= clampf(normal_y, 0.0, 1.0)
		col = col.lerp(SHORE_COLOR, shore_blend)

	if world_y > SNOW_Y:
		var snow_blend: float = clampf((world_y - SNOW_Y) / 6.0, 0.0, 1.0)
		snow_blend *= clampf(normal_y * 1.2, 0.0, 1.0)
		col = col.lerp(SNOW_COLOR, snow_blend)

	var jitter: float = lerpf(0.92, 1.08, seed_jitter)
	col = Color(col.r * jitter, col.g * jitter, col.b * jitter)

	return col