extends Node3D
## Phase 1 entry point: builds the lighting, the grey-box Mansion and the player, sets up the controls, and shows a
## small help panel. If autotest.json says "enabled": true, it runs the scripted checks and screenshots instead.

const Fighter := preload("res://fighter/fighter.gd")
const LevelBuilder := preload("res://level/level_builder.gd")

var level: Node3D
var player: CharacterBody3D
var hud: Label

func _ready() -> void:
	_inputs()
	_environment()
	level = LevelBuilder.new()
	level.name = "Level"
	add_child(level)
	level.build()
	_house_lights()
	player = Fighter.new()
	player.name = "Player"
	player.ladders = level.ladders
	add_child(player)
	# first spawn of the game: out on the front lawn, facing the house (as in Collection)
	player.place(Vector3(-6, 0.05, -36), 0.0)
	_hud()
	var auto := _autotest()
	if auto.get("enabled", false):
		_run_autotest(auto)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _inputs() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN], "move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "crouch": [KEY_C], "camera_toggle": [KEY_V], "pause": [KEY_ESCAPE, KEY_P],
	}
	for a in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		for k in keys[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(a, ev)
	# controller: left stick moves, A jumps, B crouches, Back swaps camera
	var pad := {"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0], "move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0]}
	for a in pad:
		var m := InputEventJoypadMotion.new()
		m.axis = pad[a][0]
		m.axis_value = pad[a][1]
		InputMap.action_add_event(a, m)
	for pair in [["jump", JOY_BUTTON_A], ["crouch", JOY_BUTTON_B], ["camera_toggle", JOY_BUTTON_BACK], ["pause", JOY_BUTTON_START]]:
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

func _hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(16, 12)
	hud.add_theme_color_override("font_color", Color(1, 1, 1))
	hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	hud.add_theme_constant_override("shadow_offset_x", 1)
	hud.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(hud)

func _process(_dt: float) -> void:
	if hud and player:
		var p := player.global_position
		hud.text = "imok Collection · Godot grey box (phase 1)\nWASD move · Space jump (twice: double jump) · C crouch · V camera (%s) · Esc frees the mouse\n%d fps · x %.1f  y %.1f  z %.1f · stamina %d%s" % [
			Settings.camera_mode, Engine.get_frames_per_second(), p.x, p.y, p.z, player.stamina, " · on ladder" if player.on_ladder else ""]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseButton and e.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
		_logf = FileAccess.open("res://shots/autotest.txt", FileAccess.WRITE)
	_logf.store_line(t)
	_logf.flush()

func _run_autotest(cfg: Dictionary) -> void:
	await get_tree().create_timer(1.0).timeout
	_log("AUTOTEST boxes=%d ladders=%d spawns=%d" % [level.get_child_count(), level.ladders.size(), level.spawns.size()])
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
