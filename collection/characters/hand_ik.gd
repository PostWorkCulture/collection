extends SkeletonModifier3D
## After the animation: puts a wrist on a point with two-bone IK (upper arm and forearm), keeping the elbow on the
## side the clip has it. Used to keep both hands on a carried gun and to give straight-armed holds a bend.

const SIDES := ["Right", "Left"]

var targets: Array = [Vector3.ZERO, Vector3.ZERO]   # wrist targets in the world, per side (right, left)
var weights: Array = [0.0, 0.0]                     # 0..1 per side
var pulls: Array = [0.0, 0.0]                       # > 0: no target, just draw the wrist this share back to the shoulder
var nudges: Array = [Vector3.ZERO, Vector3.ZERO]    # != 0: no target, just move the wrist this far (world)

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	var inv := sk.global_transform.affine_inverse()
	for i in 2:
		var w: float = weights[i]
		if w <= 0.0:
			continue
		var a := sk.find_bone(SIDES[i] + "Arm")
		var f := sk.find_bone(SIDES[i] + "ForeArm")
		var h := sk.find_bone(SIDES[i] + "Hand")
		if a < 0 or f < 0 or h < 0:
			continue
		var pg := sk.get_bone_global_pose(sk.get_bone_parent(a))
		var ag := pg * sk.get_bone_pose(a)
		var fg := ag * sk.get_bone_pose(f)
		var hg := fg * sk.get_bone_pose(h)
		var s := ag.origin
		var e := fg.origin
		var wr := hg.origin
		var goal: Vector3 = inv * (targets[i] as Vector3)
		if float(pulls[i]) > 0.0:
			goal = s + (wr - s) * (1.0 - float(pulls[i]))
		elif (nudges[i] as Vector3) != Vector3.ZERO:
			goal = wr + inv.basis * (nudges[i] as Vector3)
		var t := wr.lerp(goal, w)
		var la := (e - s).length()
		var lb := (wr - e).length()
		if la < 0.0001 or lb < 0.0001:
			continue
		var d := t - s
		var l := clampf(d.length(), absf(la - lb) + 0.0001, (la + lb) * 0.999)
		var dn := d.normalized()
		var pole := (e - s) - dn * (e - s).dot(dn)
		if pole.length() < 0.00001:
			pole = Vector3.DOWN - dn * dn.y
		pole = pole.normalized()
		var ca := (la * la + l * l - lb * lb) / (2.0 * la * l)
		var e2 := s + dn * (la * ca) + pole * (la * sqrt(maxf(0.0, 1.0 - ca * ca)))
		var t2 := s + dn * l
		# upper arm onto the new elbow
		var r1 := Quaternion((e - s).normalized(), (e2 - s).normalized())
		var ag2 := Transform3D(Basis(r1) * ag.basis, ag.origin)
		sk.set_bone_pose_rotation(a, (pg.basis.orthonormalized().inverse() * ag2.basis.orthonormalized()).get_rotation_quaternion())
		# forearm onto the target
		var fg2 := ag2 * sk.get_bone_pose(f)
		var hw := (fg2 * sk.get_bone_pose(h)).origin
		var r2 := Quaternion((hw - fg2.origin).normalized(), (t2 - fg2.origin).normalized())
		var fb := Basis(r2) * fg2.basis
		sk.set_bone_pose_rotation(f, (ag2.basis.orthonormalized().inverse() * fb.orthonormalized()).get_rotation_quaternion())
