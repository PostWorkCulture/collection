extends Node3D
## Entry point: builds the lighting, the grey-box Mansion, the match ("Game"), you, six test dummies and the HUD,
## and sets up the controls. If autotest.json says "enabled": true, it runs the scripted checks and screenshots
## instead (with "combat": true it also tests punches, guns, going down, dying, respawning and pickups).

const Fighter := preload("res://fighter/fighter.gd")
const LevelBuilder := preload("res://level/level_builder.gd")
const CollectionGame := preload("res://game/collection_game.gd")
const DummyBrain := preload("res://fighter/dummy_brain.gd")
const Hud := preload("res://ui/hud.gd")
const Weapons := preload("res://weapons/weapons.gd")

## phase 2 test dummies (they never attack): name, spot, facing, strafes?
const DUMMIES := [
	["Wednesday", Vector3(-9, 0.05, -31), PI, false],
	["Anti Hero", Vector3(-13, 0.05, -33), PI, true],
	["Lil Pink", Vector3(3, 0.05, -40), -PI * 0.5, false],
	["Starscreen", Vector3(0, 0.05, -18), PI, true],
	["Crusty", Vector3(-30, 0.05, -15), 1.2, false],
	["Dracz", Vector3(13, 5.85, 1), -2.4, false],
]

var level: Node3D
var game: Node3D
var player: CharacterBody3D
var dummies: Array = []
var hud: CanvasLayer
var _test_gun := -1

func _ready() -> void:
	_inputs()
	_environment()
	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()
	_house_lights()
	game = CollectionGame.new()
	game.name = "Game"
	game.level = level
	add_child(game)
	player = Fighter.new()
	player.name = "Player"
	player.ladders = level.ladders
	player.game = game
	add_child(player)
	game.add_fighter(player)
	# first spawn of the game: out on the front lawn, facing the house (as in Collection)
	player.place(Vector3(-6, 0.05, -36), 0.0)
	for d in DUMMIES:
		var f := Fighter.new()
		f.name = "Dummy_" + String(d[0]).replace(" ", "")
		f.is_player = false
		f.display_name = d[0]
		f.band_color = Color(0.91, 0.27, 0.23)
		f.ladders = level.ladders
		f.game = game
		f.home = [d[1], d[2]]
		add_child(f)
		f.place(d[1], d[2])
		var brain := DummyBrain.new()
		brain.strafe = d[3]
		f.add_child(brain)
		game.add_fighter(f)
		dummies.append(f)
	hud = Hud.new()
	hud.player = player
	hud.game = game
	add_child(hud)
	await game.start()
	var auto := _autotest()
	if auto.get("enabled", false):
		_run_autotest(auto)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "crouch": [KEY_C], "camera_toggle": [KEY_V], "pause": [KEY_ESCAPE, KEY_P],
		"weapon_melee": [KEY_1], "weapon_gun": [KEY_2], "test_gun": [KEY_G],
		"fire": [], "aim": [], "weapon_next": [], "weapon_fists": [],
		"look_left": [], "look_right": [], "look_up": [], "look_down": [],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	# mouse: left attacks, right aims, wheel up swaps weapon, wheel down goes to fists (as on the web)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT], ["weapon_next", MOUSE_BUTTON_WHEEL_UP], ["weapon_fists", MOUSE_BUTTON_WHEEL_DOWN]]:
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)
	# controller: left stick moves, right stick looks, RT attacks, LT aims, RB swaps, A jumps, B crouches, Back camera
	var pad := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0], "look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
		"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0], "aim": [JOY_AXIS_TRIGGER_LEFT, 1.0]}
	for a in pad:
		var m := InputEventJoypadMotion.new()
		m.axis = pad[a][0]
		m.axis_value = pad[a][1]
		InputMap.action_add_event(a, m)
	for pair in [["jump", JOY_BUTTON_A], ["crouch", JOY_BUTTON_B], ["camera_toggle", JOY_BUTTON_BACK], ["pause", JOY_BUTTON_START], ["weapon_next", JOY_BUTTON_RIGHT_SHOULDER]]:
		var b := InputEventJoypadButton.new()
		b.button_index = pair[1]
		InputMap.action_add_event(pair[0], b)

## lighting: afternoon sun with soft shadows, sky light, bounce light through the windows (SDFGI), ambient occlusion,
## a touch of glow and filmic tonemapping
func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.62, 0.66, 0.6)
	sky.sky_material = sm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 1.2
	env.ssao_enabled = true
	env.ssao_intensity = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 120
	add_child(sun)

## soft ceiling lights through the house on both floors (no shadows, so 100-odd of them stay cheap), so rooms
## away from the windows aren't black; the art pass replaces these with the real lamps
func _house_lights() -> void:
	var h: Dictionary = level.house
	if h.is_empty():
		return
	var hx: float = h.x
	var hz: float = h.z
	for fy in [4.6, 10.2]:
		var x := -hx + 4.5
		while x < hx:
			var z := -hz + 4.0
			while z < hz:
				var l := OmniLight3D.new()
				l.position = Vector3(x, fy, z)
				l.light_energy = 1.15
				l.light_color = Color(1.0, 0.95, 0.86)
				l.omni_range = 9.5
				l.omni_attenuation = 1.2
				l.shadow_enabled = false
				level.add_child(l)
				z += 8.0
			x += 9.0

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()   # the click that grabs the mouse doesn't also punch
	elif e.is_action_pressed("test_gun"):
		give_test_weapon()

## phase 2 test aid (G): hands you each gun in turn, then the bat, so every weapon can be tried quickly
func give_test_weapon() -> void:
	if not player.alive or player.downed:
		return
	_test_gun = (_test_gun + 1) % (Weapons.CO_GUNS.size() + 1)
	if _test_gun < Weapons.CO_GUNS.size():
		player.give_gun(Weapons.CO_GUNS[_test_gun])
	else:
		player.has_bat = false
		player.give_bat()
		player.select_slot("melee")

# ---------------- scripted checks (autotest.json) ----------------
func _autotest() -> Dictionary:
	if not FileAccess.file_exists("res://autotest.json"):
		return {}
	var t = JSON.parse_string(FileAccess.open("res://autotest.json", FileAccess.READ).get_as_text())
	return t if t is Dictionary else {}

var _logf: FileAccess
func _log(t: String) -> void:
	print(t)
	if _logf == null:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
		_logf = FileAccess.open("res://shots/autotest.txt", FileAccess.WRITE)
	_logf.store_line(t)
	_logf.flush()

func _run_autotest(cfg: Dictionary) -> void:
	await get_tree().create_timer(1.0).timeout
	_log("AUTOTEST boxes=%d ladders=%d spawns=%d" % [level.get_child_count(), level.ladders.size(), level.spawns.size()])
	if cfg.get("movement", true):
		await _movement_checks(cfg)
	if cfg.get("combat", false):
		await _combat_checks()
	# screenshots
	for sh in cfg.get("shots", []):
		Settings.camera_mode = sh.get("cam", "third")
		player.apply_camera_mode()
		player.place(Vector3(sh.pos[0], sh.pos[1], sh.pos[2]), sh.yaw)
		player.pitch = sh.get("pitch", 0.0)
		await get_tree().create_timer(sh.get("wait", 2.5)).timeout
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://shots/" + sh.file))
		_log("AUTOTEST shot " + sh.file)
	Settings.camera_mode = "third"
	_log("AUTOTEST done")
	if cfg.get("quit", true):
		get_tree().quit()

func _movement_checks(cfg: Dictionary) -> void:
	# movement checks: run forward 1 s on the lawn, jump, double jump
	player.place(Vector3(-6, 0.05, -38), 0.0)
	await get_tree().create_timer(0.3).timeout
	var p0: Vector3 = player.global_position
	Input.action_press("move_forward")
	await get_tree().create_timer(1.0).timeout
	Input.action_release("move_forward")
	_log("AUTOTEST run 1s: moved %.2f m (floor %s)" % [(player.global_position - p0).length(), player.is_on_floor()])
	await get_tree().create_timer(0.5).timeout
	var y0: float = player.global_position.y
	var peak := y0
	Input.action_press("jump")
	for i in 40:
		await get_tree().physics_frame
		peak = max(peak, player.global_position.y)
	Input.action_release("jump")
	_log("AUTOTEST jump height %.2f m" % (peak - y0))
	await get_tree().create_timer(1.0).timeout
	y0 = player.global_position.y
	peak = y0
	Input.action_press("jump")
	for i in 20:
		await get_tree().physics_frame
	Input.action_release("jump")
	for i in 6:
		await get_tree().physics_frame
	Input.action_press("jump")
	for i in 70:
		await get_tree().physics_frame
		peak = max(peak, player.global_position.y)
	Input.action_release("jump")
	_log("AUTOTEST double jump height %.2f m, stamina left %d" % [peak - y0, player.stamina])
	await get_tree().create_timer(1.0).timeout
	# stairs: walk up the first staircase found in the shots list, if given
	for s in cfg.get("walks", []):
		player.place(Vector3(s.from[0], s.from[1], s.from[2]), s.yaw)
		await get_tree().create_timer(0.4).timeout
		Input.action_press("move_forward")
		await get_tree().create_timer(s.get("secs", 2.0)).timeout
		Input.action_release("move_forward")
		_log("AUTOTEST walk %s: ended at %v" % [s.name, player.global_position])

# ---------------- phase 2 combat checks ----------------
func _face(f: Node, target: Vector3) -> void:
	var d: Vector3 = target - f.eye_pos()
	f.yaw = atan2(d.x, d.z)
	f.pitch = atan2(d.y, Vector2(d.x, d.z).length())

func _snap(file: String) -> void:
	if DisplayServer.get_name() == "headless":   # no pictures without a screen (the checks still run)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://shots/" + file))
	_log("AUTOTEST shot " + file)

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

## hold attack on `target` (re-aiming every tick) until `done` returns true or `secs` pass
func _attack_until(target: Node, done: Callable, secs: float, snap_at_hit := -1, snap_file := "") -> void:
	var hits := [0]
	var cb := func(_t, _a, _h, _f): hits[0] += 1
	player.dealt_hit.connect(cb)
	Input.action_press("fire")
	var t0 := Time.get_ticks_msec()
	var snapped := false
	while Time.get_ticks_msec() - t0 < secs * 1000.0 and not done.call():
		_face(player, target.global_position + Vector3.UP * (0.4 if target.downed else 1.3))
		await get_tree().physics_frame
		if not snapped and snap_at_hit >= 0 and hits[0] >= snap_at_hit:
			snapped = true
			var s0 := Time.get_ticks_msec()
			await _snap(snap_file)
			t0 += Time.get_ticks_msec() - s0   # saving a picture stalls the game: don't count that time
	Input.action_release("fire")
	player.dealt_hit.disconnect(cb)

func _combat_checks() -> void:
	player.force_input = true
	var hits := [0, 0]
	var count := func(_t, _a, head, _f): hits[0] += 1; hits[1] += 1 if head else 0
	player.dealt_hit.connect(count)
	_log("AUTOTEST spots inside=%d lawn=%d pickups=%d" % [game.cand_in.size(), game.cand_out.size(), game.pickups.size()])
	for pk in game.pickups:
		_log("AUTOTEST pickup %s %s at %v" % [pk.kind, pk.id, pk.global_position])
	for d in dummies:
		_log("AUTOTEST dummy %s at %v floor=%s" % [d.display_name, d.global_position, d.is_on_floor()])
	# fists: three punches put someone down
	Settings.camera_mode = "third"
	player.apply_camera_mode()
	var dum: Node = dummies[0]
	player.place(dum.global_position + Vector3(0, 0, -2.2), 0.0)
	await _wait(0.5)
	hits[0] = 0
	await _attack_until(dum, func(): return dum.downed, 3.0, 1, "p2_01_punch_third.png")
	_log("AUTOTEST fists: down after %d punches (downed=%s dhp=%d)" % [hits[0], dum.downed, dum.dhp])
	await _wait(0.8)
	await _snap("p2_02_downed_third.png")
	# left alone, a downed player gets back up after 5 s with the downed HP they had left
	var t_down := Time.get_ticks_msec()
	while dum.downed and Time.get_ticks_msec() - t_down < 7000:
		await get_tree().physics_frame
	_log("AUTOTEST get up: after %.1f s, hp %d, downed=%s" % [(Time.get_ticks_msec() - t_down) / 1000.0, dum.hp, dum.downed])
	# down again (30 HP: one punch) and finish them (one more)
	await _attack_until(dum, func(): return not dum.alive, 4.0)
	_log("AUTOTEST finish: alive=%s deaths=%d player kills=%d" % [dum.alive, dum.deaths, player.kills])
	await _wait(3.4)
	_log("AUTOTEST respawn: alive=%s hp=%d at %v shield=%.1f" % [dum.alive, dum.hp, dum.global_position, dum.shield_t])
	# MP5 in first person, aiming down sights, at 10 m
	var still: Node = dummies[0]
	Settings.camera_mode = "first"
	player.apply_camera_mode()
	player.place(still.global_position + Vector3(10, 0, 0), -PI * 0.5)
	player.give_gun("mp5")
	await _wait(0.6)
	_face(player, still.global_position + Vector3.UP * 1.3)
	Input.action_press("aim")
	await _wait(0.4)
	await _snap("p2_03_mp5_aim_first.png")
	hits[0] = 0
	hits[1] = 0
	await _attack_until(still, func(): return player.gun_id == "", 3.0, 6, "p2_04_mp5_firing_first.png")
	Input.action_release("aim")
	_log("AUTOTEST mp5: 20 bullets, %d hits (%d head), now holding %s, target hp %d downed=%s alive=%s" % [hits[0], hits[1], player.current_weapon(), still.hp, still.downed, still.alive])
	# dual pistols in third person, hip fire, inside the house
	Settings.camera_mode = "third"
	player.apply_camera_mode()
	var hall: Node = dummies[3]
	player.place(hall.global_position + Vector3(0, 0, -7), 0.0)
	player.give_gun("duals")
	await _wait(0.6)
	hits[0] = 0
	await _attack_until(hall, func(): return player.ammo <= 12, 3.0, 2, "p2_05_duals_third.png")
	_log("AUTOTEST duals: 8 shots, %d hits at ~7 m on a strafing target" % hits[0])
	# every gun fires its 20 and drops back to fists
	for id in Weapons.CO_GUNS:
		player.give_gun(id)
		var t1 := Time.get_ticks_msec()
		Input.action_press("fire")
		while player.gun_id != "" and Time.get_ticks_msec() - t1 < 4000:
			await get_tree().physics_frame
		Input.action_release("fire")
		_log("AUTOTEST %s: emptied in %.2f s, back to %s" % [id, (Time.get_ticks_msec() - t1) / 1000.0, player.current_weapon()])
		await _wait(0.4)
	# switching weapons with real key and wheel presses
	player.give_gun("mp5")
	await _wait(0.4)
	var seen: Array[String] = [player.current_weapon()]
	for step in [[KEY_1, -1], [KEY_2, -1], [-1, MOUSE_BUTTON_WHEEL_UP], [-1, MOUSE_BUTTON_WHEEL_UP], [-1, MOUSE_BUTTON_WHEEL_DOWN]]:
		var ev: InputEvent
		if step[0] >= 0:
			var k := InputEventKey.new()
			k.physical_keycode = step[0]
			k.keycode = step[0]
			k.pressed = true
			ev = k
		else:
			var mb := InputEventMouseButton.new()
			mb.button_index = step[1]
			mb.pressed = true
			ev = mb
		Input.parse_input_event(ev)
		await _wait(0.4)
		seen.append(player.current_weapon())
	_log("AUTOTEST switching (start, 1, 2, wheel up, wheel up, wheel down): %s" % ", ".join(seen))
	# walk onto a gun pickup
	var pk: Node = null
	for p in game.pickups:
		if p.active and p.kind == "gun":
			pk = p
			break
	if pk:
		var pid: String = pk.id
		var ppos: Vector3 = pk.global_position
		Settings.camera_mode = "first"
		player.apply_camera_mode()
		player.place(ppos + Vector3(0, 0.05, -2.6), 0.0)
		await _wait(0.5)
		_face(player, ppos + Vector3.UP * 0.5)
		await _wait(0.3)
		await _snap("p2_06_pickup_first.png")
		player.place(ppos + Vector3(0, 0.05, 0), 0.0)
		await _wait(0.3)
		_log("AUTOTEST pickup: took %s -> holding %s with %d bullets; pickup active=%s" % [pid, player.gun_id, player.ammo, pk.active])
	else:
		_log("AUTOTEST pickup: no gun pickup placed!")
	# a pane of upright glass breaks in one hit
	var pane: StaticBody3D = null
	for c in level.get_children():
		if c is StaticBody3D and c.has_meta("glass"):
			var sz: Vector3 = ((c.get_child(0) as CollisionShape3D).shape as BoxShape3D).size
			if minf(sz.x, sz.z) < sz.y:
				pane = c
				break
	if pane:
		game.hit_world(pane, pane.global_position, Vector3.FORWARD, Vector3.BACK)
		await get_tree().physics_frame
		_log("AUTOTEST glass: pane broken=%s" % (not is_instance_valid(pane)))
	# you: go down, get finished, respawn at the spawn point furthest from everyone with a 2 s shield
	Settings.camera_mode = "third"
	player.apply_camera_mode()
	player.place(Vector3(-6, 0.05, -36), 0.0)
	await _wait(0.3)
	player.take_damage(150, dummies[1])
	await _wait(0.6)
	await _snap("p2_07_you_down_third.png")
	player.take_damage(40, dummies[1])
	await _wait(0.5)
	await _snap("p2_08_eliminated.png")
	_log("AUTOTEST you: alive=%s deaths=%d" % [player.alive, player.deaths])
	await _wait(3.0)
	var nearest := 1e9
	for d in dummies:
		nearest = minf(nearest, d.global_position.distance_to(player.global_position))
	player.dealt_hit.disconnect(count)
	_log("AUTOTEST you respawned: alive=%s at %v, nearest dummy %.1f m, shield %.1f, weapon %s" % [player.alive, player.global_position, nearest, player.shield_t, player.current_weapon()])
	player.force_input = false
