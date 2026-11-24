extends Node
## A bot (DESIGN §7). It drives the same Fighter you do, through the same inputs, so it obeys the same physics,
## weapons and rules. It plays by its own information: it only knows about a star or weapon it has actually seen
## (in line of sight, within 9 m on Easy / 15 m Normal / 20 m Hard, under 4 m up or down, checked every 0.3 s) and
## remembers it until it's gone. It sees other players in line of sight; marked players (8+ stars) are always
## known. It hears gunshots and punches and may go and look.
## Each think (every 0.3 s), in order:
##   1. holding 10 stars → run for the shop (fighting only what blocks the way)
##   2. an enemy in its face (under 7 m with fists or a bat, under 13 m with a gun) → fight
##   3. the nearest known star or weapon (distance = across + 3 × up/down; weapons count 4 m closer when it's
##      unarmed; no gun pickups while armed, no bat if it has one)
##   4. something it heard → go and look
##   5. nothing → explore the house: a random indoor spot 8–32 m away, re-picked after 10–16 s or on arrival
## It keeps shooting at anyone further off while moving. Targets: nearest and visible first, then whoever just hurt
## it, downed players (to finish), its current target, revenge (not on Easy), plus a lean of 1.5 × stars towards the
## leader. Difficulty numbers (reaction, aim error, headshot chance, turn speed, firing rhythm, damage) are the web
## game's. Styles come from the web game's Rumble pool and are picked at random each match, hidden.

const Weapons := preload("res://weapons/weapons.gd")

const DIFF := {
	"easy": {"react": 2.2, "err": 10.0, "head": 0.0, "turn": 2.0, "sight": 9.0, "hear": 0.4, "revenge": false, "rof": 2.1, "burst": 2, "pause": [1.3, 2.2], "dmg": 0.7},
	"normal": {"react": 0.8, "err": 3.6, "head": 0.08, "turn": 5.2, "sight": 15.0, "hear": 0.7, "revenge": true, "rof": 1.4, "burst": 5, "pause": [0.5, 1.0], "dmg": 1.0},
	"hard": {"react": 0.4, "err": 1.6, "head": 0.26, "turn": 10.0, "sight": 20.0, "hear": 0.9, "revenge": true, "rof": 1.15, "burst": 8, "pause": [0.2, 0.45], "dmg": 1.0},
}
## strafe = side-to-side while fighting, jump = chance per second of a hop, react/err scale the difficulty values
const STYLES := {
	"rusher": {"strafe": 1.3, "jump": 0.35, "react": 0.75, "err": 1.25},     # charges straight in, jukes and jumps
	"lurker": {"strafe": 0.9, "jump": 0.1, "react": 0.85, "err": 1.0},       # holds still until you're within 13 m, then springs
	"flanker": {"strafe": 1.15, "jump": 0.2, "react": 0.95, "err": 1.0},     # comes at you from the side
	"duelist": {"strafe": 1.0, "jump": 0.15, "react": 1.0, "err": 1.0},      # strafes and trades shots at mid range
	"hunter": {"strafe": 1.1, "jump": 0.2, "react": 0.9, "err": 1.0},        # keeps tracking where it last saw you
	"breacher": {"strafe": 1.2, "jump": 0.3, "react": 0.8, "err": 1.1},      # closes in with hops
}
const THINK := 0.3
const SEE_FAR := 60.0          # how far it can spot another player
const MELEE_FIGHT := 7.0
const GUN_FIGHT := 13.0
const GUN_REACH := 32.0        # shoots at players this close while doing something else

var difficulty := "normal"
var style := "duelist"
var game: Node = null

var f: CharacterBody3D             # the fighter it drives
var agent: NavigationAgent3D
var state := "explore"             # shop / fight / item / listen / explore
var goal := Vector3.INF
var target: Node = null
var seen := {}                     # item → where it was when seen
var visible_foes: Array = []
var killer: Node = null            # who eliminated it last (revenge)
var _d: Dictionary
var _s: Dictionary
var _think_t := 0.0
var _explore_t := 0.0
var _heard := Vector3.INF
var _heard_t := 0.0
var _last_seen := {}               # foe → [position, time]
var _react_t := 0.0                # time spent looking at the current target before it may fire
var _burst_left := 0
var _pause_t := 0.0
var _strafe_dir := 1.0
var _strafe_t := 0.0
var _stuck_t := 0.0
var _last_pos := Vector3.ZERO
var _aim_err := Vector2.ZERO
var _aim_head := false
var _label: Label3D
var _path_mesh: MeshInstance3D
var _side := 1.0
var _ladder_t := 0.0
var _wiggle_t := 0.0
var _wiggle_dir := Vector3.ZERO

func _ready() -> void:
	f = get_parent()
	_d = DIFF.get(difficulty, DIFF["normal"])
	_s = STYLES.get(style, STYLES["duelist"])
	f.dmg_mul = float(_d.dmg)
	f.can_headshot = difficulty != "easy"
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.8
	agent.target_desired_distance = 1.0
	agent.path_max_distance = 3.0
	agent.radius = 0.45
	agent.height = 2.0
	f.add_child.call_deferred(agent)
	_side = 1.0 if randf() < 0.5 else -1.0
	_think_t = randf() * THINK
	if game:
		game.noise.connect(_on_noise)
	f.died.connect(func(src): killer = src; seen.clear())
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0009
	_label.font_size = 28
	_label.outline_size = 6
	_label.position.y = 2.9
	_label.visible = false
	f.add_child.call_deferred(_label)
	_path_mesh = MeshInstance3D.new()
	_path_mesh.top_level = true
	_path_mesh.mesh = ImmediateMesh.new()
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1, 0.8, 0.2)
	pm.no_depth_test = true
	_path_mesh.material_override = pm
	_path_mesh.visible = false
	f.add_child.call_deferred(_path_mesh)

func set_difficulty(d: String) -> void:
	difficulty = d
	_d = DIFF.get(d, DIFF["normal"])
	f.dmg_mul = float(_d.dmg)
	f.can_headshot = d != "easy"

func _now() -> float:
	return Time.get_ticks_msec() * 0.001

# ---------------------------------------------------------------- senses

func _eye() -> Vector3:
	return f.eye_pos()

func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	return f.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _items() -> Array:
	return game.stars + game.drops + game.pickups

func _perceive() -> void:
	var eye := _eye()
	var sight: float = _d.sight
	# forget what's gone or moved
	for it in seen.keys():
		if not is_instance_valid(it) or not it.active or it.global_position.distance_to(seen[it]) > 0.5:
			seen.erase(it)
	for it in _items():
		if not it.active or seen.has(it):
			continue
		var p: Vector3 = it.global_position
		var d := p - f.global_position
		if absf(d.y) > 4.0 or Vector2(d.x, d.z).length() > sight:
			continue
		if _clear_line(eye, p + Vector3.UP * 1.0):
			seen[it] = p
	visible_foes.clear()
	for o in game.fighters:
		if o == f or not o.alive:
			continue
		var top: Vector3 = o.global_position + Vector3.UP * (0.4 if o.downed else 1.4)
		var dist := eye.distance_to(top)
		if o.marked:   # marked players are always known
			visible_foes.append(o)
			_last_seen[o] = [o.global_position, _now()]
			continue
		if dist > SEE_FAR:
			continue
		var to := (top - eye).normalized()
		var ahead := to.dot(f.aim_forward()) > -0.3 or dist < 10.0   # a wide field of view, plus anything close
		if ahead and _clear_line(eye, top):
			visible_foes.append(o)
			_last_seen[o] = [o.global_position, _now()]

func _on_noise(pos: Vector3, radius: float, src: Node) -> void:
	if src == f or not f.alive or f.global_position.distance_to(pos) > radius:
		return
	if randf() < float(_d.hear):
		_heard = pos
		_heard_t = 6.0

# ---------------------------------------------------------------- deciding

func _armed() -> bool:
	return f.gun_id != ""

func _pick_target() -> void:
	var best: Node = null
	var best_s := -1e9
	for o in visible_foes:
		var dist: float = o.global_position.distance_to(f.global_position)
		var sc := -dist
		if f.last_by == o and _now() - f.last_hurt < 4.0:
			sc += 12.0
		if o.downed:
			sc += 6.0
		if o == target:
			sc += 4.0
		if bool(_d.revenge) and o == killer:
			sc += 8.0
		sc += 1.5 * float(mini(o.stars, 10))
		if sc > best_s:
			best_s = sc
			best = o
	if best != target:
		_react_t = 0.0
		_burst_left = 0
		_new_aim_error()
	target = best

func _new_aim_error() -> void:
	var e: float = float(_d.err) * float(_s.err)
	_aim_err = Vector2(randfn(0.0, e * 0.5), randfn(0.0, e * 0.35))
	_aim_head = randf() < float(_d.head)

func _think() -> void:
	# a goal it can't get to (no path): give it up
	if agent.is_inside_tree() and goal != Vector3.INF and not agent.is_navigation_finished() and not agent.is_target_reachable():
		match state:
			"item":
				seen.erase(_goal_item())
			"listen":
				_heard_t = 0.0
				_last_seen.clear()
			"explore":
				_explore_t = 0.0
	_perceive()
	_pick_target()
	var tdist := INF
	if target:
		tdist = target.global_position.distance_to(f.global_position)
	var fight_r := GUN_FIGHT if _armed() else MELEE_FIGHT
	if f.stars >= game.STARS:
		_set_state("shop", game.cash_point)
	elif target and tdist < fight_r:
		_set_state("fight", target.global_position)
	else:
		var it: Variant = _best_item()
		if it != null:
			_set_state("item", it.global_position)
		elif style == "hunter" and _hunt_spot() != Vector3.INF:
			_set_state("listen", _hunt_spot())
		elif _heard_t > 0.0:
			_set_state("listen", _heard)
		else:
			_explore_t -= THINK
			if state != "explore" or _explore_t <= 0.0 or f.global_position.distance_to(goal) < 2.0:
				_explore_t = randf_range(10.0, 16.0)
				var spot: Variant = _explore_spot()
				_set_state("explore", spot if spot != null else f.global_position)
			else:
				state = "explore"

## hunters keep heading for where they last saw someone, for 6 s
func _hunt_spot() -> Vector3:
	for o in _last_seen:
		var e: Array = _last_seen[o]
		if is_instance_valid(o) and o.alive and _now() - float(e[1]) < 6.0 and f.global_position.distance_to(e[0]) > 3.0:
			return e[0]
	return Vector3.INF

func _best_item() -> Variant:
	var best: Variant = null
	var best_d := INF
	var unarmed := not _armed()
	for it in seen:
		if not is_instance_valid(it) or not it.active:
			continue
		var is_star: bool = "dropped" in it
		if is_star and f.stars >= game.STARS:
			continue
		if not is_star:
			if it.kind == "gun" and _armed():
				continue
			if it.kind == "bat" and f.has_bat:
				continue
		var d: Vector3 = it.global_position - f.global_position
		var score := Vector2(d.x, d.z).length() + 3.0 * absf(d.y)
		if not is_star and unarmed:
			score -= 4.0
		if score < best_d:
			best_d = score
			best = it
	return best

func _explore_spot() -> Variant:
	var list: Array[Vector3] = game.cand_in
	if list.is_empty():
		return null
	for t in 30:
		var p: Vector3 = list[randi() % list.size()]
		var d := p.distance_to(f.global_position)
		if d >= 8.0 and d <= 32.0:
			return p
	return list[randi() % list.size()]

func _set_state(s: String, g: Vector3) -> void:
	state = s
	if g.distance_to(goal) > 0.75:
		goal = g
		if agent.is_inside_tree():
			agent.target_position = g

# ---------------------------------------------------------------- every physics tick

func _physics_process(dt: float) -> void:
	if game == null or not f.alive or not game.fighting():
		f.in_move = Vector2.ZERO
		f.in_fire = false
		f.in_aim = false
		f.in_jump = false
		return
	f.in_jump = false
	if agent.is_inside_tree() and goal != Vector3.INF and agent.target_position.distance_to(goal) > 0.5:
		agent.target_position = goal
	_heard_t -= dt
	_think_t -= dt
	if _think_t <= 0.0:
		_think_t = THINK
		_think()
	var move_dir := _path_dir()
	var aim_at := Vector3.INF
	var tvis: bool = target != null and is_instance_valid(target) and target.alive and visible_foes.has(target)
	if tvis:
		aim_at = target.global_position + Vector3.UP * (0.35 if target.downed else (1.95 if _aim_head else 1.3))
	var fire := false
	var aim := false
	if f.downed:
		# crawl away from whoever put it down
		if target:
			var away: Vector3 = f.global_position - target.global_position
			move_dir = Vector3(away.x, 0, away.z).normalized()
	elif tvis:
		var tdist: float = target.global_position.distance_to(f.global_position)
		var melee: bool = Weapons.is_melee(f.current_weapon())
		var fighting := state == "fight" or (state == "shop" and tdist < 3.0)
		if fighting:
			move_dir = _fight_move(tdist, melee, dt)
		_react_t += dt
		var react: float = float(_d.react) * float(_s.react)
		if _react_t >= react:
			if melee:
				fire = fighting and tdist < float(Weapons.stat(f.current_weapon()).reach) * 0.9
			else:
				fire = tdist < GUN_REACH and _gun_rhythm(dt)
				aim = tdist > 10.0 and Vector2(f.velocity.x, f.velocity.z).length() < 3.0
	# face the target when fighting it, otherwise the way it's going
	var want_yaw: float = f.yaw
	var want_pitch := 0.0
	if aim_at != Vector3.INF and (fire or state == "fight" or not Weapons.is_melee(f.current_weapon())):
		var d := aim_at - _eye()
		want_yaw = atan2(d.x, d.z) + deg_to_rad(_aim_err.x)
		want_pitch = atan2(d.y, Vector2(d.x, d.z).length()) + deg_to_rad(_aim_err.y)
	elif move_dir.length() > 0.1:
		want_yaw = atan2(move_dir.x, move_dir.z)
	var turn: float = float(_d.turn) * dt * (1.6 if state != "fight" else 1.0)
	f.yaw += clampf(wrapf(want_yaw - f.yaw, -PI, PI), -turn, turn)
	f.pitch = move_toward(f.pitch, want_pitch, turn)
	# only fire once roughly on target
	if fire and aim_at != Vector3.INF and absf(wrapf(want_yaw - f.yaw, -PI, PI)) > 0.25:
		fire = false
	f.in_fire = fire
	f.in_aim = aim
	# movement relative to where it's facing (so it can strafe while aiming)
	var fw: Vector3 = f.forward()
	var rt: Vector3 = f.right()
	f.in_move = Vector2(move_dir.dot(rt), move_dir.dot(fw))
	# ladders: climb while the goal is above, otherwise come down; never hang on one for long
	if f.on_ladder and not f.is_on_floor():
		_ladder_t += dt
		var up: bool = goal != Vector3.INF and goal.y > f.global_position.y + 1.0 and _ladder_t < 6.0
		f.in_move = Vector2(0, 1 if up else -1)
		var lad: Variant = _ladder_here()
		if up and lad != null:
			# stay over the ladder until the top (so it doesn't drift under the floor above), then step off
			var box: AABB = lad[0]
			var n: Vector3 = lad[1]
			var c := box.get_center()
			var hold := Vector3(c.x, 0, c.z) - n * 0.2
			if f.global_position.y > box.end.y - 0.4:
				hold = Vector3(c.x, 0, c.z) + n * 1.2
			var to := hold - Vector3(f.global_position.x, 0, f.global_position.z)
			f.yaw = atan2(to.x, to.z)
			f.in_move = Vector2(0, clampf(to.length() * 2.0, 0.12, 1.0))
	else:
		_ladder_t = 0.0
	# stuck: wriggle a random way with a hop for a second
	if _wiggle_t > 0.0:
		_wiggle_t -= dt
		f.in_move = Vector2(_wiggle_dir.dot(rt), _wiggle_dir.dot(fw))
		f.in_jump = f.is_on_floor() and randf() < dt * 4.0
	_unstick(dt, move_dir)
	if game.debug:
		_draw_debug()
	elif _label.visible:
		_label.visible = false
		_path_mesh.visible = false

## direction along the nav path to the goal (flat), or straight at the goal when there's no path yet
func _path_dir() -> Vector3:
	if goal == Vector3.INF:
		return Vector3.ZERO
	var to_goal := goal - f.global_position
	if state == "shop" and Vector2(to_goal.x, to_goal.z).length() < 0.8:
		return Vector3.ZERO   # on the pad: stand still to cash in
	var nxt := goal
	if agent.is_inside_tree() and not agent.is_navigation_finished():
		nxt = agent.get_next_path_position()
	# taking a short cut (launch trampoline, portal): from its start, head for the trampoline / portal itself
	for w in game.level.layout.get("warps", []):
		var b := Vector3(w.b[0], w.b[1], w.b[2])
		var a := Vector3(w.a[0], w.a[1], w.a[2])
		if Vector2(nxt.x - b.x, nxt.z - b.z).length() < 1.5 and absf(nxt.y - b.y) < 1.5 \
				and Vector2(f.global_position.x - a.x, f.global_position.z - a.z).length() < 3.0 and absf(f.global_position.y - a.y) < 1.0:
			nxt = Vector3(w.t[0], a.y, w.t[1])
			break
	var d := nxt - f.global_position
	d.y = 0
	if d.length() < 0.3:
		d = Vector3(to_goal.x, 0, to_goal.z)
		if d.length() < 0.6:
			return Vector3.ZERO
	return d.normalized()

## how it moves in a fight, by style
func _fight_move(tdist: float, melee: bool, dt: float) -> Vector3:
	var to: Vector3 = target.global_position - f.global_position
	to.y = 0
	var dir := to.normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	_strafe_t -= dt
	if _strafe_t <= 0.0:
		_strafe_t = randf_range(0.5, 1.3)
		_strafe_dir = -_strafe_dir
	var strafe: float = float(_s.strafe) * float(_d.get("strafe_k", 1.0))
	if randf() < float(_s.jump) * dt and f.is_on_floor():
		f.in_jump = true
	var path := _path_dir()
	if melee:
		if target.downed or tdist < 2.2:
			return dir if tdist > 1.4 else side * _strafe_dir * 0.4
		match style:
			"flanker":
				return (dir + side * _side * 0.9).normalized() if tdist > 3.5 else dir
			"lurker":
				return Vector3.ZERO if tdist > 13.0 else dir
			_:
				return (dir + side * _strafe_dir * 0.35 * strafe).normalized() if path.dot(dir) > 0.5 or path == Vector3.ZERO else path
	# with a gun: keep a fighting distance and strafe
	var want := 9.0 if style == "duelist" else (4.0 if style == "rusher" or style == "breacher" else 7.0)
	var push := 0.0
	if tdist > want + 2.0:
		push = 1.0
	elif tdist < want - 2.0:
		push = -0.7
	var m := dir * push + side * _strafe_dir * 0.6 * strafe
	if push > 0.0 and path != Vector3.ZERO and path.dot(dir) < 0.5:
		m = path + side * _strafe_dir * 0.3   # follow the path round corners when closing in
	return m.normalized() if m.length() > 0.05 else Vector3.ZERO

## guns fire in bursts with pauses between them (shorter, faster bursts on harder levels)
func _gun_rhythm(dt: float) -> bool:
	if _pause_t > 0.0:
		_pause_t -= dt * (1.0 / float(_d.rof))
		return false
	if _burst_left <= 0:
		_burst_left = int(_d.burst) + randi() % 3
	if f.fire_t <= 0.0:
		_burst_left -= 1
		if _burst_left <= 0:
			var p: Array = _d.pause
			_pause_t = randf_range(p[0], p[1])
			_new_aim_error()
	return true

## if it hasn't moved for a while when it should have: hop, then pick something else to do
func _unstick(dt: float, move_dir: Vector3) -> void:
	if move_dir.length() < 0.1 or f.downed or f.on_ladder:
		_stuck_t = 0.0
		_last_pos = f.global_position
		return
	if f.global_position.distance_to(_last_pos) < dt * 1.5:
		_stuck_t += dt
	else:
		_stuck_t = maxf(0.0, _stuck_t - dt * 2.0)
	_last_pos = f.global_position
	if _stuck_t > 0.6 and f.is_on_floor():
		f.in_jump = true
	if _stuck_t > 2.5:
		_stuck_t = 0.0
		var a := randf() * TAU
		_wiggle_dir = Vector3(cos(a), 0, sin(a))
		_wiggle_t = 1.0
		seen.erase(_goal_item())
		_explore_t = 0.0
		state = "stuck"
		goal = Vector3.INF

func _ladder_here() -> Variant:
	for l in game.level.layout.get("ladders", []):
		if l.get("lift", false):
			continue
		var a: Array = l.b
		var box := AABB(Vector3(a[0], a[1], a[2]), Vector3(float(a[3]) - float(a[0]), float(a[4]) - float(a[1]), float(a[5]) - float(a[2])))
		if box.grow(0.6).has_point(f.global_position + Vector3.UP * 0.6):
			return [box, Vector3(float(l.get("nx", 0)), 0, float(l.get("nz", 0)))]
	return null

func _goal_item() -> Variant:
	for it in seen:
		if is_instance_valid(it) and it.global_position.distance_to(goal) < 0.5:
			return it
	return null

# ---------------------------------------------------------------- debug view (F3)

func _draw_debug() -> void:
	_label.visible = true
	var tname: String = target.display_name if target and is_instance_valid(target) else "-"
	_label.text = "%s · %s · %s\nsees %d · target %s" % [state, style, difficulty, seen.size(), tname]
	_path_mesh.visible = true
	var im := _path_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	var pts := agent.get_current_navigation_path()
	if pts.size() >= 2:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in pts:
			im.surface_add_vertex(p + Vector3.UP * 0.15)
		im.surface_end()
