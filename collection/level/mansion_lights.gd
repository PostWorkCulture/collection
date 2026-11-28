extends Node3D
## Each room's own light, from the web Mansion's room table (DESIGN §9 "each with its own colours, lighting and props"):
## - four ceiling fittings in the room's own tint (warm in the kitchen, cool in the gym, pink in the music room ...)
## - rooms with a mood light get one more, stronger, in the middle: library, games room, cinema, hall, pool, bar, panic room,
##   kids' room, hall of mirrors, lab, observatory; it casts shadows so its colour stays in its room
## - the web's moving lights: cinema screen flicker, pool shimmer, panic-room red pulse, hall of mirrors slowly changing
##   colour, lab glow; garage strip lights that stutter (one badly)
## - only rooms near you are lit (DESIGN §9: only light the room you're in): your room and the ones next to it on your
##   floor, plus the hall and the atrium (open to each other)

const DIM_NO_FITTINGS := ["cinema", "observ", "ballroom", "panic"]   # moody rooms: no ceiling fittings
## baked lighting (AAA phase 3): the steady lamps' bounce light is baked into the lightmap while their direct light stays
## real-time (so the pools of light and the shine on glossy floors stay as they were); the lights that move (cinema
## flicker, pool shimmer, panic pulse, lab glow, the hall of mirrors' colour) and the garage strips aren't baked at all
const ANIMATED := ["cinema", "pool", "panic", "lab", "mirrors"]
const H1 := 5.5

var rooms: Array = []
var level_ref: Node = null   # the level builder: hides the furniture of a floor you can't see
var _room_lights := {}      # name -> Array of [OmniLight3D, base energy]
var _accent := {}           # name -> OmniLight3D
var _tubes: Array = []      # garage: [light, bad, on, timer]
var _t := 0.0
var _cell := Vector3i(-99, -99, -99)
var _shadows := true        # the mood light of the room you're in casts shadows (Medium and High)
var _baked := false         # a lightmap is in: the moving lights are kept out of it

func setup(layout: Dictionary, quality: String, baked: bool = false) -> void:
	_baked = baked
	rooms = layout.get("rooms", [])
	_shadows = quality != "low"
	for r in rooms:
		var nm: String = r.name
		if nm == "terrace":
			continue   # open to the sky
		var cx := (float(r.x0) + float(r.x1)) * 0.5
		var cz := (float(r.z0) + float(r.z1)) * 0.5
		var top: float = float(r.top) if r.ceiling or float(r.y) > 1.0 else 11.0
		var col := Color.html(String(r.fit))
		var list: Array = []
		if not DIM_NO_FITTINGS.has(nm) and nm != "garage":
			for o in [Vector2(-4, -4.5), Vector2(4, -4.5), Vector2(-4, 4.5), Vector2(4, 4.5)]:
				var l := _light(Vector3(cx + o.x, top - 0.45, cz + o.y), col.lerp(Color(1, 0.97, 0.92), 0.35), 1.05, 8.5, false)
				list.append([l, l.light_energy])
		var acc: float = r.accent
		if acc > 0.0 and nm != "ballroom":   # the ballroom's colour light is mansion_features' disco light
			var e := acc * 0.28
			if DIM_NO_FITTINGS.has(nm):
				e = maxf(e, 3.0)   # moody, not black
			var l := _light(Vector3(cx, top - 1.4, cz), col, e, 10.5 if top > 6.0 else 9.5, false)
			if ANIMATED.has(nm):
				_live(l)
			list.append([l, l.light_energy])
			_accent[nm] = l
		_room_lights[nm] = list
	# garage: five strip lights, cool white, humming and stuttering
	for t in [[28.0, 13.5, false], [32.5, 13.5, false], [28.0, 22.0, true], [32.5, 22.0, false], [36.0, 22.5, false]]:
		var l := _light(Vector3(t[0], H1 - 0.35, t[1]), Color("#cfe6ff"), 1.3, 7.5, false)
		_live(l)
		_tubes.append([l, t[2], true, randf() * 4.0])
		(_room_lights["garage"] as Array).append([l, l.light_energy])

func set_quality(q: String) -> void:
	_shadows = q != "low"
	_cell = Vector3i(-99, -99, -99)   # re-apply on the next frame

func _light(p: Vector3, col: Color, energy: float, rng: float, shadows: bool) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.3
	l.shadow_enabled = shadows
	l.light_specular = 0.6
	l.light_bake_mode = Light3D.BAKE_DYNAMIC   # steady: its bounce is baked, its direct light stays real-time
	add_child(l)
	return l

## a light that moves (pulses, flickers, changes colour) stays real-time and out of the lightmap
func _live(l: OmniLight3D) -> void:
	if _baked:
		l.light_bake_mode = Light3D.BAKE_DISABLED

## which room a point is in (row, column, floor), or (-1, -1, floor) outside
func _cell_of(p: Vector3) -> Vector3i:
	var fl := 1 if p.y > 5.6 else 0
	if p.x < -40 or p.x > 40 or p.z < -27 or p.z > 27:
		return Vector3i(-1, -1, fl)
	return Vector3i(clampi(int(floor((p.x + 40.0) / 16.0)), 0, 4), clampi(int(floor((p.z + 27.0) / 18.0)), 0, 2), fl)

func _process(dt: float) -> void:
	_t += dt
	var cam := get_viewport().get_camera_3d()
	if cam:
		if level_ref:
			var fs: Array = level_ref.floors_seen(cam.global_position)
			level_ref.show_floors(fs[0], fs[1])
		var c := _cell_of(cam.global_position)
		if c != _cell:
			_cell = c
			_cull(c)
	_animate(dt)

func _cull(c: Vector3i) -> void:
	for r in rooms:
		var nm: String = r.name
		if not _room_lights.has(nm):
			continue
		var rc := _cell_of(Vector3((float(r.x0) + float(r.x1)) * 0.5, float(r.y) + 1.0, (float(r.z0) + float(r.z1)) * 0.5))
		var on := false
		if c.x < 0:
			on = rc.z == 0 or nm == "hall"   # outside: the ground floor shows through the windows
		else:
			on = rc.z == c.z and absi(rc.x - c.x) <= 1 and absi(rc.y - c.y) <= 1
		if nm == "hall" or nm == "atrium":
			on = on or (c.x >= 1 and c.x <= 3 and c.y == 1)   # the hall void joins both floors
		for e in _room_lights[nm]:
			(e[0] as OmniLight3D).visible = on
		if _accent.has(nm):   # only the mood light of your own room casts shadows: its colour stays in the room, cheaply
			(_accent[nm] as OmniLight3D).shadow_enabled = _shadows and rc == c

func _animate(dt: float) -> void:
	var t := _t
	if _accent.has("cinema"):
		_flex("cinema", (2.2 + sin(t * 3.1) * 0.6 + sin(t * 7.7) * 0.4) / 3.0)
	if _accent.has("pool"):
		_flex("pool", (8.0 + sin(t * 1.7) * 1.2) / 9.0)
	if _accent.has("panic"):
		_flex("panic", maxf(0.35, (4.0 + sin(t * 6.0) * 3.0) / 6.0))
	if _accent.has("lab"):
		_flex("lab", (7.0 + sin(t * 2.3) * 2.0) / 8.0)
	if _accent.has("mirrors"):
		(_accent["mirrors"] as OmniLight3D).light_color = Color.from_hsv(fmod(t * 0.05, 1.0), 0.45, 1.0)
	for tb in _tubes:
		tb[3] -= dt
		if tb[3] <= 0.0:
			if tb[1]:   # the bad one: stutters often, sometimes stays off a moment
				tb[2] = not tb[2] if randf() < 0.7 else true
				tb[3] = randf_range(0.04, 0.12) if tb[2] == false else randf_range(0.05, 0.9)
			else:       # the others: a rare short blink
				tb[2] = not tb[2] if tb[2] else true
				tb[3] = randf_range(0.03, 0.08) if not tb[2] else randf_range(2.5, 9.0)
		(tb[0] as OmniLight3D).light_energy = 1.3 if tb[2] else 0.08

func _flex(nm: String, k: float) -> void:
	var l: OmniLight3D = _accent[nm]
	for e in _room_lights[nm]:
		if e[0] == l:
			l.light_energy = float(e[1]) * k
