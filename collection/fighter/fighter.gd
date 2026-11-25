extends CharacterBody3D
## One player: you, a test dummy, and later every bot. All of them obey the same physics, weapons and rules.
## Movement (phase 1) uses the web game's numbers: run 12.7 m/s (x1.2 with fists or bat out), ground acceleration 70,
## air 28, gravity 36 (x1.2 falling), jump 12, a double jump for 15 stamina, crouch, 0.55 m step-up, ladders.
## Combat (phase 2): 100 HP, regen 10 HP/s after 3 s unhurt; at 0 HP you go down (30 downed HP, crawl, back up on
## your own after 5 s, 15 s bleed-out backstop); finished off = dead; respawn after 3 s with a 2 s spawn shield.
## Weapons: fists or a bat in the melee slot, one picked-up gun (20 bullets, no reload) in the gun slot.
## Whoever drives the fighter (keyboard and mouse, or a brain) fills in in_move / in_jump / in_fire / in_aim.

signal hurt(amount: int, src: Node, head: bool)
signal went_down(src: Node)
signal died(src: Node)
signal got_up
signal respawned
signal dealt_hit(target: Node, amount: int, head: bool, finished: bool)
signal weapon_changed

const Weapons := preload("res://weapons/weapons.gd")
const WeaponModel := preload("res://weapons/weapon_model.gd")
const Effects := preload("res://weapons/effects.gd")
const Sfx := preload("res://audio/sfx.gd")
const CharacterModel := preload("res://characters/character_model.gd")

const RADIUS := 0.45
const HEIGHT := 2.25
const CROUCH_HEIGHT := 1.45
const RUN := 8.5               # Pete, 24 Nov: players and bots were far too fast (was 11.25 x 1.125 = 12.7 m/s)
const FISTS_MUL := 1.2
const CROUCH_MUL := 0.5
const ACC_GROUND := 55.0        # was 70, eased with the slower run
const ACC_AIR := 22.0           # was 28
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
const EYE_DOWN := 0.75

const HP_MAX := 100.0
const DOWN_HP := 30.0
const GET_UP := 5.0
const BLEED := 15.0
const REGEN_DELAY := 3.0
const REGEN_RATE := 10.0
const CRAWL := 3.0
const RESPAWN := 3.0
const SHIELD := 2.0
const SWAP := 0.3
const HEAD_TOP := 0.55          # the top 0.55 m of a standing body counts as the head

const LAYER_WORLD := 1
const LAYER_BODY := 2           # standing players: solid to each other and to bullets
const LAYER_DOWNED := 4         # downed players: bullets hit them, people walk over them
const SHOT_MASK := LAYER_WORLD | LAYER_BODY | LAYER_DOWNED

# who this is
var is_player := true
var display_name := "You"
var band_color := Color(0.18, 0.5, 0.88)
var character := ""              # rigged model id (characters/<id>/); "" = from the display name
var model: Node3D = null         # the rigged, motion-captured body when this character has one (AAA phase 1)
var game: Node = null            # the match (main.gd's CollectionGame node), set before add_child
var home: Variant = null         # test dummies respawn at their own spot: [Vector3, yaw]

# input (filled by the keyboard/mouse for you, by a brain for dummies and bots)
var in_move := Vector2.ZERO
var in_jump := false
var in_fire := false
var in_aim := false
var dmg_mul := 1.0               # bots on Easy deal 30% less damage
var can_headshot := true         # and never land headshots
var force_input := false         # the autotest presses fire without the mouse captured
var autopilot := false
var invulnerable := false        # the autotest's screenshots: nobody can hurt you           # the autotest's bot match: your fighter is driven by a bot brain too

# movement
var yaw := 0.0     # web convention: facing (sin yaw, 0, cos yaw)
var pitch := 0.0
var crouching := false
var stamina := STAM_MAX
var stam_rest := 0.0
var air_jumps := 1
var ladders: Array[AABB] = []
var on_ladder := false
var lifts: Array = []            # lifts and the fireman's pole (level.lifts): ride at 14 m/s, can't steer
var ride := -1                   # the lift being ridden, or -1
var ride_dir := 1
var ride_cd := 0.0               # no getting straight back on for 0.6 s
var clock := 0.0                 # this fighter's own running time (lift, trampoline and portal cooldowns)
var wading := false
var _step_dy := 0.0              # camera lag after a step-up (smooths kerbs, sills and odd steps)
var lift_arm := true             # leave a lift before it takes you again              # in the indoor pool: 20% slower (set by the Mansion features)

# health
var alive := true
var hp := HP_MAX
var downed := false
var dhp := 0.0
var bleed := 0.0
var revive := 0.0
var last_hurt := -99.0
var last_by: Node = null
var respawn_t := 0.0
var shield_t := 0.0
var stars := 0
var marked := false              # 8+ stars: outlined through walls for everyone
var kills := 0
var deaths := 0

# weapons
var gun_id := ""                 # "" = no gun
var ammo := 0
var has_bat := false
var slot := "melee"              # "melee" (fists or bat) or "gun"
var fire_t := 0.0
var swap_t := 0.0
var bloom := 0.0
var ads := false
var ads_k := 0.0                 # 0 = hip, 1 = fully aimed
var dual_left := false
var punch_left := false
var swing_t := 0.0
var kick_t := 0.0
var shots := 0

var _shape: CapsuleShape3D
var _cs: CollisionShape3D
var _body_mesh: MeshInstance3D
var _body_mat: StandardMaterial3D
var _shell: MeshInstance3D
var _shell_mat: StandardMaterial3D
var _pivot: Node3D
var _arm: SpringArm3D
var cam: Camera3D
var _held: Node3D                # weapon in the hand, seen in third person and by everyone else
var _view: Node3D                # first person hands and weapon, on the camera
var _view_model: Node3D
var _held_model: Node3D
var _gloves: Array[MeshInstance3D] = []
var _eye := EYE
var _jump_held := false
var _shown_weapon := "?"
var _look_pad := Vector2.ZERO
var _step_dist := 0.0
var _step_n := 0
var _air_t := 0.0
var _pad_used := false

func _ready() -> void:
	collision_layer = LAYER_BODY
	collision_mask = LAYER_WORLD | LAYER_BODY
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = HEIGHT
	_cs = CollisionShape3D.new()
	_cs.shape = _shape
	_cs.position.y = HEIGHT * 0.5
	_cs.name = "Shape"
	add_child(_cs)
	# grey capsule figure with a coloured band (you = blue, everyone else red)
	_body_mesh = MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = RADIUS
	cm.height = HEIGHT
	_body_mesh.mesh = cm
	_body_mesh.position.y = HEIGHT * 0.5
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = Color(0.72, 0.72, 0.74)
	_body_mesh.material_override = _body_mat
	add_child(_body_mesh)
	var band := MeshInstance3D.new()
	var bandm := CylinderMesh.new()
	bandm.top_radius = RADIUS + 0.02
	bandm.bottom_radius = RADIUS + 0.02
	bandm.height = 0.16
	band.mesh = bandm
	var bandmat := StandardMaterial3D.new()
	bandmat.albedo_color = band_color
	band.material_override = bandmat
	band.position = Vector3(0, HEIGHT * 0.12, 0)
	_body_mesh.add_child(band)
	var visor := MeshInstance3D.new()   # a dark visor so you can see which way a figure faces
	var vm := BoxMesh.new()
	vm.size = Vector3(0.5, 0.16, 0.2)
	visor.mesh = vm
	var vmat := StandardMaterial3D.new()
	vmat.albedo_color = Color(0.12, 0.12, 0.14)
	visor.material_override = vmat
	visor.position = Vector3(0, HEIGHT * 0.33, RADIUS - 0.04)
	_body_mesh.add_child(visor)
	# spawn shield: a faint white shell that fades over 2 s
	_shell = MeshInstance3D.new()
	var sm := CapsuleMesh.new()
	sm.radius = RADIUS + 0.12
	sm.height = HEIGHT + 0.2
	_shell.mesh = sm
	_shell_mat = StandardMaterial3D.new()
	_shell_mat.albedo_color = Color(1, 1, 1, 0.0)
	_shell_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_shell_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_shell_mat.cull_mode = BaseMaterial3D.CULL_BACK
	_shell.material_override = _shell_mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.visible = false
	_body_mesh.add_child(_shell)
	# held weapon in the right hand (body faces +Z, so the right hand is at -X)
	_held = Node3D.new()
	_held.position = Vector3(-0.42, 0.15, 0.32)
	_held.rotation.y = PI    # models point down -Z
	_body_mesh.add_child(_held)
	_make_model()
	# camera rig: pivot at the eyes, spring arm for the third person view (pulls in when a wall is behind you)
	_pivot = Node3D.new()
	_pivot.position.y = EYE
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.collision_mask = LAYER_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	cam = Camera3D.new()
	cam.current = is_player
	cam.near = 0.05
	_arm.add_child(cam)
	# first person hands: boxing gloves in your colour, and the gun
	_view = Node3D.new()
	cam.add_child(_view)
	for side in [-1.0, 1.0]:
		var gl := MeshInstance3D.new()
		var gs := SphereMesh.new()
		gs.radius = 0.05
		gs.height = 0.1
		gl.mesh = gs
		var gmat := StandardMaterial3D.new()
		gmat.albedo_color = band_color
		gmat.roughness = 0.45
		gl.material_override = gmat
		gl.scale = Vector3(1.0, 0.95, 1.25)
		gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		gl.position = Vector3(0.17 * side, -0.19, -0.48)
		_view.add_child(gl)
		_gloves.append(gl)
	# other players are never a moving floor: standing on someone who respawns or gets moved must not launch you
	platform_floor_layers = LAYER_WORLD
	platform_wall_layers = 0
	platform_on_leave = CharacterBody3D.PLATFORM_ON_LEAVE_DO_NOTHING
	floor_snap_length = STEP + 0.1
	floor_max_angle = deg_to_rad(50)
	apply_camera_mode()
	_refresh_weapon_models()

# ---------------------------------------------------------------- views and models

## the rigged character, if this one has been built (characters/<id>/<id>.glb); otherwise the grey capsule stays
func _make_model() -> void:
	var cid := character if character != "" else display_name.to_lower().replace(" ", "")
	if not CharacterModel.exists(cid):
		return
	character = cid
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.setup(cid)
	_body_mesh.mesh = null
	for c in _body_mesh.get_children():
		if c != _shell and c != _held:
			c.queue_free()

func apply_camera_mode() -> void:
	var fp := Settings.camera_mode == "first" and not downed and is_player
	_arm.spring_length = 0.0 if fp else 4.2
	_arm.position = Vector3.ZERO if fp else Vector3(0.9, 0.55, 0)   # over the right shoulder
	_body_mesh.visible = (not fp) and alive
	_view.visible = fp and alive and is_player
	if model:
		model.set_shadow_only(fp and alive)
	cam.fov = Settings.fov

func first_person() -> bool:
	return is_player and Settings.camera_mode == "first" and not downed

func current_weapon() -> String:
	if slot == "gun" and gun_id != "":
		return gun_id
	return "bat" if has_bat else "fists"

func _refresh_weapon_models() -> void:
	var id := current_weapon()
	if id == _shown_weapon:
		return
	_shown_weapon = id
	if _held_model:
		_held_model.queue_free()
	if _view_model:
		_view_model.queue_free()
	_held_model = WeaponModel.make(id)
	_held.add_child(_held_model)
	_view_model = WeaponModel.make(id)
	_view.add_child(_view_model)
	for i in _gloves.size():   # gloves show with fists; the right glove also holds a bat; guns hide them
		_gloves[i].visible = id == "fists" or (id == "bat" and i == 1)
	weapon_changed.emit()

## where shots come from: the barrel tip of the visible weapon
func muzzle_pos() -> Vector3:
	var model := _view_model if first_person() else _held_model
	if model:
		var nm := "Muzzle2" if current_weapon() == "duals" and dual_left else "Muzzle"
		var m := model.find_child(nm, true, false)
		if m:
			return (m as Node3D).global_position
	return eye_pos() + aim_forward() * 0.9

func eye_pos() -> Vector3:
	return _pivot.global_position

func aim_forward() -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))

func forward() -> Vector3:
	return Vector3(sin(yaw), 0, cos(yaw))

func right() -> Vector3:
	return Vector3(-cos(yaw), 0, sin(yaw))

func place(p: Vector3, y: float) -> void:
	global_position = p
	yaw = y
	pitch = 0.0
	velocity = Vector3.ZERO

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

# ---------------------------------------------------------------- input (you)

func _unhandled_input(e: InputEvent) -> void:
	if not is_player:
		return
	if e is InputEventMouseMotion or e is InputEventKey:
		_pad_used = false
	elif e is InputEventJoypadButton or e is InputEventJoypadMotion:
		_pad_used = true
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var s := 0.0006 * (0.5 + Settings.sensitivity * 0.25) * (lerpf(1.0, 0.65, ads_k))
		yaw -= e.relative.x * s
		pitch = clamp(pitch - e.relative.y * s, -1.45, 1.45)
	if e.is_action_pressed("camera_toggle"):
		Settings.camera_mode = "first" if Settings.camera_mode == "third" else "third"
		Settings.save()
		apply_camera_mode()
	if e.is_action_pressed("crouch") and not downed:
		_set_crouch(not crouching)
	if e.is_action_pressed("weapon_melee"):
		select_slot("melee")
	elif e.is_action_pressed("weapon_gun"):
		select_slot("gun")
	elif e.is_action_pressed("weapon_next"):
		select_slot("gun" if slot == "melee" else "melee")
	elif e.is_action_pressed("weapon_fists"):
		select_slot("melee")

func _read_player_input(dt: float) -> void:
	in_move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	in_jump = Input.is_action_pressed("jump")
	in_fire = Input.is_action_pressed("fire") and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or force_input)
	in_aim = Input.is_action_pressed("aim")
	# controller right stick looks around
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() > 0.12:
		_pad_used = true
		var r := 2.6 * (0.5 + Settings.sensitivity * 0.15) * lerpf(1.0, 0.6, ads_k)
		yaw -= look.x * r * dt
		pitch = clamp(pitch - look.y * r * 0.7 * dt, -1.45, 1.45)
	_aim_assist(dt)

## controller only, Easy only (plan: "aim assist on Easy"): while you look around with the stick or fire with the
## trigger, your aim drifts gently onto anyone within 8° of it and 40 m away, in sight
func _aim_assist(dt: float) -> void:
	if not _pad_used or Settings.bots != "easy" or game == null:
		return
	var pad_active := Input.get_vector("look_left", "look_right", "look_up", "look_down").length() > 0.12 or Input.get_action_strength("fire") > 0.3
	if not pad_active:
		return
	var eye := eye_pos()
	var fwd := aim_forward()
	var best: Vector3 = Vector3.INF
	var best_a := deg_to_rad(8.0)
	for o in game.fighters:
		if o == self or not o.alive:
			continue
		var tp: Vector3 = o.global_position + Vector3.UP * (0.4 if o.downed else 1.3)
		var d := tp - eye
		if d.length() > 40.0:
			continue
		var a := fwd.angle_to(d.normalized())
		if a < best_a:
			var q := PhysicsRayQueryParameters3D.create(eye, tp, LAYER_WORLD)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				best_a = a
				best = tp
	if best == Vector3.INF:
		return
	var d2 := best - eye
	var want_yaw := atan2(d2.x, d2.z)
	var want_pitch := atan2(d2.y, Vector2(d2.x, d2.z).length())
	yaw += clampf(wrapf(want_yaw - yaw, -PI, PI), -1.2 * dt, 1.2 * dt)
	pitch = move_toward(pitch, want_pitch, 0.8 * dt)

func select_slot(s: String) -> void:
	if s == "gun" and gun_id == "":
		return
	if s == slot:
		return
	slot = s
	var w := Weapons.stat(current_weapon())
	swap_t = float(w.get("swap", SWAP))
	ads = false
	if is_player:
		Sfx.play(get_parent(), "swap", global_position, -8.0, 1.0, 8.0)
	_refresh_weapon_models()

## marked (8+ stars): Godot's X-ray stencil draws the body in red wherever a wall hides it, for everyone
func set_marked(on: bool) -> void:
	if on == marked:
		return
	marked = on
	_body_mat.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY if on else BaseMaterial3D.STENCIL_MODE_DISABLED
	_body_mat.stencil_color = Color(0.91, 0.16, 0.16, 0.85)
	if model:
		model.set_marked(on)

# ---------------------------------------------------------------- pickups

func can_take_gun() -> bool:
	return alive and not downed and not (gun_id != "" and ammo >= Weapons.KEEP_AT)

func can_take_bat() -> bool:
	return alive and not downed and not has_bat

func give_gun(id: String) -> void:
	gun_id = id
	ammo = Weapons.AMMO
	slot = "gun"
	swap_t = float(Weapons.stat(id).get("swap", SWAP))
	_refresh_weapon_models()

func give_bat() -> void:
	has_bat = true
	_refresh_weapon_models()

# ---------------------------------------------------------------- damage

## returns true when this hit put them down or finished them
func take_damage(amount: float, src: Node, head := false, _gun := "") -> bool:
	if not alive or shield_t > 0.0 or invulnerable:
		return false
	var dmg := maxi(1, roundi(amount))
	last_hurt = _now()
	last_by = src
	hurt.emit(dmg, src, head)
	if model and not downed:
		model.hurt(dmg >= 40 or head)   # the bigger flinch for a heavy hit or a headshot
	if downed:
		dhp -= dmg
		if dhp <= 0.0:
			_die(src)
			return true
		return false
	stamina = maxf(0.0, stamina - dmg * 1.2)
	stam_rest = 0.0
	hp = maxf(0.0, hp - dmg)
	if hp <= 0.0:
		_go_down(src)
		return true
	return false

func _go_down(src: Node) -> void:
	downed = true
	dhp = DOWN_HP
	bleed = BLEED
	revive = 0.0
	ads = false
	in_aim = false
	on_ladder = false
	crouching = false
	velocity.x = 0.0
	velocity.z = 0.0
	collision_layer = LAYER_DOWNED
	collision_mask = LAYER_WORLD
	if has_bat:   # the bat drops where you fell
		has_bat = false
		if game:
			game.drop_bat(global_position)
	slot = "gun" if slot == "gun" and gun_id != "" else "melee"
	_refresh_weapon_models()
	Effects.hit_spray(get_parent(), global_position + Vector3.UP * 1.0, Vector3.ZERO, true)
	Sfx.play(get_parent(), "down", global_position, 0.0, 1.0, 30.0)
	apply_camera_mode()
	went_down.emit(src)

func _get_up() -> void:
	downed = false
	hp = maxf(1.0, roundf(dhp))   # back up with whatever downed health was left; regen waits the usual 3 s
	last_hurt = _now()
	revive = 0.0
	collision_layer = LAYER_BODY
	collision_mask = LAYER_WORLD | LAYER_BODY
	_set_pose_standing()
	apply_camera_mode()
	got_up.emit()

func _die(src: Node) -> void:
	alive = false
	downed = false
	deaths += 1
	if src and src != self and "kills" in src:
		src.kills += 1
	collision_layer = 0
	collision_mask = LAYER_WORLD
	velocity = Vector3.ZERO
	respawn_t = RESPAWN
	gun_id = ""
	ammo = 0
	has_bat = false
	slot = "melee"
	ads = false
	_set_pose_standing()
	_refresh_weapon_models()
	Effects.hit_spray(get_parent(), global_position + Vector3.UP * 0.5, Vector3.ZERO, true)
	Sfx.play(get_parent(), "kill", global_position, -2.0, 1.0, 40.0)
	apply_camera_mode()
	died.emit(src)

## back in the game at a new spot, fists only, with a 2 s spawn shield
func respawn_at(p: Vector3, y: float) -> void:
	alive = true
	downed = false
	hp = HP_MAX
	stamina = STAM_MAX
	shield_t = SHIELD
	bloom = 0.0
	collision_layer = LAYER_BODY
	collision_mask = LAYER_WORLD | LAYER_BODY
	ride = -1
	place(p, y)
	_set_pose_standing()
	if model:
		model.restart()
	apply_camera_mode()
	Sfx.play(get_parent(), "respawn", global_position, -4.0, 1.0, 20.0)
	respawned.emit()

func _set_pose_standing() -> void:
	_shape.radius = RADIUS
	_shape.height = CROUCH_HEIGHT if crouching else HEIGHT
	_cs.basis = Basis()
	_cs.position = Vector3(0, _shape.height * 0.5, 0)
	_body_mesh.basis = Basis(Vector3.UP, yaw)
	_body_mesh.position = Vector3(0, HEIGHT * 0.5, 0)

## lying flat: body and collider both turn horizontal along the facing, so a downed player never pokes through walls
func _set_pose_downed() -> void:
	_shape.radius = 0.4
	_shape.height = 1.5
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5)
	_cs.basis = b
	_cs.position = Vector3(0, 0.4, 0)
	_body_mesh.basis = b * Basis.from_scale(Vector3(0.88, 0.66, 0.88))
	_body_mesh.position = Vector3(0, 0.4, 0)

# ---------------------------------------------------------------- attacking

func can_attack() -> bool:
	return alive and not downed and not on_ladder and swap_t <= 0.0

func _attack() -> void:
	var id := current_weapon()
	var g := Weapons.stat(id)
	shield_t = 0.0    # attacking ends your spawn shield
	fire_t = float(g.rate)
	if Weapons.is_melee(id):
		_melee(id, g)
	else:
		_shoot(id, g)

func _melee(id: String, g: Dictionary) -> void:
	swing_t = 0.26
	punch_left = not punch_left
	if model:
		model.attack(id, punch_left)
	var lunge: float = g.lunge
	velocity.x += sin(yaw) * lunge
	velocity.z += cos(yaw) * lunge
	var world := get_parent()
	Sfx.play(world, "fistwhoosh" if id == "fists" else "batswing", global_position, -4.0, 1.0, 14.0, 0.08)
	if game:
		game.make_noise(global_position, 12.0, self)
	var reach: float = g.reach
	var arc: float = g.arc
	var eye := eye_pos()
	var foes: Array = game.fighters.duplicate() if game else []
	foes.sort_custom(func(a, b): return a.global_position.distance_squared_to(global_position) < b.global_position.distance_squared_to(global_position))
	for foe in foes:
		if foe == self or not foe.alive:
			continue
		var d: Vector3 = foe.global_position - global_position
		var dist := Vector2(d.x, d.z).length()
		if dist > reach or absf(d.y) > 1.9:
			continue
		var ang := absf(wrapf(atan2(d.x, d.z) - yaw, -PI, PI))
		if ang > arc:
			continue
		var chest: Vector3 = foe.global_position + Vector3.UP * (0.4 if foe.downed else 1.2)
		var q := PhysicsRayQueryParameters3D.create(eye, chest, LAYER_WORLD, [get_rid()])
		if get_world_3d().direct_space_state.intersect_ray(q):
			continue   # a wall in the way
		var dmg: float = float(g.dmg) * dmg_mul
		var hd := Vector3(d.x, 0, d.z).normalized()
		var knock: float = g.knock
		foe.velocity.x += hd.x * knock
		foe.velocity.z += hd.z * knock
		Effects.hit_spray(world, foe.global_position + Vector3.UP * (0.5 if foe.downed else 1.4), hd)
		Sfx.play(world, "fisthit" if id == "fists" else "swordhit", foe.global_position, 0.0, 1.0, 20.0, 0.07)
		var fin: bool = foe.take_damage(dmg, self, false, id)
		dealt_hit.emit(foe, roundi(dmg), false, fin)
		return
	# nobody in reach: a punch or swing still breaks glass in front of you
	for hy in [0.0, -0.9]:
		var o: Vector3 = eye + Vector3.UP * hy
		var q2 := PhysicsRayQueryParameters3D.create(o, o + forward() * reach, LAYER_WORLD, [get_rid()])
		var hit := get_world_3d().direct_space_state.intersect_ray(q2)
		if hit and game:
			game.hit_world(hit.collider, hit.position, hit.normal, forward(), 25.0)
			return

## where you're actually aiming: for you, the point under the crosshair (so third person shots go where the
## camera looks, fired from your eyes); for brains, straight down yaw/pitch
func aim_direction() -> Vector3:
	if not is_player:
		return aim_forward()
	var co := cam.global_position
	var cd := -cam.global_basis.z
	var eye := eye_pos()
	var t0 := maxf(0.0, (eye - co).dot(cd))
	var q := PhysicsRayQueryParameters3D.create(co + cd * t0, co + cd * 300.0, SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var p: Vector3 = hit.position if hit else co + cd * 300.0
	var d := p - eye
	return d.normalized() if d.length() > 0.5 else cd

func current_spread() -> float:
	var g := Weapons.stat(current_weapon())
	if Weapons.is_melee(current_weapon()):
		return 0.0
	var s := lerpf(float(g.spread), float(g.ads_spread), ads_k)
	if Vector2(velocity.x, velocity.z).length() > 2.0:
		s *= 1.45
	if not is_on_floor() and not on_ladder:
		s *= 2.2
	if crouching:
		s *= 0.65
	return s + bloom * (0.3 if ads_k > 0.9 else 1.0)

func _shoot(id: String, g: Dictionary) -> void:
	ammo -= 1
	shots += 1
	if id == "duals":
		dual_left = not dual_left
	kick_t = 1.0
	if model:
		model.fired()
	var world := get_parent()
	var origin := eye_pos()
	var dir := Weapons.spread_dir(aim_direction(), current_spread())
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 250.0, SHOT_MASK, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end := origin + dir * 180.0
	if hit:
		end = hit.position
		var col: Object = hit.collider
		if col and col.has_method("take_damage") and col != self:
			var foe = col
			var dist := origin.distance_to(end)
			var foe_y: float = foe.global_position.y
			var head: bool = can_headshot and (not foe.downed) and end.y - foe_y > HEIGHT - HEAD_TOP
			var dmg: float = float(g.dmg) * (float(g.head) if head else 1.0) * Weapons.falloff(id, dist) * dmg_mul
			Effects.hit_spray(world, end, dir)
			var fin: bool = foe.take_damage(dmg, self, head, id)
			dealt_hit.emit(foe, roundi(dmg), head, fin)
		elif game:
			game.hit_world(col, end, hit.normal, dir, float(g.dmg) * Weapons.falloff(id, origin.distance_to(end)) * dmg_mul)
	var mz := muzzle_pos()
	if shots % 2 == 1:   # a thin streak on every other bullet
		Effects.tracer(world, mz, end)
	Effects.muzzle_flash(world, mz)
	var snd: Array = g.sound
	Sfx.play(world, snd[0], mz, -3.0, float(snd[1]), 45.0, 0.03)
	bloom = minf(bloom + float(g.bloom), 3.0)
	if game and shots % 3 == 1:
		game.make_noise(global_position, 40.0, self)
	if is_player:
		var k: float = g.kick
		pitch = clamp(pitch + k * (0.6 if ads else 1.0), -1.45, 1.45)
		yaw += (randf() - 0.5) * k * 0.4
	if ammo <= 0:
		gun_id = ""
		slot = "melee"
		ads = false
		swap_t = SWAP
		Sfx.play(world, "dry", global_position, -6.0, 1.0, 8.0)
		if game:
			game.feed_out_of_ammo(self)
		_refresh_weapon_models()

# ---------------------------------------------------------------- crouch

func _set_crouch(on: bool) -> void:
	if not on and crouching:   # only stand up if there's room above
		var t := global_transform
		if test_move(t, Vector3.UP * (HEIGHT - CROUCH_HEIGHT)):
			return
	crouching = on
	_shape.height = CROUCH_HEIGHT if on else HEIGHT
	_cs.position.y = _shape.height * 0.5

# ---------------------------------------------------------------- every physics tick

func _physics_process(dt: float) -> void:
	if is_player and not autopilot:
		_read_player_input(dt)
	if game and not game.fighting():   # countdown and after the win: nobody moves or attacks
		in_move = Vector2.ZERO
		in_jump = false
		in_fire = false
		in_aim = false
	if not alive:
		respawn_t -= dt
		if model:   # the death fall plays out until the respawn
			model.tick(dt, self)
		if respawn_t <= 0.0 and game:
			game.respawn(self)
		return
	_tick_health(dt)
	if not alive:
		return
	# weapons: cooldowns, bloom, aiming, firing
	fire_t -= dt
	swap_t -= dt
	shield_t = maxf(0.0, shield_t - dt)
	bloom = maxf(0.0, bloom - dt * (1.0 if in_fire else 3.0))
	var id := current_weapon()
	var melee := Weapons.is_melee(id)
	ads = in_aim and not melee and not downed
	ads_k = move_toward(ads_k, 1.0 if ads else 0.0, dt / Weapons.ADS_TIME)
	if in_fire and fire_t <= 0.0 and can_attack():
		_attack()
		id = current_weapon()
		melee = Weapons.is_melee(id)
	# movement
	var mv := in_move
	var jump := in_jump and not downed
	var jump_press := jump and not _jump_held
	_jump_held = jump
	var wish := (forward() * mv.y + right() * mv.x)
	if wish.length() > 1.0:
		wish = wish.normalized()
	var grounded := is_on_floor()
	if grounded:
		air_jumps = 1
	clock += dt
	if _ride_step(dt, wish, jump):
		_update_view(dt)
		return
	on_ladder = false
	if not downed:   # ladders: inside a ladder zone and pushing forward = climb
		var feet := global_position
		for l in ladders:
			if l.grow(0.55).has_point(feet + Vector3.UP * 0.6) or l.grow(0.55).has_point(feet + Vector3.UP * 1.6):
				on_ladder = true
				break
	var speed := RUN * (FISTS_MUL if melee else float(Weapons.stat(id).get("weight", 1.0)))
	if ads:
		speed = Weapons.ADS_SPEED * float(Weapons.stat(id).get("weight", 1.0))
	if crouching:
		speed *= CROUCH_MUL
	if downed:
		speed = CRAWL
	if wading and global_position.y < 0.25:
		speed *= 0.8
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
	stam_rest += dt
	if stam_rest > STAM_DELAY:
		stamina = min(STAM_MAX, stamina + STAM_REGEN * dt)
	var before := global_position
	move_and_slide()
	if not downed:
		_step_up(before, hv * dt, grounded)
	_footsteps(dt, grounded)
	if downed:
		_set_pose_downed()
	_update_view(dt)

## lifts and the pole (web ladderStep for `lift` ladders): walk into one (or drop in from the top) and it carries you
## 14 m/s to the other end, then steps you out 1.45 m past the top edge; nothing to steer while riding
func _ride_step(dt: float, wish: Vector3, jump: bool) -> bool:
	if downed or not alive:
		ride = -1
		return false
	if ride >= 0:   # already riding: keep going to the end, whatever the height
		_ride_move(dt)
		return true
	var p := global_position
	var near := false
	for i in lifts.size():
		var L: Dictionary = lifts[i]
		var b: AABB = L.box
		if p.x < b.position.x - RADIUS or p.x > b.end.x + RADIUS or p.z < b.position.z - RADIUS or p.z > b.end.z + RADIUS \
				or p.y < b.position.y - 0.5 or p.y > b.end.y + 0.05:
			continue
		near = true
		if clock < ride_cd:
			continue
		var into := wish.x * float(L.nx) + wish.z * float(L.nz)
		var at_top := p.y > b.end.y - 0.25 and into < -0.2
		# step into the car at the bottom (from any side), walk back into the shaft at the top
		var c := b.get_center()
		var in_car := lift_arm and p.y < b.position.y + 0.3 and Vector2(p.x - c.x, p.z - c.z).length() < 0.75
		if not (in_car or into > 0.3 or (jump and into > -0.2) or at_top):
			continue
		start_ride(i, -1 if at_top else 1)
		_ride_move(dt)
		return true
	if not near:
		lift_arm = true
	return false

var rides := 0                   # lifts and pole taken (autotest)

func start_ride(i: int, dir: int) -> void:
	ride = i
	rides += 1
	lift_arm = false
	ride_dir = dir
	velocity = Vector3.ZERO
	if crouching:
		_set_crouch(false)

func _ride_move(dt: float) -> void:
	var L: Dictionary = lifts[ride]
	var b: AABB = L.box
	var nx: float = L.nx
	var nz: float = L.nz
	var p := global_position
	var c := b.get_center()
	var tx := c.x
	var tz := c.z
	if nx != 0.0:
		tx = float(L.rung) - nx * 0.85
	else:
		tz = float(L.rung) - nz * 0.85
	var k := minf(1.0, dt * 10.0)
	p.x += (tx - p.x) * k
	p.z += (tz - p.z) * k
	p.y += 14.0 * ride_dir * dt
	velocity = Vector3.ZERO
	if ride_dir < 0 and p.y <= b.position.y:
		p.y = b.position.y
		ride = -1
		ride_cd = clock + 0.6
	elif ride_dir > 0 and p.y >= b.end.y:
		p.y = b.end.y + 0.02
		p.x += nx * 1.45
		p.z += nz * 1.45
		ride = -1
		ride_cd = clock + 0.6
	global_position = p

## footsteps (phase 5): one step every 2.6 m of running, quieter crouched or crawling, softer and lower on the lawns;
## a thump when you land from a real fall. Bots hear every fourth running step within 10 m.
func _footsteps(dt: float, was_grounded: bool) -> void:
	var on := is_on_floor()
	if not on:
		_air_t += dt
		return
	if _air_t > 0.45 and not was_grounded:
		Sfx.play(get_parent(), "land", global_position, -6.0 if is_player else -3.0, 1.0, 16.0, 0.06)
	_air_t = 0.0
	var sp := Vector2(velocity.x, velocity.z).length()
	if sp < 1.5:
		_step_dist = 0.0
		return
	_step_dist += sp * dt
	var stride := 2.6 if not (crouching or downed) else 1.6
	if _step_dist < stride:
		return
	_step_dist = 0.0
	_step_n += 1
	var p := global_position
	var h: Dictionary = game.level.house if game else {}
	var indoors := not h.is_empty() and absf(p.x) < float(h.x) and absf(p.z) < float(h.z) and p.y < 10.5
	var vol := -14.0 if is_player else -6.0
	if crouching or downed:
		vol -= 12.0
	if not indoors:
		vol -= 4.0
	Sfx.play(get_parent(), "step%d" % (1 + randi() % 5), p, vol, (1.0 if indoors else 0.82), 6.0 if (crouching or downed) else 16.0, 0.05)
	if game and not (crouching or downed) and _step_n % 4 == 0:
		game.make_noise(p, 10.0, self)

func _tick_health(dt: float) -> void:
	if downed:
		bleed -= dt
		revive += dt / GET_UP
		if randf() < dt * 11.0:
			Effects.downed_wisp(get_parent(), global_position + Vector3(randf_range(-0.25, 0.25), 0.4, randf_range(-0.25, 0.25)))
		if revive >= 1.0:
			_get_up()
		elif bleed <= 0.0:
			_die(last_by)
	elif hp < HP_MAX and _now() - last_hurt > REGEN_DELAY:
		hp = minf(HP_MAX, hp + REGEN_RATE * dt)

## camera, aim zoom, first person hands, shield shell
func _update_view(dt: float) -> void:
	var g := Weapons.stat(current_weapon())
	_eye = lerp(_eye, EYE_DOWN if downed else (EYE_CROUCH if crouching else EYE), min(1.0, dt * 12.0))
	_step_dy = move_toward(_step_dy, 0.0, dt * 2.0) * maxf(0.0, 1.0 - dt * 9.0)
	_pivot.position.y = _eye + _step_dy
	_pivot.rotation = Vector3(pitch, yaw + PI, 0)
	if not downed:
		_body_mesh.rotation.y = yaw
	var fp := first_person()
	if is_player:
		cam.fov = lerpf(Settings.fov, float(g.get("zoom", Settings.fov)), ads_k) if not Weapons.is_melee(current_weapon()) else Settings.fov
		if not fp:
			_arm.spring_length = lerpf(4.2, 3.2, ads_k) if not downed else 3.4
			# aiming: the camera drops to shoulder height and moves out, so she sits at the side of the frame
			_arm.position = Vector3(lerpf(0.9, 1.45, ads_k), lerpf(0.55, 0.35, ads_k), 0)
	# first person hands: punches jab forward, guns kick back and come to the centre when aiming
	swing_t = maxf(0.0, swing_t - dt)
	kick_t = maxf(0.0, kick_t - dt * 14.0)
	if _view.visible:
		var jab := sin((1.0 - swing_t / 0.26) * PI) if swing_t > 0.0 else 0.0
		for i in _gloves.size():
			var side := -1.0 if i == 0 else 1.0
			var active := (i == 0) == punch_left
			_gloves[i].position = Vector3(0.17 * side, -0.19 + (0.06 * jab if active else 0.0), -0.48 - (0.3 * jab if active else 0.0))
		if _view_model:
			# aimed: the sights sit just under the centre of the screen so you look over the front post, not
			# through the gun; the whole hand is pushed out as the view zooms so the gun keeps its size on screen
			var hip := Vector3(0.2, -0.2, -0.5)
			var aimed := Vector3(0.0, -0.097, -0.5)
			if current_weapon() == "duals":
				hip = Vector3(0.0, -0.2, -0.5)
				aimed = Vector3(0.0, -0.15, -0.5)
			elif current_weapon() == "bat":
				# a full swing from over the right shoulder across to the left, in 0.26 s
				hip = Vector3(0.24, -0.3, -0.38)
				aimed = hip
				var u := 1.0 - swing_t / 0.26 if swing_t > 0.0 else 0.0
				var e := u * u * (3.0 - 2.0 * u)
				_view_model.rotation = Vector3(-0.5 * sin(u * PI), lerpf(0.9, -1.1, e) if swing_t > 0.0 else 0.0, -0.7 * sin(u * PI))
				hip += Vector3(lerpf(0.0, -0.4, e), 0.08 * sin(u * PI), -0.1 * sin(u * PI)) if swing_t > 0.0 else Vector3.ZERO
			var zoom_k := tan(deg_to_rad(Settings.fov) * 0.5) / tan(deg_to_rad(cam.fov) * 0.5)
			_view_model.position = (hip.lerp(aimed, ads_k) + Vector3(0, 0, 0.045 * kick_t)) * zoom_k
	if model:
		model.tick(dt, self)
		_hold_in_hand()
	# third person: the bat sweeps across from the right shoulder when swung; at rest it's held up and back
	elif current_weapon() == "bat" and swing_t > 0.0:
		var u2 := 1.0 - swing_t / 0.26
		var e2 := u2 * u2 * (3.0 - 2.0 * u2)
		_held.rotation = Vector3(0.6 * sin(u2 * PI), PI + lerpf(1.3, -1.4, e2), 0.0)
	else:
		_held.rotation = Vector3(0.0, PI, 0.0)
	_shell.visible = shield_t > 0.0 and _body_mesh.visible
	if _shell.visible:
		_shell_mat.albedo_color.a = 0.22 * clampf(shield_t / SHIELD, 0.0, 1.0)

## the weapon in the model's hands, following the hands so it moves with every clip; third-person weapons are drawn
## at full size (the first-person models are made small for the camera)
## - a gun lies along the line from the right palm to the left one (both hands are on it in every gun clip), its
##   grip in the right hand; aiming or firing turns it the rest of the way onto the aim
## - dual pistols: one in each hand, along the hand, onto the aim
## - the bat: held in both fists (it leaves them on the thumb side, the way a handle does) while the hands are
##   together, in the right fist alone when they're apart; carried hanging from the right hand
## - running with a gun (not aiming): the low ready, muzzle forward and down
const GUN_SCALE := 1.7
const GUN_GRIP := Vector3(0.0, -0.08, 0.03)      # where the right hand holds an SMG, in the gun model
const PISTOL_GRIP := Vector3(0.0, -0.05, 0.0)
const GUN_LEN := {"mp5": 0.42, "uzi": 0.3, "vector": 0.38, "p90": 0.45, "ump": 0.46, "sting": 0.26}   # weapon_model.gd
const BAT_TILT := 0.52                           # the bat model points this far above its -Z
func _hold_in_hand() -> void:
	var w := current_weapon()
	if w == "fists":
		return
	var r: Vector3 = model.palm(true)
	var l: Vector3 = model.palm(false)
	var rw: Vector3 = model.hand_transform(true).origin    # the wrists line up along a held bat or gun (the palms
	var lw: Vector3 = model.hand_transform(false).origin   # are turned differently, so they don't)
	var aim := aim_forward()
	var raised: bool = ads or kick_t > 0.0 or model._fire_t > 0.0
	if w == "bat":
		var g: Array = model.grip_axes()
		var dir: Vector3 = g[0]
		var at := r
		if swing_t <= 0.0 and model._combat <= 0.0:
			dir = (dir * 0.35 + Vector3.DOWN + forward() * 0.25).normalized()   # carried, tip down and a little forward
		else:   # swinging: the bat leaves the right fist; the left hand is put on the handle below it (IK), always
			dir = model.fist_dir(true)
			if rw.distance_to(lw) < 0.32:   # hands together in the clip: both fists agree on the line
				dir = ((model.fist_dir(true) as Vector3) + (model.fist_dir(false) as Vector3)).normalized()
			at = r - dir * 0.17
			model.hik.targets[1] = at + dir * 0.05 - (model.hand_dir(false) as Vector3) * 0.07
			model.hik.weights = [0.0, 1.0]
		var b := _aim_basis(dir, g[1]) * Basis(Vector3.RIGHT, -BAT_TILT)
		_held.global_transform = Transform3D(b, at)
		return
	if w == "duals":
		# arms out but not locked: each wrist drawn 12% back towards its shoulder, so the elbows give
		model.hik.pulls = [0.12, 0.12]
		model.hik.weights = [1.0, 1.0]
		_held.global_transform = Transform3D(Basis(), r)
		for side in ["R", "L"]:
			var p := _held_model.get_node_or_null("Pistol" + side) as Node3D
			if not p:
				continue
			var is_r: bool = side == "R"
			var d: Vector3 = aim   # both pistols on the aim, so they converge on the target
			var pb := _aim_basis(d, Vector3.UP).scaled(Vector3.ONE * GUN_SCALE)
			p.global_transform = Transform3D(pb, (r if is_r else l) - pb * PISTOL_GRIP)
		return
	if raised:   # aiming: the gun along the hands (the aim clip has them on it), turned onto the aim
		var gb := _aim_basis(aim, Vector3.UP).scaled(Vector3.ONE * GUN_SCALE)
		_held.global_transform = Transform3D(gb, r - gb * GUN_GRIP)
		return
	# carried at the low ready: the gun sits steady in front of the chest, muzzle forward and a little down, and the
	# hands are put on its grip and handguard (two-bone IK), so it doesn't swing with the arms
	var ab := global_transform.basis.orthonormalized() * Basis(Vector3.UP, model.body_yaw)
	var fw := ab.z
	var lf := ab.x
	var gb2 := _aim_basis((fw + Vector3.DOWN * 0.3).normalized(), Vector3.UP).scaled(Vector3.ONE * GUN_SCALE)
	var grip_at: Vector3 = model.bone_world("Spine2") - lf * 0.14 + fw * 0.3 + Vector3.DOWN * 0.24
	_held.global_transform = Transform3D(gb2, grip_at - gb2 * GUN_GRIP)
	var fore := _held.global_transform * Vector3(0.0, -0.035, -minf(0.24, float(GUN_LEN.get(w, 0.42)) * 0.6))
	model.hik.targets = [grip_at - (model.hand_dir(true) as Vector3) * 0.07, fore - (model.hand_dir(false) as Vector3) * 0.07]
	model.hik.weights = [1.0, 1.0]

## a basis whose -Z points along dir, kept as upright as it can be
func _aim_basis(dir: Vector3, up: Vector3) -> Basis:
	var u := up - dir * up.dot(dir)
	if u.length() < 0.05:
		u = Vector3.UP - dir * dir.y
		if u.length() < 0.05:
			u = Vector3.FORWARD
	return Basis.looking_at(dir, u.normalized())

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
	var y0 := global_position.y
	global_position = before + Vector3.UP * STEP + motion
	apply_floor_snap()
	_step_dy = clampf(_step_dy - (global_position.y - y0), -1.2, 0.0)   # the view eases up the step instead of popping
