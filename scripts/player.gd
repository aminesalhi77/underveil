class_name Player
extends CharacterBody3D

const WALK_SPEED := 5.0
const SPRINT_MULT := 1.8
const JUMP_VELOCITY := 5.5
const GRAVITY := 18.0
const MOUSE_SENS := 0.0025
const ACCEL := 60.0
const FRICTION := 80.0
const PITCH_MAX := 1.4
const TP_CAM_DISTANCE := 4.5

var head: Node3D
var mesh: MeshInstance3D
var fps_camera: Camera3D
var tp_camera: Camera3D
var is_tps := true


func _ready() -> void:
	_build()
	_apply_camera_mode()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _build() -> void:
	# Collision capsule
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	col.shape = cap
	add_child(col)

	# Visible mesh (hidden in first-person)
	mesh = MeshInstance3D.new()
	var cap_mesh := CapsuleMesh.new()
	cap_mesh.radius = 0.5
	cap_mesh.height = 1.8
	mesh.mesh = cap_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.5, 0.85)
	mat.roughness = 0.6
	mesh.material_override = mat
	add_child(mesh)

	# Head pivot (both cameras attach here, pitch rotates this)
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	add_child(head)

	# First-person camera at eye level
	fps_camera = Camera3D.new()
	fps_camera.name = "FPS_Camera"
	head.add_child(fps_camera)

	# Third-person camera placed behind the player
	tp_camera = Camera3D.new()
	tp_camera.name = "TP_Camera"
	tp_camera.position = Vector3(0, 0, TP_CAM_DISTANCE)
	head.add_child(tp_camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENS)
		var new_pitch := head.rotation.x - event.relative.y * MOUSE_SENS
		head.rotation.x = clamp(new_pitch, -PITCH_MAX, PITCH_MAX)

	if event.is_action_pressed("ui_cancel"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	if event.is_action_pressed("toggle_camera"):
		is_tps = not is_tps
		_apply_camera_mode()


func _apply_camera_mode() -> void:
	if is_tps:
		fps_camera.current = false
		tp_camera.current = true
		mesh.visible = true
	else:
		fps_camera.current = true
		tp_camera.current = false
		mesh.visible = false


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	)
	input_dir = input_dir.normalized()

	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := WALK_SPEED
	if Input.is_action_pressed("sprint"):
		speed *= SPRINT_MULT

	if direction.length_squared() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * speed, ACCEL * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	move_and_slide()