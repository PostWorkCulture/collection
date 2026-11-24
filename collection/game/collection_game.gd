extends Node3D
## The match: every fighter, the weapon pickups, respawning, glass breaking and the kill feed.
## Phase 2 (combat): 6 gun + 2 bat pickups placed 80% inside the house and 20% on the lawns, at least 6 m from other
## pickups and players, back somewhere new 15 s after being taken; bats dropped by downed players lie where they fell
## for 20 s; the dead respawn after 3 s at the spawn point furthest from everyone else (test dummies go back home).
## Phase 3 adds stars, the shop cash-in and the win to this node.
## main.gd creates it (as "Game") and hands it to every fighter, so it isn't an autoload: the open editor rewrites
## project.godot, and keeping the match out of it means nothing an agent adds there can be lost.

signal feed_msg(text: String, mine: bool)

const Weapons := preload("res://weapons/weapons.gd")
const Effects := preload("res://weapons/effects.gd")
const Sfx := preload("res://audio/sfx.gd")
const Pickup := preload("res://pickups/pickup.gd")

const GUN_PICKS := 6
const BAT_PICKS := 2
const PICK_BACK := 15.0
const DROP_LIFE := 20.0
const PICK_GAP := 6.0
const INDOOR_SHARE := 0.8

var level: Node3D
var fighters: Array = []
var pickups: Array = []
var cand_in: Array[Vector3] = []     # walkable floor spots inside the house (both floors, never the roof)
var cand_out: Array[Vector3] = []    # walkable spots on the front and back lawns
var ready_done := false

func add_fighter(f: Node) -> void:
	fighters.append(f)
	f.went_down.connect(_on_down.bind(f))
	f.died.connect(_on_died.bind(f))
	f.got_up.connect(_on_up.bind(f))

## call once the level is built: waits for physics, finds floor spots, lays out the pickups
func start() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_find_spots()
	for i in GUN_PICKS + BAT_PICKS:
		var p := Pickup.new()
		p.game = self
		p.kind = "gun" if i < GUN_PICKS else "bat"
		add_child(p)
		pickups.append(p)
		place_pickup(p)
	ready_done = true

# ---------------------------------------------------------------- floor spots

## a grid of downward rays over the grounds: every floor a standing body fits on becomes a spot
func _find_spots() -> void:
	var space := get_world_3d().direct_space_state
	var h: Dictionary = level.house
	var hx: float = h.get("x", 40.0)
	var hz: float = h.get("z", 27.0)
	var bd: Dictionary = level.layout.get("bounds", {"x0": -60, "x1": 60, "z0": -45, "z1": 45})
	var body := CapsuleShape3D.new()
	body.radius = 0.4
	body.height = 1.8
	var sq := PhysicsShapeQueryParameters3D.new()
	sq.shape = body
	sq.collision_mask = 1
	var x: float = float(bd.x0) + 1.5
	while x < float(bd.x1) - 1.0:
		var z: float = float(bd.z0) + 1.5
		while z < float(bd.z1) - 1.0:
			var inside := absf(x) < hx - 0.5 and absf(z) < hz - 0.5
			var lawn := absf(z) > hz + 1.0   # only the front and back lawns are open; the sides are walled off
			if inside:
				# from just under the roof slab (y 11) down to the first floor, then from under that slab to the ground
				for top in [10.9, 5.4]:
					var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, -1.0, z), 1))
					if hit and hit.normal.y > 0.8 and hit.position.y < 7.0:
						var p: Vector3 = hit.position
						sq.transform = Transform3D(Basis(), p + Vector3.UP * 1.05)
						if space.intersect_shape(sq, 1).is_empty():
							cand_in.append(p)
			elif lawn:
				var hit2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 4.0, z), Vector3(x, -1.0, z), 1))
				if hit2 and hit2.normal.y > 0.8 and hit2.position.y < 0.6:
					var p2: Vector3 = hit2.position
					sq.transform = Transform3D(Basis(), p2 + Vector3.UP * 1.05)
					if space.intersect_shape(sq, 1).is_empty():
						cand_out.append(p2)
			z += 2.0
		x += 2.0

## a random spot at least `gap` m from everything in `avoid` (vertical separation over 3 m also counts as clear)
func pick_spot(list: Array[Vector3], avoid: Array[Vector3], gap: float) -> Variant:
	if list.is_empty():
		return null
	for t in 60:
		var p: Vector3 = list[randi() % list.size()]
		var ok := true
		for a in avoid:
			if absf(a.y - p.y) < 3.0 and Vector2(a.x - p.x, a.z - p.z).length() < gap:
				ok = false
				break
		if ok:
			return p
	return null

func _avoid_list(skip: Node = null) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for p in pickups:
		if p != skip and p.active:
			out.append(p.global_position)
	for f in fighters:
		if f.alive:
			out.append(f.global_position)
	return out

# ---------------------------------------------------------------- pickups

func place_pickup(p: Node) -> void:
	var use_out := randf() > INDOOR_SHARE and not cand_out.is_empty()
	var spot: Variant = pick_spot(cand_out if use_out else cand_in, _avoid_list(p), PICK_GAP)
	if spot == null:
		p.wait(3.0)   # nowhere free right now: try again shortly
		return
	var id := ""
	if p.kind == "gun":
		id = Weapons.CO_GUNS[randi() % Weapons.CO_GUNS.size()]
	p.show_at(spot, id)

## a downed player's bat, lying where they fell for 20 s
func drop_bat(pos: Vector3) -> void:
	var p := Pickup.new()
	p.game = self
	p.kind = "bat"
	p.temporary = true
	add_child(p)
	pickups.append(p)
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.5, pos + Vector3.DOWN * 3.0, 1))
	p.show_at(hit.position if hit else pos, "")
	p.life = DROP_LIFE

func forget_pickup(p: Node) -> void:
	pickups.erase(p)

func feed_pickup(f: Node, p: Node) -> void:
	var what := "a bat" if p.kind == "bat" else "a %s (%d bullets)" % [Weapons.stat(p.id).name, Weapons.AMMO]
	_feed(f, "picked up " + what)

func feed_out_of_ammo(f: Node) -> void:
	if f.is_player:
		feed_msg.emit("Out of bullets: back to fists", true)

# ---------------------------------------------------------------- health events

func _on_down(_src: Node, f: Node) -> void:
	_feed(f, "is down" if not f.is_player else "are down")

func _on_up(f: Node) -> void:
	_feed(f, "got back up" if not f.is_player else "got back up")

func _on_died(src: Node, f: Node) -> void:
	if src and src != f:
		var victim: String = "you" if f.is_player else f.display_name
		feed_msg.emit("%s eliminated %s" % [src.display_name, victim], src.is_player or f.is_player)
	else:
		_feed(f, "bled out")

func _feed(f: Node, what: String) -> void:
	feed_msg.emit("%s %s" % [f.display_name, what], f.is_player)

# ---------------------------------------------------------------- respawn

func respawn(f: Node) -> void:
	if f.home != null:
		var h: Array = f.home
		f.respawn_at(h[0], h[1])
		return
	var best: Variant = null
	var best_d := -1.0
	for s in level.spawns:
		var p := Vector3(float(s.x), float(s.y) + 0.05, float(s.z))
		var d := 1e9
		for o in fighters:
			if o != f and o.alive:
				d = minf(d, o.global_position.distance_to(p))
		if d > best_d:
			best_d = d
			best = s
	if best == null:
		f.respawn_at(Vector3(-6, 0.05, -36), 0.0)
		return
	f.respawn_at(Vector3(float(best.x), float(best.y) + 0.05, float(best.z)), float(best.get("yaw", 0.0)))

# ---------------------------------------------------------------- the world getting hit

## a bullet or punch hitting the level: upright glass and roof skylights break in one hit; everything else gets dust
func hit_world(col: Object, pos: Vector3, normal: Vector3, dir: Vector3) -> void:
	if col is StaticBody3D and col.has_meta("glass"):
		var body := col as StaticBody3D
		var cs := body.get_child(0) as CollisionShape3D
		var size: Vector3 = (cs.shape as BoxShape3D).size if cs and cs.shape is BoxShape3D else Vector3.ONE
		var upright := minf(size.x, size.z) < size.y or size.y > 0.5
		var skylight := body.global_position.y > 10.0
		if upright or skylight:
			Effects.glass_shards(self, body.global_position, size)
			Sfx.play(self, "smash", pos, 0.0, 1.0, 30.0, 0.05)
			body.queue_free()
			return
	Effects.impact(self, pos, normal)
	if randf() < 0.35:
		Sfx.play(self, "impact", pos, -10.0, 1.0, 9.0, 0.1)
