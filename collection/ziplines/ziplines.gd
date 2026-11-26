extends Node3D
## Two ziplines up to the roof (Pete, 26 Nov): one each side of the top of the grand staircase, on the walkway you
## reach coming in through the front door. Step onto a zipline's pad and jump to grab the handle: it whisks you up
## over the hall at 11 m/s and you smash through the big glass skylight pane above, out onto the roof. The pane
## rebuilds 5 s after it breaks, so most people who ride get to smash it.
## The rider is moved here (fighter.gd's zip_ride skips its own movement); the handle slides back down afterwards.

const Sfx := preload("res://audio/sfx.gd")

const SPEED := 11.0
const HANG := 2.15            # from the handle down to the rider's feet
const PAD_R := 1.0
const GLASS_BACK := 5.0       # (Pete, 26 Nov)
## per side: the pad (feet) at the top of the stairs, the handle's start and end, and the skylight pane it goes through
const LINES := [
	{"pad": Vector3(-3.0, 5.8, 7.5), "end": Vector3(-1.6, 13.55, -6.0), "pane": Vector3(-1.6, 11.18, -1.9)},
	{"pad": Vector3(3.0, 5.8, 7.5), "end": Vector3(1.6, 13.55, -6.0), "pane": Vector3(1.6, 11.18, -1.9)},
]

var game: Node = null
var level: Node3D = null
var lines: Array = []          # {a (handle start), b (handle end), pad, pane (its glass body), handle (Node3D), t (handle along the line), rider}
var rides := 0
var _look_t := 0.0

func setup(g: Node, lv: Node3D) -> void:
	game = g
	level = lv
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.77)
	steel.metallic = 0.9
	steel.roughness = 0.3
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.metallic = 0.6
	dark.roughness = 0.4
	var yellow := StandardMaterial3D.new()   # the pad: a ring on the floor like the pole's and the trampoline's
	yellow.albedo_color = Color("#f4c22b")
	yellow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for L in LINES:
		var a: Vector3 = (L.pad as Vector3) + Vector3.UP * HANG
		var b: Vector3 = L.end
		var line := {"a": a, "b": b, "pad": L.pad, "pane": null, "pane_at": L.pane, "handle": null, "t": 0.0, "rider": null}
		# the cable, a post at the bottom with its arm out over the pad, and a block at the top on the roof
		_rod(a + Vector3.UP * 0.05, b + Vector3.UP * 0.05, 0.014, steel)
		var post_at: Vector3 = (L.pad as Vector3) + Vector3(0, 0, 0.9)
		_rod(post_at, post_at + Vector3.UP * (HANG + 0.4), 0.06, dark)
		_rod(post_at + Vector3.UP * (HANG + 0.3), a + Vector3.UP * 0.1, 0.035, dark)
		var top := MeshInstance3D.new()
		var tb := BoxMesh.new()
		tb.size = Vector3(0.4, 0.5, 0.4)
		top.mesh = tb
		top.material_override = dark
		add_child(top)
		top.global_position = b + Vector3(0, 0.1, -0.3)
		_rod(b + Vector3(0, -0.15, -0.3), Vector3(b.x, 11.35, b.z - 0.3), 0.05, dark)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.85
		tm.outer_radius = 1.0
		ring.mesh = tm
		ring.scale = Vector3(1, 0.05, 1)
		ring.material_override = yellow
		add_child(ring)
		ring.global_position = (L.pad as Vector3) + Vector3.UP * 0.03
		var sign_lbl := Label3D.new()
		sign_lbl.text = "ZIPLINE TO THE ROOF\nJUMP TO GRAB"
		sign_lbl.font_size = 64
		sign_lbl.pixel_size = 0.004
		sign_lbl.modulate = Color("#f4c22b")
		sign_lbl.outline_size = 8
		sign_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		add_child(sign_lbl)
		sign_lbl.global_position = post_at + Vector3.UP * (HANG + 0.75)
		# the handle: a trolley on the cable with a bar to hold
		var h := Node3D.new()
		add_child(h)
		var tro := MeshInstance3D.new()
		var trb := BoxMesh.new()
		trb.size = Vector3(0.12, 0.14, 0.3)
		tro.mesh = trb
		tro.material_override = dark
		h.add_child(tro)
		var bar := MeshInstance3D.new()
		var bc := CylinderMesh.new()
		bc.top_radius = 0.022
		bc.bottom_radius = 0.022
		bc.height = 0.55
		bar.mesh = bc
		bar.rotation.z = PI * 0.5
		bar.position = Vector3(0, -0.3, 0)
		bar.material_override = yellow
		h.add_child(bar)
		_rod_local(h, Vector3(0, -0.05, 0), Vector3(0, -0.3, 0), 0.012, steel)
		line.handle = h
		lines.append(line)
		_place_handle(line)
	# the two skylight panes the lines go through: they come back 5 s after breaking
	for line in lines:
		line.pane = _pane_near(line.pane_at)

func _pane_near(at: Vector3) -> StaticBody3D:
	if level == null:
		return null
	var best: StaticBody3D = null
	var bd := 2.0
	for i in level.bodies:
		var o: Variant = level.bodies[i]
		if not is_instance_valid(o) or not (o is StaticBody3D) or not (o as Node).has_meta("glass"):
			continue
		var b := o as StaticBody3D
		var d := b.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = b
	if best:
		best.set_meta("rebuild", GLASS_BACK)
	return best

func _rod(a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	c.radial_segments = 8
	mi.mesh = c
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = (a + b) * 0.5
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.global_basis = Basis(side, up, side.cross(up))

func _rod_local(parent: Node3D, a: Vector3, b: Vector3, r: float, m: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = a.distance_to(b)
	mi.mesh = c
	mi.material_override = m
	mi.position = (a + b) * 0.5
	parent.add_child(mi)

func _hook(line: Dictionary) -> Vector3:
	return (line.a as Vector3).lerp(line.b, float(line.t))

func _place_handle(line: Dictionary) -> void:
	var h: Node3D = line.handle
	h.global_position = _hook(line)
	var d: Vector3 = (line.b as Vector3) - (line.a as Vector3)
	h.rotation.y = atan2(d.x, d.z)

func _physics_process(dt: float) -> void:
	if game == null:
		return
	var length: float = 1.0
	for line in lines:
		length = (line.a as Vector3).distance_to(line.b)
		var f: Node = line.rider
		if f != null:
			if not is_instance_valid(f) or not f.alive or f.downed:
				_let_go(line, false)
				continue
			line.t = minf(1.0, float(line.t) + SPEED * dt / length)
			var hook := _hook(line)
			f.global_position = hook - Vector3.UP * HANG
			f.zip_handle = hook
			# through the skylight
			var pane: StaticBody3D = line.pane
			if pane and is_instance_valid(pane) and not pane.is_queued_for_deletion() and hook.y - 1.0 > float(line.pane_at.y) - 0.6:
				game.break_glass(pane, line.pane_at)
				line.pane = null
			if float(line.t) >= 1.0:
				_let_go(line, true)
		else:
			# the handle slides back down to the pad once it's been ridden
			if float(line.t) > 0.0:
				line.t = maxf(0.0, float(line.t) - 6.0 * dt / length)
			elif float(line.t) <= 0.0:
				for o in game.fighters:
					if not o.alive or o.downed or o.zip_ride or not o.in_jump:
						continue
					var d: Vector3 = o.global_position - (line.pad as Vector3)
					if Vector2(d.x, d.z).length() < PAD_R and absf(d.y) < 0.8:
						_grab(line, o)
						break
			if line.pane == null:   # it rebuilds 5 s after breaking: look for the new one now and then
				_look_t -= dt
				if _look_t <= 0.0:
					_look_t = 0.5
					line.pane = _pane_near(line.pane_at)
		_place_handle(line)

func _grab(line: Dictionary, f: Node) -> void:
	line.rider = f
	line.t = 0.0
	f.zip_ride = true
	f.velocity = Vector3.ZERO
	var d: Vector3 = (line.b as Vector3) - (line.a as Vector3)
	f.yaw = atan2(d.x, d.z)
	rides += 1
	Sfx.play(self, "fistwhoosh", f.global_position + Vector3.UP * 2.0, 0.0, 0.5, 20.0)

func _let_go(line: Dictionary, at_top: bool) -> void:
	var f: Node = line.rider
	line.rider = null
	if f == null or not is_instance_valid(f):
		return
	f.zip_ride = false
	f.zip_handle = Vector3.INF
	if at_top:   # off at the top: a little forward onto the roof
		var d: Vector3 = (line.b as Vector3) - (line.a as Vector3)
		f.velocity = Vector3(d.x, 0, d.z).normalized() * 4.0 + Vector3.UP * 2.0
