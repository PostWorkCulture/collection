extends SkeletonModifier3D
## After the animation: turns the chest towards the aim when the legs run off at an angle, leans it up or down with
## the aim (spread over the spine so it bends like a back, not a hinge), and steadies the head so it looks where
## she's looking instead of bobbing down with the run.

var yaw := 0.0      # radians about the character's up axis, + = to the left
var pitch := 0.0    # radians, + = looking up
var steady := 0.0   # 0..1: how much the head is pulled back to look along the aim
var head_up := 0.0  # radians added to where the head looks (lifts the head when crawling)
var head_max := 0.6 # the most the head is turned to get there
var arm_drop := 0.0 # radians: both upper arms lowered at the shoulder (a guard or pistols held below the eyes)
var arm_in := 0.0   # radians: both upper arms brought in towards the body

const BONES := ["Spine1", "Spine2", "Neck"]
const SHARE := [0.4, 0.35, 0.25]      # a turn of the chest, then the neck: the head stays level, it doesn't tip

var _head := -1
var _head_fwd := Vector3(0, 0, 1)
var _head_side := Vector3(1, 0, 0)

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	var first := sk.find_bone(BONES[0])
	if first < 0:
		return
	if _head < 0:
		_head = sk.find_bone("Head")
		if _head >= 0:
			var hi := sk.get_bone_global_rest(_head).basis.orthonormalized().inverse()
			_head_fwd = hi * Vector3(0, 0, 1)
			_head_side = hi * Vector3(1, 0, 0)
	var parent := sk.get_bone_parent(first)
	var pg: Transform3D = sk.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var chest := Transform3D()
	for i in BONES.size():
		var b := sk.find_bone(BONES[i])
		if b < 0:
			continue
		var g := pg * sk.get_bone_pose(b)
		var r := Basis(Vector3.UP, yaw * SHARE[i]) * Basis(Vector3.LEFT, pitch * SHARE[i])
		var g2 := Transform3D(r * g.basis, g.origin)
		sk.set_bone_pose_rotation(b, (pg.affine_inverse() * g2).basis.get_rotation_quaternion())
		pg = g2
		if BONES[i] == "Spine2":
			chest = g2
	if arm_drop != 0.0 or arm_in != 0.0:
		for side in ["Left", "Right"]:
			var sh := sk.find_bone(side + "Shoulder")
			var ab := sk.find_bone(side + "Arm")
			if sh < 0 or ab < 0:
				continue
			var shg := chest * sk.get_bone_pose(sh)
			var ag := shg * sk.get_bone_pose(ab)
			# the model faces +Z with its left at +X: about +X lowers the arms, about +Z swings an arm towards -X
			var r := Basis(Vector3.RIGHT, arm_drop) * Basis(Vector3.BACK, -arm_in if side == "Left" else arm_in)
			var ag2 := Transform3D(r * ag.basis, ag.origin)
			sk.set_bone_pose_rotation(ab, (shg.affine_inverse() * ag2).basis.get_rotation_quaternion())
	if _head < 0 or steady <= 0.0:
		return
	var hg := pg * sk.get_bone_pose(_head)
	var fwd := (hg.basis.orthonormalized() * _head_fwd).normalized()
	var fh := Vector3(fwd.x, 0, fwd.z)
	if fh.length() < 0.2:
		return
	fh = fh.normalized()
	var cur := asin(clampf(fwd.y, -1.0, 1.0))
	var want := pitch * 0.6 + head_up
	var corr := clampf((want - cur) * steady, -head_max, head_max)
	var axis := fh.cross(Vector3.UP).normalized()
	var hb := Basis(axis, corr) * hg.basis
	# and level: the eyes stay level instead of the head tipping over to one side
	var side := (hb.orthonormalized() * _head_side).normalized()
	var roll := clampf(-asin(clampf(side.y, -1.0, 1.0)) * steady, -0.5, 0.5)
	hb = Basis((hb.orthonormalized() * _head_fwd).normalized(), roll) * hb
	var hg2 := Transform3D(hb, hg.origin)
	sk.set_bone_pose_rotation(_head, (pg.affine_inverse() * hg2).basis.get_rotation_quaternion())
