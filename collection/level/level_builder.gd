extends Node3D
## Builds the grey-box Mansion from level/mansion_layout.json, which is exported straight from the web game's Mansion
## (every solid box, ladder and spawn point, in the same metres and the same coordinates: x across, y up, z front to back,
## the front door facing -z). Grey-box look: light grey with a 1 m grid, a muted tint per room from the web colours,
## clear glass. Every box is solid, exactly as in the web game.
## Phase 6: level/mansion.glb is the web Mansion's own look (rooms, finishes, furniture, lamps), exported from the same build
## as the layout, so it lines up with these colliders box for box. When it loads, the grey-box drawing is skipped; the colliders,
## ladders and glass (drawn here so it can break) stay. Moving parts in it are named (lift_car, tramp_mat, disco_*, pool_water,
## portal_swirl) for level/mansion_features.gd to animate.

const MansionEdits := preload("res://level/mansion_edits.gd")

var layout: Dictionary = {}
var ladders: Array[AABB] = []
var ladder_normals: Array[Vector3] = []   # per ladder: out from the wall, towards whoever climbs it
var lifts: Array = []            # the 2 lifts and the fireman's pole: {box, nx, nz, rung}; ridden, not climbed
var dressed := false             # mansion.glb loaded
var dressing: Node3D = null
var parts := {}                  # name -> Array of the GLB's named moving parts
var props: Array = []            # smashable furniture, crates, hedges and lamps: {body, kind, hp, hp0, node (its look), back}
var loose: Array = []            # the small things that get knocked about: {body (RigidBody3D), home (Transform3D), h, prop (index or -1)}
var box_nodes := {}              # box index -> the dressing node that draws it
var bodies := {}                 # box index -> its collider
var windows: Array = []          # the 40 big windows: {body, ax (pane runs along x), at, a, b, s0 (sill), s1 (top)}
var spawns: Array = []
var house: Dictionary = {}
var shop_pos := Vector3.ZERO
var edits := {}                  # mansion_edits.gd's result: {scope (the telescope's pivot), ...}
var _removed: Node3D

var _grid_tex: ImageTexture
var _mats := {}
var skirting := 0     # skirting boards placed

func build() -> void:
	var f := FileAccess.open("res://level/mansion_layout.json", FileAccess.READ)
	layout = JSON.parse_string(f.get_as_text())
	house = layout.get("house", {})
	spawns = layout.get("spawns", [])
	var sh: Array = layout.get("shop", [])
	if sh.size() > 0:
		shop_pos = Vector3(sh[0].x, sh[0].y, sh[0].z)
	_grid_tex = _make_grid()
	_load_dressing()
	_build_ground()
	_removed = Node3D.new()   # what Pete had taken out (mansion_edits.gd): its look parked here, hidden
	_removed.name = "Removed"
	_removed.visible = false
	add_child(_removed)
	for i in layout.boxes.size():
		var b: Dictionary = layout.boxes[i]
		if MansionEdits.removed(b):
			if box_nodes.has(i):
				(box_nodes[i] as Node).reparent(_removed, true)
				box_nodes.erase(i)
			continue
		b = MansionEdits.move_scope_box(MansionEdits.move_box(b))
		_add_box(b, i)
	for l in layout.ladders:
		_add_ladder(l)
	for st in layout.get("stairs", []):
		_add_ramp(st)
	# the big windows (4.4 m wide on a 0.45 m sill since 24 Nov): {body, ax (runs along x), at, a, b, s0 (sill), s1 (top)}
	for w in layout.get("windows", []):
		var body: Variant = bodies.get(int(w.pane))
		windows.append({"body": body, "ax": bool(w.ax), "at": float(w.at), "a": float(w.a), "b": float(w.b), "s0": float(w.s0), "s1": float(w.s1)})
	_add_shop()
	edits = MansionEdits.apply(self)
	_make_loose()
	if dressed:
		_add_skirting()

## skirting boards (AAA phase 3): a satin-white board along the foot of every inside wall face on both floors,
## so walls meet floors the way they do in a real house. One MultiMesh, so it costs a single draw.
const SKIRT_H := 0.13
const SKIRT_D := 0.022
func _add_skirting() -> void:
	var xf: Array[Transform3D] = []
	for bx in layout.boxes:
		if String(bx.p) != "":
			continue
		var b: Array = bx.b
		var y0: float = b[1]
		var sx: float = float(b[3]) - float(b[0])
		var sz: float = float(b[5]) - float(b[2])
		if float(b[4]) - y0 < 2.0 or minf(sx, sz) > 0.7 or maxf(sx, sz) < 0.8:
			continue
		if absf(y0) > 0.05 and absf(y0 - 5.8) > 0.05:
			continue   # only walls that stand on a floor (not lintels over doorways)
		var along_x := sx > sz
		var length := sx if along_x else sz
		var mid := Vector3((float(b[0]) + float(b[3])) * 0.5, y0 + SKIRT_H * 0.5, (float(b[2]) + float(b[5])) * 0.5)
		for side in [-1.0, 1.0]:
			var face := (sz if along_x else sx) * 0.5 + SKIRT_D * 0.5
			var off := Vector3(0, 0, side * face) if along_x else Vector3(side * face, 0, 0)
			var beyond := mid + off * (1.0 + 0.3 / face)
			if absf(beyond.x) > float(house.x) - 0.1 or absf(beyond.z) > float(house.z) - 0.1:
				continue   # the outside of the house
			var bs := Basis.from_scale(Vector3(length, SKIRT_H, SKIRT_D) if along_x else Vector3(SKIRT_D, SKIRT_H, length))
			xf.append(Transform3D(bs, mid + off))
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BoxMesh.new()
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.88, 0.84)
	m.roughness = 0.38
	var mi := MultiMeshInstance3D.new()
	mi.name = "Skirting"
	mi.multimesh = mm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	skirting = xf.size()

## the Mansion's look: the imported scene when Godot has imported the .glb, otherwise read straight from the file
func _load_dressing() -> void:
	var path := "res://level/mansion.glb"
	var root: Node = null
	if ResourceLoader.exists(path):
		var ps: Resource = load(path)
		if ps is PackedScene:
			root = (ps as PackedScene).instantiate()
	if root == null and FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) == OK:
			root = doc.generate_scene(st)
	if root == null or not root is Node3D:
		return
	dressing = root as Node3D
	dressing.name = "Dressing"
	add_child(dressing)
	dressed = true
	_collect_parts(dressing)
	_fix_materials(dressing, {})
	_set_ranges(dressing)

## small things stop being drawn (fading out) once they're too far away to matter, and the smallest cast no shadows:
## a cup 25 m off, a chair 45 m off. Walls, floors and big furniture always draw.
var ranged := 0
var floor_things := [[], []]     # furniture-sized meshes on the ground floor and the first floor
var _floors_shown := [true, true]

## hide the furniture of a floor you can't see into (the house's own walls and floors always draw)
func show_floors(ground: bool, upper: bool) -> void:
	for i in 2:
		var on := ground if i == 0 else upper
		if _floors_shown[i] == on:
			continue
		_floors_shown[i] = on
		for mi in floor_things[i]:
			(mi as MeshInstance3D).visible = on

## which floors can be seen from here: outside, in the hall, on a staircase or by a hole between floors, both;
## otherwise just your own
static func floors_seen(p: Vector3) -> Array:
	if absf(p.x) > 40.0 or absf(p.z) > 27.0 or p.y > 11.5:
		return [true, true]
	if absf(p.x) < 9.5 and absf(p.z) < 10.5:
		return [true, true]   # the hall and the atrium round its void
	for hole in [Vector2(-32, 0), Vector2(32, 0), Vector2(-22.35, 25.5), Vector2(22.35, -7.5), Vector2(-38.2, -13.8), Vector2(38.2, 13.8)]:
		if Vector2(p.x, p.z).distance_to(hole) < 6.5:
			return [true, true]   # pole, launch hole, lifts, back stairs
	if p.y > 1.2 and p.y < 5.6:
		return [true, true]
	return [p.y < 5.6, p.y >= 5.6]

func _set_ranges(n: Node) -> void:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.mesh:
			var sz := mi.mesh.get_aabb().size * mi.global_transform.basis.get_scale()
			var big := maxf(sz.x, maxf(sz.y, sz.z))
			if big < 1.4:
				mi.visibility_range_end = 25.0 if big < 0.4 else 45.0
				mi.visibility_range_end_margin = 4.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				ranged += 1
			if big < 0.6:
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# furniture-sized things inside the house, away from the hall void, belong to one floor
			if big < 3.0:
				var cp := mi.global_transform * mi.mesh.get_aabb().get_center()
				if absf(cp.x) < 40.0 and absf(cp.z) < 27.0 and not (absf(cp.x) < 8.0 and absf(cp.z) < 9.0) and cp.y < 11.0:
					floor_things[1 if cp.y > 5.75 else 0].append(mi)
		_set_ranges(c)

## the web drew its light beams and glows additively (faint, never solid); glTF has no additive blend, so the faint unlit
## see-through materials go back to additive here
func _fix_materials(n: Node, seen: Dictionary) -> void:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as StandardMaterial3D
				if m and m.has_meta("extras") and str(m.get_meta("extras")).contains("\"grass\""):
					# the lawn doesn't bounce light: its bright green turned faces and walls lime in the shade
					mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				if m == null or seen.has(m):
					continue
				seen[m] = true
				if m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and m.albedo_color.a < 0.3:
					m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
					m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					m.cull_mode = BaseMaterial3D.CULL_BACK   # one layer, not both sides of the cone
					m.albedo_color.a *= 0.5                  # with glow and haze on top, half the web's strength reads the same
				m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_fix_materials(c, seen)

func _collect_parts(n: Node) -> void:
	for c in n.get_children():
		var nm := String(c.name)
		if nm.begins_with("box_"):
			var bits := nm.split("_")
			if bits.size() > 1 and bits[1].is_valid_int():
				box_nodes[int(bits[1])] = c
		for key in ["lift_car", "tramp_mat", "tramp_arrow", "disco_ball", "disco_floor", "disco_beam", "pool_water", "portal_swirl"]:
			if nm.begins_with(key):
				if not parts.has(key):
					parts[key] = []
				parts[key].append(c)
				break
		_collect_parts(c)

## a 1 m grid: pale grey squares with a thin darker line, so distances read at a glance
func _make_grid() -> ImageTexture:
	var n := 128
	var img := Image.create(n, n, true, Image.FORMAT_RGBA8)
	img.fill(Color(0.86, 0.86, 0.86))
	for i in n:
		for k in [0, 1]:
			img.set_pixel(i, k, Color(0.62, 0.62, 0.62))
			img.set_pixel(k, i, Color(0.62, 0.62, 0.62))
	for i in n:   # a fainter half-metre line
		img.set_pixel(i, n >> 1, Color(0.78, 0.78, 0.78))
		img.set_pixel(n >> 1, i, Color(0.78, 0.78, 0.78))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## the web colour, pulled most of the way to grey: rooms stay tellable apart without looking finished
func _mat(col: String, glass: bool) -> Material:
	var key := col + ("g" if glass else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	if glass:
		m.albedo_color = Color(0.86, 0.94, 1.0, 0.16)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.25
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	else:
		var c := Color.html(col) if Color.html_is_valid(col) else Color(0.8, 0.8, 0.8)
		var g := c.get_luminance()
		var tint := Color(g, g, g).lerp(c, 0.28)
		tint = tint.lerp(Color(0.82, 0.82, 0.82), 0.45)
		m.albedo_color = tint
		m.albedo_texture = _grid_tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE
		m.roughness = 0.85
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m

func _add_box(b: Dictionary, index: int = -1) -> void:
	var a: Array = b.b
	var p0 := Vector3(a[0], a[1], a[2])
	var p1 := Vector3(a[3], a[4], a[5])
	var size := (p1 - p0).abs()
	if size.x < 0.01 or size.y < 0.01 or size.z < 0.01:
		return
	var glass: bool = int(b.g) == 1 or b.p == "glass"
	var is_loose := _is_loose(b, size)
	var body: CollisionObject3D = RigidBody3D.new() if is_loose else StaticBody3D.new()
	body.position = (p0 + p1) * 0.5
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if index >= 0:
		body.set_meta("index", index)
		bodies[index] = body
	var kind := String(b.get("p", ""))
	var hp := float(b.get("hp", 0))
	if kind in ["crate", "bush", "lamp"] and hp > 0.0 and hp < 1e6:
		var pr := {"body": body, "kind": kind, "hp": hp, "hp0": hp, "node": box_nodes.get(index), "back": 0.0,
			"box": AABB(p0, size)}
		body.set_meta("prop", props.size())
		props.append(pr)
	if glass:
		body.set_meta("glass", true)
	if is_loose:
		var rb := body as RigidBody3D
		rb.mass = clampf(size.x * size.y * size.z * 30.0, 5.0, 40.0)
		rb.linear_damp = 0.4
		rb.angular_damp = 0.8
		rb.can_sleep = true
		rb.sleeping = true
		rb.continuous_cd = rb.mass < 12.0
		var pm := PhysicsMaterial.new()
		pm.friction = 0.7
		pm.bounce = 0.05
		rb.physics_material_override = pm
		body.set_meta("loose", loose.size())
		body.set_meta("h", size.y)
		loose.append({"body": rb, "home": Transform3D(Basis(), (p0 + p1) * 0.5), "h": size.y, "prop": int(body.get_meta("prop", -1)), "index": index})
	if dressed and not glass:   # the dressing draws it
		add_child(body)
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	if glass:   # glass is drawn thin (the collider keeps its size), as in the web game
		var thin := 0.03
		if size.x <= size.y and size.x <= size.z: mesh.size.x = thin
		elif size.z <= size.y: mesh.size.z = thin
		else: mesh.size.y = thin
	mi.mesh = mesh
	mi.material_override = _mat(String(b.c), glass)
	if glass:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)
	add_child(body)

## Loose things (Pete, 27 Nov: "if you run into balls or other items they should move, fall over"): stools, bins, barrels,
## floor lamps, small crates and side tables standing on a floor are rigid bodies. People push them as they run into
## them (fighter.gd), hits and blasts knock them, and they go home when they grow back and at each countdown.
const LOOSE_KINDS := ["crate", "lamp", "fuel"]
const LOOSE_MAX_W := 1.2       # across, metres
const LOOSE_MAX_H := 1.8
const LOOSE_MAX_VOL := 1.4     # cubic metres
const FLOORS := [0.0, 5.8, 11.35, -0.8]

func _is_loose(b: Dictionary, size: Vector3) -> bool:
	if not String(b.get("p", "")) in LOOSE_KINDS or int(b.g) == 1:
		return false
	if float(b.get("hp", 0)) >= 1e6 or maxf(size.x, size.z) > LOOSE_MAX_W or size.y > LOOSE_MAX_H or size.x * size.y * size.z > LOOSE_MAX_VOL:
		return false
	if minf(size.x, size.z) < 0.25:
		return false   # thin panels and shelves
	var y0: float = b.b[1]
	var on_floor := false
	for fy in FLOORS:
		if absf(y0 - float(fy)) < 0.06:
			on_floor = true
	if not on_floor:
		return false
	var c := MansionEdits.box_centre(b)
	if Vector2(c.x - MansionEdits.SCOPE_TO.x, c.z - MansionEdits.SCOPE_TO.z).length() < 0.6:
		return false   # the telescope turns on its own pivot
	return true

## each loose thing carries its look with it
func _make_loose() -> void:
	for l in loose:
		var rb: RigidBody3D = l.body
		var node: Node3D = box_nodes.get(int(l.index))
		if node and node.get_parent() != _removed:
			node.reparent(rb, true)
			l.node = node

## put every loose thing back where it started, still
func reset_loose() -> void:
	for l in loose:
		send_home(l)

func send_home(l: Dictionary) -> void:
	var rb: RigidBody3D = l.body
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	rb.global_transform = l.home
	PhysicsServer3D.body_set_state(rb.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, l.home)
	rb.sleeping = true

## the indoor pool is sunk 0.8 m (x 11..21, z -5..5): the ground has a hole there and the pool floor sits below it
const POOL := Rect2(11, -5, 10, 10)
const POOL_FLOOR := -0.8

func _build_ground() -> void:
	var bd: Dictionary = layout.bounds
	var w: float = bd.x1 - bd.x0 + 80.0
	var d: float = bd.z1 - bd.z0 + 80.0
	var x0 := -w * 0.5
	var x1 := w * 0.5
	var z0 := -d * 0.5
	var z1 := d * 0.5
	var pr := POOL
	for r in [Rect2(x0, z0, w, pr.position.y - z0), Rect2(x0, pr.end.y, w, z1 - pr.end.y),
			Rect2(x0, pr.position.y, pr.position.x - x0, pr.size.y), Rect2(pr.end.x, pr.position.y, x1 - pr.end.x, pr.size.y)]:
		_ground_box(r, -1.0, 0.0)
	_ground_box(pr, POOL_FLOOR - 1.0, POOL_FLOOR)
	if dressed:
		_edge_walls(bd, w, d)
		return
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, 1, d)
	mi.mesh = mesh
	mi.position = Vector3(0, -0.51, 0)
	var m: StandardMaterial3D = _mat("#7fae6a", false).duplicate()
	m.albedo_color = Color(0.55, 0.66, 0.52)   # lawn: a muted green so outside reads as outside
	mi.material_override = m
	add_child(mi)
	# the house sits on a plain grey floor (the lawn stops at its walls)
	if not house.is_empty():
		var fl := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(house.x * 2.0, 0.02, house.z * 2.0)
		fl.mesh = fm
		fl.position = Vector3(0, -0.01, 0)
		fl.material_override = _mat("#c8c4bc", false)
		add_child(fl)
	_edge_walls(bd, w, d)

## an invisible ramp over a staircase, its top surface touching the front edge of every step, so you glide up and down
## instead of popping up each step (the steps still show; Pete, 24 Nov: stairs felt rough)
func _add_ramp(st: Dictionary) -> void:
	var dir: float = st.dir
	var run: float = st.run
	var rise: float = st.rise
	var n: float = st.n
	var y0: float = st.y0
	var u0: float = float(st.u0) - dir * run
	var u1: float = u0 + dir * run * n
	var h := rise * n
	var length := sqrt(pow(run * n, 2) + h * h)
	var t := 0.4
	var along := Vector3(0, h, dir * run * n) / length
	var up := Vector3(0, run * n, -dir * h) / length
	var mid := Vector3((float(st.v0) + float(st.v1)) * 0.5, y0 + h * 0.5, (u0 + u1) * 0.5)
	if not st.get("along_z", true):
		along = Vector3(along.z, along.y, 0)
		up = Vector3(up.z, up.y, 0)
		mid = Vector3(mid.z, mid.y, mid.x)
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(up.cross(along), up, along), mid - up * t * 0.5)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(float(st.v1) - float(st.v0), t, length)
	cs.shape = sh
	body.add_child(cs)
	body.set_meta("ramp", true)
	body.add_to_group("stair_ramp")   # the feet stand on the steps under it, not on it (characters/foot_ik.gd)
	add_child(body)

func _ground_box(r: Rect2, y0: float, y1: float) -> void:
	var body := StaticBody3D.new()
	body.position = Vector3(r.get_center().x, (y0 + y1) * 0.5 - 0.01, r.get_center().y)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(r.size.x, y1 - y0, r.size.y)
	cs.shape = sh
	body.add_child(cs)
	add_child(body)

## invisible walls round the edge of the grounds
func _edge_walls(bd: Dictionary, w: float, d: float) -> void:
	for s in [[Vector3(bd.x0 - 0.5, 5, 0), Vector3(1, 10, d)], [Vector3(bd.x1 + 0.5, 5, 0), Vector3(1, 10, d)],
			[Vector3(0, 5, bd.z0 - 0.5), Vector3(w, 10, 1)], [Vector3(0, 5, bd.z1 + 0.5), Vector3(w, 10, 1)]]:
		var wb := StaticBody3D.new()
		wb.position = s[0]
		var wc := CollisionShape3D.new()
		var ws := BoxShape3D.new()
		ws.size = s[1]
		wc.shape = ws
		wb.add_child(wc)
		add_child(wb)

## ladders: a climb zone (the player script reads `ladders`) plus two rails and rungs so you can see them
func _add_ladder(l: Dictionary) -> void:
	var a: Array = l.b
	var box := AABB(Vector3(a[0], a[1], a[2]), Vector3(a[3] - a[0], a[4] - a[1], a[5] - a[2]))
	if l.get("lift", false):
		lifts.append({"box": box, "nx": float(l.nx), "nz": float(l.nz), "rung": float(l.rung)})
		return
	ladders.append(box)
	ladder_normals.append(-Vector3(float(l.get("nx", 0)), 0, float(l.get("nz", 0))))   # out from the wall (the layout's nx/nz point up and over, into it)
	if dressed:   # the dressing has the white ladders
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.97, 0.97)
	var along_x: bool = box.size.x > box.size.z
	var c := box.get_center()
	for side in [-1, 1]:
		var rail := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.08, box.size.y, 0.08)
		rail.mesh = rm
		rail.material_override = m
		var off := (box.size.x if along_x else box.size.z) * 0.5 - 0.06
		rail.position = c + (Vector3(side * off, 0, 0) if along_x else Vector3(0, 0, side * off))
		add_child(rail)
	var y := box.position.y + 0.3
	while y < box.end.y:
		var rung := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(box.size.x - 0.1, 0.05, 0.06) if along_x else Vector3(0.06, 0.05, box.size.z - 0.1)
		rung.mesh = gm
		rung.material_override = m
		rung.position = Vector3(c.x, y, c.z)
		add_child(rung)
		y += 0.35

## the four cash-in shops (Pete, 26 Nov): one in each corner of the front and back lawns, backed up against the
## boundary hedge and facing the house. Only one is open at a time (CollectionGame moves it). The web Mansion's
## kiosk (in the dressing, on the front lawn) is lifted out and copied to each corner; its own collider goes.
const SHOP_SPOTS := [Vector3(-56, 0, -44.1), Vector3(56, 0, -44.1), Vector3(-56, 0, 44.1), Vector3(56, 0, 44.1)]
const SHOP_NAMES := ["front left", "front right", "back left", "back right"]   # left = -x, seen from the front lawn
const SHOP_SIZE := Vector3(2.34, 4.35, 1.34)
var shop_spots: Array = []       # {pos, face (the way it faces: where you stand), name, look}

func _add_shop() -> void:
	var old := shop_pos
	for i in bodies:   # the old kiosk's collider
		var a: Array = layout.boxes[i].b
		var c := Vector3(a[0] + a[3], 0, a[2] + a[5]) * 0.5
		if absf(c.x - old.x) < 1.0 and absf(c.z - old.z) < 1.0 and float(a[4]) > 3.0:
			(bodies[i] as Node).queue_free()
			bodies.erase(i)
			break
	var look := Node3D.new()
	look.name = "ShopLook"
	add_child(look)
	look.global_position = old
	var lifted := 0
	if dressed:
		for n in dressing.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			var ab: AABB = mi.global_transform * mi.get_aabb()
			var c := ab.get_center()
			if absf(c.x - old.x) < 1.6 and absf(c.z - old.z) < 1.2 and c.y < 5.0 and ab.size.x < 3.0 and ab.size.z < 3.0:
				mi.reparent(look, true)
				lifted += 1
	if lifted == 0:   # grey box: a kiosk with a SHOP sign
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = SHOP_SIZE
		mi.mesh = bm
		mi.material_override = _mat("#9a9a9a", false)
		mi.position.y = SHOP_SIZE.y * 0.5
		look.add_child(mi)
		var sign_lbl := Label3D.new()
		sign_lbl.text = "SHOP"
		sign_lbl.font_size = 96
		sign_lbl.pixel_size = 0.006
		sign_lbl.position = Vector3(0, 3.6, SHOP_SIZE.z * 0.5 + 0.02)
		look.add_child(sign_lbl)
	for i in SHOP_SPOTS.size():
		var pos: Vector3 = SHOP_SPOTS[i]
		var face := Vector3(0, 0, 1) if pos.z < 0.0 else Vector3(0, 0, -1)   # towards the house
		var copy: Node3D = look if i == 0 else look.duplicate() as Node3D
		if i > 0:
			add_child(copy)
		copy.name = "Shop%d" % i
		copy.global_position = pos
		copy.rotation.y = 0.0 if face.z > 0.0 else PI
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = SHOP_SIZE
		cs.shape = sh
		body.add_child(cs)
		add_child(body)
		body.global_position = pos + Vector3(0, SHOP_SIZE.y * 0.5, 0)
		shop_spots.append({"pos": pos, "face": face, "name": SHOP_NAMES[i], "look": copy})
