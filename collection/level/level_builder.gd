extends Node3D
## Builds the grey-box Mansion from level/mansion_layout.json, which is exported straight from the web game's Mansion
## (every solid box, ladder and spawn point, in the same metres and the same coordinates: x across, y up, z front to back,
## the front door facing -z). Grey-box look: light grey with a 1 m grid, a muted tint per room from the web colours,
## clear glass. Every box is solid, exactly as in the web game.
## Phase 6: level/mansion.glb is the web Mansion's own look (rooms, finishes, furniture, lamps), exported from the same build
## as the layout, so it lines up with these colliders box for box. When it loads, the grey-box drawing is skipped; the colliders,
## ladders and glass (drawn here so it can break) stay. Moving parts in it are named (lift_car, tramp_mat, disco_*, pool_water,
## portal_swirl) for level/mansion_features.gd to animate.

var layout: Dictionary = {}
var ladders: Array[AABB] = []
var lifts: Array = []            # the 2 lifts and the fireman's pole: {box, nx, nz, rung}; ridden, not climbed
var dressed := false             # mansion.glb loaded
var dressing: Node3D = null
var parts := {}                  # name -> Array of the GLB's named moving parts
var windows: Array = []          # the 40 big windows: {body, ax (pane runs along x), at, a, b, s0 (sill), s1 (top)}
var spawns: Array = []
var house: Dictionary = {}
var shop_pos := Vector3.ZERO

var _grid_tex: ImageTexture
var _mats := {}

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
	for b in layout.boxes:
		_add_box(b)
	for l in layout.ladders:
		_add_ladder(l)
	for st in layout.get("stairs", []):
		_add_ramp(st)
	_add_shop()

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

## the web drew its light beams and glows additively (faint, never solid); glTF has no additive blend, so the faint unlit
## see-through materials go back to additive here
func _fix_materials(n: Node, seen: Dictionary) -> void:
	for c in n.get_children():
		var mi := c as MeshInstance3D
		if mi and mi.mesh:
			for si in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(si) as StandardMaterial3D
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

func _add_box(b: Dictionary) -> void:
	var a: Array = b.b
	var p0 := Vector3(a[0], a[1], a[2])
	var p1 := Vector3(a[3], a[4], a[5])
	var size := (p1 - p0).abs()
	if size.x < 0.01 or size.y < 0.01 or size.z < 0.01:
		return
	var glass: bool = int(b.g) == 1 or b.p == "glass"
	var body := StaticBody3D.new()
	body.position = (p0 + p1) * 0.5
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	if glass:
		body.set_meta("glass", true)
		# the big windows: 3 m panes on a 0.8 m sill, downstairs and up
		if size.y > 2.9 and size.y < 3.1 and (absf(p0.y - 0.8) < 0.05 or absf(p0.y - 6.6) < 0.05):
			var ax := size.x > size.z
			windows.append({"body": body, "ax": ax, "at": body.position.z if ax else body.position.x,
				"a": p0.x if ax else p0.z, "b": p1.x if ax else p1.z, "s0": p0.y, "s1": p1.y})
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

## the cash-in shop on the front lawn: a grey kiosk with a lit SHOP sign facing the front door (phase 3 makes it work)
func _add_shop() -> void:
	var body := StaticBody3D.new()
	if dressed:   # the dressing has the kiosk; keep it solid
		body.position = shop_pos + Vector3(0, 1.4, 0)
		var c2 := CollisionShape3D.new()
		var s2 := BoxShape3D.new()
		s2.size = Vector3(2.2, 2.8, 1.2)
		c2.shape = s2
		body.add_child(c2)
		add_child(body)
		return
	body.position = shop_pos + Vector3(0, 1.4, 0)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(2.2, 2.8, 1.2)
	cs.shape = sh
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sh.size
	mi.mesh = bm
	mi.material_override = _mat("#9a9a9a", false)
	body.add_child(mi)
	var sign_lbl := Label3D.new()
	sign_lbl.text = "SHOP"
	sign_lbl.font_size = 96
	sign_lbl.pixel_size = 0.006
	sign_lbl.modulate = Color(1, 1, 1)
	sign_lbl.outline_size = 0
	sign_lbl.position = Vector3(0, 1.0, 0.62)
	body.add_child(sign_lbl)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0, 1.0, 1.2)
	lamp.light_energy = 1.2
	lamp.omni_range = 5
	body.add_child(lamp)
	add_child(body)
