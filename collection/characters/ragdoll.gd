extends SkeletonModifier3D
## Limp falls on death (Pete, 27 Nov; 1v1's ragdolls as the model). When she dies, eleven rigid bodies are made where
## her hips, chest, head, upper and lower arms and legs are at that moment (sized in metres, outside the scaled model,
## so the physics stays steady), joined by cone joints with human limits, and shoved the way the killing hit was
## going. They fall under their own weight against whatever is there and settle; this modifier, last after the
## animation, puts each bone where its body is. The bodies collide with the world and with each other (not players or
## bullets); parts already touching when she dies (an arm at her side) skip each other, and joined parts never collide.
## Knees and elbows are hinges that only bend the way they do (0 to 140-145 degrees); the rest are cone joints.
## The body keeps the speed she was moving at, plus the shove (27 Nov review). The respawn takes them away.

const LAYER := 8
const PARTS := [
	# bone, child bone (its end), parent part, radius (share of the length), swing, twist (degrees), mass (kg)
	# (radii sized to these chunky bodies, 27 Nov review: the thinner ones let the torso sink into the floor)
	["Hips", "Spine1", "", 0.72, 0, 0, 10.0],
	["Spine1", "Neck", "Hips", 0.62, 25, 15, 12.0],
	["Head", "", "Spine1", 0.0, 35, 30, 5.0],
	["LeftArm", "LeftForeArm", "Spine1", 0.3, 80, 40, 2.0],
	["RightArm", "RightForeArm", "Spine1", 0.3, 80, 40, 2.0],
	["LeftForeArm", "LeftHand", "LeftArm", 0.27, 145, 0, 1.5],   # hinge: the swing is how far it bends
	["RightForeArm", "RightHand", "RightArm", 0.27, 145, 0, 1.5],
	["LeftUpLeg", "LeftLeg", "Hips", 0.34, 55, 20, 6.0],
	["RightUpLeg", "RightLeg", "Hips", 0.34, 55, 20, 6.0],
	["LeftLeg", "LeftFoot", "LeftUpLeg", 0.3, 140, 0, 4.0],      # hinge
	["RightLeg", "RightFoot", "RightUpLeg", 0.3, 140, 0, 4.0],
]
const HINGES := {"LeftForeArm": "elbow", "RightForeArm": "elbow", "LeftLeg": "knee", "RightLeg": "knee"}

var on := false
var bodies := {}            # bone name -> RigidBody3D
var _rel := {}              # bone name -> the body's frame in the bone's (unscaled) frame
var _ids := {}              # bone name -> bone index
var _holder: Node3D = null  # top level: the bodies and joints live here, unscaled
var _seg := {}              # bone name -> [start, end, radius] at the start (world), for the touching test
var _apart: Array = []      # pairs that touched at the start: they collide again once they've come apart
var _age := 0.0

func _ready() -> void:
	active = false

## the bone's frame in the world, without the model's scale
func _bone_world(sk: Skeleton3D, b: int) -> Transform3D:
	var w := sk.global_transform * sk.get_bone_global_pose(b)
	return Transform3D(w.basis.orthonormalized(), w.origin)

## go limp from the pose she's in now, moving at `carry` and shoved by `push` (world, m/s); `fwd` is the way she faces
func start(push: Vector3, carry := Vector3.ZERO, fwd := Vector3.FORWARD) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	stop()
	_holder = Node3D.new()
	_holder.top_level = true
	_holder.name = "RagdollBodies"
	add_child(_holder)
	_holder.global_transform = Transform3D.IDENTITY
	var ks: float = sk.global_transform.basis.get_scale().y
	for p in PARTS:
		var b := sk.find_bone(p[0])
		if b < 0:
			continue
		var bw := _bone_world(sk, b)
		var end: Vector3
		var cb := sk.find_bone(p[1]) if String(p[1]) != "" else -1
		if cb >= 0:
			end = _bone_world(sk, cb).origin
		else:   # the head: up from the neck, about as tall as the head is
			var nb := sk.get_bone_parent(b)
			end = bw.origin + (bw.origin - _bone_world(sk, nb).origin).normalized() * 0.8 * ks
		var along := end - bw.origin
		var length := along.length()
		if length < 0.02:
			continue
		var axis := along / length
		var bb := Basis(Quaternion(Vector3.UP, axis)) if absf(axis.dot(Vector3.UP)) < 0.999 else Basis()
		var frame := Transform3D(bb, bw.origin + along * 0.5)
		var rb := RigidBody3D.new()
		rb.name = String(p[0])
		rb.mass = float(p[6])
		rb.collision_layer = LAYER
		rb.collision_mask = 1 | LAYER
		rb.linear_damp = 0.4
		rb.angular_damp = 3.0
		rb.continuous_cd = true
		var pm := PhysicsMaterial.new()
		pm.friction = 0.95
		pm.bounce = 0.0
		rb.physics_material_override = pm
		var cs := CollisionShape3D.new()
		var rad := length * 0.5
		if String(p[0]) == "Head":
			var sp := SphereShape3D.new()
			sp.radius = rad
			cs.shape = sp
			_seg[p[0]] = [frame.origin, frame.origin, rad]
		else:
			var cap := CapsuleShape3D.new()
			cap.radius = maxf(0.04, length * float(p[3]))
			cap.height = maxf(length, cap.radius * 2.0 + 0.01)
			cs.shape = cap
			rad = cap.radius
			var half := axis * maxf(0.0, cap.height * 0.5 - rad)
			_seg[p[0]] = [frame.origin - half, frame.origin + half, rad]
		rb.add_child(cs)
		_holder.add_child(rb)
		rb.global_transform = frame
		rb.linear_velocity = carry + push * (1.0 if String(p[0]) in ["Spine1", "Head"] else 0.6)
		bodies[p[0]] = rb
		_rel[p[0]] = bw.affine_inverse() * frame
		_ids[p[0]] = b
	# parts already touching skip each other (an arm hanging against her side would otherwise be shot out)
	var names := bodies.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Array = _seg[names[i]]
			var c: Array = _seg[names[j]]
			if _seg_dist(a[0], a[1], c[0], c[1]) < float(a[2]) + float(c[2]) + 0.02:
				(bodies[names[i]] as RigidBody3D).add_collision_exception_with(bodies[names[j]])
				_apart.append([names[i], names[j]])
	# joints: at each child's bone, twisting about the bone
	for p in PARTS:
		var par := String(p[2])
		if par == "" or not bodies.has(p[0]) or not bodies.has(par):
			continue
		var child: RigidBody3D = bodies[p[0]]
		if HINGES.has(p[0]):   # knee or elbow: one way only, from straight to fully bent
			var at2 := _bone_world(sk, int(_ids[p[0]])).origin
			var u := (at2 - _bone_world(sk, int(_ids[par])).origin).normalized()   # upper segment, towards the joint
			var l := (child.global_position - at2).normalized()                    # lower segment, away from it
			var bend := u.angle_to(l)
			var k := u.cross(l)
			if bend < deg_to_rad(8.0) or k.length() < 0.05:   # nearly straight: the way it would bend
				var flex := -fwd if HINGES[p[0]] == "knee" else fwd   # shins fold back, forearms come forward
				k = u.cross((u + flex * 0.3).normalized())
				bend = 0.0
			k = k.normalized()
			var hj := HingeJoint3D.new()
			_holder.add_child(hj)
			var hx := u
			hj.global_transform = Transform3D(Basis(hx, k.cross(hx).normalized(), k).orthonormalized(), at2)
			hj.exclude_nodes_from_collision = true
			hj.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			# Godot's hinge angle runs against the right-hand turn about its Z: bending more is a negative angle
			hj.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, -(deg_to_rad(float(p[4])) - bend))
			hj.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, bend)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_SOFTNESS, 0.9)
			hj.set_param(HingeJoint3D.PARAM_LIMIT_RELAXATION, 1.0)
			hj.node_a = hj.get_path_to(bodies[par])
			hj.node_b = hj.get_path_to(child)
			continue
		var jt := ConeTwistJoint3D.new()
		_holder.add_child(jt)
		var at := _bone_world(sk, int(_ids[p[0]])).origin
		var x := (child.global_position - at).normalized()
		var jb := Basis(Quaternion(Vector3.RIGHT, x)) if absf(x.dot(Vector3.RIGHT)) < 0.999 else Basis()
		jt.global_transform = Transform3D(jb, at)
		jt.exclude_nodes_from_collision = true
		jt.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(float(p[4])))
		jt.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(float(p[5])))
		jt.set_param(ConeTwistJoint3D.PARAM_SOFTNESS, 0.9)
		jt.set_param(ConeTwistJoint3D.PARAM_RELAXATION, 1.0)
		jt.node_a = jt.get_path_to(bodies[par])
		jt.node_b = jt.get_path_to(child)
	on = true
	active = true

## a part's capsule now (world): its ends and radius
func _now_seg(n: String) -> Array:
	var rb: RigidBody3D = bodies[n]
	var s0: Array = _seg[n]
	var half := ((s0[1] as Vector3) - (s0[0] as Vector3)).length() * 0.5
	var ax := rb.global_basis.y.normalized() * half
	return [rb.global_position - ax, rb.global_position + ax, s0[2]]

## closest distance between two segments
func _seg_dist(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var best := INF
	for i in 9:   # sample one, find the nearest point on the other (plenty for a yes/no at start)
		var t := i / 8.0
		var a := p1.lerp(q1, t)
		var b := p2.lerp(q2, t)
		best = minf(best, a.distance_to(Geometry3D.get_closest_point_to_segment(a, p2, q2)))
		best = minf(best, b.distance_to(Geometry3D.get_closest_point_to_segment(b, p1, q1)))
	return best

func stop() -> void:
	on = false
	active = false
	bodies.clear()
	_seg.clear()
	_apart.clear()
	_age = 0.0
	_rel.clear()
	_ids.clear()
	if _holder:
		_holder.queue_free()
		_holder = null

func _process_modification() -> void:
	if not on:
		return
	_age += 1.0 / 60.0
	if _age > 0.2 and not _apart.is_empty():   # parts that started touching collide again once they're apart
		for pr in _apart.duplicate():
			if not bodies.has(pr[0]) or not bodies.has(pr[1]):
				_apart.erase(pr)
				continue
			var a: Array = _now_seg(pr[0])
			var c: Array = _now_seg(pr[1])
			if _seg_dist(a[0], a[1], c[0], c[1]) > float(a[2]) + float(c[2]) + 0.03:
				(bodies[pr[0]] as RigidBody3D).remove_collision_exception_with(bodies[pr[1]])
				_apart.erase(pr)
	var sk := get_skeleton()
	if sk == null:
		return
	var inv := sk.global_transform.affine_inverse()
	for p in PARTS:
		var n: String = p[0]
		if not bodies.has(n):
			continue
		var rb: RigidBody3D = bodies[n]
		if not is_instance_valid(rb):
			continue
		var bw: Transform3D = rb.global_transform * (_rel[n] as Transform3D).affine_inverse()
		var g := inv * bw
		sk.set_bone_global_pose(int(_ids[n]), Transform3D(g.basis.orthonormalized(), g.origin))
