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
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	col.shape = cap
	add_child(col)

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

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 1.6, 0)
	add_child(head)

	fps_camera = Camera3D.new()
	fps_camera.name = "FPS_Camera"
	head.add_child(fps_camera)

	tp_camera = Camera3D.new()
	tp_camera.name = "TP_Camera"
	tp_camera.position = Vector3(0, 0, TP_CAM_DISTANCE)
	head.add_child(tp_camera)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			rotate_y(-motion.relative.x * MOUSE_SENS)
			var new_pitch: float = head.rotation.x - motion.relative.y * MOUSE_SENS
			head.rotation.x = clamp(new_pitch, -PITCH_MAX, PITCH_MAX)

	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			match k.keycode:
				KEY_V:
					is_tps = not is_tps
					_apply_camera_mode()
				KEY_ESCAPE:
					if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
						Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
					else:
						Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


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

	if Input.is_key_pressed(KEY_SPACE) and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_x := 0.0
	var input_z := 0.0

	if Input.is_key_pressed(KEY_Z):
		input_z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_z += 1.0
	if Input.is_key_pressed(KEY_Q):
		input_x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input_x += 1.0

	var input_dir := Vector2(input_x, input_z).normalized()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := WALK_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= SPRINT_MULT

	if direction.length_squared() > 0.01:
		velocity.x = move_toward(velocity.x, direction.x * speed, ACCEL * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0.0, FRICTION * delta)

	move_and_slide()