extends Node3D


func _ready() -> void:
	_build_environment()
	_build_world()
	_build_player()
	_build_hud()


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.09, 0.20)
	sky_mat.sky_horizon_color = Color(0.20, 0.26, 0.42)
	sky_mat.ground_bottom_color = Color(0.03, 0.04, 0.08)
	sky_mat.ground_horizon_color = Color(0.12, 0.15, 0.24)
	sky.sky_material = sky_mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.position = Vector3(30, 40, 20)
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_color = Color(0.9, 0.92, 1.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	add_child(sun)


func _build_world() -> void:
	var w := World.new()
	w.name = "World"
	add_child(w)


func _build_player() -> void:
	var player := Player.new()
	player.name = "Player"
	player.position = Vector3(40, 30, 40)
	add_child(player)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "HUD"

	var label := Label.new()
	label.name = "FPSLabel"
	label.position = Vector2(20, 20)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.text = "FPS: --"
	canvas.add_child(label)

	add_child(canvas)

	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(func(): label.text = "FPS: %d" % Engine.get_frames_per_second())
	add_child(timer)