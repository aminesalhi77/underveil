class_name NightSky
extends RefCounted

# ============================================================
#	Night sky factory
# ============================================================
#	Builds a Sky resource with:
#	  - shader-driven gradient dome (deep navy top → warm horizon)
#	  - procedural star field (2000 points, tinted, twinkling)
#	  - moon disk with soft glow halo
#
#	Call install(env) to attach the sky to a WorldEnvironment.
#	Call moon_direction() to point a DirectionalLight at the moon.
# ============================================================

const STAR_COUNT := 2000
const DOME_RADIUS := 400.0
const MOON_RADIUS := 6.0
const MOON_DISTANCE := 320.0

var sky_resource: Sky
var moon_dir: Vector3


# ============================================================
#	Public
# ============================================================

static func create(seed_value: int = 0) -> NightSky:
	var s := NightSky.new()
	s._build(seed_value)
	return s


func install(env: Environment) -> void:
	env.background_mode = Environment.BG_SKY
	env.sky = sky_resource
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0


func moon_direction() -> Vector3:
	return moon_dir


# ============================================================
#	Build
# ============================================================

func _build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else 918273

	var sky_material := ShaderMaterial.new()
	sky_material.shader = _gradient_shader()
	sky_material.set_shader_parameter("top_color", Color(0.02, 0.03, 0.08))
	sky_material.set_shader_parameter("mid_color", Color(0.05, 0.08, 0.18))
	sky_material.set_shader_parameter("bottom_color", Color(0.10, 0.14, 0.26))
	sky_material.set_shader_parameter("horizon_tint", Color(0.22, 0.26, 0.42))
	sky_material.set_shader_parameter("horizon_power", 2.5)
	sky_material.set_shader_parameter("star_density", 0.6)
	sky_material.set_shader_parameter("star_seed", float(rng.randi() % 10000))

	var sky_res := Sky.new()
	sky_res.sky_material = sky_material
	sky_res.radiance_size = Sky.RADIANCE_SIZE_128
	sky_resource = sky_res

	# Compute moon direction — high in the sky, slightly behind the player
	var azimuth := rng.randf_range(0.0, TAU)
	var elevation := rng.randf_range(0.55, 0.85)
	moon_dir = Vector3(
		cos(azimuth) * cos(elevation),
		sin(elevation),
		sin(azimuth) * cos(elevation),
	).normalized()
	sky_material.set_shader_parameter("moon_dir", moon_dir)
	sky_material.set_shader_parameter("moon_color", Color(0.98, 0.96, 0.88))
	sky_material.set_shader_parameter("moon_size", 0.035)
	sky_material.set_shader_parameter("moon_glow", 0.45)


# ============================================================
#	Shader — sky dome with stars and moon, all procedural
# ============================================================

func _gradient_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.02, 0.03, 0.08);
uniform vec3 mid_color : source_color = vec3(0.05, 0.08, 0.18);
uniform vec3 bottom_color : source_color = vec3(0.10, 0.14, 0.26);
uniform vec3 horizon_tint : source_color = vec3(0.22, 0.26, 0.42);
uniform float horizon_power : hint_range(0.5, 6.0) = 2.5;

uniform float star_density : hint_range(0.0, 1.0) = 0.6;
uniform float star_seed = 42.0;

uniform vec3 moon_dir = vec3(0.0, 0.8, -0.5);
uniform vec3 moon_color : source_color = vec3(0.98, 0.96, 0.88);
uniform float moon_size : hint_range(0.001, 0.2) = 0.035;
uniform float moon_glow : hint_range(0.0, 2.0) = 0.45;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float stars(vec3 dir, float density) {
	float above = smoothstep(-0.10, 0.05, dir.y);
	if (above < 0.001) return 0.0;

	vec2 uv = vec2(atan(dir.z, dir.x), asin(clamp(dir.y, -1.0, 1.0)));
	uv *= 4.0;

	vec2 cell = floor(uv * 12.0 + star_seed);
	float h = hash21(cell);
	if (h > density) return 0.0;

	vec2 lp = fract(uv * 12.0 + star_seed);
	vec2 star_pos = vec2(hash21(cell + 1.0), hash21(cell + 2.0));
	float d = length(lp - star_pos);

	float tw = 0.6 + 0.4 * vnoise(uv * 4.0 + TIME * 0.6 + star_seed);
	float size = mix(0.012, 0.025, hash21(cell + 3.0));
	float b = smoothstep(size, 0.0, d) * tw;

	float bright = smoothstep(0.85, 1.0, hash21(cell + 4.0));
	b += smoothstep(size * 2.5, 0.0, d) * bright * 0.4;

	return b;
}

void sky() {
	float y = EYEDIR.y;
	float up = smoothstep(0.0, 0.7, y);
	vec3 col = mix(bottom_color, mid_color, smoothstep(-0.2, 0.35, y));
	col = mix(col, top_color, up);

	float horizon = pow(max(0.0, 1.0 - abs(y) * 3.0), horizon_power);
	col = mix(col, horizon_tint, horizon * 0.6);

	float md = dot(EYEDIR, normalize(moon_dir));
	if (md > 0.0) {
		float disk = smoothstep(1.0 - moon_size, 1.0 - moon_size * 0.55, md);
		vec3 tangent = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		vec3 bitangent = cross(moon_dir, tangent);
		vec2 muv = vec2(dot(EYEDIR, tangent), dot(EYEDIR, bitangent)) * 40.0;
		float crater = vnoise(muv) * 0.35 + 0.65;
		vec3 moon_col = moon_color * crater;

		float halo = pow(max(0.0, md), 32.0) * moon_glow;
		col += moon_color * halo * 0.5;

		col = mix(col, moon_col, disk);

		float rim = smoothstep(1.0 - moon_size * 0.65, 1.0 - moon_size * 0.35, md)
			- smoothstep(1.0 - moon_size * 0.35, 1.0 - moon_size * 0.20, md);
		col += moon_color * rim * 0.4;
	}

	float s = stars(EYEDIR, star_density);
	vec3 star_tint = mix(vec3(0.85, 0.90, 1.0), vec3(1.0, 0.94, 0.82), hash21(vec2(star_seed, 7.7)));
	col += star_tint * s;

	col += vec3(0.01, 0.02, 0.04) * up;

	COLOR = col;
}
"""
	return sh