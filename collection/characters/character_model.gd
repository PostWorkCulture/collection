extends Node3D
## A rigged character with motion-captured movement (AAA phase 1). The model is the 1v1 character joined into one
## body and rigged (tools/characters/rig_wednesday.py); its clips are Mixamo motion capture moved onto that rig
## (tools/characters/retarget.py, list in tools/characters/build_character.sh). The fighter calls tick() every frame.
##
## How it moves:
## - free running (fists or bat, not fighting): she turns and runs the way she's going, like a person would, and only
##   her head and chest turn back towards the aim (up to 25 degrees); idle, walk, run and sprint by speed
## - fighting with fists or the bat (just attacked, or aiming): she faces the aim and the legs use the strafe and
##   backward-run set, turning up to 40 degrees towards where she's going
## - with a gun: she faces the aim and runs with the rifle 8-way set (forward, back, sideways, diagonals); the gun is
##   raised to the shoulder when aiming or firing; dual pistols are held out in both hands
## - every clip plays at the speed that keeps the feet with the ground
## - crouched, in the air (take-off, falling, a soft landing; a heavy landing after a long drop), on ladders, downed
##   (crawling) and dead (a fall to the ground that stays until the respawn)
## - over the top: a boxing guard while fists are up, jab / cross / hook, a two-handed bat swing, a flinch when hit;
##   the head steadies towards the aim

const SpineTwist := preload("res://characters/spine_twist.gd")
const HandIK := preload("res://characters/hand_ik.gd")

const GAME_HEIGHT := 2.2          # the model is scaled so the top of the head is here (the fighter's capsule is 2.25)
const FREE_TWIST := deg_to_rad(25.0)
const FIGHT_TURN := deg_to_rad(40.0)
const COMBAT_HOLD := 1.4          # seconds after an attack that she keeps facing the aim
const STANCE_FISTS := 0.5         # radians the body turns back to the left in the boxing stance
const STRAFE_TURN := deg_to_rad(62.0)
const AIR_TURN := deg_to_rad(-20.0)
const ARMS := ["LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand", "RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const UPPER := ["Spine1", "Spine2", "Neck", "Head", "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
		"RightShoulder", "RightArm", "RightForeArm", "RightHand"]
const LOOPS := ["idle", "walk", "run", "sprint", "run_back", "strafe_left", "strafe_right", "strafe_walk_left",
		"strafe_walk_right", "crouch_idle", "crouch_fwd", "crouch_back", "crouch_left", "crouch_right", "fall",
		"ladder_climb", "downed_crawl", "smg_idle", "pistol_idle", "box_guard", "smg_aim", "u_run_fwd", "r_idle",
		"r_sprint_fwd", "r_sprint_back", "r_sprint_left", "r_sprint_right", "r_sprint_fwd_left", "r_sprint_fwd_right",
		"crouch_idle2", "crouch_walk2", "walk2", "crouch_sneak", "crawl2", "fight_idle", "dance_kick_step", "dance_raise_roof",
		"dance_running_man", "dance_arm_wave", "dance_shimmy", "dance_tut", "dance_step", "dance_twist", "dance_salsa",
		"dance_side_to_side", "cel_victory_idle_vegas", "cel_victory_idle_aj", "pose_hand_hip", "pose_happy_idle", "pose_bored"]
const PALM := 0.07
## celebrations (once), dances and poses (looping); Mixamo clips, see tools/characters/build_character.sh
const CELEBRATIONS := ["cel_victory", "cel_cheer", "cel_flex", "cel_arms_back"]
const DANCES := ["dance_kick_step", "dance_raise_roof", "dance_running_man", "dance_arm_wave", "dance_shimmy", "dance_tut",
		"dance_step", "dance_twist", "dance_salsa", "dance_side_to_side", "cel_victory_idle_vegas", "cel_victory_idle_aj"]
const POSES := ["pose_hand_hip", "pose_happy_idle", "pose_bored", "pose_bboy"]
const EMOTES := CELEBRATIONS + DANCES + POSES                # game metres from the wrist to the middle of the palm, along the hand

var id := ""
var scene: Node3D
var skel: Skeleton3D
var player: AnimationPlayer
var tree: AnimationTree
var twist: Node                    # SpineTwist modifier
var hik: Node                      # HandIK modifier (after the twist): the fighter sets its targets each frame
var meta := {}
var k := 1.0                       # model units -> game metres
var meshes: Array[MeshInstance3D] = []
var hand_r := -1
var hand_l := -1
var head := -1
var hand_fwd := Vector3.FORWARD    # in the right hand's bone space: the way a held thing points (forward in the T-pose)
var hand_up := Vector3.UP
var _fist := [Vector3.FORWARD, Vector3.FORWARD]   # per hand: the way a gripped bat leaves the fist (forward in the T-pose)
var _along := [Vector3.UP, Vector3.UP]   # per hand (right, left), in its bone space: wrist to fingers in the T-pose
var body_yaw := 0.0

var _state := ""
var _kind := ""
var _air_t := 0.0
var _fall_t := 0.0
var _jumping := 0.0
var _was_ground := true
var _combat := 0.0                 # > 0: facing the aim after an attack
var _fire_t := 0.0                 # > 0: gun raised after a shot
var _atk_n := 0
var _mats: Array[StandardMaterial3D] = []
var _rings := {}
var _free_pts: Array = []
var _jump_t := 0.0
var _dead_t := 0.0
var _hit_t := -1.0                 # time since the last flinch (< 0: none)
var _hit_big := false
var _emote := ""                   # playing a celebration, dance or pose ("" = none)
var _emote_t := 0.0
var _emote_next := ""              # after a one-off celebration ends, this plays (a dance)
var _stance := 0.0

static func path_for(cid: String) -> String:
	return "res://characters/%s/%s.glb" % [cid, cid]

static func exists(cid: String) -> bool:
	return cid != "" and ResourceLoader.exists(path_for(cid))

func setup(cid: String) -> void:
	id = cid
	scene = (load(path_for(cid)) as PackedScene).instantiate()
	add_child(scene)
	skel = scene.find_children("*", "Skeleton3D")[0]
	player = scene.find_children("*", "AnimationPlayer")[0]
	var mf := FileAccess.open("res://characters/%s/%s.json" % [cid, cid], FileAccess.READ)
	if mf:
		meta = JSON.parse_string(mf.get_as_text())
	var top := 0.0
	for m in scene.find_children("*", "MeshInstance3D"):
		var mi := m as MeshInstance3D
		meshes.append(mi)
		mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC   # lit by the bounce light, never baked into it (a moving body
		                                                  # left as "static" makes SDFGI re-voxelise around it every frame)
		top = maxf(top, mi.get_aabb().end.y)
	k = GAME_HEIGHT / maxf(top, 0.1)
	scene.scale = Vector3.ONE * k
	hand_r = skel.find_bone("RightHand")
	hand_l = skel.find_bone("LeftHand")
	head = skel.find_bone("Head")
	if hand_r >= 0:
		var rb := skel.get_bone_global_rest(hand_r).basis.orthonormalized()
		hand_fwd = rb.inverse() * Vector3(0, 0, 1)
		hand_up = rb.inverse() * Vector3(0, 1, 0)
	for i in 2:
		var hb := hand_r if i == 0 else hand_l
		if hb >= 0 and skel.get_bone_parent(hb) >= 0:
			var hr := skel.get_bone_global_rest(hb)
			var er := skel.get_bone_global_rest(skel.get_bone_parent(hb))
			_along[i] = (hr.basis.orthonormalized().inverse() * (hr.origin - er.origin)).normalized()
			_fist[i] = hr.basis.orthonormalized().inverse() * Vector3(0, 0, 1)
	for a in player.get_animation_list():
		var an := player.get_animation(a)
		an.loop_mode = Animation.LOOP_LINEAR if a in LOOPS else Animation.LOOP_NONE
	# own copies of the materials (so marking one character doesn't mark them all), with a soft rim so the dark
	# clothes keep their shape against dark backgrounds
	for mi in meshes:
		for s in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(s)
			if mat is StandardMaterial3D:
				var c := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.rim_enabled = true
				c.rim = 0.5
				c.rim_tint = 0.6
				c.roughness = 0.62
				mi.set_surface_override_material(s, c)
				_mats.append(c)
	_build_tree()
	twist = SpineTwist.new()
	skel.add_child(twist)
	hik = HandIK.new()
	skel.add_child(hik)

func _speed(clip: String) -> float:
	return float(meta.get(clip, {}).get("speed", 0.0)) * k

func _len(clip: String) -> float:
	return float(meta.get(clip, {}).get("frames", 30)) / 30.0

func _anim(clip: String, from := -1.0, to := -1.0) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = clip
	if from >= 0.0:
		a.use_custom_timeline = true
		a.start_offset = from
		a.timeline_length = maxf(0.05, (to if to > 0.0 else _len(clip)) - from)
		a.stretch_time_scale = false
	return a

func _filter(node: AnimationNode, bones: Array) -> void:
	node.filter_enabled = true
	for b in bones:
		node.set_filter_path(NodePath("Armature/Skeleton3D:" + b), true)

func _space2(points: Dictionary, centre: String) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-12, -12)
	bs.max_space = Vector2(12, 12)
	bs.sync = true
	bs.add_blend_point(_anim(centre), Vector2.ZERO, -1, centre)
	for c in points:
		bs.add_blend_point(_anim(c), (points[c] as Vector2).normalized() * _speed(c), -1, c)
	return bs

func _space1(points: Array) -> AnimationNodeBlendSpace1D:
	var bs := AnimationNodeBlendSpace1D.new()
	bs.min_space = 0.0
	bs.max_space = 12.0
	bs.sync = true
	for c in points:
		bs.add_blend_point(_anim(c), 0.0 if c.contains("idle") else _speed(c), -1, c)
	return bs

func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	# the five ways of getting about on the ground
	# free: idle, walk, a quick walk (the walk played up to 1.5x as fast, so a fast walk doesn't turn into a
	# half-walk, half-run), run, sprint; _free_pts are [where on the blend, the speed the clip really covers]
	var sw := _speed("walk2")
	_free_pts = [[0.0, 0.0], [sw, sw], [sw * 1.5, sw], [_speed("u_run_fwd"), _speed("u_run_fwd")], [_speed("sprint"), _speed("sprint")]]
	var fb := AnimationNodeBlendSpace1D.new()
	fb.min_space = 0.0
	fb.max_space = 12.0
	fb.sync = true
	var fclips := ["idle", "walk2", "walk2", "u_run_fwd", "sprint"]
	for i in fclips.size():
		fb.add_blend_point(_anim(fclips[i]), _free_pts[i][0], -1, "p%d" % i)
	bt.add_node("free", fb)
	_rings["free"] = _speed("sprint")
	bt.add_node("fight", _space2({"walk2": Vector2(0, 1), "run": Vector2(0, 1), "sprint": Vector2(0, 1), "run_back": Vector2(0, -1),
			"strafe_right": Vector2(1, 0), "strafe_left": Vector2(-1, 0), "strafe_walk_right": Vector2(1, 0),
			"strafe_walk_left": Vector2(-1, 0)}, "box_guard"))   # standing: the boxing stance (lead foot forward)
	_rings["fight"] = {"f": _speed("sprint"), "b": _speed("run_back"), "r": _speed("strafe_right"), "l": _speed("strafe_left")}
	bt.add_node("gun", _space2({"r_sprint_fwd": Vector2(0, 1), "r_sprint_back": Vector2(0, -1), "r_sprint_left": Vector2(-1, 0),
			"r_sprint_right": Vector2(1, 0), "r_sprint_fwd_left": Vector2(-1, 1), "r_sprint_fwd_right": Vector2(1, 1)}, "r_idle"))
	_rings["gun"] = _speed("r_sprint_fwd")
	bt.add_node("crouch", _space1(["crouch_idle", "crouch_sneak"]))
	_rings["crouch"] = _speed("crouch_sneak")
	bt.add_node("crouch_fight", _space2({"crouch_fwd": Vector2(0, 1), "crouch_back": Vector2(0, -1), "crouch_right": Vector2(1, 0),
			"crouch_left": Vector2(-1, 0)}, "crouch_idle"))
	_rings["crouch_fight"] = {"f": _speed("crouch_fwd"), "b": _speed("crouch_back"), "r": _speed("crouch_right"), "l": _speed("crouch_left")}
	var kind := AnimationNodeTransition.new()
	kind.xfade_time = 0.22
	var kinds := ["free", "fight", "gun", "crouch", "crouch_fight"]
	for n in kinds:
		kind.add_input(n)
	bt.add_node("kind", kind)
	for i in kinds.size():
		bt.connect_node("kind", i, kinds[i])
	bt.add_node("ground_ts", AnimationNodeTimeScale.new())
	bt.connect_node("ground_ts", 0, "kind")
	# jump (from the push-off), falling, ladders, downed, dead
	# a running jump from the push-off; at the top it eases into a balanced airborne pose (arms out, legs split)
	# that it holds until the landing; falling off a ledge uses the same pose
	bt.add_node("jump_anim", _anim("jump_run", 0.33, 0.62))
	bt.add_node("jump", AnimationNodeTimeScale.new())
	bt.connect_node("jump", 0, "jump_anim")
	var air := _anim("jump_run", 0.42, 0.5)   # in the air: one knee up, the other leg reaching down; drifts slowly
	air.loop_mode = Animation.LOOP_PINGPONG
	bt.add_node("fall_legs", air)
	bt.add_node("fall_top", _anim("run", 0.47, 0.5))   # the top half from a running stride: chest square, arms bent low
	var ft := AnimationNodeBlend2.new()
	_filter(ft, UPPER + ["Spine"])
	bt.add_node("fall_anim", ft)
	bt.connect_node("fall_anim", 0, "fall_legs")
	bt.connect_node("fall_anim", 1, "fall_top")
	bt.add_node("fall", AnimationNodeTimeScale.new())
	bt.connect_node("fall", 0, "fall_anim")
	bt.add_node("ladder", _anim("ladder_climb"))
	bt.add_node("ladder_ts", AnimationNodeTimeScale.new())
	bt.connect_node("ladder_ts", 0, "ladder")
	bt.add_node("crawl", _anim("crawl2"))
	bt.add_node("crawl_ts", AnimationNodeTimeScale.new())
	bt.connect_node("crawl_ts", 0, "crawl")
	# death: the jolt of the hit, then the collapse (the clip's long stagger between the two is cut out)
	var dk := AnimationNodeTransition.new()
	dk.xfade_time = 0.3
	dk.add_input("knees")
	dk.add_input("down")
	bt.add_node("death_kind", dk)
	bt.add_node("death_a", _anim("death", 0.15, 0.5))   # the hit: head and chest jolt
	bt.add_node("death_b", _anim("death", 1.5))         # the knees go, she folds forward and lies face down
	bt.connect_node("death_kind", 0, "death_a")
	bt.connect_node("death_kind", 1, "death_b")
	bt.add_node("death", AnimationNodeTimeScale.new())
	bt.connect_node("death", 0, "death_kind")
	var st := AnimationNodeTransition.new()
	st.xfade_time = 0.16
	var states := ["ground", "jump", "fall", "ladder", "downed", "dead", "emote"]
	for n in states:
		st.add_input(n)
	bt.add_node("state", st)
	bt.connect_node("state", 0, "ground_ts")
	bt.connect_node("state", 1, "jump")
	bt.connect_node("state", 2, "fall")
	bt.connect_node("state", 3, "ladder_ts")
	bt.connect_node("state", 4, "crawl_ts")
	bt.connect_node("state", 5, "death")
	# celebrations, dances and poses: the whole body, one at a time
	var ek := AnimationNodeTransition.new()
	ek.xfade_time = 0.3
	for e in EMOTES:
		ek.add_input(e)
	bt.add_node("emote_kind", ek)
	for i in EMOTES.size():
		bt.add_node("em_" + EMOTES[i], _anim(EMOTES[i]))
		bt.connect_node("emote_kind", i, "em_" + EMOTES[i])
	bt.connect_node("state", 6, "emote_kind")
	# landings: a soft knee bend after a hop, the heavy landing after a long drop
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.05
	land.fadeout_time = 0.22
	bt.add_node("land", land)
	var lk := AnimationNodeTransition.new()
	lk.xfade_time = 0.0
	lk.add_input("soft")
	lk.add_input("hard")
	bt.add_node("land_kind", lk)
	bt.add_node("land_soft", _anim("jump2", 1.17, 1.62))
	bt.add_node("land_hard", _anim("land", 0.18, 0.95))
	bt.connect_node("land_kind", 0, "land_soft")
	bt.connect_node("land_kind", 1, "land_hard")
	bt.connect_node("land", 0, "state")
	bt.connect_node("land", 1, "land_kind")
	# arms: boxing guard with fists up, the gun at the shoulder when aiming, two pistols held out
	var arms_k := AnimationNodeTransition.new()
	arms_k.xfade_time = 0.15
	for n in ["guard", "aim", "duals", "relax"]:
		arms_k.add_input(n)
	bt.add_node("arms_kind", arms_k)
	bt.add_node("guard", _anim("box_guard"))
	bt.add_node("aim", _anim("smg_aim"))
	bt.add_node("duals", _anim("pistol_idle"))
	bt.connect_node("arms_kind", 0, "guard")
	bt.connect_node("arms_kind", 1, "aim")
	bt.connect_node("arms_kind", 2, "duals")
	bt.add_node("relax", _anim("idle"))   # mixed into the walk and the sneak: arms nearer the body, less bent
	bt.connect_node("arms_kind", 3, "relax")
	var arms := AnimationNodeBlend2.new()
	_filter(arms, ARMS + ["Spine2", "Neck"])
	bt.add_node("arms", arms)
	bt.connect_node("arms", 0, "land")
	bt.connect_node("arms", 1, "arms_kind")
	# attacks: from the guard / wind-up straight into the strike; one set for the top half while moving, one for the
	# whole body when standing (steps and hip turn); a node's output can only feed one input, so each has its own
	for suf in ["", "_full"]:
		var ak := AnimationNodeTransition.new()
		ak.xfade_time = 0.0
		for n in ["jab", "cross", "hook", "bat"]:
			ak.add_input(n)
		bt.add_node("atk_kind" + suf, ak)
		bt.add_node("jab" + suf, _anim("box_jab", 0.32, 1.25))
		bt.add_node("cross" + suf, _anim("box_cross", 0.36, 1.35))
		bt.add_node("hook" + suf, _anim("box_hook", 0.3, 1.2))
		bt.add_node("bat" + suf, _anim("bat_swing2", 1.02, 1.75))   # from the load through the follow-through, both hands on
		bt.connect_node("atk_kind" + suf, 0, "jab" + suf)
		bt.connect_node("atk_kind" + suf, 1, "cross" + suf)
		bt.connect_node("atk_kind" + suf, 2, "hook" + suf)
		bt.connect_node("atk_kind" + suf, 3, "bat" + suf)
		bt.add_node("atk_ts" + suf, AnimationNodeTimeScale.new())
		bt.connect_node("atk_ts" + suf, 0, "atk_kind" + suf)
	var atk := AnimationNodeOneShot.new()           # upper body only (moving)
	atk.fadein_time = 0.04
	atk.fadeout_time = 0.18
	_filter(atk, UPPER + ["Spine"])
	bt.add_node("attack", atk)
	bt.connect_node("attack", 0, "arms")
	bt.connect_node("attack", 1, "atk_ts")
	var atk_full := AnimationNodeOneShot.new()      # the whole body (standing)
	atk_full.fadein_time = 0.04
	atk_full.fadeout_time = 0.2
	bt.add_node("attack_full", atk_full)
	bt.connect_node("attack_full", 0, "attack")
	bt.connect_node("attack_full", 1, "atk_ts_full")
	# hit flinch over the top
	var hk := AnimationNodeTransition.new()
	hk.xfade_time = 0.0
	hk.add_input("light")
	hk.add_input("medium")
	bt.add_node("hit_kind", hk)
	bt.add_node("hit_light", _anim("hit_medium", 0.05, 0.5))   # the body-and-head jolt of the medium hit, at less strength
	bt.add_node("hit_medium", _anim("hit_medium", 0.05, 0.9))
	bt.connect_node("hit_kind", 0, "hit_light")
	bt.connect_node("hit_kind", 1, "hit_medium")
	bt.add_node("hit_ts", AnimationNodeTimeScale.new())
	bt.connect_node("hit_ts", 0, "hit_kind")
	bt.add_node("hit_seek", AnimationNodeTimeSeek.new())
	bt.connect_node("hit_seek", 0, "hit_ts")
	var hit := AnimationNodeBlend2.new()   # mixed in by an envelope from tick(): a quick jolt, then back
	_filter(hit, ["Spine", "Spine1", "Spine2", "Neck", "Head"])   # the body and head jolt; the arms stay
	bt.add_node("hit", hit)
	bt.connect_node("hit", 0, "attack_full")
	bt.connect_node("hit", 1, "hit_seek")
	bt.connect_node("output", 0, "hit")
	tree = AnimationTree.new()
	tree.tree_root = bt
	scene.add_child(tree)
	tree.anim_player = tree.get_path_to(player)
	tree.root_node = tree.get_path_to(scene)
	tree.active = true
	tree.set("parameters/hit_ts/scale", 1.5)
	tree.set("parameters/fall_anim/blend_amount", 0.75)
	tree.set("parameters/fall/scale", 0.4)
	tree.set("parameters/death/scale", 1.45)

## clip speed on a 2D blend's outer ring in this local direction (an ellipse through the four ring speeds)
func _ring_speed(ring, d: Vector2) -> float:
	if ring is float:
		return ring
	if d.length() < 0.001:
		return 1.0
	d = d.normalized()
	var fx: float = ring.r if d.x > 0.0 else ring.l
	var fy: float = ring.f if d.y > 0.0 else ring.b
	return 1.0 / sqrt((d.x * d.x) / maxf(0.01, fx * fx) + (d.y * d.y) / maxf(0.01, fy * fy))

func _go(s: String) -> void:
	if s != _state:
		_state = s
		tree.set("parameters/state/transition_request", s)

func _set_kind(s: String) -> void:
	if s != _kind:
		_kind = s
		tree.set("parameters/kind/transition_request", s)

## once a frame from the fighter
func tick(dt: float, f) -> void:
	if not tree:
		return
	hik.weights = [0.0, 0.0]   # the fighter's weapon hold switches it on after this
	hik.pulls = [0.0, 0.0]
	hik.nudges = [Vector3.ZERO, Vector3.ZERO]
	var yaw: float = f.yaw
	var v: Vector3 = f.velocity
	var hv := Vector2(v.x, v.z)
	var speed := hv.length()
	var ground: bool = f.is_on_floor()
	var w: String = f.current_weapon()
	var gun := w != "fists" and w != "bat"
	_combat = maxf(0.0, _combat - dt)
	_fire_t = maxf(0.0, _fire_t - dt)
	var aiming: bool = f.ads or _fire_t > 0.0
	var fighting := gun or _combat > 0.0 or aiming
	var alive: bool = f.alive and not f.downed
	# which way the body faces
	var target := yaw
	if alive and not fighting:
		if speed > 1.0:
			target = atan2(v.x, v.z)
		else:
			target = body_yaw if absf(wrapf(yaw - body_yaw, -PI, PI)) < FREE_TWIST else yaw
	elif alive and not gun and speed > 0.6:   # fighting with fists or the bat: the legs lean towards the run
		var rel := wrapf(atan2(v.x, v.z) - yaw, -PI, PI)
		# forward and its diagonals turn the legs up to 40 degrees; straight sideways is a real side-step (no turn)
		var side_k := clampf((deg_to_rad(80.0) - absf(rel)) / deg_to_rad(35.0), 0.0, 1.0)
		if absf(rel) < PI * 0.62:
			target = yaw + clampf(rel, -FIGHT_TURN, FIGHT_TURN) * side_k
	body_yaw = lerp_angle(body_yaw, target, minf(1.0, dt * (14.0 if fighting else 9.0)))
	if f.downed:
		body_yaw = yaw
	# a fighter stands bladed (lead shoulder to the target): the boxing clips turn the hips about 40 degrees to the
	# right, so standing in the fight stance the whole body is turned back partway to the left
	# the strafe clips run with the body turned about 65 degrees towards where she's going; turned back by that much,
	# the chest stays on the aim and the legs side-step under it
	var st := 0.0
	if alive and _kind == "fight" and speed < 1.2 and w == "fists":
		st = STANCE_FISTS
	elif alive and _state in ["jump", "fall"]:
		st = AIR_TURN   # the jump clip's hips are turned about 20 degrees left: square her up to where she's going
	elif alive and _kind == "fight" and speed >= 1.2:
		var lr := wrapf(atan2(v.x, v.z) - body_yaw, -PI, PI)   # + = to her left
		st = -STRAFE_TURN * sin(lr) * clampf((speed - 1.2) / 2.0, 0.0, 1.0)
	_stance = move_toward(_stance, st, dt * 3.0)
	rotation = Vector3(0, body_yaw + _stance, 0)
	var fwd := Vector2(sin(body_yaw), cos(body_yaw))
	var rgt := Vector2(-cos(body_yaw), sin(body_yaw))
	var local := Vector2(hv.dot(rgt), hv.dot(fwd))
	# state
	if _emote != "" and (not f.alive or f.downed or hv.length() > 0.8 or not ground):
		stop_emote()   # moving, falling or getting hurt ends it
	if _emote != "":
		_go("emote")
		_emote_t += dt
		if _emote_next != "" and _emote_t >= _len(_emote) - 0.3:
			_play_emote(_emote_next)
			_emote_next = ""
	elif not f.alive:
		if _state != "dead":
			_dead_t = 0.0
			tree.set("parameters/death_kind/transition_request", "knees")
			tree.set("parameters/death/scale", 1.4)
		_go("dead")
		_dead_t += dt
		if _dead_t > 0.24 and _dead_t - dt <= 0.24:
			tree.set("parameters/death_kind/transition_request", "down")
			tree.set("parameters/death/scale", 1.9)   # down and settled flat in about 1.2 s
	elif f.downed:
		_go("downed")
		tree.set("parameters/crawl_ts/scale", clampf(speed / maxf(0.1, _speed("crawl2")), 0.0, 3.0) if speed > 0.2 else 0.0)
	elif f.on_ladder and not ground:
		_go("ladder")
		tree.set("parameters/ladder_ts/scale", clampf(absf(v.y) / 3.0, 0.0, 2.2))
	elif ground or _air_t < 0.12:
		if _state in ["fall", "jump"] and ground:
			if _fall_t > 0.3 or _air_t > 0.25:
				tree.set("parameters/land_kind/transition_request", "hard" if _fall_t > 0.9 else "soft")
				tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		_go("ground")
		var crouch: bool = f.crouching
		var kind := "free"
		if crouch:
			kind = "crouch_fight" if fighting else "crouch"
		elif gun:
			kind = "gun"
		elif fighting:
			kind = "fight"
		_set_kind(kind)
		var ts := 1.0
		if kind == "free":
			tree.set("parameters/free/blend_position", speed)
			var real := speed
			for i in range(1, _free_pts.size()):
				var a: Array = _free_pts[i - 1]
				var b: Array = _free_pts[i]
				if speed <= float(b[0]):
					var wt := (speed - float(a[0])) / maxf(0.001, float(b[0]) - float(a[0]))
					real = lerpf(float(a[1]), float(b[1]), wt)
					break
				real = float(b[1])
			ts = speed / real if real > 0.05 else 1.0
		elif kind == "crouch":
			var top: float = _rings[kind]
			var pos := minf(speed, top)
			if speed > top:
				ts = speed / top
			tree.set("parameters/%s/blend_position" % kind, pos)
		else:
			var rs := _ring_speed(_rings[kind], local)
			var p2 := local
			if local.length() > rs:
				ts = local.length() / rs
				p2 = local.normalized() * rs
			tree.set("parameters/%s/blend_position" % kind, p2)
		tree.set("parameters/ground_ts/scale", clampf(ts, 0.8, 2.3 if crouch else 1.7))
	else:
		if v.y > 2.0 and _was_ground:
			_jumping = 0.29   # the push-off, then the air loop
			_jump_t = 0.0
		_jumping = maxf(0.0, _jumping - dt)
		if _jumping > 0.0:
			_go("jump")
		else:
			_go("fall")
	if ground:
		_jumping = 0.0
	_air_t = 0.0 if ground else _air_t + dt
	_fall_t = 0.0 if ground else (_fall_t + dt if v.y < 0.0 else _fall_t)
	_was_ground = ground
	# arms over the top
	var arms_on := 0.0
	if alive and not (f.on_ladder and not ground):
		if w == "fists" and fighting:
			tree.set("parameters/arms_kind/transition_request", "guard")
			arms_on = 1.0
		elif w == "duals":
			tree.set("parameters/arms_kind/transition_request", "duals")
			arms_on = 1.0
		elif gun and aiming:
			tree.set("parameters/arms_kind/transition_request", "aim")
			arms_on = 1.0
		elif w == "fists" and f.crouching:   # sneaking: forearms up at the waist, elbows bent
			tree.set("parameters/arms_kind/transition_request", "guard")
			arms_on = 0.4
		elif w == "fists" and _kind == "free" and speed > 0.3:   # walking: half the arms from standing, so they
			tree.set("parameters/arms_kind/transition_request", "relax")   # swing closer to the body
			arms_on = 0.45 * clampf((5.0 - speed) / 2.5, 0.0, 1.0)
	var a0 := float(tree.get("parameters/arms/blend_amount"))
	var a1 := move_toward(a0, arms_on, dt * 7.0)
	tree.set("parameters/arms/blend_amount", a1)
	var drop := 0.0
	if w == "fists" and fighting:
		drop = 0.36      # fists at the chin, not over the eyes
	elif w == "duals":
		drop = 0.2       # pistols just under the eye line
	twist.arm_drop = drop * a1
	# walking and crouching: the arms swing close to the body (the clips' arm swing is for a narrower body)
	var arm_k := clampf(speed / 1.5, 0.0, 1.0) * clampf((6.0 - speed) / 3.0, 0.3, 1.0) * (1.0 - a1)   # most at a walk
	twist.arm_in = 0.25 * arm_k if alive and _kind in ["free", "crouch", "crouch_fight"] and _state == "ground" else 0.0
	if alive and f.crouching and w == "fists" and not fighting:
		twist.arm_in = 0.2
	if w == "fists" and fighting:
		twist.arm_in = -0.12 * a1   # guard: fists apart at the cheeks, not pressed together
		if not bool(tree.get("parameters/attack/active")) and not bool(tree.get("parameters/attack_full/active")):
			var ahead := Vector3(sin(yaw), 0.0, cos(yaw)) * 0.09   # and held a hand's width out in front of the face
			hik.nudges = [ahead, ahead]
			hik.weights = [a1, a1]
	# a flinch: up in 0.05 s, back by 0.4 s (0.6 s for a heavy hit)
	var amt := 0.0
	if _hit_t >= 0.0:
		_hit_t += dt
		var span := 0.6 if _hit_big else 0.4
		amt = minf(_hit_t / 0.05, 1.0) * clampf(1.0 - (_hit_t - 0.05) / (span - 0.05), 0.0, 1.0) * (1.0 if _hit_big else 0.75)
		if _hit_t > span:
			_hit_t = -1.0
	tree.set("parameters/hit/blend_amount", amt if alive else 0.0)
	# spine and head: free running looks back towards the aim; fighting keeps the chest on the aim
	var to_aim := wrapf(yaw - body_yaw, -PI, PI)
	twist.yaw = clampf(to_aim, -FREE_TWIST, FREE_TWIST) if alive else 0.0
	twist.pitch = clampf(f.pitch, -0.9, 0.9) * (0.7 if alive and fighting else 0.25 if alive else 0.0) + 0.35 * amt \
			- (0.22 if alive and f.crouching and not fighting else 0.0)   # + the flinch rocks the chest back; sneaking leans in
	twist.steady = (1.0 if fighting else 0.9) if alive else (0.8 if f.downed and f.alive else 0.0)
	twist.head_up = 0.8 if f.downed and f.alive else (0.5 if alive and f.crouching else (0.25 if alive and fighting and not gun else 0.0))   # eyes on the target over the guard   # crawling, crouching: look ahead
	twist.head_max = 1.4 if f.downed else (0.8 if f.crouching or fighting else 0.6)

func attack(weapon: String, _left: bool) -> void:
	if not tree:
		return
	_combat = COMBAT_HOLD
	var kind := "bat"
	if weapon != "bat":
		_atk_n += 1
		kind = ["jab", "cross", "jab", "hook"][_atk_n % 4]
	for suf in ["", "_full"]:
		tree.set("parameters/atk_kind%s/transition_request" % suf, kind)
		tree.set("parameters/atk_ts%s/scale" % suf, 1.5 if kind == "bat" else 1.6)
	var p := get_parent() as CharacterBody3D
	# punches are thrown by the top half (spine, shoulders, arms) over the boxing stance's legs; a standing bat
	# swing is the whole body (the stride and the hip turn); on the move only the top half swings
	var still := kind == "bat" and Vector2(p.velocity.x, p.velocity.z).length() < 1.5
	tree.set("parameters/%s/request" % ("attack_full" if still else "attack"), AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

func fired() -> void:
	_fire_t = 1.2

## a flinch: a light one for most hits, a bigger one for a heavy hit (bat, headshot)
func hurt(big := false) -> void:
	if tree and _state == "ground":
		tree.set("parameters/hit_kind/transition_request", "medium" if big else "light")
		tree.set("parameters/hit_seek/seek_request", 0.0)
		_hit_t = 0.0
		_hit_big = big

## play a celebration, dance or pose (one of EMOTES); a one-off celebration can be followed by a looping dance
func emote(ename: String, then := "") -> void:
	if not tree or not ename in EMOTES:
		return
	_play_emote(ename)
	_emote_next = then if then in EMOTES else ""

func _play_emote(ename: String) -> void:
	_emote = ename
	_emote_t = 0.0
	tree.set("parameters/emote_kind/transition_request", ename)
	_state = ""   # so _go("emote") restarts the state's transition
	_go("emote")

func stop_emote() -> void:
	_emote = ""
	_emote_next = ""

func is_emoting() -> bool:
	return _emote != ""

func restart() -> void:
	stop_emote()
	_state = ""
	_kind = ""
	_air_t = 0.0
	_fall_t = 0.0
	_combat = 0.0
	_jumping = 0.0
	_hit_t = -1.0
	var p := get_parent()
	body_yaw = float(p.yaw) if p else 0.0

## a bone's position in the world
func bone_world(bname: String) -> Vector3:
	var b := skel.find_bone(bname)
	if b < 0:
		return global_position
	return skel.global_transform * skel.get_bone_global_pose(b).origin

## the right (or left) hand in the world
func hand_transform(right := true) -> Transform3D:
	var b := hand_r if right else hand_l
	if b < 0:
		return global_transform
	return skel.global_transform * skel.get_bone_global_pose(b)

## the middle of a palm in the world (the wrist plus a little along the hand)
func palm(right := true) -> Vector3:
	return hand_transform(right).origin + hand_dir(right) * PALM

## which way the hand points (wrist to fingers) in the world
func hand_dir(right := true) -> Vector3:
	return (hand_transform(right).basis.orthonormalized() * (_along[0 if right else 1] as Vector3)).normalized()

## which way a gripped handle leaves this fist, in the world (thumb side, along the knuckles)
func fist_dir(right := true) -> Vector3:
	return (hand_transform(right).basis.orthonormalized() * (_fist[0 if right else 1] as Vector3)).normalized()

## which way something gripped in the right hand points out of the fist (the bat), the hand's up, and the wrist
func grip_axes() -> Array:
	var h := hand_transform(true)
	var b := h.basis.orthonormalized()
	return [(b * hand_fwd).normalized(), (b * hand_up).normalized(), h.origin]

func head_position() -> Vector3:
	if head < 0:
		return global_position + Vector3.UP * GAME_HEIGHT * 0.85
	return (skel.global_transform * skel.get_bone_global_pose(head)).origin

func set_marked(on: bool) -> void:
	for m in _mats:
		m.stencil_mode = BaseMaterial3D.STENCIL_MODE_XRAY if on else BaseMaterial3D.STENCIL_MODE_DISABLED
		m.stencil_color = Color(0.91, 0.16, 0.16, 0.85)

## first person: only your shadow shows
func set_shadow_only(on: bool) -> void:
	for mi in meshes:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
