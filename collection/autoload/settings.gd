extends Node
## Saved player settings (phase 1: camera, field of view, mouse sensitivity).

var camera_mode := "third"   # "third" (default, as on the web) or "first"
var fov := 70.0
var sensitivity := 5.0       # 0-10, like the web game's slider

const PATH := "user://settings.cfg"

func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		camera_mode = c.get_value("view", "camera", camera_mode)
		fov = c.get_value("view", "fov", fov)
		sensitivity = c.get_value("input", "sensitivity", sensitivity)

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("view", "camera", camera_mode)
	c.set_value("view", "fov", fov)
	c.set_value("input", "sensitivity", sensitivity)
	c.save(PATH)
