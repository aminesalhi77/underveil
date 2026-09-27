extends Node3D

# ============================================================
#	Underveil — main scene
# ============================================================
#	Boots the world, sky, moonlight, player, and HUD.
#	Order matters: world must finish generating before we can
#	ask it for a spawn point.
# ============================================================

var world: World
var player: Player
var night_sky: NightSky
var moon_light: DirectionalLight3D
var hud_label: Label


func _ready() -> void:
	_build_world()
	_build_sky_and_light()
	_build_player()
	_build_hud()
	print("[Main] boot complete")


# ============================================================
#	World
# ============================================================

func _build_world() -> void:
	world = World.new()
	world.name = "World"
	add_child(world)
	# World._ready() runs synchronously during add_child — generation
	# completes before this function returns.


# ============================================================
#	Sky + moonlight
# ============================================================

func _build_sky_and_light() -> void:
	night_sky = NightSky.create(7717)

	var env := Environment.new()
	night_sky.install(env)

	# Add a soft fog so distant terrain fades naturally
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.14, 0.26)
	env.fog_light_energy = 1.0
	env.fog_density = 0.008
	env.fog_sky_affect = 0.4

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# Moon light — main shadow caster
	moon_light = DirectionalLight3D.new()
	moon_light.name = "MoonLight"
	var md := night_sky.moon_direction()
	moon_light.position = md * 60.0
	moon_light.look_at_from_position(md * 60.0, Vector3.ZERO, Vector3.UP)
	moon_light.light_color = Color(0.82, 0.86, 1.0)
	moon_light.light_energy = 1.15
	moon_light.shadow_enabled = true
	moon_light.shadow_bias = 0.03
	moon_light.shadow_normal_bias = 0.6
	moon_light.directional_shadow_max_distance = 90.0
	moon_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	moon_light.directional_shadow_split_1 = 0.08
	moon_light.directional_shadow_split_2 = 0.20
	moon_light.directional_shadow_split_3 = 0.45
	add_child(moon_light)

	# Fill light — soft bounce from the opposite side, no shadows
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(-30, 20, -30)
	fill.look_at_from_position(Vector3(-30, 20, -30), Vector3.ZERO, Vector3.UP)
	fill.light_color = Color(0.42, 0.52, 0.78)
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)


# ============================================================
#	Player
# ============================================================

func _build_player() -> void:
	var spawn := world.get_spawn_point()
	print("[Main] spawn point: ", spawn)
	player = Player.new()
	player.name = "Player"
	player.position = spawn
	add_child(player)


# ============================================================
#	HUD
# ============================================================

func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"

	hud_label = Label.new()
	hud_label.name = "FPSLabel"
	hud_label.position = Vector2(20, 20)
	hud_label.add_theme_font_size_override("font_size", 16)
	hud_label.add_theme_color_override("font_color", Color(1, 1, 1))
	hud_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hud_label.add_theme_constant_override("outline_size", 4)
	hud_label.text = "FPS: --"
	canvas.add_child(hud_label)

	add_child(canvas)

	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(_update_fps)
	add_child(timer)


func _update_fps() -> void:
	hud_label.text = "FPS: %d" % Engine.get_frames_per_second()