extends RefCounted
## Hit and gun effects, kept small and quick (studio rules: no confetti, no coloured squares, no big sparks).
## Hits: a red spray of droplets with a soft red mist puff. Guns: a brief muzzle flash and a thin warm-white streak.
## Impacts: a few grey dust specks. Glass: tiny clear shards. Downed players: a faint dark-red wisp.

static var _cache := {}

static func _drop_mesh(r: float, col: Color, unshaded := false) -> Mesh:
	var key := "d%.3f%s%s" % [r, col.to_html(), unshaded]
	if _cache.has(key):
		return _cache[key]
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.3
	m.vertex_color_use_as_albedo = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = m
	_cache[key] = sm
	return sm

static func _puff_mesh(col: Color) -> Mesh:
	var key := "p" + col.to_html()
	if _cache.has(key):
		return _cache[key]
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	m.albedo_color = col
	q.material = m
	_cache[key] = q
	return q

static func _soft_dot() -> Texture2D:
	if _cache.has("dot"):
		return _cache["dot"]
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	var t := ImageTexture.create_from_image(img)
	_cache["dot"] = t
	return t

static func _fade_ramp() -> Gradient:
	if _cache.has("ramp"):
		return _cache["ramp"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	_cache["ramp"] = g
	return g

static func _burst(world: Node, pos: Vector3, mesh: Mesh, amount: int, life: float, speed: Vector2, grav: float,
		dir := Vector3.UP, spread_deg := 70.0, scale := Vector2(1, 1), ramp: Gradient = null) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.mesh = mesh
	p.direction = dir
	p.spread = spread_deg
	p.initial_velocity_min = speed.x
	p.initial_velocity_max = speed.y
	p.gravity = Vector3(0, -grav, 0)
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = scale.x
	p.scale_amount_max = scale.y
	if ramp:
		p.color_ramp = ramp
	p.local_coords = false
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## red spray with a mist puff; `big` for going down
static func hit_spray(world: Node, pos: Vector3, dir: Vector3, big := false) -> void:
	var back := -dir if dir.length() > 0.01 else Vector3.UP
	back = (back + Vector3.UP * 0.6).normalized()
	_burst(world, pos, _drop_mesh(0.022, Color(0.62, 0.04, 0.06)), 16 if big else 7, 0.4, Vector2(1.5, 3.6), 14.0, back, 55.0, Vector2(0.6, 1.3))
	_burst(world, pos, _puff_mesh(Color(0.77, 0.09, 0.12)), 3 if big else 2, 0.35, Vector2(0.2, 0.6), -0.5, back, 40.0, Vector2(0.35, 0.8) * (1.6 if big else 1.0), _fade_ramp())

## a bullet hitting a wall or floor: a few grey dust specks
static func impact(world: Node, pos: Vector3, normal: Vector3) -> void:
	_burst(world, pos + normal * 0.04, _drop_mesh(0.018, Color(0.7, 0.69, 0.66)), 3, 0.3, Vector2(1.2, 2.6), 9.0, normal, 35.0)

## tiny clear shards falling from a broken pane
static func glass_shards(world: Node, pos: Vector3, size: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 60
	p.lifetime = 1.4
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, 0.004, 0.035)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.95, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.3
	bm.material = m
	p.mesh = bm
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = size * 0.5
	p.direction = Vector3.UP
	p.spread = 90.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, -20, 0)
	p.angular_velocity_min = -400
	p.angular_velocity_max = 400
	p.local_coords = false
	world.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)

## a faint wisp of dark red rising off a downed player (never green)
static func downed_wisp(world: Node, pos: Vector3) -> void:
	_burst(world, pos, _puff_mesh(Color(0.45, 0.06, 0.09)), 1, 0.8, Vector2(0.2, 0.4), -0.5, Vector3.UP, 15.0, Vector2(0.25, 0.4), _fade_ramp())

## a short thin warm-white streak leaving the muzzle (not a beam to the target), gone in 0.05 s
static func tracer(world: Node, a: Vector3, b: Vector3, col := Color(1.0, 0.97, 0.9, 0.7), width := 0.013) -> void:
	var L := a.distance_to(b)
	if L < 1.5:
		return
	var d := (b - a) / L
	var start := a + d * minf(1.2, L * 0.15)
	var len := minf(L - minf(1.2, L * 0.15), 7.0)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, width, len)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = col
	bm.material = m
	mi.mesh = bm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	mi.look_at_from_position(start + d * len * 0.5, b, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
	var tw := mi.create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.05)
	tw.tween_callback(mi.queue_free)

## a brief warm flash at the muzzle: a small light and a bright core, 0.05 s
static func muzzle_flash(world: Node, pos: Vector3) -> void:
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.82, 0.55)
	l.light_energy = 2.2
	l.omni_range = 3.5
	l.shadow_enabled = false
	world.add_child(l)
	l.global_position = pos
	var core := MeshInstance3D.new()
	core.mesh = _drop_mesh(0.035, Color(1.0, 0.9, 0.7), true)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(core)
	core.global_position = pos
	var tw := l.create_tween()
	tw.tween_interval(0.05)
	tw.tween_callback(l.queue_free)
	tw.tween_callback(core.queue_free)
