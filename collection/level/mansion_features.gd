extends Node3D
## The Mansion's moving parts and toys (DESIGN §9), ported from the web game's mansion() (1v1 collection-v1):
## - fireman's pole (games room ↔ playroom): stand on the yellow ring to whizz up, drop into the hole upstairs to slide down
## - 2 lifts (ballroom → kids' room, pool → guest room): the cars follow whoever rides them (riding is in fighter.gd)
## - gym trampolines: two bouncy ones, and the launch one that throws you up through the ceiling into the trophy room
## - 2 portal pairs linking opposite corners (bar ↔ conservatory, panic room ↔ observatory), swirls turning
## - indoor pool: wade through it 20% slower; the springboard bounces you out into the water
## - playroom ball pit: balls scatter when you walk through and burst out all over the room when you land in it
## - ballroom: dance floor patterns, turning disco ball, moving-head beams kept inside the room, its own music
## - hot tubs (spa and roof terrace): jets streaming in from the rim, the water moving, a splash and a ring on the water
##   when you get in, wading sounds as you move about (DESIGN §9: jets only, no ducks)
## Every fighter (you and the bots) gets the same treatment.

const Sfx := preload("res://audio/sfx.gd")
const UF := 5.8                      # upstairs floor height
const GRAV := 36.0
const JUMP := 12.0

var game: Node
var level: Node

var _t := 0.0
var uses := {"pole up": 0, "pole down": 0, "launch": 0, "trampoline": 0, "portal": 0, "springboard": 0}
var _st := {}                        # per fighter: pole arm, trampoline / springboard / portal timers, ball pit landing

# ---- pole
const POLE := Vector2(-32, 0)
var _pole := -1                      # its index in level.lifts

# ---- trampolines: x, z, radius, launch
const TRAMPS := [[32.0, 0.0, 1.4, true], [27.5, -5.5, 1.2, false], [36.5, 5.5, 1.2, false]]
var TRV := sqrt(2.0 * (JUMP * JUMP + pow(JUMP * 1.05, 2)))   # twice a double jump's height
var LV := sqrt(2.0 * GRAV * 7.2)
var _tr_t := [9.0, 9.0, 9.0]
var _tr_mats := [null, null, null]
var _arrow: Node3D

# ---- portals: [A, A.nx, B, B.nx]
const PORTALS := [[Vector3(-39.75, 0, 18), 1.0, Vector3(39.75, 0, -18), -1.0],
		[Vector3(-39.75, UF, 18), 1.0, Vector3(39.75, UF, -18), -1.0]]
const SWIRL_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float speed = 2.2;
void fragment() {
	float a = TIME * speed;
	vec2 uv = mat2(vec2(cos(a), sin(a)), vec2(-sin(a), cos(a))) * (UV - 0.5) + 0.5;
	uv = abs(mod(uv + 1.0, 2.0) - 1.0);
	vec4 c = texture(tex, uv);
	ALBEDO = c.rgb;
	ALPHA = 0.95;
}
"""

# ---- pool
const POOL_IN := Rect2(11.4, -4.6, 9.2, 9.2)
const WATER_Y := -0.3
var _water: Array = []
var _water_base: Array = []

# ---- ball pit (playroom, upstairs)
const BR := 0.17
const PIT_WALLS := [[-36.0, 2.4, 5.0, 0.3], [-36.0, 7.6, 5.0, 0.3], [-38.5, 5.0, 0.3, 5.5], [-33.5, 4.0, 0.3, 3.5]]
const ROOM := Rect2(-39.6 + BR, -8.6 + BR, 15.2 - 2.0 * BR, 17.2 - 2.0 * BR)
const BALL_COLS := ["#e8463a", "#f4c22b", "#2f7fe0", "#3bb54a", "#ff8fab", "#a05ad6"]
var _home: PackedVector3Array = []
var _pos: PackedVector3Array = []
var _vel: PackedVector3Array = []
var _awake: PackedByteArray = []
var _cd: PackedFloat32Array = []
var _balls: MultiMeshInstance3D
var _pit_snd := 0.0

# ---- ballroom
const DISCO := Vector3(-16, 0, 17)
const DISCO_COLS := ["#ff2aa0", "#2affd0", "#ffd23f", "#7a5cff", "#ff6a2a", "#3aa8ff"]
var _df_img: Image
var _df_tex: ImageTexture
var _df_last := -1
var _beams: Array = []               # [node, [materials]]
var _disco_light: OmniLight3D

var _cars: Array = []                # [node, lift index]

# ---- hot tubs: x, z (both on the upstairs floor, deck 0.3 m, water 0.42 m above it)
const TUBS := [Vector2(-16, 4), Vector2(30, 23)]
const TUB_R := 1.5
var _tubs: Array = []                # {c, wy, water, base, burst, rings: [[mesh, t, s]], ri, inside: {}}

func setup(g: Node, lv: Node) -> void:
	game = g
	level = lv
	for i in level.lifts.size():
		var c: Vector3 = (level.lifts[i].box as AABB).get_center()
		if Vector2(c.x, c.z).distance_to(POLE) < 1.5:
			_pole = i
	var parts: Dictionary = level.parts
	for car in parts.get("lift_car", []):
		var best := -1
		var bd := 3.0
		for i in level.lifts.size():
			var c: Vector3 = (level.lifts[i].box as AABB).get_center()
			var d := Vector2(c.x, c.z).distance_to(Vector2(car.position.x, car.position.z))
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			_cars.append([car, best])
	for m in parts.get("tramp_mat", []):
		for i in TRAMPS.size():
			if Vector2(m.position.x, m.position.z).distance_to(Vector2(TRAMPS[i][0], TRAMPS[i][1])) < 0.5:
				_tr_mats[i] = m
	if parts.has("tramp_arrow"):
		_arrow = parts.tramp_arrow[0]
	for w in parts.get("pool_water", []):
		var mi := w as MeshInstance3D
		if mi == null:
			continue
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			mi.material_override = mat
			_water.append(mi)
			_water_base.append((mat as StandardMaterial3D).uv1_offset)
	for s in parts.get("portal_swirl", []):
		_swirl(s as MeshInstance3D)
	_setup_disco(parts)
	_setup_ball_pit()
	_setup_tubs()
	if game.has_signal("state_changed"):
		game.state_changed.connect(func(s: String) -> void:
			if s == "countdown":
				_pit_home())

func _fs(f: Node) -> Dictionary:
	var k := f.get_instance_id()
	if not _st.has(k):
		_st[k] = {"arm": true, "tr": -9.0, "trl": false, "dv": -9.0, "pt": -9.0, "air": false, "vy": 0.0}
	return _st[k]

func _physics_process(dt: float) -> void:
	if game == null:
		return
	_t += dt
	for f in game.fighters:
		if not is_instance_valid(f) or not f.alive:
			continue
		var s := _fs(f)
		_pole_step(f, s)
		_tramp_step(f, s, dt)
		_portal_step(f, s)
		_pool_step(f, s, dt)
		_window_step(f)
		_tub_step(f, s)
	_ball_pit(dt)

func _process(dt: float) -> void:
	_animate(dt)

# ---------------------------------------------------------------- pole

func _pole_step(f: Node, s: Dictionary) -> void:
	if _pole < 0 or f.downed or f.ride >= 0 or f.clock < f.ride_cd:
		return
	var p: Vector3 = f.global_position
	var d := Vector2(p.x, p.z).distance_to(POLE)
	if d > 1.3:
		s.arm = true
	if f.is_on_floor() and p.y < 0.2 and d < 0.9 and s.arm:
		f.start_ride(_pole, 1)
		s.arm = false
		uses["pole up"] += 1
	elif not f.is_on_floor() and p.y > UF - 1.2 and p.y < UF + 0.4 and d < 1.15 and f.velocity.y <= 0.0:
		f.start_ride(_pole, -1)
		s.arm = false
		uses["pole down"] += 1

# ---------------------------------------------------------------- trampolines

func _tramp_step(f: Node, s: Dictionary, dt: float) -> void:
	var p: Vector3 = f.global_position
	# the launch carries you east over the edge of the hole so you land on the trophy-room floor
	if s.trl and not f.is_on_floor() and f.clock - float(s.tr) < 1.6 and p.y > UF + 0.2 and p.x < 35.4:
		p.x = minf(35.4, p.x + 6.0 * dt)
		f.global_position = p
		if f.velocity.x < 0.0:
			f.velocity.x = 0.0
	if f.downed or not f.is_on_floor() or p.y > 0.1 or f.clock - float(s.tr) < 0.25:
		return
	for i in TRAMPS.size():
		var T: Array = TRAMPS[i]
		if Vector2(p.x - T[0], p.z - T[1]).length() < T[2]:
			var launch: bool = T[3]
			f.velocity.y = LV if launch else TRV
			if launch:
				f.velocity.x = 3.4
				f.velocity.z *= 0.3
			s.trl = launch
			uses["launch" if launch else "trampoline"] += 1
			f.air_jumps = 1
			s.tr = f.clock
			_tr_t[i] = 0.0
			Sfx.play(self, "land", p, -3.0, 1.8, 18.0)
			break

# ---------------------------------------------------------------- portals

func _portal_step(f: Node, s: Dictionary) -> void:
	if f.downed or f.clock - float(s.pt) < 1.0:
		return
	var p: Vector3 = f.global_position
	for pair in PORTALS:
		for i in 2:
			var A: Vector3 = pair[i * 2]
			var anx: float = pair[i * 2 + 1]
			var O: Vector3 = pair[(1 - i) * 2]
			var onx: float = pair[(1 - i) * 2 + 1]
			if absf(p.y - A.y) > 1.2 or absf(p.z - A.z) > 0.85 or (p.x - A.x) * anx > 0.7 or (p.x - A.x) * anx < -0.2:
				continue
			var sp := maxf(4.0, Vector2(f.velocity.x, f.velocity.z).length())
			f.global_position = Vector3(O.x + onx * 1.1, O.y + (p.y - A.y), O.z)
			f.velocity = Vector3(onx * sp, f.velocity.y, 0)
			f.yaw = PI / 2 if onx > 0 else -PI / 2
			s.pt = f.clock
			uses["portal"] += 1
			Sfx.play(self, "blink", f.global_position, -4.0, 1.0, 16.0)
			return

# ---------------------------------------------------------------- pool

func _pool_step(f: Node, s: Dictionary, dt: float) -> void:
	var p: Vector3 = f.global_position
	f.wading = POOL_IN.has_point(Vector2(p.x, p.z))
	# the springboard at the shallow end: walk to the end and it bounces you up and out into the pool
	if f.is_on_floor() and p.x > 10.9 and p.x < 12.05 and absf(p.z + 3.0) < 0.5 and absf(p.y - 0.42) < 0.15 and f.clock - float(s.dv) > 0.6:
		f.velocity.y = 13.0
		s.dv = f.clock
		uses["springboard"] += 1
		Sfx.play(self, "bounce1", p, -2.0, 1.0, 16.0)
	elif f.clock - float(s.dv) < 0.9 and not f.is_on_floor() and p.x < 17.0:
		p.x += 5.0 * dt
		f.global_position = p

# ---------------------------------------------------------------- windows

## jump at a window and you crash straight through the glass (as on the web); once it's open, just keep walking into
## it and you climb over the 0.8 m sill without needing to jump (Pete, 24 Nov: windows felt too tight)
func _window_step(f: Node) -> void:
	if f.downed or f.ride >= 0:
		return
	var p: Vector3 = f.global_position
	var wish: Vector3 = f.forward() * f.in_move.y + f.right() * f.in_move.x
	for w in level.windows:
		var ax: bool = w.ax
		var d: float = (p.z if ax else p.x) - float(w.at)
		var u: float = p.x if ax else p.z
		if absf(d) > 1.0 or u < float(w.a) + 0.15 or u > float(w.b) - 0.15:
			continue
		var s0: float = w.s0
		var s1: float = w.s1
		if p.y + 1.6 < s0 or p.y > s1 - 0.3:
			continue
		var into: float = -signf(d) * (wish.z if ax else wish.x)   # pushing towards the pane
		var v: float = -signf(d) * (f.velocity.z if ax else f.velocity.x)
		if is_instance_valid(w.body) and not (w.body as Node).is_queued_for_deletion():
			if not f.is_on_floor() and absf(d) < 0.62 and (into > 0.2 or v > 1.0):
				game.break_glass(w.body, Vector3(p.x, p.y + 1.2, p.z))
			continue
		# open: step up onto the sill when walking into it from below
		if into > 0.3 and absf(d) < 0.8 and p.y < s0 - 0.05 and p.y > s0 - 1.2:
			var lift := s0 + 0.03 - p.y
			f.global_position = p + Vector3(0, lift, 0) + Vector3(0, 0, -signf(d) * 0.08) * (1.0 if ax else 0.0) \
					+ Vector3(-signf(d) * 0.08, 0, 0) * (0.0 if ax else 1.0)
			f._step_dy = clampf(f._step_dy - lift, -1.2, 0.0)
			if f.velocity.y < 0.0:
				f.velocity.y = 0.0
		return

# ---------------------------------------------------------------- ball pit

func _setup_ball_pit() -> void:
	var x := -38.35 + BR
	while x <= -33.65 - BR + 1e-6:
		var z := 2.55 + BR
		while z <= 7.45 - BR + 1e-6:
			_home.append(Vector3(x + randf_range(-0.015, 0.015), UF + BR, z + randf_range(-0.015, 0.015)))
			z += BR * 2.0
		x += BR * 2.0
	var n := _home.size()
	_pos.resize(n)
	_vel.resize(n)
	_awake.resize(n)
	_cd.resize(n)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = BR
	sm.height = BR * 2.0
	sm.radial_segments = 12
	sm.rings = 8
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.35
	mat.clearcoat_enabled = true
	sm.material = mat
	mm.mesh = sm
	mm.instance_count = n
	for i in n:
		mm.set_instance_color(i, Color.html(BALL_COLS[randi() % BALL_COLS.size()]))
	_balls = MultiMeshInstance3D.new()
	_balls.multimesh = mm
	_balls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_balls.custom_aabb = AABB(Vector3(-40, UF - 1, -9), Vector3(16, 7, 18))
	add_child(_balls)
	_pit_home()

func _pit_home() -> void:
	for i in _home.size():
		_pos[i] = _home[i]
		_vel[i] = Vector3.ZERO
		_awake[i] = 0
		_cd[i] = 0.0
		_balls.multimesh.set_instance_transform(i, Transform3D(Basis(), _pos[i]))

func _ball_pit(dt: float) -> void:
	if _balls == null:
		return
	dt = minf(dt, 0.05)
	var U := UF
	for f in game.fighters:
		if not is_instance_valid(f) or not f.alive:
			continue
		var s := _fs(f)
		var p: Vector3 = f.global_position
		if p.x < -40 or p.x > -24 or p.z < -9 or p.z > 9 or p.y < U - 0.3 or p.y > U + 1.6:
			s.air = false
			continue
		var v: Vector3 = f.velocity
		var hv := Vector2(v.x, v.z).length()
		var air: bool = not f.is_on_floor()
		var land := 0.0
		if not air and s.air:
			land = clampf(-float(s.vy) / 12.0, 0.4, 1.4)
		s.air = air
		s.vy = v.y
		if land == 0.0 and hv < 1.2 and not (air and v.y < 0.0):
			continue
		var rr := 1.5 if land > 0.0 else 0.62
		var hits := 0
		for i in _pos.size():
			var b := _pos[i]
			var dx := b.x - p.x
			var dz := b.z - p.z
			var d2 := dx * dx + dz * dz
			if d2 > rr * rr or b.y > p.y + 0.7 or b.y < p.y - 0.5 or _cd[i] > _t:
				continue
			var d := maxf(sqrt(d2), 0.01)
			var sp := (2.2 + hv * 0.9) * randf_range(0.6, 1.25) + land * randf_range(3, 7)
			_vel[i] = Vector3(dx / d * sp + v.x * 0.45 + randf_range(-0.6, 0.6), randf_range(2, 4.2) + hv * 0.45 + land * randf_range(4, 9),
					dz / d * sp + v.z * 0.45 + randf_range(-0.6, 0.6))
			_awake[i] = 1
			_cd[i] = _t + 0.18
			hits += 1
		if hits > 0 and _t > _pit_snd:
			_pit_snd = _t + 0.25
			Sfx.play(self, "bounce1", p, linear_to_db(minf(0.8, 0.25 + hits * 0.03 + land * 0.3)), 1.6 + randf() * 0.4, 14.0)
	var mm := _balls.multimesh
	for i in _pos.size():
		if _awake[i] == 0:
			continue
		var b := _pos[i]
		var v := _vel[i]
		v.y -= 24.0 * dt
		b += v * dt
		if b.x < ROOM.position.x:
			b.x = ROOM.position.x; v.x = absf(v.x) * 0.5
		elif b.x > ROOM.end.x:
			b.x = ROOM.end.x; v.x = -absf(v.x) * 0.5
		if b.z < ROOM.position.y:
			b.z = ROOM.position.y; v.z = absf(v.z) * 0.5
		elif b.z > ROOM.end.y:
			b.z = ROOM.end.y; v.z = -absf(v.z) * 0.5
		if b.y > U + 5.2 - BR:
			b.y = U + 5.2 - BR; v.y = -absf(v.y) * 0.3
		for w in PIT_WALLS:
			if b.y > U + 0.7 + BR:
				continue
			var ex: float = w[2] * 0.5 + BR - absf(b.x - w[0])
			var ez: float = w[3] * 0.5 + BR - absf(b.z - w[1])
			if ex > 0.0 and ez > 0.0:
				if b.y > U + 0.65 and v.y < 0.0:
					b.y = U + 0.7 + BR; v.y *= -0.35
				elif ex < ez:
					b.x += signf(b.x - w[0] if b.x != w[0] else 1.0) * ex; v.x *= -0.5
				else:
					b.z += signf(b.z - w[1] if b.z != w[1] else 1.0) * ez; v.z *= -0.5
		if b.y < U + BR:
			b.y = U + BR
			if v.y < 0.0:
				v.y *= -0.38
			v.x *= 0.78
			v.z *= 0.78
			if absf(v.y) < 0.7:
				v.y = 0.0
			if v.y == 0.0 and Vector2(v.x, v.z).length() < 0.25:
				_awake[i] = 0
		_pos[i] = b
		_vel[i] = v
		mm.set_instance_transform(i, Transform3D(Basis(), b))

# ---------------------------------------------------------------- ballroom

func _setup_disco(parts: Dictionary) -> void:
	_df_img = Image.create(128, 128, false, Image.FORMAT_RGB8)
	_df_tex = ImageTexture.create_from_image(_df_img)
	for fl in parts.get("disco_floor", []):
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_texture = _df_tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		(fl as MeshInstance3D).material_override = mat
	for b in parts.get("disco_beam", []):
		var mats: Array = []
		for c in (b as Node).get_children():
			var mi := c as MeshInstance3D
			if mi == null:
				continue
			var m := mi.get_active_material(0)
			if m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				m = m.duplicate()
				mi.material_override = m
				mats.append(m)
		_beams.append([b, mats])
	if parts.has("disco_ball"):
		_beams_ball = parts.disco_ball[0]
	_disco_light = OmniLight3D.new()
	_disco_light.position = DISCO + Vector3(0, 3.6, 0)
	_disco_light.omni_range = 7.5
	_disco_light.light_energy = 1.6
	_disco_light.shadow_enabled = true   # the disco light stays inside the ballroom (Pete)
	add_child(_disco_light)
	_paint_floor(0.0)
	# the ballroom's own music, heard through its doors
	var path := "res://audio/music/disco.wav"
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	elif FileAccess.file_exists(path):
		st = AudioStreamWAV.load_from_file(path)
	if st:
		if st is AudioStreamWAV:
			(st as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			(st as AudioStreamWAV).loop_end = int((st as AudioStreamWAV).get_length() * (st as AudioStreamWAV).mix_rate)
		var pl := AudioStreamPlayer3D.new()
		pl.stream = st
		pl.bus = "Music"
		pl.volume_db = -6.0
		pl.max_distance = 18.0
		pl.unit_size = 4.0
		pl.area_mask = Sfx.AREA_LAYER
		pl.position = DISCO + Vector3(0, 2.5, 8.5)
		pl.autoplay = true
		add_child(pl)

var _beams_ball: Node3D

func _paint_floor(t: float) -> void:
	var k := int(floor(t * 8.0))
	if k == _df_last:
		return
	_df_last = k
	var mode := int(floor(t / 5.0)) % 4
	var nc := DISCO_COLS.size()
	for i in 8:
		for j in 8:
			var c := Color.html(DISCO_COLS[0])
			var on := 1.0
			if mode == 0:
				c = Color.html(DISCO_COLS[(i + j + k) % nc])
			elif mode == 1:
				var r := int(round(Vector2(i - 3.5, j - 3.5).length()))
				c = Color.html(DISCO_COLS[(r - k + 60) % nc])
			elif mode == 2:
				c = Color.html(DISCO_COLS[(k / 4) % nc])
				on = 1.0 if (i + k) % 4 < 2 else 0.15
			else:
				c = Color.html(DISCO_COLS[(i * 3 + j * 5 + k) % nc])
				on = 1.0 if randf() < 0.45 else 0.12
			var col := Color(0.02, 0.01, 0.04).lerp(c, on)
			_df_img.fill_rect(Rect2i(i * 16, j * 16, 16, 16), col)
			var edge := col.darkened(0.4)
			_df_img.fill_rect(Rect2i(i * 16, j * 16, 16, 1), edge)
			_df_img.fill_rect(Rect2i(i * 16, j * 16, 1, 16), edge)
	_df_tex.update(_df_img)
	_disco_light.light_color = Color.html(DISCO_COLS[k % nc])

# ---------------------------------------------------------------- animation

func _animate(dt: float) -> void:
	var t := _t
	for cr in _cars:
		var car: Node3D = cr[0]
		var y := -1.0
		for f in game.fighters:
			if is_instance_valid(f) and f.ride == cr[1]:
				y = f.global_position.y
				break
		car.position.y = maxf(0.0, y - 0.18) if y >= 0.0 else maxf(0.0, car.position.y - dt * 10.0)
	for i in TRAMPS.size():
		_tr_t[i] += dt
		var m: Node3D = _tr_mats[i]
		if m:
			m.position.y = 0.014 - (sin(_tr_t[i] / 0.4 * PI) * 0.18 if _tr_t[i] < 0.4 else 0.0)
	if _arrow:
		_arrow.position.y = 4.4 + sin(t * 3.0) * 0.25
		_arrow.rotation.y = t
	for i in _water.size():
		var w: MeshInstance3D = _water[i]
		var m := w.material_override as StandardMaterial3D
		m.uv1_offset = _water_base[i] + Vector3(sin(t * 0.13) * 0.4, t * 0.05, 0)
		w.position.y = WATER_Y + sin(t * 1.3) * 0.012
	for tb in _tubs:
		if tb.water:
			var wm: StandardMaterial3D = (tb.water as MeshInstance3D).material_override
			wm.uv1_offset = tb.base + Vector3(sin(t * 0.4) * 0.3, t * 0.12, 0)
			(tb.water as Node3D).position.y = float(tb.wy) + sin(t * 2.3) * 0.012
		for r in tb.rings:
			if r[1] > 1.2:
				continue
			r[1] += dt
			var rm: MeshInstance3D = r[0]
			rm.visible = r[1] < 1.2
			var kk: float = r[1] / 1.2
			var sc: float = 0.15 + float(r[2]) * 1.3 * sqrt(kk)
			rm.scale = Vector3(sc, 0.02, sc)
			(rm.material_override as StandardMaterial3D).albedo_color.a = 0.6 * (1.0 - kk) * (1.0 - kk)
	_paint_floor(t)
	if _beams_ball:
		_beams_ball.rotation.y = t * 0.8
	for bi in _beams.size():
		var b: Node3D = _beams[bi][0]
		var ph := t * (0.7 + bi * 0.07) + bi
		b.rotation = Vector3(sin(ph) * 0.42, 0, cos(ph * 1.3) * 0.42)
		var c := Color.html(DISCO_COLS[(bi + int(floor(t * 1.5))) % DISCO_COLS.size()])
		for m in _beams[bi][1]:
			var sm := m as StandardMaterial3D
			sm.albedo_color = Color(c.r, c.g, c.b, sm.albedo_color.a)

# ---------------------------------------------------------------- hot tubs

func _setup_tubs() -> void:
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.07
	drop.radial_segments = 6
	drop.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.92, 0.98, 1.0, 0.75)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.roughness = 0.05
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	drop.material = dm
	var ring := TorusMesh.new()
	ring.inner_radius = 0.86
	ring.outer_radius = 1.0
	ring.rings = 28
	ring.ring_segments = 4
	for c in TUBS:
		var wy := UF + 0.3 + 0.42
		var t := {"c": c, "wy": wy, "rings": [], "ri": 0, "inside": {}, "water": null}
		# the jets: six, streaming in from the rim just under the surface
		for i in 6:
			var a := float(i) / 6.0 * TAU + 0.3
			var jet := GPUParticles3D.new()
			var pm := ParticleProcessMaterial.new()
			pm.direction = Vector3(-cos(a), 0.12, -sin(a))
			pm.spread = 9.0
			pm.initial_velocity_min = 2.0
			pm.initial_velocity_max = 3.0
			pm.gravity = Vector3(0, -3, 0)
			pm.scale_min = 0.6
			pm.scale_max = 1.2
			jet.process_material = pm
			jet.draw_pass_1 = drop
			jet.amount = 14
			jet.lifetime = 0.35
			jet.local_coords = false
			jet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			jet.position = Vector3(c.x + cos(a) * (TUB_R - 0.1), wy - 0.06, c.y + sin(a) * (TUB_R - 0.1))
			jet.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 2, 4))
			add_child(jet)
		# a burst of spray for getting in
		var b := GPUParticles3D.new()
		var bp := ParticleProcessMaterial.new()
		bp.direction = Vector3.UP
		bp.spread = 55.0
		bp.initial_velocity_min = 2.0
		bp.initial_velocity_max = 4.5
		bp.gravity = Vector3(0, -15, 0)
		bp.scale_min = 0.9
		bp.scale_max = 1.8
		b.process_material = bp
		b.draw_pass_1 = drop
		b.amount = 24
		b.lifetime = 0.7
		b.one_shot = true
		b.explosiveness = 0.95
		b.emitting = false
		b.local_coords = false
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
		add_child(b)
		t.burst = b
		for i in 4:
			var rm := MeshInstance3D.new()
			rm.mesh = ring
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(1, 1, 1, 0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			rm.material_override = m
			rm.scale = Vector3(1, 0.02, 1)
			rm.visible = false
			rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rm)
			t.rings.append([rm, 9.0, 1.0])
		_tubs.append(t)
	if level.dressing:
		_find_tub_water(level.dressing)

func _find_tub_water(n: Node) -> void:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi:
			for t in _tubs:
				var p := mi.global_position
				if t.water == null and absf(p.y - float(t.wy)) < 0.05 and Vector2(p.x, p.z).distance_to(t.c) < 0.1:
					var m := mi.get_active_material(0)
					if m is StandardMaterial3D:
						m = m.duplicate()
						mi.material_override = m
						t.water = mi
						t.base = (m as StandardMaterial3D).uv1_offset
		_find_tub_water(c)

func _tub_splash(t: Dictionary, at: Vector3, size: float) -> void:
	var r: Array = t.rings[int(t.ri)]
	t.ri = (int(t.ri) + 1) % (t.rings as Array).size()
	r[1] = 0.0
	r[2] = size
	(r[0] as Node3D).position = Vector3(at.x, float(t.wy) + 0.02, at.z)
	if size > 0.5:
		var b: GPUParticles3D = t.burst
		b.global_position = Vector3(at.x, float(t.wy) + 0.05, at.z)
		b.amount_ratio = clampf(size / 1.6, 0.3, 1.0)
		b.restart()

func _tub_step(f: Node, s: Dictionary) -> void:
	var p: Vector3 = f.global_position
	var k := f.get_instance_id()
	for t in _tubs:
		var c: Vector2 = t.c
		var wy: float = t.wy
		var inn: bool = Vector2(p.x - c.x, p.z - c.y).length() < TUB_R + 0.05 and p.y < wy + 0.6 and p.y > wy - 0.75
		var was: bool = t.inside.get(k, false)
		if inn and not was:
			var size := minf(1.6, 0.6 + maxf(0.0, -float(s.vy if s.has("vy") else 0.0)) / 9.0)
			size = minf(1.6, 0.6 + maxf(0.0, -f.velocity.y) / 9.0) if f.velocity.y < 0.0 else size
			_tub_splash(t, p, size)
			Sfx.play(self, "splash", p, linear_to_db(minf(1.0, 0.45 + size * 0.35)), 1.0, 18.0)
		elif inn and Vector2(f.velocity.x, f.velocity.z).length() > 1.5 and f.clock > float(s.get("tw", 0.0)):
			s.tw = f.clock + 0.32
			_tub_splash(t, p + f.velocity * 0.06, 0.4)
			Sfx.play(self, "wade1" if randf() < 0.5 else "wade2", p, linear_to_db(0.3), 1.0, 12.0, 0.1)
		t.inside[k] = inn

func _swirl(mi: MeshInstance3D) -> void:
	if mi == null:
		return
	var old := mi.get_active_material(0) as StandardMaterial3D
	if old == null or old.albedo_texture == null:
		return
	var sh := Shader.new()
	sh.code = SWIRL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", old.albedo_texture)
	# the web turns each swirl the way its portal faces
	var nx := 1.0 if mi.global_position.x < 0.0 else -1.0
	m.set_shader_parameter("speed", -2.2 * nx)
	mi.material_override = m
