extends RefCounted
## Pete's room changes (26 Nov), made on top of the imported Mansion: the colliders come from mansion_layout.json and
## the look from mansion.glb, both exported from the web game, so these are applied as the level is built rather
## than by editing the export.
## - Stairs kept clear: the garage shelf at the foot of the garage stairs, the drum and crate at the foot of the kitchen
##   back stairs and the wardrobe at their top (in the master bedroom) are taken out.
## - Roof terrace: the hot tub goes into the far corner (the back wall's end away from the garage stairs, so the stairs
##   stay clear) and is 25% bigger; the sun loungers and the palm that stood in that corner are taken out.
## - Hall of Fame (the trophy room): rock singers and guitarists in glittery gold frames.
## - Observatory (the space room): a ceiling of twinkling stars, and the telescope spins round when you walk up to it.
## - Hot tubs (27 Nov): you walk in and out without jumping. The web's rim was 0.55 m above the deck, exactly the most a
##   step can climb, so it always needed a jump. Now a low stone step runs round the outside and a seat round the inside,
##   both 0.28 m, and the rim's collider matches the white stone you see.
## Things are found by where they stand (centre within 0.3 m), not by box number, so a re-export doesn't break this.

const UF := 5.8

## boxes to leave out: centre, and what it is
const REMOVE := [
	[Vector3(37.5, 0.55, 9.76), "garage: the shelf at the foot of the stairs"],
	[Vector3(-37.9, 0.53, -9.47), "kitchen: the fuel drum at the foot of the back stairs"],
	[Vector3(-36.5, 0.48, -9.51), "kitchen: the crate at the foot of the back stairs"],
	[Vector3(-39.2, 7.1, -19.5), "master bedroom: the wardrobe at the top of the back stairs"],
	[Vector3(34.0, 6.05, 24.5), "terrace: sun lounger"],
	[Vector3(36.0, 6.05, 24.5), "terrace: sun lounger"],
	[Vector3(25.5, 7.1, 26.0), "terrace: the palm in the corner the tub now fills"],
]
## the terrace tub: where it was, where it goes, how much bigger (across; the heights stay)
const TUB_FROM := Vector3(30, UF, 23)
const TUB_SCALE := 1.25
const TUB_TO := Vector3(28.45, UF, 22.45)      # its 8.5 m deck in the corner of the back wall and the house's middle wall
const TUB_AREA := AABB(Vector3(26.4, 5.7, 19.4), Vector3(7.2, 2.2, 7.2))
## the telescope: moved 1.2 m out from the wall so its tube clears the wall as it spins
const SCOPE_FROM := Vector3(25.36, UF, -21.0)
const SCOPE_TO := Vector3(26.56, UF, -21.0)
## the hot tubs: centre and how much bigger than the spa's; the deck is 0.3 m, the white stone surround runs from
## 1.5 m to 2.1 m out and stands 0.56 m above the deck (all × the tub's scale across)
const TUBS := [[Vector3(-16, UF, 4), 1.0], [TUB_TO, TUB_SCALE]]
const TUB_DECK := 0.3
const TUB_RIM := [1.5, 2.1, 0.56]
const TUB_STEP := [2.1, 2.55, 0.28]     # outside: from, to, height above the deck
const TUB_SEAT := [1.15, 1.5, 0.28]     # inside, under the water

static func box_centre(b: Dictionary) -> Vector3:
	var a: Array = b.b
	return Vector3(a[0] + a[3], a[1] + a[4], a[2] + a[5]) * 0.5

## true for a box Pete had taken out (level_builder skips its collider and hides its look)
static func removed(b: Dictionary) -> bool:
	var c := box_centre(b)
	for r in REMOVE:
		if c.distance_to(r[0]) < 0.3:
			return true
	return false

## a terrace tub box (deck or rim) moves with the tub
static func move_box(b: Dictionary) -> Dictionary:
	var c := box_centre(b)
	if not TUB_AREA.has_point(c) or b.get("p", "") != "":
		return b
	var a: Array = b.b
	var lo := Vector3(a[0], a[1], a[2])
	var hi := Vector3(a[3], a[4], a[5])
	var size := hi - lo
	var nc := TUB_TO + Vector3((c.x - TUB_FROM.x) * TUB_SCALE, c.y - TUB_FROM.y, (c.z - TUB_FROM.z) * TUB_SCALE)
	size.x *= TUB_SCALE
	size.z *= TUB_SCALE
	var out := b.duplicate()
	out.b = [nc.x - size.x * 0.5, lo.y, nc.z - size.z * 0.5, nc.x + size.x * 0.5, hi.y, nc.z + size.z * 0.5]
	return out

## the telescope's box moves out from the wall with it
static func move_scope_box(b: Dictionary) -> Dictionary:
	var c := box_centre(b)
	if Vector2(c.x - SCOPE_FROM.x, c.z - SCOPE_FROM.z).length() > 0.3 or b.get("p", "") != "crate":
		return b
	var a: Array = b.b
	var d := SCOPE_TO.x - SCOPE_FROM.x
	var out := b.duplicate()
	out.b = [a[0] + d, a[1], a[2], a[3] + d, a[4], a[5]]
	return out

## the look: tub moved and scaled, telescope on a pivot (CollectionGame-free: level only)
static func apply(level: Node3D) -> Dictionary:
	var out := {"scope": null, "hidden": 0, "tub_meshes": 0}
	_tub_steps(level)
	if not level.dressed:
		return out
	var meshes: Array = level.dressing.find_children("*", "MeshInstance3D", true, false)
	var tub := Node3D.new()
	tub.name = "TerraceTub"
	level.add_child(tub)
	tub.global_position = TUB_FROM
	for n in meshes:
		var mi := n as MeshInstance3D
		var ab: AABB = mi.global_transform * mi.get_aabb()
		var c := ab.get_center()
		if TUB_AREA.has_point(c) and ab.size.x < 7.5 and ab.size.z < 7.5:
			mi.reparent(tub, true)
			out.tub_meshes += 1
	tub.global_position = TUB_TO
	tub.scale = Vector3(TUB_SCALE, 1.0, TUB_SCALE)
	# the telescope: its box node (its look) goes on a pivot at its foot
	for i in level.box_nodes:
		var node: Node3D = level.box_nodes[i]
		if not String(node.name).ends_with("_crate"):
			continue
		var c := box_centre(level.layout.boxes[i])
		if Vector2(c.x - SCOPE_FROM.x, c.z - SCOPE_FROM.z).length() < 0.3 and c.y > UF:
			var pivot := Node3D.new()
			pivot.name = "Telescope"
			level.add_child(pivot)
			pivot.global_position = SCOPE_FROM
			node.reparent(pivot, true)
			pivot.global_position = SCOPE_TO
			out.scope = pivot
			break
	return out

## the tubs' step, rim and seat (see the top): the web's rim blocks stop colliding and three rings take over
static func _tub_steps(level: Node3D) -> void:
	for t in TUBS:
		var c: Vector3 = t[0]
		var sc: float = t[1]
		for i in level.bodies:
			var body: CollisionObject3D = level.bodies[i]
			var p := body.global_position
			if absf(p.y - (c.y + TUB_DECK + 0.275)) < 0.05 and Vector2(p.x - c.x, p.z - c.z).length() < 2.0 * sc:
				body.collision_layer = 0   # a rim block
		var holder := StaticBody3D.new()
		holder.name = "TubSteps"
		level.add_child(holder)
		holder.global_position = c + Vector3.UP * TUB_DECK
		var stone := StandardMaterial3D.new()
		stone.albedo_color = Color(0.93, 0.93, 0.94)
		stone.roughness = 0.55
		stone.cull_mode = BaseMaterial3D.CULL_DISABLED
		var tile := StandardMaterial3D.new()
		tile.albedo_color = Color(0.31, 0.7, 0.78)
		tile.roughness = 0.3
		tile.cull_mode = BaseMaterial3D.CULL_DISABLED
		for ring in [[TUB_STEP, stone], [TUB_SEAT, tile], [TUB_RIM, null]]:
			var r: Array = ring[0]
			var mesh := _annulus(float(r[0]) * sc, float(r[1]) * sc, float(r[2]), 48)
			var cs := CollisionShape3D.new()
			var shape := mesh.create_trimesh_shape()
			shape.backface_collision = true
			cs.shape = shape
			holder.add_child(cs)
			if ring[1] != null:   # (the rim is already drawn by the Mansion)
				var mi := MeshInstance3D.new()
				mi.mesh = mesh
				mi.material_override = ring[1]
				holder.add_child(mi)

## a flat ring from r0 to r1, h tall, standing on y = 0: its top and both upright faces
static func _annulus(r0: float, r1: float, h: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP * h
	for i in n:
		var a0 := float(i) / n * TAU
		var a1 := float(i + 1) / n * TAU
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		st.set_normal(Vector3.UP)   # top
		for v in [d0 * r0 + up, d1 * r1 + up, d0 * r1 + up, d0 * r0 + up, d1 * r0 + up, d1 * r1 + up]:
			st.add_vertex(v)
		for v in [d0 * r1, d0 * r1 + up, d1 * r1 + up, d0 * r1, d1 * r1 + up, d1 * r1]:   # outside face
			st.set_normal(Vector3(v.x, 0, v.z).normalized())
			st.add_vertex(v)
		for v in [d0 * r0, d1 * r0 + up, d0 * r0 + up, d0 * r0, d1 * r0, d1 * r0 + up]:   # inside face
			st.set_normal(-Vector3(v.x, 0, v.z).normalized())
			st.add_vertex(v)
	return st.commit()
