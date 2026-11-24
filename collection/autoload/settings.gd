extends Node
## Saved player settings: camera, field of view, mouse sensitivity (phase 1), bot difficulty (phase 4), graphics
## quality, volumes in 10% steps and key bindings (phase 5). Stored in user://settings.cfg.

var camera_mode := "third"   # "third" (default, as on the web) or "first"
var fov := 70.0
var sensitivity := 5.0       # 0-10, like the web game's slider
var bots := "normal"         # bot difficulty: "easy", "normal" or "hard"
var quality := "high"        # graphics: "low", "medium" or "high"
var vol_master := 10         # volumes 0-10 (each step is 10%)
var vol_weapons := 8
var vol_sfx := 8
var vol_music := 6
var vol_voice := 8
var keys := {}               # action -> saved binding ("k:<physical keycode>" or "m:<mouse button>"), only rebound ones
var play_now := false        # "Play again" from the results skips the start screen once (not saved)

const PATH := "user://settings.cfg"

func _ready() -> void:
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		camera_mode = c.get_value("view", "camera", camera_mode)
		fov = c.get_value("view", "fov", fov)
		quality = c.get_value("view", "quality", quality)
		sensitivity = c.get_value("input", "sensitivity", sensitivity)
		keys = c.get_value("input", "keys", keys)
		bots = c.get_value("game", "bots", bots)
		vol_master = c.get_value("audio", "master", vol_master)
		vol_weapons = c.get_value("audio", "weapons", vol_weapons)
		vol_sfx = c.get_value("audio", "sfx", vol_sfx)
		vol_music = c.get_value("audio", "music", vol_music)
		vol_voice = c.get_value("audio", "voice", vol_voice)

func save() -> void:
	var c := ConfigFile.new()
	c.set_value("view", "camera", camera_mode)
	c.set_value("view", "fov", fov)
	c.set_value("view", "quality", quality)
	c.set_value("input", "sensitivity", sensitivity)
	c.set_value("input", "keys", keys)
	c.set_value("game", "bots", bots)
	c.set_value("audio", "master", vol_master)
	c.set_value("audio", "weapons", vol_weapons)
	c.set_value("audio", "sfx", vol_sfx)
	c.set_value("audio", "music", vol_music)
	c.set_value("audio", "voice", vol_voice)
	c.save(PATH)
