extends Node3D
## Crossbow bolts in flight (Pete, 27 Nov: the crossbow from 1v1). CollectionGame makes one of these. A bolt flies
## at 200 m/s with a little drop (1.5 m/s²), leaves a thin green streak so you can follow it, and is silent (no noise
## for the bots to hear). It hits like the guns do: 83 damage, twice that to the head, no fall-off with range; glass
## breaks and props take the hit. Bolts that hit stick in walls, floors and people for a few seconds.

const Effects := preload("res://weapons/effects.gd")
const Weapons := preload("res://weapons/weapons.gd")

const LIFE := 2.0
const STICK := 6.0

var game: Node = null
var bolts: Array = []      # {f, pos, vel, t, mesh}
var _mat_shaft: StandardMaterial3D
var _mat_tip: StandardMaterial3D
var _mat_nock: StandardMaterial3D

func _ready() -> void:
	_mat_shaft = StandardMaterial3D.new()
	_mat_shaft.albedo_color = Color("#24272c")
	_mat_shaft.metallic = 0.4
	_mat_shaft.roughness = 0.45
	_mat_tip = StandardMaterial3D.new()
	_mat_tip.albedo_color = Color("#d5dae2")
	_mat_tip.metallic = 1.0
	_mat_tip.roughness = 0.2
	_mat_nock = StandardMaterial3D.new()
	_mat_nock.albedo_color = Color("#b8ffd0")
	_mat_nock.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

## 1v1's bolt: a thin carbon shaft, a steel broadhead and a lighted nock (it points along -Z)
func _bolt_mesh() -> Node3D:
	var b := Node3D.new()
	var shaft := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0045
	c.bottom_radius = 0.0045
	c.height = 0.42
	c.radial_segments = 6
	shaft.mesh = c
	shaft.rotation.x = PI * 0.5
	shaft.material_override = _mat_shaft
	b.add_child(shaft)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.011
	cone.height = 0.045
	cone.radial_segments = 4
	tip.mesh = cone
	tip.rotation.x = -PI * 0.5
	tip.position.z = -0.23
	tip.material_override = _mat_tip
	b.add_child(tip)
	var nock := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.007
	sp.height = 0.014
	nock.mesh = sp
	nock.position.z = 0.21
	nock.material_override = _mat_nock
	b.add_child(nock)
	return b

func fire(f: Node, from: Vector3, dir: Vector3) -> void:
	var g := Weapons.stat("crossbow")
	var mesh := _bolt_mesh()
	add_child(mesh)
	mesh.global_position = from
	mesh.look_at(from + dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT)
	bolts.append({"f": f, "pos": from, "vel": dir * float(g.speed), "t": 0.0, "mesh": mesh})

func _physics_process(dt: float) -> void:
	var g := Weapons.stat("crossbow")
	var space := get_world_3d().direct_space_state
	for b in bolts.duplicate():
		b.t = float(b.t) + dt
		var vel: Vector3 = b.vel
		vel.y -= float(g.grav) * dt
		var p: Vector3 = b.pos
		var nxt := p + vel * dt
		var f: Node = b.f
		var ex: Array[RID] = []
		if is_instance_valid(f):
			ex.append(f.get_rid())
		var q := PhysicsRayQueryParameters3D.create(p, nxt, f.SHOT_MASK if is_instance_valid(f) else 1, ex)
		var hit := space.intersect_ray(q)
		Effects.tracer(get_parent(), p, hit.position if hit else nxt, Color(0.49, 1.0, 0.6, 0.55), 0.006)
		var mesh: Node3D = b.mesh
		if hit:
			bolts.erase(b)
			_hit(b, hit, vel.normalized(), g)
			continue
		b.vel = vel
		b.pos = nxt
		mesh.global_position = nxt
		mesh.look_at(nxt + vel, Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT)
		if float(b.t) > LIFE:
			bolts.erase(b)
			mesh.queue_free()

func _hit(b: Dictionary, hit: Dictionary, dir: Vector3, g: Dictionary) -> void:
	var f: Node = b.f
	var mesh: Node3D = b.mesh
	var at: Vector3 = hit.position
	var col: Object = hit.collider
	var world := get_parent()
	if col and col.has_method("take_damage") and is_instance_valid(f) and col != f:
		var foe = col
		var head: bool = f.can_headshot and (not foe.downed) and at.y - float(foe.global_position.y) > f.HEIGHT - f.HEAD_TOP
		var dmg: float = float(g.dmg) * (float(g.head) if head else 1.0) * float(f.dmg_mul)
		Effects.hit_spray(world, at, dir)
		var fin: bool = foe.take_damage(dmg, f, head, "crossbow")
		f.dealt_hit.emit(foe, roundi(dmg), head, fin)
		if foe.alive:   # stuck in them, moving with them
			mesh.reparent(foe as Node3D, true)
			mesh.global_position = at - dir * 0.12
			get_tree().create_timer(STICK).timeout.connect(func() -> void:
				if is_instance_valid(mesh): mesh.queue_free())
		else:
			mesh.queue_free()
		return
	if game and is_instance_valid(f):
		game.hit_world(col, at, hit.normal, dir, float(g.dmg) * float(f.dmg_mul))
	if col is Node and ((col as Node).has_meta("glass") or (col as Node).has_meta("prop")):
		mesh.queue_free()   # (not in glass or a smashable prop: those break or take the hit)
		return
	mesh.global_position = at - dir * 0.12   # stuck in the wall or floor
	get_tree().create_timer(STICK).timeout.connect(func() -> void:
		if is_instance_valid(mesh): mesh.queue_free())

## start of a match: nothing in the air
func clear_all() -> void:
	for b in bolts:
		(b.mesh as Node).queue_free()
	bolts.clear()
