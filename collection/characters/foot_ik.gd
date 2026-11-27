extends SkeletonModifier3D
## After the animation, before the spine twist (Pete, 27 Nov: "feet that adjust to stairs and slopes"; 1v1 plants
## its feet on the ground): each foot is put on the ground under it. A ray finds the floor below each ankle; the
## foot is raised or lowered by how far that floor is above or below the one the body stands on (the bottom of the
## capsule), the hips drop by the lower foot's share so it can reach, and two-bone IK (thigh and shin) bends the
## knee to suit, keeping it pointing the way the clip has it. The foot is tipped to lie along the slope (up to 25°).
## Off when weight is 0 (in the air, on ladders, downed, dead); weight eases in and out so nothing pops.
## Each foot is held up by the higher of two rays, under the ankle and under the ball of the foot, so toes don't sink
## into the face of a step going up and the heel can hang off a tread going down (27 Nov review).
## Standing still the feet are planted (`plant`): each stays where it was put while the body turns over it, and once
## a foot is more than STEP_DIST from where the clip wants it, or turned more than STEP_TURN from it, it takes a quick
## step there (a little lift on the way): turning on the spot is small real steps, not feet sliding (27 Nov review).

const SIDES := ["Left", "Right"]
const REACH := 0.6        # metres a foot is moved up or down at most
const TILT := deg_to_rad(25.0)
const MASK := 1           # the world (not players)

const STEP_DIST := 0.13  # metres off before a planted foot steps
const STEP_TURN := deg_to_rad(32.0)
const STEP_TIME := 0.2
const STEP_LIFT := 0.07

var weight := 0.0         # 0..1, set by the character every frame
var plant := false        # standing still: plant the feet (set by the character every frame)
var floor_y := 0.0        # where the body stands (the capsule's bottom), world y
var exclude: Array[RID] = []

var _off := [0.0, 0.0]    # smoothed per-foot height change (world metres)
var _nrm := [Vector3.UP, Vector3.UP]
var _drop := 0.0          # smoothed hip drop
var _dt := 0.016
var _t0 := 0
var _pw := 0.0            # how much the plant holds (eases in and out)
var _pin: Array = [null, null]          # planted ankle positions (world), null = not planted yet
var _pin_yaw := [0.0, 0.0]              # planted foot headings (world)
var _from: Array = [Vector3.ZERO, Vector3.ZERO]
var _from_yaw := [0.0, 0.0]
var _step := [-1.0, -1.0]               # stepping progress 0..1, -1 = planted

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk or not sk.is_inside_tree():
		return
	var now := Time.get_ticks_usec()
	_dt = clampf((now - _t0) / 1e6, 0.001, 0.05) if _t0 > 0 else 0.016
	_t0 = now
	var gt := sk.global_transform
	var inv := gt.affine_inverse()
	var k := 1.0 - exp(-_dt * 18.0)
	var space := sk.get_world_3d().direct_space_state
	var want := [0.0, 0.0]
	var nrm := [Vector3.UP, Vector3.UP]
	var ids := []
	var anim := [Vector3.ZERO, Vector3.ZERO]   # where the clip puts each ankle (world)
	var ayaw := [0.0, 0.0]                     # and the way it points
	for i in 2:
		var up := sk.find_bone(SIDES[i] + "UpLeg")
		var lg := sk.find_bone(SIDES[i] + "Leg")
		var ft := sk.find_bone(SIDES[i] + "Foot")
		var toe := sk.find_bone(SIDES[i] + "ToeBase")
		ids.append([up, lg, ft])
		if up < 0 or lg < 0 or ft < 0:
			continue
		anim[i] = gt * sk.get_bone_global_pose(ft).origin
		var tp: Vector3 = gt * sk.get_bone_global_pose(toe).origin if toe >= 0 else (anim[i] as Vector3) + gt.basis.z
		ayaw[i] = atan2(tp.x - (anim[i] as Vector3).x, tp.z - (anim[i] as Vector3).z)
	# planting: the feet stay put while standing, and step when they're left too far behind
	_pw = move_toward(_pw, 1.0 if plant and weight > 0.5 else 0.0, _dt * 8.0)
	for i in 2:
		if _pin[i] == null or _pw <= 0.0 or ((_pin[i] as Vector3) - (anim[i] as Vector3)).length() > 1.0:
			_pin[i] = anim[i]
			_pin_yaw[i] = ayaw[i]
			_step[i] = -1.0
	if _pw > 0.0:
		var worst := -1
		var worst_e := 0.0
		for i in 2:
			if float(_step[i]) >= 0.0:
				_step[i] = float(_step[i]) + _dt / STEP_TIME
				var s := minf(float(_step[i]), 1.0)
				var e := s * s * (3.0 - 2.0 * s)
				_pin[i] = (_from[i] as Vector3).lerp(anim[i], e)
				_pin_yaw[i] = lerp_angle(float(_from_yaw[i]), float(ayaw[i]), e)
				if float(_step[i]) >= 1.0:
					_step[i] = -1.0
				continue
			var d := Vector2((_pin[i] as Vector3).x - (anim[i] as Vector3).x, (_pin[i] as Vector3).z - (anim[i] as Vector3).z).length()
			var t := absf(wrapf(float(_pin_yaw[i]) - float(ayaw[i]), -PI, PI))
			var err := maxf(d / STEP_DIST, t / STEP_TURN)
			if err > 1.0 and err > worst_e:
				worst = i
				worst_e = err
		if worst >= 0 and float(_step[0]) < 0.0 and float(_step[1]) < 0.0:   # one foot at a time
			_from[worst] = _pin[worst]
			_from_yaw[worst] = _pin_yaw[worst]
			_step[worst] = 0.0
	var at := [anim[0], anim[1]]   # where each foot will be (the pin, as much as it holds)
	for i in 2:
		at[i] = (anim[i] as Vector3).lerp(_pin[i], _pw)
	for i in 2:
		var b: Array = ids[i]
		if int(b[0]) < 0 or int(b[1]) < 0 or int(b[2]) < 0 or weight <= 0.001:
			continue
		var best := -INF
		var n := Vector3.UP
		var fwd := Vector3(sin(float(ayaw[i])), 0.0, cos(float(ayaw[i])))
		for probe in [at[i], (at[i] as Vector3) + fwd * 0.16]:   # under the ankle and under the ball of the foot
			var pp: Vector3 = probe
			var q := PhysicsRayQueryParameters3D.create(Vector3(pp.x, floor_y + REACH + 0.3, pp.z), Vector3(pp.x, floor_y - REACH - 0.1, pp.z), MASK, exclude)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.6:
				continue   # nothing, or a wall
			if (hit.position as Vector3).y > best:
				best = (hit.position as Vector3).y
				n = hit.normal
		if best == -INF:
			continue
		want[i] = clampf(best - floor_y, -REACH, REACH)
		nrm[i] = n
	for i in 2:
		_off[i] = lerpf(float(_off[i]), float(want[i]) * weight, k)
		_nrm[i] = (_nrm[i] as Vector3).lerp(Vector3.UP.lerp(nrm[i], weight), k).normalized()
	_drop = lerpf(_drop, minf(0.0, minf(float(_off[0]), float(_off[1]))), k)
	if absf(_drop) < 0.0005 and absf(float(_off[0])) < 0.0005 and absf(float(_off[1])) < 0.0005 and _pw <= 0.0:
		return
	# hips down by the lower foot's share (in skeleton space: the model is scaled)
	var hips := sk.find_bone("Hips")
	if hips >= 0:
		var hp := sk.get_bone_pose_position(hips)
		var down := inv.basis * Vector3(0, _drop, 0)
		var par := sk.get_bone_parent(hips)
		if par >= 0:
			down = sk.get_bone_global_pose(par).basis.inverse() * down
		sk.set_bone_pose_position(hips, hp + down)
	for i in 2:
		var b: Array = ids[i]
		if int(b[0]) < 0 or int(b[1]) < 0 or int(b[2]) < 0:
			continue
		var lift: float = float(_off[i]) - _drop    # how far this ankle must go up from where the lowered hips put it
		var slide: Vector3 = ((at[i] as Vector3) - (anim[i] as Vector3)) * Vector3(1, 0, 1)
		if float(_step[i]) >= 0.0:   # a foot stepping lifts on its way
			lift += sin(PI * minf(float(_step[i]), 1.0)) * STEP_LIFT * _pw
		var turn := wrapf(float(_pin_yaw[i]) - float(ayaw[i]), -PI, PI) * _pw
		_leg(sk, int(b[0]), int(b[1]), int(b[2]), inv.basis * (Vector3(0, lift, 0) + slide), gt, _nrm[i], turn)

## two-bone IK: the ankle moved by `shift` (skeleton space), knee kept on its own side; then the foot laid on the slope
func _leg(sk: Skeleton3D, a: int, f: int, h: int, shift: Vector3, gt: Transform3D, n: Vector3, turn := 0.0) -> void:
	var pg := sk.get_bone_global_pose(sk.get_bone_parent(a))
	var ag := pg * sk.get_bone_pose(a)
	var fg := ag * sk.get_bone_pose(f)
	var hg := fg * sk.get_bone_pose(h)
	var s := ag.origin
	var e := fg.origin
	var wr := hg.origin
	var t := wr + shift
	var la := (e - s).length()
	var lb := (wr - e).length()
	if la < 0.0001 or lb < 0.0001:
		return
	var d := t - s
	var l := clampf(d.length(), absf(la - lb) + 0.0001, (la + lb) * 0.999)
	var dn := d.normalized()
	var pole := (e - s) - dn * (e - s).dot(dn)
	if pole.length() < 0.00001:
		pole = (e - wr) - dn * (e - wr).dot(dn)
	if pole.length() < 0.00001:
		return
	pole = pole.normalized()
	var ca := (la * la + l * l - lb * lb) / (2.0 * la * l)
	var e2 := s + dn * (la * ca) + pole * (la * sqrt(maxf(0.0, 1.0 - ca * ca)))
	var t2 := s + dn * l
	var r1 := Quaternion((e - s).normalized(), (e2 - s).normalized())
	var ag2 := Transform3D(Basis(r1) * ag.basis, ag.origin)
	sk.set_bone_pose_rotation(a, (pg.basis.orthonormalized().inverse() * ag2.basis.orthonormalized()).get_rotation_quaternion())
	var fg2 := ag2 * sk.get_bone_pose(f)
	var hw := (fg2 * sk.get_bone_pose(h)).origin
	var r2 := Quaternion((hw - fg2.origin).normalized(), (t2 - fg2.origin).normalized())
	var fb := Basis(r2) * fg2.basis
	sk.set_bone_pose_rotation(f, (ag2.basis.orthonormalized().inverse() * fb.orthonormalized()).get_rotation_quaternion())
	# the foot: turned to where it was planted, and tipped from flat onto the slope under it
	var nl := (gt.basis.inverse() * n).normalized()
	var ang := minf(Vector3.UP.angle_to(nl), TILT)
	if ang < 0.01 and absf(turn) < 0.005:
		return
	var upl := (gt.basis.inverse() * Vector3.UP).normalized()
	var r := Basis(upl, turn)
	if ang >= 0.01:
		r = Basis(upl.cross(nl).normalized(), ang) * r
	var fg3 := Transform3D(fb, fg2.origin)
	var hg3 := fg3 * sk.get_bone_pose(h)
	var hb := r * hg3.basis
	sk.set_bone_pose_rotation(h, (fb.orthonormalized().inverse() * hb.orthonormalized()).get_rotation_quaternion())
