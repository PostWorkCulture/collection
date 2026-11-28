extends SceneTree
## Builds the Mansion exactly as the game does (level_builder.gd, mansion_edits.gd, mansion_lights.gd), marks what gets
## baked (level/lightmap.gd) and saves it as collection/level/lightmap/mansion_bake.scn, ready to bake in the editor:
##   godot --headless --path collection --script <repo>/tools/lightmap/make_bake_scene.gd
## tools/lightmap/bake.ps1 runs this, then has the editor bake it (Level/Lightmap, Bake Lightmaps), which writes
## mansion_bake.lmbake and mansion_bake.exr next to it; those two (and the .exr's .import) are committed, the
## .scn isn't (it's made again from the game's own code whenever the Mansion changes).

const LevelBuilder := preload("res://level/level_builder.gd")
const MansionLights := preload("res://level/mansion_lights.gd")
const Lightmap := preload("res://level/lightmap.gd")
const OUT := "res://level/lightmap/mansion_bake.scn"

func _initialize() -> void:
	await process_frame   # the tree is live: the Mansion's edits work out positions as they do in the game
	var root := Node3D.new()
	root.name = "MansionBake"
	get_root().add_child(root)
	var level: Node3D = LevelBuilder.new()
	level.name = "Level"
	root.add_child(level)
	level.build()
	# what the bake doesn't need: colliders (and the loose things and glass they carry), the shops, the telescope,
	# and what Pete had taken out
	for c in level.get_children():
		if c is CollisionObject3D or String(c.name) in ["Removed", "Telescope"] or String(c.name).begins_with("Shop"):
			level.remove_child(c)
			c.free()
	var baked: int = Lightmap.prepare(level)
	# the lamps as the game makes them (the moving ones left out of the bake)
	var lights: Node3D = MansionLights.new()
	lights.name = "Lights"
	level.add_child(lights)   # the bake only gathers lights from inside the LightmapGI's parent
	lights.setup(level.layout, "high", true)
	lights.set_script(null)
	# the sun and sky as main.gd makes them: the sun's bounce is baked, its direct light stays real-time
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	level.add_child(sun)
	var lm: LightmapGI = Lightmap.make_node()
	# the sky light: an even colour matched to level/sky.gdshader's average (the bake can't draw a shader sky: it came
	# out black, so the shaded front of the house was dark)
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	lm.environment_custom_color = Color(0.6, 0.68, 0.8)
	lm.environment_custom_energy = 1.0
	# the bake writes over this file; without one the editor stops to ask where to save
	if not ResourceLoader.exists(Lightmap.DATA_PATH):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Lightmap.DATA_PATH.get_base_dir()))
		ResourceSaver.save(LightmapGIData.new(), Lightmap.DATA_PATH)
	lm.light_data = load(Lightmap.DATA_PATH)
	level.add_child(lm)
	# save it as plain nodes (the imported Mansion's meshes go inside the file)
	var dressing: Node = level.get_node("Dressing")
	dressing.scene_file_path = ""
	_own(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err == OK:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://level/lightmap"))
		err = ResourceSaver.save(ps, OUT)
	var n_lights := lights.find_children("*", "OmniLight3D", true, false).size()
	print("BAKE SCENE %s: %d meshes baked, %d lamps, saved=%s" % [OUT, baked, n_lights, error_string(err)])
	quit(0 if err == OK else 1)

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)
