extends SkeletonModifier3D
## Springy hair and trouser chains (Pete, 27 Nov; 1v1's springs as the model): the rig has a Hair bone (what hangs
## off the head at the sides and back) and, where a character has one, a chain bone on the
## front of a thigh (tools/characters/rig_wednesday.py). After the animation each of those bones lags behind the way
## its tip is being thrown about: a damped spring on the tip's acceleration (stiffness, damping, how hard it's
## thrown, the most it moves), so hair bounces when she lands, swings when she turns and settles when she stops.
## Hair also hangs: when the head tips (lying down, crawling, a ragdoll) it falls back towards how
## it hangs from an upright head, so long tails droop instead of sticking out (27 Nov review); it runs after the
## ragdoll, so a limp body's hair hangs too. Hats and hoods aren't
## in the Hair bone (the rig leaves the top of the head out).

const SPRINGS := {
	# bone: [stiffness, damping, gain, most it moves (m), length (model units, tip from the pivot)]
	"Hair": [330.0, 8.5, 0.85, 0.13, 0.6],
	"LeftChain": [210.0, 5.0, 1.5, 0.16, 0.3],
	"RightChain": [210.0, 5.0, 1.5, 0.16, 0.3],
}

var _st := {}          # bone -> {id, p, v, tip, vel}
var _t0 := 0

func _process_modification() -> void:
	var sk := get_skeleton()
	if not sk:
		return
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _t0) / 1e6, 0.001, 0.05) if _t0 > 0 else 0.016
	_t0 = now
	var gt := sk.global_transform
	var inv := gt.affine_inverse()
	for n in SPRINGS:
		if not _st.has(n):
			var id := sk.find_bone(n)
			_st[n] = {"id": id, "p": Vector3.ZERO, "v": Vector3.ZERO, "tip": Vector3.INF, "vel": Vector3.ZERO}
		var s: Dictionary = _st[n]
		var b: int = s.id
		if b < 0:
			continue
		var c: Array = SPRINGS[n]
		var g := sk.get_bone_global_pose(b)
		var tip_w := gt * (g * Vector3(0, float(c[4]), 0))
		var old: Vector3 = s.tip
		s.tip = tip_w
		if old == Vector3.INF or old.distance_to(tip_w) > 2.0:   # first frame, or a teleport (respawn, portal)
			s.vel = Vector3.ZERO
			s.p = Vector3.ZERO
			s.v = Vector3.ZERO
			continue
		var vel := (tip_w - old) / dt
		var acc := (vel - (s.vel as Vector3)) / dt
		s.vel = vel
		var p: Vector3 = s.p
		var v: Vector3 = s.v
		v += (-float(c[0]) * p - float(c[1]) * v - acc * float(c[2])) * dt
		p += v * dt
		if p.length() > float(c[3]):
			p = p.normalized() * float(c[3])
		s.p = p
		s.v = v
		var base_w := gt * g.origin
		var dir_w := tip_w - base_w
		var par := sk.get_bone_parent(b)
		var pg := sk.get_bone_global_pose(par) if par >= 0 else Transform3D()
		var hang := dir_w
		if n == "Hair" and par >= 0:   # gravity: undo most of the head's tip for the hair
			var hu := (gt.basis * pg.basis.y).normalized()
			var tilt := hu.angle_to(Vector3.UP)
			if tilt > 0.05:
				var ax := hu.cross(Vector3.UP).normalized()
				hang = Basis(ax, minf(tilt, deg_to_rad(175.0))) * dir_w   # all the way: hair hangs as from an upright head
		if p.length() < 0.001 and hang.is_equal_approx(dir_w):
			continue
		# turn the bone so its tip moves by p (and hangs)
		var to_w := hang + p
		var q := Quaternion(dir_w.normalized(), to_w.normalized())
		var rot_s := (inv.basis.orthonormalized() * Basis(q) * gt.basis.orthonormalized())
		var ng := Transform3D(rot_s * g.basis, g.origin)
		sk.set_bone_pose_rotation(b, (pg.basis.orthonormalized().inverse() * ng.basis.orthonormalized()).get_rotation_quaternion())
