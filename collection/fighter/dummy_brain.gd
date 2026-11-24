extends Node
## Phase 2 test dummy: stands still, or strafes left and right at a jog (about 5 m/s) within 3 m of its spot,
## never attacks. Lets you try punches and guns on something that moves. Phase 4 replaces this with the real bot
## brain, driving the same Fighter.

const RANGE := 3.0
const PACE := 0.4

var strafe := false
var _dir := 1.0

func _physics_process(_dt: float) -> void:
	var f := get_parent()
	if not f.alive:
		return
	if strafe and not f.downed and f.home != null:
		var off: Vector3 = f.global_position - f.home[0]
		var side: float = off.dot(f.right())
		if side > RANGE:
			_dir = -1.0
		elif side < -RANGE:
			_dir = 1.0
		f.in_move = Vector2(_dir * PACE, 0)
	else:
		f.in_move = Vector2.ZERO
