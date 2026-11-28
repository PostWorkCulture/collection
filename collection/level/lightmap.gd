extends RefCounted
## Baked lighting (AAA phase 3): which parts of the Mansion are in the lightmap, and the bake's settings.
## tools/lightmap/make_bake_scene.gd builds the Mansion exactly as the game does, marks it with prepare() and saves it
## as level/lightmap/mansion_bake.scn; tools/lightmap/bake.ps1 has the editor bake that (Godot only bakes from the editor's button), which
## writes mansion_bake.lmbake and its .exr. The game builds the same Mansion, calls prepare() and adds the LightmapGI
## with that data at the same place, so every baked mesh is found at the same path.
##
## Baked (static): the house's own walls, floors, ceilings and furniture (level/mansion.glb, imported with lightmap UVs),
## and the terrace hot tub that mansion_edits.gd moves. Not baked (dynamic, lit by the lightmap's probes like the
## characters): anything that moves (lift cars, trampolines, the disco floor and ball, pool water, portals, the
## telescope, the loose things that get knocked about) and anything built in code (glass, tub steps, shops).
## Not in the bake at all: the lawn (its green bounced onto everything) and the faint see-through beams and glows.

const DATA_PATH := "res://level/lightmap/mansion_bake.lmbake"
const NODE_NAME := "Lightmap"
const MOVING_PARTS := ["lift_car", "tramp_mat", "tramp_arrow", "disco_ball", "disco_floor", "disco_beam", "pool_water", "portal_swirl"]
const STATIC_ROOTS := ["Dressing", "TerraceTub"]

## true when a bake is there to use
static func available() -> bool:
	return ResourceLoader.exists(DATA_PATH)

## sets every mesh in the level to baked, dynamic or left out (see the top); returns how many are baked
static func prepare(level: Node3D) -> int:
	var baked := 0
	for n in level.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.gi_mode == GeometryInstance3D.GI_MODE_DISABLED:
			continue   # the lawn (level_builder.gd)
		if _faint(mi):
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		elif _static(level, mi):
			mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			baked += 1
		else:
			mi.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	return baked

## the LightmapGI node, set up the same way for the bake and in the game
static func make_node() -> LightmapGI:
	var lm := LightmapGI.new()
	lm.name = NODE_NAME
	lm.quality = LightmapGI.BAKE_QUALITY_MEDIUM
	lm.bounces = 3
	lm.directional = false
	lm.interior = false
	lm.use_denoiser = true
	lm.max_texture_size = 8192
	lm.generate_probes_subdiv = LightmapGI.GENERATE_PROBES_SUBDIV_8
	return lm

static func _static(level: Node3D, mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	if not (mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV2):
		return false   # made in code, no lightmap UVs
	var p: Node = mi
	var under := false
	while p != null and p != level:
		var nm := String(p.name)
		for key in MOVING_PARTS:
			if nm.begins_with(key):
				return false
		if p.get_parent() == level:
			under = STATIC_ROOTS.has(nm)
		p = p.get_parent()
	return under

## the web's light beams and glows: faint, unlit and see-through (level_builder.gd makes them additive)
static func _faint(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for si in mi.mesh.get_surface_count():
		var m := mi.get_active_material(si) as BaseMaterial3D
		if m == null or m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED:
			return false
	return true
