extends Node3D
## Entry point: builds the lighting, the grey-box Mansion, the match ("Game"), you, seven bots (8 players) and the
## HUD, and sets up the controls. Everyone's first spawn is out on the front and back lawns, facing the house.
## The start screen comes first (Play, Bots, Settings, Quit); Esc pauses; F3 shows what each bot is doing; after a
## win, Enter plays again and Esc goes back to the start screen. Graphics quality, volumes and key bindings come from
## the saved settings. If autotest.json says "enabled": true, it runs the scripted checks and
## screenshots instead: "combat" and "stars" use seven standing test dummies; "bots_match" plays a full 8-bot match
## (you on autopilot too) and reports how it went.

const Fighter := preload("res://fighter/fighter.gd")
const LevelBuilder := preload("res://level/level_builder.gd")
const MansionFeatures := preload("res://level/mansion_features.gd")
const MansionLights := preload("res://level/mansion_lights.gd")
const CollectionGame := preload("res://game/collection_game.gd")
const DummyBrain := preload("res://fighter/dummy_brain.gd")
const BotBrain := preload("res://fighter/bot_brain.gd")
## the cast: imok 1v1's ten playable characters and their colours (DESIGN §5); 7 are drawn at random as bots each match
const CAST := [
	["Wednesday", "#d0202a"], ["Lil Pink", "#ff6fae"], ["North West", "#2e8bff"], ["Johnny Rotten", "#e0202a"],
	["Emo Bunny", "#b79cff"], ["Glitch", "#1fd6ff"], ["Kitty", "#a77bff"], ["Puffa", "#ffd21a"], ["Raven", "#d0202a"], ["Toxic", "#5dff3a"],
]
const Hud := preload("res://ui/hud.gd")
const Menu := preload("res://ui/menu.gd")
const Sfx := preload("res://audio/sfx.gd")
const Weapons := preload("res://weapons/weapons.gd")

## standing test dummies for the scripted combat and star checks (they never attack or collect): name, spot, facing, strafes?
const DUMMIES := [
	["Wednesday", Vector3(-9, 0.05, -31), PI, false],
	["Lil Pink", Vector3(-13, 0.05, -33), PI, true],
	["North West", Vector3(3, 0.05, -40), -PI * 0.5, false],
	["Johnny Rotten", Vector3(0, 0.05, -18), PI, true],
	["Emo Bunny", Vector3(-30, 0.05, -15), 1.2, false],
	["Glitch", Vector3(13, 5.85, 1), -2.4, false],
	["Kitty", Vector3(6, 0.05, 34), PI, true],
]

var level: Node3D
var features: Node3D
var lights: Node3D
var game: Node3D
var player: CharacterBody3D
var dummies: Array = []
var bots: Array = []
var hud: CanvasLayer
var menu: CanvasLayer
var music: AudioStreamPlayer
var _env: Environment
var _sun: DirectionalLight3D
var _probes: Node3D
var _key_defaults := {}

var _t_start := 0
var load_ms := 0

func _ready() -> void:
	_t_start = Time.get_ticks_msec()
	_inputs()
	Sfx.setup()
	_environment()
	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()
	if level.dressed and level.layout.has("rooms"):
		lights = MansionLights.new()
		lights.name = "MansionLights"
		add_child(lights)
		lights.setup(level.layout, String(Settings.quality))
		lights.level_ref = level
	else:
		_house_lights()
	game = CollectionGame.new()
	game.name = "Game"
	game.level = level
	add_child(game)
	features = MansionFeatures.new()
	features.name = "MansionFeatures"
	add_child(features)
	features.setup(game, level)
	player = Fighter.new()
	player.name = "Player"
	player.ladders = level.ladders
	player.lifts = level.lifts
	player.game = game
	add_child(player)
	game.add_fighter(player)
	# first spawn of the game: out on the front lawn, facing the house (as in Collection)
	player.place(Vector3(-6, 0.05, -36), 0.0)
	var auto := _autotest()
	var testing: bool = auto.get("enabled", false)
	if testing and auto.has("difficulty"):
		Settings.bots = auto.difficulty   # for this run only (not saved)
	var use_dummies: bool = testing and (auto.get("combat", false) or auto.get("stars", false)) and not auto.get("bots_match", false)
	if use_dummies:
		_add_dummies()
	elif not (testing and not auto.get("bots", true) and not auto.get("bots_match", false)):   # "bots": false = an empty house for preview shots
		_add_bots()
	if testing and auto.get("bots_match", false):
		player.autopilot = true   # you play as a bot too, so the whole match runs by itself
		_add_brain(player, "duelist")
	hud = Hud.new()
	hud.player = player
	hud.game = game
	add_child(hud)
	menu = Menu.new()
	menu.defaults = _key_defaults
	add_child(menu)
	menu.play.connect(_on_play)
	menu.resume.connect(_on_resume)
	menu.quit_to_menu.connect(_on_quit_to_menu)
	menu.settings_changed.connect(_on_settings_changed)
	music = AudioStreamPlayer.new()
	music.bus = "Music"
	add_child(music)
	game.won.connect(func(_f): _music("matchend"))
	var skip_menu: bool = (testing and not auto.get("menu", false)) or Settings.play_now
	Settings.play_now = false
	await game.start(skip_menu)
	_lawn_spawns()
	_add_probes()
	load_ms = Time.get_ticks_msec() - _t_start   # everything built and the nav ready
	if testing:
		if not skip_menu:
			hud.visible = false
			menu.show_start()
		_run_autotest(auto)
	elif skip_menu:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		hud.visible = false
		menu.show_start()
		_music("menu")
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play() -> void:
	hud.visible = true
	music.stop()
	game.begin_countdown()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_settings_changed(what: String) -> void:
	match what:
		"quality":
			_apply_quality()
			if lights:
				lights.set_quality(String(Settings.quality))
		"view":
			player.apply_camera_mode()
		"audio":
			Sfx.apply_volumes()
		"bots":
			set_bot_difficulty(Settings.bots)

## the web game's menu and match-end music on the Music bus, looping
func _music(which: String) -> void:
	var path := "res://audio/music/%s.mp3" % which
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else (AudioStreamMP3.load_from_file(path) if FileAccess.file_exists(path) else null)
	if s == null:
		return
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	music.stream = s
	music.play()

func _add_dummies() -> void:
	for d in DUMMIES:
		var f := _new_fighter(d[0])
		f.home = [d[1], d[2]]
		f.place(d[1], d[2])
		var brain := DummyBrain.new()
		brain.strafe = d[3]
		f.add_child(brain)
		dummies.append(f)

## seven bots, each with a style from the web game's Rumble pool (picked at random, no repeats until all are used)
func _add_bots() -> void:
	var styles: Array = BotBrain.STYLES.keys()
	styles.shuffle()
	var cast: Array = CAST.duplicate()
	cast.shuffle()
	for i in 7:
		var f := _new_fighter(cast[i][0], Color(cast[i][1]))
		f.place(Vector3(-24.0 + i * 8.0, 0.05, -42.0), 0.0)   # spread out on the front lawn until the real spawns are picked
		_add_brain(f, styles[i % styles.size()])
		bots.append(f)

func _new_fighter(nm: String, col := Color(0.91, 0.27, 0.23)) -> CharacterBody3D:
	var f := Fighter.new()
	f.name = "Fighter_" + nm.replace(" ", "")
	f.is_player = false
	f.display_name = nm
	f.band_color = col
	f.ladders = level.ladders
	f.lifts = level.lifts
	f.game = game
	add_child(f)
	game.add_fighter(f)
	return f

func _add_brain(f: Node, style: String) -> void:
	var b := BotBrain.new()
	b.game = game
	b.style = style
	b.difficulty = Settings.bots
	f.add_child(b)

## first spawn of the match: everyone out on the front and back lawns, spread out, facing the house
func _lawn_spawns() -> void:
	var taken: Array[Vector3] = [player.global_position]
	for f in bots:
		var spot: Variant = game.pick_spot(game.cand_out, taken, 8.0)
		if spot == null:
			continue
		var p: Vector3 = spot
		taken.append(p)
		f.place(p + Vector3(0, 0.05, 0), 0.0 if p.z < 0.0 else PI)

func set_bot_difficulty(d: String) -> void:
	Settings.bots = d
	Settings.save()
	for f in game.fighters:
		for c in f.get_children():
			if c.has_method("set_difficulty"):
				c.set_difficulty(d)

func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "crouch": [KEY_C], "camera_toggle": [KEY_V], "pause": [KEY_ESCAPE, KEY_P],
		"weapon_melee": [KEY_1], "weapon_gun": [KEY_2],
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
	# remember the default key/mouse binding of each action (for "reset"), then apply the saved rebinds
	for a in InputMap.get_actions():
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey or ev is InputEventMouseButton:
				_key_defaults[a] = ev
				break
	for a in Settings.keys:
		if not InputMap.has_action(a):
			continue
		var code: String = Settings.keys[a]
		var ev2: InputEvent = null
		if code.begins_with("k:"):
			var k := InputEventKey.new()
			k.physical_keycode = int(code.substr(2))
			ev2 = k
		elif code.begins_with("m:"):
			var mb2 := InputEventMouseButton.new()
			mb2.button_index = int(code.substr(2))
			ev2 = mb2
		if ev2:
			for old in InputMap.action_get_events(a):
				if old is InputEventKey or old is InputEventMouseButton:
					InputMap.action_erase_event(a, old)
			InputMap.action_add_event(a, ev2)

## lighting (DESIGN plan, "Visuals"): afternoon sun with soft shadows, sky light, filmic (AgX) tonemapping, and by
## quality setting: bounce light through the windows (SDFGI), ambient occlusion (SSAO) and indirect light (SSIL),
## screen-space reflections, a reflection probe per room, light shafts and haze (volumetric fog), glow on lamps and
## the SHOP sign, gentle colour grading. No vignette: the design stays minimal and clean.
func _environment() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.36, 0.55, 0.85)
	sm.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sm.ground_horizon_color = Color(0.62, 0.66, 0.6)
	sky.sky_material = sm
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_AGX
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.05
	_env.adjustment_saturation = 1.04
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-48, 35, 0)
	_sun.light_energy = 1.6
	_sun.light_color = Color(1.0, 0.96, 0.9)
	_sun.shadow_enabled = true
	_sun.shadow_blur = 1.5
	add_child(_sun)
	_apply_quality()

## Low / Medium / High (Settings → Graphics)
func _apply_quality() -> void:
	var q: String = Settings.quality
	var high := q == "high"
	var low := q == "low"
	# Low has no bounce light, so it uses a neutral warm ambient instead of the blue sky's
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR if low else Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_color = Color(0.66, 0.64, 0.6)
	_env.ambient_light_energy = 1.0 if low else 0.8
	_env.sdfgi_enabled = not low
	_env.sdfgi_use_occlusion = true
	_env.sdfgi_energy = 1.2
	_env.ssao_enabled = not low
	_env.ssao_intensity = 1.6
	_env.ssil_enabled = high
	_env.ssil_intensity = 0.8
	_env.ssr_enabled = high
	_env.ssr_max_steps = 48
	_env.ssr_fade_out = 2.5
	_env.volumetric_fog_enabled = high
	_env.volumetric_fog_density = 0.0012   # a touch of haze for the light shafts, not a mist over the house (Pete, 25 Nov)
	_env.volumetric_fog_albedo = Color(1.0, 0.96, 0.9)
	_env.volumetric_fog_ambient_inject = 0.05
	_env.glow_enabled = not low
	_env.glow_intensity = 0.4
	_env.glow_bloom = 0.0                   # bloom lifted the whole picture: only bright lamps and signs glow now
	_env.glow_hdr_threshold = 1.1
	_sun.light_volumetric_fog_energy = 0.8
	_sun.directional_shadow_max_distance = 60.0 if low else 120.0
	_sun.shadow_blur = 1.0 if low else 1.5
	get_viewport().msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	if _probes:
		_probes.visible = high

## one reflection probe per room (5 × 3 a floor), captured once, so glossy floors and glass show the room around
## them; High only
func _add_probes() -> void:
	var h: Dictionary = level.house
	if h.is_empty():
		return
	_probes = Node3D.new()
	_probes.name = "Probes"
	add_child(_probes)
	var hx: float = float(h.x)
	var hz: float = float(h.z)
	var cw := hx * 2.0 / 5.0
	var cd := hz * 2.0 / 3.0
	for fl in 2:
		for i in 5:
			for j in 3:
				var p := ReflectionProbe.new()
				p.update_mode = ReflectionProbe.UPDATE_ONCE
				p.size = Vector3(cw, 5.6, cd)
				p.box_projection = true
				p.interior = true
				p.enable_shadows = false
				p.intensity = 0.8
				p.position = Vector3(-hx + cw * (i + 0.5), (0.0 if fl == 0 else 5.8) + 2.8, -hz + cd * (j + 0.5))
				_probes.add_child(p)
	_probes.visible = Settings.quality == "high"

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
	if menu.visible:
		return
	if e.is_action_pressed("pause"):
		if game.state == "won":
			_on_quit_to_menu()   # results: Esc goes back to the start screen
		elif game.state in ["fight", "countdown"]:
			get_tree().paused = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			menu.show_pause()
	elif e.is_action_pressed("ui_accept") and game.state == "won":
		Settings.play_now = true   # play again, straight into the countdown
		get_tree().reload_current_scene()
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and game.state != "won":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()   # the click that grabs the mouse doesn't also punch
	elif e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F3:
		game.debug = not game.debug

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
		FileAccess.open("res://shots/.gdignore", FileAccess.WRITE)   # keep the editor from importing test screenshots
		_logf = FileAccess.open("res://shots/autotest.txt", FileAccess.WRITE)
	_logf.store_line(t)
	_logf.flush()

func _run_autotest(cfg: Dictionary) -> void:
	await get_tree().create_timer(1.0).timeout
	if cfg.get("menu", false):
		await _menu_checks()
	_log("AUTOTEST load: %d ms from start to playable" % load_ms)
	_log("AUTOTEST boxes=%d ladders=%d lifts=%d spawns=%d dressed=%s, %d small things with a draw distance, floor furniture %d + %d" % [level.get_child_count(), level.ladders.size(), level.lifts.size(), level.spawns.size(), level.dressed, level.ranged, level.floor_things[0].size(), level.floor_things[1].size()])
	while game.state != "fight":   # the 3 s countdown
		await get_tree().physics_frame
	if cfg.get("movement", true):
		await _movement_checks(cfg)
	if cfg.get("mansion", false):
		await _mansion_checks()
	if cfg.get("combat", false):
		await _combat_checks()
	if cfg.get("stars", false):
		await _star_checks()
	if cfg.get("bots_match", false):
		await _bots_match(cfg)
	# screenshots
	var perf_rows: PackedStringArray = []
	for sh in cfg.get("shots", []):
		player.invulnerable = true   # nobody spoils a screenshot
		if sh.has("quality") and sh.quality != Settings.quality:
			Settings.quality = sh.quality
			_apply_quality()
		Settings.camera_mode = sh.get("cam", "third")
		player.apply_camera_mode()
		player.place(Vector3(sh.pos[0], sh.pos[1], sh.pos[2]), sh.yaw)
		player.pitch = sh.get("pitch", 0.0)
		await get_tree().create_timer(sh.get("wait", 2.5)).timeout
		if sh.get("bat", false):   # mid-swing with the bat
			player.force_input = true
			player.give_bat()
			player.select_slot("melee")
			await _wait(0.3)
			Input.action_press("fire")
			await _wait(0.12)
			Input.action_release("fire")
			player.force_input = false
		# performance at this spot: frames over one second, the worst frame, and what was drawn
		var frames := 0
		var worst := 0.0
		var t0 := Time.get_ticks_usec()
		var last := t0
		while Time.get_ticks_usec() - t0 < 1000000:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			frames += 1
		var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		var tris: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://shots/" + sh.file))
		_log("AUTOTEST shot %s: %d fps, worst frame %.1f ms, %d draw calls, %dk triangles" % [sh.file, frames, worst, draws, tris / 1000])
		perf_rows.append("%s,%s,%d,%.1f,%d,%d" % [sh.file, Settings.quality, frames, worst, draws, tris])
	if not perf_rows.is_empty() and DisplayServer.get_name() != "headless":
		var pf := FileAccess.open(ProjectSettings.globalize_path("res://shots/perf.csv"), FileAccess.WRITE)
		if pf:
			pf.store_string("shot,quality,fps,worst_ms,draw_calls,triangles\n" + "\n".join(perf_rows) + "\n")
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
		var pop := 0.0   # the biggest single-frame climb: a smooth staircase stays small
		var py: float = player.global_position.y
		var tw := 0.0
		while tw < float(s.get("secs", 2.0)):
			await get_tree().physics_frame
			tw += get_physics_process_delta_time()
			pop = maxf(pop, player.global_position.y - py)
			py = player.global_position.y
		Input.action_release("move_forward")
		_log("AUTOTEST walk %s: ended at %v, biggest step in one frame %.2f m" % [s.name, player.global_position, pop])

# ---------------- phase 6 Mansion feature checks ----------------
func _hold(action: String, secs: float) -> void:
	Input.action_press(action)
	await get_tree().create_timer(secs).timeout
	Input.action_release(action)

func _track(secs: float) -> Array:   # [peak y, end position]
	var peak := player.global_position.y
	var t := 0.0
	while t < secs:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		peak = maxf(peak, player.global_position.y)
	return [peak, player.global_position]

func _mansion_checks() -> void:
	player.invulnerable = true
	var r: Array
	player.place(Vector3(-32.5, 0.05, 0), PI / 2)
	r = await _track(1.5)
	_log("AUTOTEST pole up: ended at %v (upstairs is 5.8)" % r[1])
	player.place(Vector3(-32.2, 6.6, 0.2), PI / 2)
	r = await _track(1.5)
	_log("AUTOTEST pole down: ended at %v" % r[1])
	player.place(Vector3(-24.0, 0.05, 25.5), PI / 2)
	await _hold("move_forward", 0.5)
	r = await _track(1.0)
	_log("AUTOTEST lift up (ballroom): ended at %v" % r[1])
	player.place(Vector3(-20.9, 5.85, 25.5), -PI / 2)
	await _hold("move_forward", 0.3)
	r = await _track(1.5)
	_log("AUTOTEST lift down (kids' room): ended at %v" % r[1])
	player.place(Vector3(20.0, 0.05, -7.5), PI / 2)
	await _hold("move_forward", 0.25)
	r = await _track(1.0)
	_log("AUTOTEST lift up (pool): ended at %v" % r[1])
	player.place(Vector3(32.0, 0.05, 0.0), PI / 2)
	r = await _track(2.5)
	_log("AUTOTEST launch trampoline: peak %.1f, ended at %v (trophy room floor 5.8)" % [r[0], r[1]])
	player.place(Vector3(27.5, 0.05, -5.5), 0.0)
	r = await _track(1.2)
	_log("AUTOTEST trampoline: peak %.1f m" % r[0])
	player.place(Vector3(-38.4, 0.05, 18.0), -PI / 2)
	await _hold("move_forward", 0.6)
	await get_tree().create_timer(0.3).timeout
	_log("AUTOTEST portal (conservatory -> bar side): now at %v" % player.global_position)
	player.place(Vector3(38.4, 5.85, -18.0), PI / 2)
	await _hold("move_forward", 0.6)
	await get_tree().create_timer(0.3).timeout
	_log("AUTOTEST portal upstairs: now at %v" % player.global_position)
	var runs: Array = []
	for at in [Vector3(-6, 0.05, -38), Vector3(12.6, -0.75, -3.0)]:
		player.place(at, 0.0)
		await get_tree().create_timer(0.6).timeout
		var p0: Vector3 = player.global_position
		await _hold("move_forward", 0.5)
		var d: Vector3 = player.global_position - p0
		runs.append(Vector2(d.x, d.z).length())
	_log("AUTOTEST pool: wading=%s, 0.5 s run %.2f m (lawn %.2f m)" % [player.wading, runs[1], runs[0]])
	player.place(Vector3(10.4, 0.5, -3.0), PI / 2)
	await _hold("move_forward", 0.3)
	r = await _track(1.2)
	_log("AUTOTEST springboard: peak %.1f, ended at %v" % [r[0], r[1]])
	player.place(Vector3(-36.0, 9.5, 5.0), 0.0)
	r = await _track(1.5)
	var moved := 0
	for i in features._pos.size():
		if features._pos[i].distance_to(features._home[i]) > 0.5:
			moved += 1
	_log("AUTOTEST ball pit: landed at %v, %d of %d balls thrown" % [r[1], moved, features._pos.size()])
	# windows: jump at one from inside and crash out; walk back in over the sill without jumping
	var win: Dictionary = {}
	for w in level.windows:
		if float(w.s0) < 1.0 and w.ax and float(w.at) < -20.0 and w.body != null:
			win = w
			break
	if not win.is_empty():
		var u := (float(win.a) + float(win.b)) * 0.5
		var at: float = win.at
		var inside := 1.0 if at < 0.0 else -1.0   # the house is towards z = 0
		player.place(Vector3(u, 0.05, at + inside * 2.2), 0.0 if inside < 0.0 else PI)
		await get_tree().create_timer(0.3).timeout
		Input.action_press("move_forward")
		await get_tree().create_timer(0.12).timeout
		Input.action_press("jump")
		await get_tree().create_timer(0.7).timeout
		Input.action_release("jump")
		Input.action_release("move_forward")
		await get_tree().create_timer(0.4).timeout
		var out_side: bool = (player.global_position.z - at) * inside < 0.0
		_log("AUTOTEST window: jumped through=%s glass broken=%s, now %.1f m outside" % [out_side, not is_instance_valid(win.body) or (win.body as Node).is_queued_for_deletion(), absf(player.global_position.z - at)])
		player.place(Vector3(u, 0.05, at - inside * 1.6), PI if inside < 0.0 else 0.0)
		await get_tree().create_timer(0.3).timeout
		await _hold("move_forward", 1.0)
		_log("AUTOTEST window: walked back in without jumping=%s (at %v, wall at %.1f, sill %.2f)" % [(player.global_position.z - at) * inside > 0.0, player.global_position, at, float(win.s0)])
	# hot tub: jump in and it splashes
	player.place(Vector3(-16, 8.5, 4), 0.0)
	await get_tree().create_timer(1.0).timeout
	var tub: Dictionary = features._tubs[0]
	var rings_on := 0
	for rg in tub.rings:
		if float(rg[1]) < 1.2:
			rings_on += 1
	_log("AUTOTEST hot tub: in it=%s at y %.2f, splash rings %d, water found=%s, jets %d" % [tub.inside.get(player.get_instance_id(), false), player.global_position.y, rings_on, tub.water != null, features.get_children().filter(func(c): return c is GPUParticles3D).size()])
	# smashable props: shoot one apart, then it grows back once its 40 s are up
	var kinds := {}
	var with_look := 0
	for pr in level.props:
		kinds[pr.kind] = int(kinds.get(pr.kind, 0)) + 1
		if pr.node:
			with_look += 1
	_log("AUTOTEST props: %d smashable %s, %d with their look found" % [level.props.size(), str(kinds), with_look])
	var target: Dictionary = {}
	for pr in level.props:
		if pr.kind == "crate" and pr.node and float(pr.hp0) <= 40.0:
			target = pr
			break
	if not target.is_empty():
		var tb: AABB = target.box
		var shots := 0
		while (target.body as StaticBody3D).collision_layer != 0 and shots < 20:
			game.hit_world(target.body, tb.get_center(), Vector3.UP, Vector3.FORWARD, 12.0)
			shots += 1
		await get_tree().create_timer(0.5).timeout
		_log("AUTOTEST prop (%.0f hp): broke after %d hits of 12, look hidden=%s, solid=%s" % [target.hp0, shots, not (target.node as Node3D).visible, (target.body as StaticBody3D).collision_layer != 0])
		target.back = 0.01
		player.place(Vector3(0, 0.05, -40), 0.0)
		await get_tree().create_timer(0.6).timeout
		_log("AUTOTEST prop grew back: solid=%s visible=%s size %.2f" % [(target.body as StaticBody3D).collision_layer != 0, (target.node as Node3D).visible, float(target.get("grow", 1.0))])
	player.invulnerable = false

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
		player.ammo = 5   # under 10 bullets left, so the new gun can be taken
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

# ---------------- phase 3 Collection rules checks ----------------
func _active_stars() -> Array:
	return game.stars.filter(func(st): return st.active)

func _star_checks() -> void:
	player.force_input = true
	await _wait(1.0)
	# 6 stars, all inside the house (ground or first floor, never the roof), spread out
	var act := _active_stars()
	var inside := true
	var gap := 1e9
	for a in act:
		var p: Vector3 = a.global_position
		if absf(p.x) > 40.0 or absf(p.z) > 27.0 or p.y > 7.0:
			inside = false
		for b in act:
			if a != b and absf(p.y - b.global_position.y) < 3.0:
				gap = minf(gap, Vector2(p.x - b.global_position.x, p.z - b.global_position.z).length())
	_log("AUTOTEST stars: %d out, all inside=%s, closest pair on a floor %.1f m" % [act.size(), inside, gap])
	# take one: it's gone for 8-14 s, then comes back at least 25 m from where it was
	var s0: Node = act[0]
	var at: Vector3 = s0.global_position
	Settings.camera_mode = "first"
	player.apply_camera_mode()
	player.place(at + Vector3(0, 0.05, -2.6), 0.0)
	await _wait(0.4)
	_face(player, at + Vector3.UP * 1.0)
	await _wait(0.3)
	await _snap("p3_01_star_first.png")
	player.place(at + Vector3(0, 0.05, 0), 0.0)
	await _wait(0.2)
	var wait_s: float = game._star_wait.get(s0, -1.0)
	var out_now := _active_stars().size()
	game._star_wait[s0] = 0.01   # skip the wait
	await _wait(0.2)
	_log("AUTOTEST take star: you have %d, stars out %d, back in %.1f s, then %d out and that star moved %.1f m" % [player.stars, out_now, wait_s, _active_stars().size(), s0.global_position.distance_to(at)])
	# hold 10 and you can't take an 11th
	game.add_stars(player, game.STARS - player.stars)
	var s1: Node = _active_stars()[1]
	var at1: Vector3 = s1.global_position
	Settings.camera_mode = "third"
	player.apply_camera_mode()
	player.place(at1 + Vector3(0, 0.05, 0), 0.0)
	await _wait(0.5)
	await _snap("p3_02_ten_stars_third.png")
	_log("AUTOTEST at 10: still %d, star still there=%s, marked=%s" % [player.stars, s1.active and s1.global_position == at1, player.marked])
	# a marked leader shows through walls and on the minimap
	var lead: Node = dummies[4]
	game.add_stars(lead, 8)
	_log("AUTOTEST %s at 8: marked=%s stencil=%d" % [lead.display_name, lead.marked, lead._body_mat.stencil_mode])
	player.place(Vector3(-27, 0.05, -31), 0.0)
	_face(player, lead.global_position + Vector3.UP * 1.2)
	await _wait(1.0)
	await _snap("p3_03_marked_xray_third.png")
	# down costs 2 (dropped where you fell), death costs the rest
	player.place(Vector3(-6, 0.05, -36), 0.0)
	await _wait(0.3)
	player.take_damage(150, dummies[1])
	await _wait(0.4)
	_log("AUTOTEST down: you have %d, dropped stars %d" % [player.stars, game.drops.size()])
	await _wait(0.6)
	await _snap("p3_04_dropped_stars_third.png")
	player.take_damage(40, dummies[1])
	await _wait(0.3)
	_log("AUTOTEST dead: you have %d, dropped stars %d, %s kills %d" % [player.stars, game.drops.size(), dummies[1].display_name, dummies[1].kills])
	while not player.alive:
		await get_tree().physics_frame
	await _wait(0.3)
	# pick up a dropped star
	var d0: Node = game.drops[0]
	player.place(d0.global_position + Vector3(0, 0.05, 0), 0.0)
	await _wait(0.2)
	_log("AUTOTEST picked up a dropped star: you have %d, dropped stars left %d" % [player.stars, game.drops.size()])
	# cash in: 10 stars, stand still at the shop for 2 s
	game.add_stars(player, game.STARS - player.stars)
	player.place(game.cash_point + Vector3(0, 0.05, 0), PI)
	var t0 := Time.get_ticks_msec()
	await _wait(1.0)
	await _snap("p3_05_cashing_in_third.png")
	while game.state != "won" and Time.get_ticks_msec() - t0 < 5000:
		await get_tree().physics_frame
	_log("AUTOTEST cash in: state=%s winner=%s after %.1f s" % [game.state, game.winner.display_name if game.winner else "none", (Time.get_ticks_msec() - t0) / 1000.0])
	await _wait(3.0)
	await _snap("p3_06_victory_results.png")
	player.force_input = false

# ---------------- phase 4: a full 8-bot match ----------------
func _bots_match(cfg: Dictionary) -> void:
	var limit: float = cfg.get("match_secs", 300.0)
	Engine.time_scale = float(cfg.get("speed", 1.0))
	_log("AUTOTEST nav: %d ladder and lift links of %d, %d short cuts of %d" % [game.ladder_links, level.ladders.size() + level.lifts.size(), game.warp_links, level.layout.get("warps", []).size()])
	_log("AUTOTEST bots: difficulty %s, styles %s" % [Settings.bots, ", ".join(game.fighters.map(func(f): return "%s=%s" % [f.display_name, _brain(f).style]))])
	var t0: float = game.clock
	var next_report := 15.0
	var stuck := {}
	var last_pos := {}
	var shot_i := 0
	var shots: Array = cfg.get("match_shots", [])
	var outdoor := [0, 0, 0, 0]   # outside, all, on the roof, after the first 10 s outside
	while game.state == "fight" and game.clock - t0 < limit:
		await get_tree().physics_frame
		for f in game.fighters:
			if f.alive:
				outdoor[1] += 1
				var p: Vector3 = f.global_position
				if absf(p.x) > 40.0 or absf(p.z) > 27.0 or p.y > 10.5:
					outdoor[0] += 1
					if p.y > 10.5:
						outdoor[2] += 1
					if game.clock - t0 > 10.0:
						outdoor[3] += 1
		var t: float = game.clock - t0
		if t >= next_report:
			next_report += 15.0
			var parts: Array[String] = []
			for f in game.fighters:
				var b := _brain(f)
				var moved: float = f.global_position.distance_to(last_pos.get(f, f.global_position)) if last_pos.has(f) else 99.0
				if f.alive and not f.downed and moved < 1.0:
					stuck[f] = int(stuck.get(f, 0)) + 1
					_log("AUTOTEST   still: %s %s at %v goal %v ladder=%s floor=%s target=%s" % [f.display_name, b.state if b else "-", f.global_position, b.goal if b else Vector3.ZERO, f.on_ladder, f.is_on_floor(), b.target.display_name if b and b.target else "-"])
				last_pos[f] = f.global_position
				parts.append("%s %d★ %dk/%dd %s y%.0f" % [f.display_name, f.stars, f.kills, f.deaths, b.state if b else "-", f.global_position.y])
			_log("AUTOTEST t=%ds stars out %d | %s" % [int(t), _active_stars().size(), " | ".join(parts)])
		if shot_i < shots.size() and t >= float(shots[shot_i].get("at", 0.0)):
			var sh: Dictionary = shots[shot_i]
			shot_i += 1
			Settings.camera_mode = sh.get("cam", "third")
			player.apply_camera_mode()
			game.debug = sh.get("debug", false)
			await _snap(sh.file)
	Engine.time_scale = 1.0
	var total_stars := 0
	var total_kills := 0
	for f in game.fighters:
		total_stars += f.stars
		total_kills += f.kills
	_log("AUTOTEST bots match: state=%s winner=%s after %.0f s, kills %d, stars held %d, times stuck (15 s checks) %s, time outside or on the roof %d%% (roof %d%%, outside after the first 10 s %d%%)" % [game.state, game.winner.display_name if game.winner else "none", game.clock - t0, total_kills, total_stars, str(stuck.values()), roundi(100.0 * outdoor[0] / maxf(1.0, outdoor[1])), roundi(100.0 * outdoor[2] / maxf(1.0, outdoor[1])), roundi(100.0 * outdoor[3] / maxf(1.0, outdoor[1]))])
	for f in game.standings():
		_log("AUTOTEST   %s: %d stars, %d kills, %d deaths" % [f.display_name, f.stars, f.kills, f.deaths])
	_log("AUTOTEST props broken in the match: %d" % game.props_broken)
	_log("AUTOTEST Mansion features used: %s" % str(features.uses) + ", lift and pole rides " + str(game.fighters.reduce(func(a, f): return a + f.rides, 0)))
	if game.state == "won" and cfg.has("end_shot"):
		await _wait(3.2)
		await _snap(cfg.end_shot)

func _brain(f: Node) -> Node:
	for c in f.get_children():
		if c.has_method("set_difficulty"):
			return c
	return null

# ---------------- phase 5: menus, settings, rebinding ----------------
func _press(key: int) -> void:
	var k := InputEventKey.new()
	k.physical_keycode = key
	k.keycode = key
	k.pressed = true
	Input.parse_input_event(k)
	await get_tree().process_frame
	var up := k.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

func _menu_checks() -> void:
	_log("AUTOTEST menu: start screen shown=%s state=%s" % [menu.visible and menu.screen == "start", game.state])
	await _snap("p5_01_start_menu.png")
	menu.hide_menu()   # what the PLAY button does before it signals
	menu.play.emit()
	await get_tree().process_frame
	_log("AUTOTEST menu: after Play state=%s hud=%s" % [game.state, hud.visible])
	while game.state != "fight":
		await get_tree().physics_frame
	await _press(KEY_ESCAPE)
	await _wait(0.2)
	_log("AUTOTEST pause: paused=%s screen=%s" % [get_tree().paused, menu.screen])
	menu.show_settings("pause")
	await get_tree().process_frame
	await _snap("p5_02_settings.png")
	for q in ["low", "medium", "high"]:
		Settings.quality = q
		_on_settings_changed("quality")
		await get_tree().process_frame
		_log("AUTOTEST quality %s: sdfgi=%s ssr=%s fog=%s ssil=%s probes=%s msaa=%d" % [q, _env.sdfgi_enabled, _env.ssr_enabled, _env.volumetric_fog_enabled, _env.ssil_enabled, _probes.visible if _probes else false, get_viewport().msaa_3d])
	Settings.vol_weapons = 3
	_on_settings_changed("audio")
	_log("AUTOTEST volume: Weapons bus %.1f dB (setting 3 = 30%%)" % AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Weapons")))
	Settings.vol_weapons = 8
	_on_settings_changed("audio")
	menu.show_keys()
	await get_tree().process_frame
	await _snap("p5_03_keys.png")
	var before: String = menu.key_name("jump")
	menu._bind("jump", (func():
		var k := InputEventKey.new()
		k.physical_keycode = KEY_K
		return k).call(), false)
	_log("AUTOTEST rebind: jump %s -> %s" % [before, menu.key_name("jump")])
	menu._bind("jump", _key_defaults["jump"], false)
	_log("AUTOTEST rebind reset: jump %s" % menu.key_name("jump"))
	menu.hide_menu()
	_on_resume()
	await get_tree().process_frame
	_log("AUTOTEST resume: paused=%s" % get_tree().paused)
