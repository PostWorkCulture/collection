@tool
extends EditorPlugin
## Presses the editor's Bake Lightmaps button on level/lightmap/mansion_bake.scn, then quits (Godot has no other way
## to bake). tools/lightmap/bake.ps1 turns this plugin on for one editor run with COLLECTION_BAKE=1 and turns it off
## again; without that variable it does nothing.

const SCENE := "res://level/lightmap/mansion_bake.scn"

func _enter_tree() -> void:
	if OS.get_environment("COLLECTION_BAKE") != "1":
		return
	_run.call_deferred()

func _run() -> void:
	for i in 600:   # the editor and the scene finish loading
		await get_tree().process_frame
		var root := EditorInterface.get_edited_scene_root()
		if root and root.scene_file_path == SCENE:
			break
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != SCENE:
		EditorInterface.open_scene_from_path(SCENE)
		for i in 300:
			await get_tree().process_frame
		root = EditorInterface.get_edited_scene_root()
	var lms := root.find_children("*", "LightmapGI", true, false) if root else []
	if lms.is_empty():
		_done("no LightmapGI in %s" % SCENE)
		return
	var lm := lms[0] as LightmapGI
	EditorInterface.edit_node(lm)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(lm)
	EditorInterface.set_main_screen_editor("3D")
	for i in 30:
		await get_tree().process_frame
	var button := _find_button(EditorInterface.get_base_control())
	if button == null:
		_done("Bake Lightmaps button not found")
		return
	var t0 := Time.get_ticks_msec()
	button.pressed.emit()   # the bake runs here, with its own progress window
	for i in 30:
		await get_tree().process_frame
	var data := lm.light_data
	var said := _dialog_text(EditorInterface.get_base_control())   # the editor reports bake problems in a pop-up
	_done("baked in %.0f s: %s%s" % [(Time.get_ticks_msec() - t0) / 1000.0, data.resource_path if data else "no data",
		(" | editor said: " + said) if said != "" else ""])

func _dialog_text(n: Node) -> String:
	var out := ""
	var w := n as Window
	if w and w.visible and n != EditorInterface.get_base_control():
		var d := n as AcceptDialog
		var lbls: PackedStringArray = []
		for l in n.find_children("*", "Label", true, false):
			if (l as Label).text != "" and (l as Label).is_visible_in_tree():
				lbls.append((l as Label).text)
		out += "[%s '%s' %s: %s] " % [n.get_class(), w.title, d.dialog_text if d else "", " / ".join(lbls)]
	for c in n.get_children():
		out += _dialog_text(c)
	return out

func _find_button(n: Node) -> Button:
	var b := n as Button
	if b and b.text.contains("Bake Lightmaps"):
		return b
	for c in n.get_children():
		var f := _find_button(c)
		if f:
			return f
	return null

func _done(msg: String) -> void:
	print("LIGHTMAP BAKE: " + msg)
	var f := FileAccess.open("res://level/lightmap/bake_result.txt", FileAccess.WRITE)
	if f:
		f.store_string(msg + "\n")
		f.close()
	get_tree().quit()
