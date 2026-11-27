extends Node3D
## Mines and stun grenades in play (Pete, 26 Nov; numbers from the web game's lethals). CollectionGame makes one of
## these. A fighter carries at most one mine and one stun grenade, picked up from the floor.
## - Proximity mine (Q / D-pad left): laid on the floor 1.1 m in front of you, armed after 1 s (its light blinks fast
##   while arming, then once every 2 s), goes off when anyone else comes within 1.7 m (and 1.1 m up or down): 60 damage
##   at the middle, less further out, over 3.4 m, behind cover nothing. A blast nearby sets it off too.
## - Stun grenade (G / D-pad right): thrown along your aim, bursts 0.6 s after it lands (or 1.6 s after the throw):
##   everyone within 6.5 m who can see the burst is stunned for 1 s (a quarter speed, can't attack, aim knocked out,
##   a white flash on their screen); you get 0.5 s if you're caught in your own.
## Explosions are fire and grey smoke, no coloured particles (studio rules).

const GadgetModel := preload("res://gadgets/gadget_model.gd")
const Sfx := preload("res://audio/sfx.gd")

const MINE_DMG := 60.0
const MINE_R := 3.4
const MINE_TRIGGER := 1.7
const MINE_ARM := 1.0
const STUN_R := 6.5
const STUN_T := 1.0
const STUN_SPEED := 22.0
const STUN_GRAV := 18.0
const STUN_FUSE := 0.6
const STUN_MAX := 1.6

var game: Node = null
var mines: Array = []      # {f, pos, arm, t, mesh, led}
var stuns: Array = []      # {f, pos, vel, t, landed, fuse, mesh}

func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state

func _floor_under(p: Vector3) -> Variant:
	var hit := _space().intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.4, p + Vector3.DOWN * 4.0, 1))
	return hit.position if hit else null

## lay f's mine: in front of them if there's floor there and nothing in the way, else at their feet
func lay_mine(f: Node) -> bool:
	if not f.has_mine or not f.alive or f.downed:
		return false
	var fw: Vector3 = f.forward()
	var at: Vector3 = f.global_position + Vector3(fw.x, 0, fw.z).normalized() * 1.1
	var fl: Variant = _floor_under(at)
	var blocked := not _space().intersect_ray(PhysicsRayQueryParameters3D.create(f.global_position + Vector3.UP * 0.3, at + Vector3.UP * 0.3, 1)).is_empty()
	if fl == null or blocked or absf((fl as Vector3).y - f.global_position.y) > 0.6:
		fl = _floor_under(f.global_position)
	if fl == null:
		return false
	f.has_mine = false
	var mesh := GadgetModel.make("mine")
	add_child(mesh)
	mesh.global_position = fl
	mines.append({"f": f, "pos": fl, "arm": MINE_ARM, "t": 0.0, "mesh": mesh, "led": mesh.get_node("Led")})
	Sfx.play(self, "dry", fl, -6.0, 1.4, 8.0)
	return true

## throw f's stun grenade along their aim
func throw_stun(f: Node) -> bool:
	if not f.has_stun or not f.alive or f.downed:
		return false
	f.has_stun = false
	var dir: Vector3 = f.aim_forward()
	var from: Vector3 = f.eye_pos() + dir * 0.5
	var mesh := GadgetModel.make("stun")
	add_child(mesh)
	mesh.global_position = from
	stuns.append({"f": f, "pos": from, "vel": dir * STUN_SPEED + Vector3.UP * 3.0, "t": 0.0, "landed": false, "fuse": STUN_FUSE, "mesh": mesh})
	Sfx.play(self, "fistwhoosh", from, -4.0, 0.8, 12.0)
	return true

func _physics_process(dt: float) -> void:
	if game == null:
		return
	for m in mines.duplicate():
		m.t = float(m.t) + dt
		var led: Node3D = m.led
		if float(m.arm) > 0.0:
			m.arm = float(m.arm) - dt
			led.visible = sin(float(m.t) * 30.0) > 0.0
			continue
		led.visible = fmod(float(m.t), 2.0) < 0.12
		if not game.fighting():
			continue
		for o in game.fighters:
			if o == m.f or not o.alive:
				continue
			var d: Vector3 = o.global_position - (m.pos as Vector3)
			if Vector2(d.x, d.z).length() < MINE_TRIGGER and absf(d.y) < 1.1:
				_boom_mine(m)
				break
	for s in stuns.duplicate():
		s.t = float(s.t) + dt
		if not s.landed:
			var vel: Vector3 = s.vel
			vel.y -= STUN_GRAV * dt
			var p: Vector3 = s.pos
			var nxt := p + vel * dt
			var hit := _space().intersect_ray(PhysicsRayQueryParameters3D.create(p, nxt, 1))
			if hit:
				var n: Vector3 = hit.normal
				nxt = hit.position + n * 0.05
				vel = vel.bounce(n) * 0.35
				if n.y > 0.6 and vel.length() < 3.0:
					s.landed = true
					vel = Vector3.ZERO
				Sfx.play(self, "dry", nxt, -10.0, 1.8, 8.0)
			s.vel = vel
			s.pos = nxt
			(s.mesh as Node3D).global_position = nxt
			(s.mesh as Node3D).rotation += Vector3(7.0, 5.0, 0) * dt
		else:
			s.fuse = float(s.fuse) - dt
		if (s.landed and float(s.fuse) <= 0.0) or float(s.t) >= STUN_MAX:
			_burst_stun(s)

func _boom_mine(m: Dictionary) -> void:
	mines.erase(m)
	(m.mesh as Node).queue_free()
	explode(m.f, (m.pos as Vector3) + Vector3.UP * 0.35, MINE_DMG, MINE_R)

## a blast: damage to everyone in reach that it can see (full at the middle, 40% at the edge), fire, smoke, a flash;
## other mines in it go off too
func explode(src: Node, at: Vector3, dmg: float, radius: float) -> void:
	Sfx.play(self, "explode", at, 2.0, 1.0, 70.0)
	_fireball(at, radius)
	if game:
		game.noise.emit(at, 40.0, src)
		for o in game.fighters:
			if not o.alive:
				continue
			var c: Vector3 = o.global_position + Vector3.UP * 0.9
			var d := c.distance_to(at)
			if d > radius or not _space().intersect_ray(PhysicsRayQueryParameters3D.create(at, c, 1)).is_empty():
				continue
			o.take_damage(dmg * lerpf(1.0, 0.4, d / radius), src if is_instance_valid(src) else null)
		if game.level:   # loose things in reach are thrown about
			for l in game.level.loose:
				var rb: RigidBody3D = l.body
				var off: Vector3 = rb.global_position - at
				var dl := off.length()
				if dl < radius * 1.5:
					var push := (off.normalized() + Vector3.UP * 0.6).normalized() * rb.mass * 7.0 * (1.0 - dl / (radius * 1.5))
					game.knock(rb, push, rb.global_position + Vector3.UP * float(l.h) * 0.3)
	for m in mines.duplicate():
		if (m.pos as Vector3).distance_to(at) < radius and mines.has(m):
			_boom_mine(m)

func _burst_stun(s: Dictionary) -> void:
	stuns.erase(s)
	(s.mesh as Node).queue_free()
	var at: Vector3 = (s.pos as Vector3) + Vector3.UP * 0.3
	Sfx.play(self, "stun", at, 0.0, 1.0, 45.0)
	_flash(at, Color(1, 1, 1), 18.0, 0.35, 1.4)
	if game == null:
		return
	game.noise.emit(at, 30.0, s.f)
	for o in game.fighters:
		if not o.alive:
			continue
		var c: Vector3 = o.global_position + Vector3.UP * 1.4
		var d := c.distance_to(at)
		if d > STUN_R or not _space().intersect_ray(PhysicsRayQueryParameters3D.create(at, c, 1)).is_empty():
			continue
		o.stun(0.5 if o == s.f else STUN_T, 1.0 - d / STUN_R)

# ---------------------------------------------------------------- the look of a blast

func _flash(at: Vector3, col: Color, energy: float, secs: float, size: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = energy
	l.omni_range = 9.0
	l.shadow_enabled = false
	add_child(l)
	l.global_position = at
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	ball.mesh = sm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ball)
	ball.global_position = at
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "light_energy", 0.0, secs)
	tw.tween_property(ball, "scale", Vector3.ONE * size * 2.0, secs).from(Vector3.ONE * size * 0.4)
	tw.tween_property(m, "albedo_color:a", 0.0, secs)
	tw.chain().tween_callback(func() -> void:
		l.queue_free()
		ball.queue_free())

func _fireball(at: Vector3, radius: float) -> void:
	_flash(at, Color(1.0, 0.5, 0.12), 8.0, 0.5, radius * 0.75)    # the fire
	_flash(at + Vector3.UP * 0.2, Color(1.0, 0.92, 0.7), 3.0, 0.22, radius * 0.4)   # its white-hot middle
	# grey smoke rolling up and out
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, 0.8, 0)
	pm.damping_min = 1.5
	pm.damping_max = 2.5
	pm.scale_min = 1.0
	pm.scale_max = 2.4
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	curve.curve = c
	pm.scale_curve = curve
	var grad := GradientTexture1D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.09, 0.085, 0.08, 0.92))
	g.set_color(1, Color(0.38, 0.37, 0.36, 0.0))
	grad.gradient = g
	pm.color_ramp = grad
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	sm.radial_segments = 8
	sm.rings = 4
	var mm := StandardMaterial3D.new()
	mm.vertex_color_use_as_albedo = true
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.roughness = 1.0
	sm.material = mm
	p.draw_pass_1 = sm
	p.amount = 28
	p.lifetime = 2.2
	p.one_shot = true
	p.explosiveness = 0.9
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(2.6).timeout.connect(p.queue_free)

## start of a match: nothing left lying about
func clear_all() -> void:
	for m in mines:
		(m.mesh as Node).queue_free()
	for s in stuns:
		(s.mesh as Node).queue_free()
	mines.clear()
	stuns.clear()
