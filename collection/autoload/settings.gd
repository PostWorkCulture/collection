extends Node
## Saved player settings, stored in user://settings.cfg. Phase 1: camera, field of view, mouse sensitivity; phase 4:
## bot difficulty; phase 5: graphics quality, volumes in 10% steps, key bindings. 27 Nov (Pete: "professional menus
## with all the options you'd typically find in an FPS", 1v1's settings as the base): display, aim and controller
## feel, the crosshair and hit feedback, and a reset. ui/menu.gd shows them; main.gd, fighter.gd and hud.gd use them.

# ---- view and graphics
var camera_mode := "third"   # "third" (default, as on the web) or "first"
var fov := 70.0
var quality := "high"        # graphics: "low", "medium" or "high"
var aa := "msaa2"            # anti-aliasing: "off", "fxaa", "msaa2", "msaa4", "taa"
var render_scale := 100      # % of the screen's resolution the 3D view is drawn at
var brightness := 100        # %
# ---- display
var window_mode := "windowed"   # "windowed", "borderless" (full screen without a border) or "fullscreen"
var vsync := true
var max_fps := 0             # 0 = no limit
var show_fps := true
var show_help := true        # the controls line along the bottom of the screen
var ui_scale := 100          # % size of the HUD and menus
# ---- sound
var vol_master := 10         # volumes 0-10 (each step is 10%)
var vol_weapons := 8
var vol_sfx := 8
var vol_music := 6
var vol_voice := 8
var hit_sound := true        # the tick when you land a hit
var mute_unfocused := true   # quiet while the game is in the background
# ---- mouse and controller
var sensitivity := 5.0       # 0-10, like the web game's slider
var ads_sensitivity := 100   # % of your look speed while aiming down sights
var invert_y := false
var pad_sensitivity := 5.0   # 0-10, the right stick
var pad_invert_y := false
var aim_toggle := false      # aim: hold (false) or press to toggle
var crouch_hold := false     # crouch: press to toggle (false) or hold
var aim_assist := "easy"     # controller only: "off", "easy" (on Easy bots, as before) or "on"
# ---- crosshair and hits
var xh_style := "crossdot"   # "crossdot", "cross", "tee", "dot", "circle"
var xh_color := "#ffffff"
var xh_size := "m"           # "s", "m", "l"
var xh_thick := "m"          # "s", "m", "l"
var xh_opacity := 100        # %
var xh_outline := true
var xh_dynamic := true       # opens with your gun's spread
var xh_red := true           # turns red when an enemy is under it and in reach
var hit_marker := true
var dmg_numbers := true
# ---- game
var bots := "normal"         # bot difficulty: "easy", "normal" or "hard"
var keys := {}               # action -> saved binding ("k:<physical keycode>" or "m:<mouse button>"), only rebound ones
var play_now := false        # "Play again" from the results skips the start screen once (not saved)

const PATH := "user://settings.cfg"
## what's saved: [section, key, property]
const SAVED := [
	["view", "camera", "camera_mode"], ["view", "fov", "fov"], ["view", "quality", "quality"], ["view", "aa", "aa"],
	["view", "render_scale", "render_scale"], ["view", "brightness", "brightness"],
	["display", "window_mode", "window_mode"], ["display", "vsync", "vsync"], ["display", "max_fps", "max_fps"],
	["display", "show_fps", "show_fps"], ["display", "show_help", "show_help"], ["display", "ui_scale", "ui_scale"],
	["audio", "master", "vol_master"], ["audio", "weapons", "vol_weapons"], ["audio", "sfx", "vol_sfx"],
	["audio", "music", "vol_music"], ["audio", "voice", "vol_voice"], ["audio", "hit_sound", "hit_sound"],
	["audio", "mute_unfocused", "mute_unfocused"],
	["input", "sensitivity", "sensitivity"], ["input", "ads_sensitivity", "ads_sensitivity"], ["input", "invert_y", "invert_y"],
	["input", "pad_sensitivity", "pad_sensitivity"], ["input", "pad_invert_y", "pad_invert_y"], ["input", "aim_toggle", "aim_toggle"],
	["input", "crouch_hold", "crouch_hold"], ["input", "aim_assist", "aim_assist"], ["input", "keys", "keys"],
	["crosshair", "style", "xh_style"], ["crosshair", "color", "xh_color"], ["crosshair", "size", "xh_size"],
	["crosshair", "thickness", "xh_thick"], ["crosshair", "opacity", "xh_opacity"], ["crosshair", "outline", "xh_outline"],
	["crosshair", "dynamic", "xh_dynamic"], ["crosshair", "red_on_target", "xh_red"], ["crosshair", "hit_marker", "hit_marker"],
	["crosshair", "damage_numbers", "dmg_numbers"],
	["game", "bots", "bots"],
]
var _defaults := {}

func _ready() -> void:
	for s in SAVED:
		var v: Variant = get(s[2])
		_defaults[s[2]] = v.duplicate() if v is Dictionary else v
	var c := ConfigFile.new()
	if c.load(PATH) == OK:
		for s in SAVED:
			set(s[2], c.get_value(s[0], s[1], get(s[2])))

func save() -> void:
	var c := ConfigFile.new()
	for s in SAVED:
		c.set_value(s[0], s[1], get(s[2]))
	c.save(PATH)

## every setting back to how it came, keys included (then saved)
func reset_all() -> void:
	for p in _defaults:
		var v: Variant = _defaults[p]
		set(p, v.duplicate() if v is Dictionary else v)
	save()

func default_of(prop: String) -> Variant:
	return _defaults.get(prop)
