extends Node3D
## The match: every fighter, the stars, the weapon pickups, the shop cash-in, respawning, glass and the kill feed.
## main.gd creates it (as "Game") and hands it to every fighter. It isn't an autoload: the open editor rewrites
## project.godot, so keeping the match out of it means nothing an agent adds there can be lost.
##
## Rules (DESIGN §2–6): 14 stars hidden inside the house (both floors, never the roof), each at least 7 m from other
## stars, pickups and players; a taken star is replaced at once at least 12 m away, and if fewer than 14 are out one
## more appears every 4 s. Hold 10 and you can't pick up more: get to the shop on the front lawn and stand at it.
## Going down costs 2 stars, dying costs the rest; lost stars lie where you fell for 20 s (approved improvement).
## 8+ stars and you're marked: outlined through walls and pinned on every minimap. Cashing in takes 2 s standing
## still at the shop (approved improvement; getting hurt or moving away starts it again). First to cash in wins.
## Weapons (phase 2): 6 gun + 2 bat pickups, 80% indoors, 6 m apart, back somewhere new 15 s after being taken.
## Respawn 3 s after dying at the spawn point furthest from everyone, leaving out the 3 roof spawns (test dummies go
## back to their own spot).

signal feed_msg(text: String, mine: bool)
signal center_msg(title: String, sub: String, secs: float)
signal leader_marked(f: Node)         # someone just reached 8 stars: cue + screen-edge flash
signal state_changed(state: String)
signal won(f: Node)
signal noise(pos: Vector3, radius: float, src: Node)   # gunshots and punches; bots within earshot may go and look

const Weapons := preload("res://weapons/weapons.gd")
const Effects := preload("res://weapons/effects.gd")
const Sfx := preload("res://audio/sfx.gd")
const Pickup := preload("res://pickups/pickup.gd")
const Star := preload("res://stars/star.gd")

const STARS := 10             # to win
const LOSE := 2               # lost when you go down
const MARK := 8               # marked from here
const ON_MAP := 14
const STAR_GAP := 7.0
const STAR_FAR := 12.0        # a replacement appears at least this far from the star just taken
const STAR_BACK := 4.0        # backup: one more every 4 s while fewer than 14 are out
const STAR_R := 1.2           # pick-up reach, across
const STAR_H := 1.6           # and up/down
const DROP_LIFE := 20.0       # lost stars and dropped bats lie there this long
const CASH_TIME := 2.0
const CASH_R := 2.2
const COUNTDOWN := 3.0
const GUN_PICKS := 6
const BAT_PICKS := 2
const PICK_GAP := 6.0
const INDOOR_SHARE := 0.8

var level: Node3D
var fighters: Array = []
var pickups: Array = []
var stars: Array = []                # map stars (always 14 nodes, some may be waiting to come back)
var drops: Array = []                # stars dropped by players
var cand_in: Array[Vector3] = []     # walkable floor spots inside the house (both floors, never the roof)
var cand_out: Array[Vector3] = []    # walkable spots on the front and back lawns
var ready_done := false
var state := "loading"               # loading → countdown → fight → won
var clock := 0.0                     # counts up from the start of the fight
var countdown := COUNTDOWN
var winner: Node = null
var cash_point := Vector3.ZERO       # where you stand to cash in: just in front of the shop
var cash_t := {}                     # fighter → seconds stood at the shop
var nav_region: NavigationRegion3D
var ladder_links := 0
var debug := false                   # F3: show what every bot is doing, seeing and where it's going
var _star_back := 0.0
var _pad_mat: StandardMaterial3D
var _t := 0.0

func add_fighter(f: Node) -> void:
	fighters.append(f)
	f.went_down.connect(_on_down.bind(f))
	f.died.connect(_on_died.bind(f))
	f.got_up.connect(_on_up.bind(f))
	f.hurt.connect(func(_a, _s, _h): cash_t[f] = 0.0)

func fighting() -> bool:
	return state == "fight"

## call once the level is built: waits for physics, finds floor spots, bakes navigation, lays out stars and pickups,
## then starts the countdown (or, with begin = false, waits on the start screen until begin_countdown())
func start(begin := true) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_find_spots()
	await _bake_nav()
	cash_point = level.shop_pos + Vector3(0, 0, 1.7)   # the shop faces the house (+z); you stand in front of it
	_make_pad()
	for i in ON_MAP:
		var s := Star.new()
		add_child(s)
		stars.append(s)
		var spot: Variant = pick_spot(cand_in, _avoid_for_star(s), STAR_GAP)
		if spot == null:
			s.hide_star()
		else:
			s.move_to(spot)
	for i in GUN_PICKS + BAT_PICKS:
		var p := Pickup.new()
		p.game = self
		p.kind = "gun" if i < GUN_PICKS else "bat"
		add_child(p)
		pickups.append(p)
		place_pickup(p)
	ready_done = true
	_add_room_echo()
	if begin:
		begin_countdown()
	else:
		_set_state("menu")

func begin_countdown() -> void:
	countdown = COUNTDOWN
	_set_state("countdown")
	center_msg.emit("COLLECTION · 8 PLAYERS · THE MANSION", "Start with fists · find 10 hidden stars · cash them in at the shop outside · first to cash in wins", COUNTDOWN)

func _set_state(s: String) -> void:
	state = s
	state_changed.emit(s)

# ---------------------------------------------------------------- every tick

func _physics_process(dt: float) -> void:
	_t += dt
	if _pad_mat:
		_pad_mat.albedo_color.a = 0.35 + sin(_t * 3.0) * 0.15
	match state:
		"countdown":
			var before := ceili(countdown)
			countdown -= dt
			if ceili(countdown) != before and countdown > 0.0:
				Sfx.play_ui(self, "tick", -8.0)
			if countdown <= 0.0:
				_set_state("fight")
				center_msg.emit("GO", "Find 10 stars", 1.0)
		"fight":
			clock += dt
			_tick_stars(dt)
			_tick_cash_in(dt)

func _tick_stars(dt: float) -> void:
	# taking stars
	for f in fighters:
		if not f.alive or f.downed or f.stars >= STARS:
			continue
		for s in stars + drops:
			if not s.active:
				continue
			var d: Vector3 = f.global_position - s.global_position
			if Vector2(d.x, d.z).length() < STAR_R and absf(d.y) < STAR_H:
				_take_star(f, s)
				break
	# dropped stars fade out after 20 s
	for s in drops.duplicate():
		s.life -= dt
		if s.life <= 0.0:
			drops.erase(s)
			s.queue_free()
	# backup: one more star every 4 s while fewer than 14 are out
	var out := 0
	for s in stars:
		if s.active:
			out += 1
	if out < ON_MAP:
		_star_back -= dt
		if _star_back <= 0.0:
			_star_back = STAR_BACK
			for s in stars:
				if not s.active:
					var spot: Variant = pick_spot(cand_in, _avoid_for_star(s), STAR_GAP)
					if spot != null:
						s.move_to(spot)
					break
	else:
		_star_back = STAR_BACK

func _take_star(f: Node, s: Node) -> void:
	var at: Vector3 = s.global_position
	if s.dropped:
		drops.erase(s)
		s.queue_free()
	else:
		s.hide_star()
		var spot: Variant = pick_spot(cand_in, _avoid_for_star(s), STAR_GAP, at, STAR_FAR)
		if spot != null:   # a new one straight away, well away from this one (or the 4 s backup brings it)
			s.move_to(spot)
	add_stars(f, 1)
	Sfx.play(self, "bing", at, 0.0, 1.25, 14.0)
	if f.is_player:
		feed_msg.emit("You found a star (%d/%d)" % [f.stars, STARS], true)
		if f.stars >= STARS:
			center_msg.emit("%d STARS" % STARS, "Get outside to the shop and cash them in", 2.6)

## change someone's stars, with the feed lines and the marking that come with it
func add_stars(f: Node, n: int) -> void:
	var before: int = f.stars
	f.stars = clampi(before + n, 0, STARS)
	_update_mark(f, before)
	if not f.is_player and f.stars > before:
		if f.stars >= STARS:
			feed_msg.emit("%s has %d stars and is heading for the shop" % [f.display_name, STARS], false)

func _update_mark(f: Node, before: int) -> void:
	var now: int = f.stars
	f.set_marked(now >= MARK)
	if now >= MARK and before < MARK:
		feed_msg.emit("%s %s %d stars: %s marked" % ["You" if f.is_player else f.display_name, "have" if f.is_player else "has", now, "you're" if f.is_player else "they're"], f.is_player)
		Sfx.play_ui(self, "gong", -6.0)
		leader_marked.emit(f)

## lose up to n stars; they drop where you fell as pickups for 20 s
func lose_stars(f: Node, n: int) -> void:
	var k: int = mini(n, f.stars)
	if k <= 0:
		return
	var before: int = f.stars
	f.stars -= k
	_update_mark(f, before)
	if f.is_player:
		feed_msg.emit("You lost %d star%s (%d/%d)" % [k, "" if k == 1 else "s", f.stars, STARS], true)
	else:
		feed_msg.emit("%s lost %d star%s" % [f.display_name, k, "" if k == 1 else "s"], false)
	var space := get_world_3d().direct_space_state
	for i in k:
		var s := Star.new()
		s.dropped = true
		s.life = DROP_LIFE
		add_child(s)
		drops.append(s)
		# spread them in a small ring so each one shows, kept on the floor and out of walls
		var a := TAU * float(i) / maxf(1.0, float(k)) + randf() * 0.4
		var want: Vector3 = f.global_position + Vector3(cos(a), 0, sin(a)) * (0.0 if k == 1 else 1.1)
		var from: Vector3 = f.global_position + Vector3.UP * 0.6
		var side := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, want + Vector3.UP * 0.6, 1))
		if side:
			want = f.global_position
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(want + Vector3.UP * 0.6, want + Vector3.DOWN * 3.0, 1))
		s.move_to(down.position if down else want)

# ---------------------------------------------------------------- the shop

func _make_pad() -> void:
	var pad := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.2
	cm.bottom_radius = 1.2
	cm.height = 0.02
	cm.radial_segments = 40
	pad.mesh = cm
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.albedo_color = Color(1, 1, 1, 0.35)
	_pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pad.material_override = _pad_mat
	pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pad)
	pad.global_position = cash_point + Vector3(0, 0.02, 0)

func at_shop(f: Node) -> bool:
	var d: Vector3 = f.global_position - cash_point
	return Vector2(d.x, d.z).length() < CASH_R and absf(d.y) < 2.0

func _tick_cash_in(dt: float) -> void:
	for f in fighters:
		var standing: bool = f.alive and not f.downed and f.stars >= STARS and at_shop(f) and Vector2(f.velocity.x, f.velocity.z).length() < 2.0
		if standing:
			cash_t[f] = float(cash_t.get(f, 0.0)) + dt
			if cash_t[f] >= CASH_TIME:
				_win(f)
				return
		else:
			cash_t[f] = 0.0

func cash_progress(f: Node) -> float:
	return clampf(float(cash_t.get(f, 0.0)) / CASH_TIME, 0.0, 1.0)

func _win(f: Node) -> void:
	winner = f
	_set_state("won")
	Sfx.play_ui(self, "cash", -2.0)
	Sfx.play_ui(self, "win" if f.is_player else "lose", -4.0)
	feed_msg.emit("%s cashed in %d stars" % ["You" if f.is_player else f.display_name, STARS], f.is_player)
	won.emit(f)

# ---------------------------------------------------------------- room echo

## the house is 15 rooms a floor on a 5 × 3 grid: each gets an audio area sending its sounds to an echo bus. The
## grand hall (centre, double height) rings, ground-floor rooms have some echo, upstairs is soft (carpets), outside
## stays dry. Phase 6 gives each real room its own echo.
func _add_room_echo() -> void:
	Sfx.setup()
	var h: Dictionary = level.house
	if h.is_empty():
		return
	var hx: float = float(h.x)
	var hz: float = float(h.z)
	var cw := hx * 2.0 / 5.0
	var cd := hz * 2.0 / 3.0
	for fl in 2:
		for i in 5:
			for j in 3:
				var hall := i == 2 and j == 1
				if hall and fl == 1:
					continue   # the hall's one tall area covers both floors
				var a := Area3D.new()
				a.collision_layer = Sfx.AREA_LAYER
				a.collision_mask = 0
				a.monitoring = false
				a.reverb_bus_enabled = true
				a.reverb_bus_name = "Hall" if hall else ("Room" if fl == 0 else "Soft")
				a.reverb_bus_amount = 0.6 if hall else 0.4
				a.reverb_bus_uniformity = 0.4
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				var tall := 11.0 if hall else 5.6
				bx.size = Vector3(cw, tall, cd)
				cs.shape = bx
				a.add_child(cs)
				add_child(a)
				a.global_position = Vector3(-hx + cw * (i + 0.5), (0.0 if fl == 0 else 5.8) + tall * 0.5, -hz + cd * (j + 0.5))

# ---------------------------------------------------------------- navigation

## bake a navigation mesh from the Mansion's own collision boxes (both floors, the stairs, the lawns and the roof),
## with a link up every ladder (bots climb up; coming down they drop off the edge, as there's no fall damage)
func _bake_nav() -> void:
	var bd: Dictionary = level.layout.get("bounds", {"x0": -60, "x1": 60, "z0": -45, "z1": 45})
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.6
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 50.0
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.filter_baking_aabb = AABB(Vector3(float(bd.x0), -1.0, float(bd.z0)), Vector3(float(bd.x1) - float(bd.x0), 14.0, float(bd.z1) - float(bd.z0)))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, level)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	nav_region = NavigationRegion3D.new()
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	# Godot loads the baked mesh into the map in the background: wait until it answers (a few frames)
	var probe := Vector3(0, 0, -40)
	for i in 240:
		await get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(map) > 0 and NavigationServer3D.map_get_closest_point(map, probe) != Vector3.ZERO:
			break
	# ladder links: the foot on the floor in front of the ladder, the top on the floor past its top edge
	# (stepping further out until there's walkable floor to land on)
	for l in level.layout.get("ladders", []):
		var a: Array = l.b
		var n := Vector3(float(l.get("nx", 0)), 0, float(l.get("nz", 0)))
		var c := Vector3((float(a[0]) + float(a[3])) * 0.5, 0, (float(a[2]) + float(a[5])) * 0.5)
		var foot := _nav_floor(map, c - n * 0.9 + Vector3(0, float(a[1]), 0), -n)
		var top := _nav_floor(map, c + n * 0.9 + Vector3(0, float(a[4]), 0), n)
		if foot == Vector3.INF or top == Vector3.INF:
			continue
		var link := NavigationLink3D.new()
		link.bidirectional = true
		add_child(link)
		link.start_position = foot
		link.end_position = top
		ladder_links += 1
	await get_tree().physics_frame
	await get_tree().physics_frame

## the nearest walkable point at about this height, stepping out along `out` up to 3 m to find one
func _nav_floor(map: RID, p: Vector3, out: Vector3) -> Vector3:
	for k in 7:
		var q := p + out * (k * 0.5)
		var c := NavigationServer3D.map_get_closest_point(map, q)
		if c.distance_to(q) < 0.6:
			return c
	return Vector3.INF

func make_noise(pos: Vector3, radius: float, src: Node) -> void:
	noise.emit(pos, radius, src)

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
						if space.intersect_shape(sq, 1).is_empty() and not cand_in.has(p):
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

## a random spot at least `gap` m from everything in `avoid` (vertical separation over 3 m also counts as clear),
## and, if given, at least `far_d` m from `far_from`
func pick_spot(list: Array[Vector3], avoid: Array[Vector3], gap: float, far_from := Vector3.INF, far_d := 0.0) -> Variant:
	if list.is_empty():
		return null
	for t in 120:
		var p: Vector3 = list[randi() % list.size()]
		if far_d > 0.0 and p.distance_to(far_from) < far_d:
			continue
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
	for s in stars:
		if s != skip and s.active:
			out.append(s.global_position)
	for f in fighters:
		if f.alive:
			out.append(f.global_position)
	return out

func _avoid_for_star(s: Node) -> Array[Vector3]:
	return _avoid_list(s)

# ---------------------------------------------------------------- weapon pickups

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
	cash_t[f] = 0.0
	_feed(f, "are down" if f.is_player else "is down")
	lose_stars(f, LOSE)

func _on_up(f: Node) -> void:
	_feed(f, "got back up")

func _on_died(src: Node, f: Node) -> void:
	if src and src != f:
		var victim: String = "you" if f.is_player else f.display_name
		feed_msg.emit("%s eliminated %s" % [src.display_name, victim], src.is_player or f.is_player)
	else:
		_feed(f, "bled out")
	lose_stars(f, f.stars)

func _feed(f: Node, what: String) -> void:
	feed_msg.emit("%s %s" % [f.display_name, what], f.is_player)

# ---------------------------------------------------------------- respawn

func respawn(f: Node) -> void:
	if state == "won":
		return
	if f.home != null:
		var h: Array = f.home
		f.respawn_at(h[0], h[1])
		return
	var best: Variant = null
	var best_d := -1.0
	for s in level.spawns:
		if float(s.y) > 10.0:
			continue   # not the 3 roof spawns: they always measure furthest, and the game happens indoors
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
func hit_world(col: Object, pos: Vector3, normal: Vector3, _dir: Vector3) -> void:
	if col is StaticBody3D and col.has_meta("glass"):
		var body := col as StaticBody3D
		var cs := body.get_child(0) as CollisionShape3D
		var size: Vector3 = (cs.shape as BoxShape3D).size if cs and cs.shape is BoxShape3D else Vector3.ONE
		var upright := minf(size.x, size.z) < size.y or size.y > 0.5
		var skylight := body.global_position.y > 10.0
		if upright or skylight:
			_shatter(body.global_position, size)
			Sfx.play(self, "smash", pos, 0.0, 1.0, 30.0, 0.05)
			body.queue_free()
			return
	Effects.impact(self, pos, normal)
	if randf() < 0.35:
		Sfx.play(self, "impact", pos, -10.0, 1.0, 9.0, 0.1)

# ---------------------------------------------------------------- glass

const SHARD_POOL := 360
var _shards: Array[RigidBody3D] = []
var _shard_i := 0
var _shard_mesh: BoxMesh
var _shard_shape: BoxShape3D

## a pane breaks into tiny clear shards that fall, bounce and settle on the floor (studio rule); the oldest shards
## are reused once 360 are lying about
func _shatter(center: Vector3, size: Vector3) -> void:
	if _shard_mesh == null:
		_shard_mesh = BoxMesh.new()
		_shard_mesh.size = Vector3(0.06, 0.006, 0.045)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.86, 0.95, 1.0, 0.5)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.05
		m.metallic = 0.3
		_shard_mesh.material = m
		_shard_shape = BoxShape3D.new()
		_shard_shape.size = Vector3(0.06, 0.02, 0.045)
	var n := clampi(int(maxf(size.x, size.z) * size.y * 6.0), 14, 40)
	for k in n:
		var sh: RigidBody3D
		if _shards.size() < SHARD_POOL:
			sh = RigidBody3D.new()
			sh.collision_layer = 0
			sh.collision_mask = 1
			sh.mass = 0.02
			var cs := CollisionShape3D.new()
			cs.shape = _shard_shape
			sh.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.mesh = _shard_mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			sh.add_child(mi)
			add_child(sh)
			_shards.append(sh)
		else:
			sh = _shards[_shard_i % SHARD_POOL]
			_shard_i += 1
		sh.sleeping = false
		sh.global_position = center + Vector3(randf_range(-0.5, 0.5) * size.x, randf_range(-0.5, 0.5) * size.y, randf_range(-0.5, 0.5) * size.z)
		sh.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		sh.linear_velocity = Vector3(randf_range(-1.5, 1.5), randf_range(0.0, 2.0), randf_range(-1.5, 1.5))
		sh.angular_velocity = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))

# ---------------------------------------------------------------- leaderboard

## everyone, most stars first, then most kills
func standings() -> Array:
	var l := fighters.duplicate()
	l.sort_custom(func(a, b): return a.stars > b.stars or (a.stars == b.stars and a.kills > b.kills))
	return l
