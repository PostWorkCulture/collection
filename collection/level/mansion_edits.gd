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
