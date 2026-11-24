extends CharacterBody3D
## One player. Phase 1: the local player's movement and cameras, using the web game's numbers so it feels the same:
## run 12.7 m/s (x1.2 with fists out), ground acceleration 70, air 28, gravity 36 (x1.2 falling), jump 12,
## a double jump for 15 stamina, crouch, 0.55 m step-up onto stairs and kerbs, ladders. Bots reuse this script later.

const RADIUS := 0.45
const HEIGHT := 2.25
const CROUCH_HEIGHT := 1.45
const RUN := 11.25 * 1.125
const FISTS_MUL := 1.2
const CROUCH_MUL := 0.5
const ACC_GROUND := 70.0
const ACC_AIR := 28.0
const GRAV := 36.0
const JUMP := 12.0
const STEP := 0.55
const LADDER_SPEED := 6.0
const STAM_MAX := 100.0
const DJ_COST := 15.0
const STAM_REGEN := 40.0
const STAM_DELAY := 0.5
const EYE := 2.0
const EYE_CROUCH := 1.3

var yaw := 0.0     # web convention: facing (sin yaw, 0, cos yaw)
var pitch := 0.0
var crouching := false
var stamina := STAM_MAX
var stam_rest := 0.0
var air_jumps := 1
var ladders: Array[AABB] = []
var on_ladder := false
var is_player := true

var _shape: CapsuleShape3D
var _body_mesh: MeshInstance3D
var _pivot: Node3D
var _arm: SpringArm3D
var cam: Camera3D
var _eye := EYE
var _jump_held := false

func _ready() -> void:
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = HEIGHT
	var cs := CollisionShape3D.new()
	cs.shape = _shape
	cs.position.y = HEIGHT * 0.5
	cs.name = "Shape"
	add_child(cs)
	# grey capsule figure with a coloured band (you = blue)
	_body_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = RADIUS
	cm.height = HEIGHT
	_body_mesh.mesh = cm
	_body_mesh.position.y = HEIGHT * 0.5
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.72, 0.72, 0.74)
	_body_mesh.material_override = bm
	add_child(_body_mesh)
	var band := MeshInstance3D.new()
	var bandm := CylinderMesh.new()
	bandm.top_radius = RADIUS + 0.02
	bandm.bottom_radius = RADIUS + 0.02
	bandm.height = 0.16
	band.mesh = bandm
	var bandmat := StandardMaterial3D.new()
	bandmat.albedo_color = Color(0.18, 0.5, 0.88) if is_player else Color(0.91, 0.27, 0.23)
	band.material_override = bandmat
	band.position.y = HEIGHT * 0.62
	_body_mesh.add_child(band)
	band.position = Vector3(0, HEIGHT * 0.12, 0)
	var visor := MeshInstance3D.new()   # a dark visor so you can see which way a figure faces
	var vm := BoxMesh.new()
	vm.size = Vector3(0.5, 0.16, 0.2)
	visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.12, 0.12, 0.14)
	visor.material_override = vmat
	visor.position = Vector3(0, HEIGHT * 0.33, RADIUS - 0.04)
	_body_mesh.add_child(visor)
	# camera rig: pivot at the eyes, spring arm for the third person view (pulls in when a wall is behind you)
	_pivot = Node3D.new()
	_pivot.position.y = EYE
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = 1
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	cam = Camera3D.new()
	cam.current = is_player
	cam.near = 0.05
	_arm.add_child(cam)
	floor_snap_length = STEP + 0.1
	floor_max_angle = deg_to_rad(50)
	apply_camera_mode()

func apply_camera_mode() -> void:
	var fp := Settings.camera_mode == "first"
	_arm.spring_length = 0.0 if fp else 4.2
	_arm.position = Vector3.ZERO if fp else Vector3(0.9, 0.55, 0)   # over the right shoulder
	_body_mesh.visible = not fp
	cam.fov = Settings.fov

func place(p: Vector3, y: float) -> void:
	global_position = p
	yaw = y
	pitch = 0.0
	velocity = Vector3.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if not is_player:
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0006 * (0.5 + Settings.sensitivity * 0.25)
		yaw -= e.relative.x * s
		pitch = clamp(pitch - e.relative.y * s, -1.45, 1.45)
	if e.is_action_pressed("camera_toggle"):
		Settings.camera_mode = "first" if Settings.camera_mode == "third" else "third"
		Settings.save()
		apply_camera_mode()
	if e.is_action_pressed("crouch"):
		_set_crouch(not crouching)

func _set_crouch(on: bool) -> void:
	if not on and crouching:   # only stand up if there's room above
		var t := global_transform
		if test_move(t, Vector3.UP * (HEIGHT - CROUCH_HEIGHT)):
			return
	crouching = on
	_shape.height = CROUCH_HEIGHT if on else HEIGHT
	get_node("Shape").position.y = _shape.height * 0.5

func forward() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))

func right() -> Vector3:
	return Vector3(-cos(yaw), 0, sin(yaw))

func _physics_process(dt: float) -> void:
	var mv := Vector2.ZERO
	var jump := false
	var jump_press := false
	if is_player:
		mv = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		jump = Input.is_action_pressed("jump")
		jump_press = jump and not _jump_held
		_jump_held = jump
	var wish := (forward() * mv.y + right() * mv.x)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var grounded := is_on_floor()
	if grounded:
		air_jumps = 1
	# ladders: inside a ladder zone and pushing forward = climb
	on_ladder = false
	var feet := global_position
	for l in ladders:
		if l.grow(0.55).has_point(feet + Vector3.UP * 0.6) or l.grow(0.55).has_point(feet + Vector3.UP * 1.6):
			on_ladder = true
			break
	var speed := RUN * FISTS_MUL * (CROUCH_MUL if crouching else 1.0)
	var target := wish * speed
	var acc := ACC_GROUND if grounded else ACC_AIR
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(target, acc * dt)
	velocity.x = hv.x
	velocity.z = hv.z
	if on_ladder and mv.y > 0.1:
		velocity.y = LADDER_SPEED
	elif on_ladder and mv.y < -0.1 and not grounded:
		velocity.y = -LADDER_SPEED
	elif on_ladder and not grounded:
		velocity.y = 0.0
	else:
		if jump_press and crouching:
			_set_crouch(false)
		if jump_press and grounded:
			velocity.y = JUMP
		elif jump_press and not grounded and air_jumps > 0 and stamina >= DJ_COST:
			velocity.y = max(velocity.y, JUMP * 1.05)
			air_jumps -= 1
			stamina -= DJ_COST
			stam_rest = 0.0
		if not grounded:
			velocity.y -= GRAV * dt * (1.2 if velocity.y < 0 else 1.0)
	# stamina comes back after a short rest
	stam_rest += dt
	if stam_rest > STAM_DELAY:
		stamina = min(STAM_MAX, stamina + STAM_REGEN * dt)
	var before := global_position
	move_and_slide()
	_step_up(before, hv * dt, grounded)
	# camera
	_eye = lerp(_eye, EYE_CROUCH if crouching else EYE, min(1.0, dt * 12.0))
	_pivot.position.y = _eye
	_pivot.rotation = Vector3(pitch, yaw + PI, 0)
	_body_mesh.rotation.y = yaw

## stairs and kerbs up to 0.55 m: if we ran into something low while walking, try the same move from 0.55 m higher
func _step_up(before: Vector3, motion: Vector3, was_grounded: bool) -> void:
	if not was_grounded or motion.length() < 0.001 or not is_on_wall():
		return
	var moved := (global_position - before)
	moved.y = 0
	if moved.length() > motion.length() * 0.6:
		return
	var t := global_transform
	t.origin = before
	if test_move(t, Vector3.UP * STEP):
		return
	t.origin += Vector3.UP * STEP
	if test_move(t, motion):
		return
	global_position = before + Vector3.UP * STEP + motion
	apply_floor_snap()
