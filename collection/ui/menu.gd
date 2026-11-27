extends CanvasLayer
## Menus (Pete, 27 Nov: "professional menus with all the options you'd typically find in an FPS shooting game, 1v1's
## menus as the foundation"), laid out like 1v1's and drawn in Collection's monochrome look (black cards, thin grey
## edges, white Arial, gold as the one accent):
## - Start: the title and blurb, bot difficulty, PLAY, Settings, Controls, Quit; beside it how a match plays and
##   your main keys.
## - Pause (Esc / Start): what's going on (time, your stars, where the shop is), Resume, Settings, Controls, Quit to
##   menu; beside it the standings and what you're carrying (1v1's score and loadout cards).
## - Settings (1v1's layout): tabs down the left (Graphics, Display, Sound, Mouse & controller, Crosshair & hits,
##   Gameplay), Controls and Reset all settings under them, the options on the right, Back / Resume at the bottom.
## - Controls: every action with its key or mouse button in groups; click one and press the new key (Esc cancels);
##   a key already in use swaps over; Reset keys. The controller's buttons are listed beside them.
## Works with mouse, keyboard or a controller (D-pad / stick to move, A to choose, B to go back), and runs while the
## game is paused. Every option is saved at once (autoload/settings.gd) and applied by main.gd (settings_changed).

signal play
signal resume
signal quit_to_menu
signal settings_changed(what: String)

const Crosshair := preload("res://ui/crosshair.gd")
const Weapons := preload("res://weapons/weapons.gd")

const WHITE := Color(1, 1, 1)
const GREY := Color(0.62, 0.62, 0.62)
const DIM := Color(0.42, 0.42, 0.42)
const EDGE := Color(0.32, 0.32, 0.32)
const GOLD := Color("#ffc83a")
const BLUE := Color(0.35, 0.62, 1.0)
const BLACK := Color(0, 0, 0)

## actions you can rebind, by group, with their names
const GROUPS := [
	["Move", [["move_forward", "Forward"], ["move_back", "Back"], ["move_left", "Left"], ["move_right", "Right"], ["jump", "Jump (twice to double jump)"], ["crouch", "Crouch"]]],
	["Fight", [["fire", "Attack (guns aim as they fire)"], ["aim", "Aim, or use your item"], ["weapon_melee", "Bat"], ["weapon_gun", "Gun"], ["interact", "Swap gun"]]],
	["Items and view", [["use_mine", "Lay mine"], ["use_stun", "Throw stun"], ["camera_toggle", "First / third person"]]],
]
const PAD := [["Left stick", "Move"], ["Right stick", "Look"], ["RT", "Attack"], ["LT", "Aim, or use your item"], ["A", "Jump"], ["B", "Crouch"],
	["X", "Swap gun"], ["RB", "Bat / gun"], ["D-pad left", "Lay mine"], ["D-pad right", "Throw stun"], ["Back", "Camera"], ["Start", "Pause"]]
const TABS := [["gfx", "Graphics"], ["display", "Display"], ["sound", "Sound"], ["input", "Mouse & controller"], ["xh", "Crosshair & hits"], ["game", "Gameplay"]]

var defaults := {}        # action -> its first keyboard/mouse event as set up by main.gd (for Reset keys)
var game: Node = null     # for the pause screen's cards
var player: Node = null
var screen := ""
var in_game := false      # pause menu vs start screen
var tab := "gfx"
var _font: SystemFont
var _bold: SystemFont
var _dim: ColorRect
var _card: PanelContainer
var _root: Control        # the current screen inside the card
var _waiting := ""        # action waiting for a new key
var _wait_btn: Button
var _back_to := ""
var _first: Control       # what gets focus when a screen opens
var _preview: Control     # the crosshair preview (Crosshair & hits)
var _key_msg: Label
var _keys_from_settings := false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans"])
	_bold = SystemFont.new()
	_bold.font_names = _font.font_names
	_bold.font_weight = 700
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _box(Color(0.02, 0.02, 0.025, 0.86), EDGE, 32))
	_card.custom_minimum_size = Vector2(1080, 620)
	center.add_child(_card)
	hide_menu()

func hide_menu() -> void:
	screen = ""
	visible = false

# ---------------------------------------------------------------- building blocks

func _box(bg: Color, edge: Color, pad: float, radius := 4) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = edge
	st.set_border_width_all(1)
	st.set_corner_radius_all(radius)
	st.set_content_margin_all(pad)
	return st

func _set_screen(root: Control) -> void:
	for c in _card.get_children():
		_card.remove_child(c)
		c.queue_free()
	_root = root
	_first = null
	_card.add_child(root)

func _label(parent: Node, text: String, size: int, col: Color, bold := false, wraps := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _bold if bold else _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wraps else TextServer.AUTOWRAP_OFF
	if parent:
		parent.add_child(l)
	return l

func _eyebrow(parent: Node, text: String, col := GREY) -> Label:
	return _label(parent, text.to_upper(), 12, col, true)

## a short gold line under a title (1v1's rule)
func _rule(parent: Node) -> void:
	var r := ColorRect.new()
	r.color = GOLD
	r.custom_minimum_size = Vector2(56, 2)
	r.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	parent.add_child(r)

func _style_button(b: Button, primary := false, size := 16) -> void:
	b.add_theme_font_override("font", _bold if primary else _font)
	b.add_theme_font_size_override("font_size", size)
	var fill := WHITE if primary else Color(0, 0, 0, 0)
	for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
		var bg := fill
		if not primary and state != "normal":
			bg = Color(1, 1, 1, 0.1)
		elif primary and state in ["hover", "pressed", "hover_pressed"]:
			bg = Color(0.88, 0.88, 0.88)
		var edge := WHITE if state != "normal" or primary else EDGE
		if primary and state == "focus":
			edge = GOLD
		var s := _box(bg, edge, 10, 3)
		if state == "focus":
			s.set_border_width_all(2)
		s.content_margin_left = 16
		s.content_margin_right = 16
		b.add_theme_stylebox_override(state, s)
	var ink := BLACK if primary else WHITE
	for k in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, ink)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if not primary else HORIZONTAL_ALIGNMENT_CENTER

func _button(parent: Node, text: String, cb: Callable, primary := false, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	_style_button(b, primary, size)
	b.pressed.connect(cb)
	parent.add_child(b)
	if _first == null:
		_first = b
	return b

## a segmented choice (1v1's .seg): the chosen one is filled white
func _seg(options: Array, current: Variant, cb: Callable) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for o in options:
		var b := Button.new()
		b.text = String(o[1])
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = str(o[0]) == str(current)
		b.add_theme_font_override("font", _font)
		b.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			var on: bool = state in ["pressed", "hover_pressed"]
			var s := _box(WHITE if on else (Color(1, 1, 1, 0.1) if state in ["hover", "focus"] else Color(0, 0, 0, 0)), WHITE if state == "focus" else EDGE, 7, 0)
			s.content_margin_left = 12
			s.content_margin_right = 12
			b.add_theme_stylebox_override(state, s)
		for k in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(k, WHITE)
		b.add_theme_color_override("font_pressed_color", BLACK)
		b.add_theme_color_override("font_hover_pressed_color", BLACK)
		var v: Variant = o[0]
		b.pressed.connect(func(): cb.call(v))
		h.add_child(b)
		if _first == null:
			_first = b
	return h

## an options row: the name (and a short grey note under it) on the left, the control on the right
func _row(parent: Node, title: String, note: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(left, title, 15, WHITE)
	if note != "":
		_label(left, note, 12, DIM, false, true)
	h.add_child(left)
	ctrl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ctrl)
	parent.add_child(h)
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.06)
	line.custom_minimum_size.y = 1
	parent.add_child(line)

func _changed(prop: String, v: Variant, what: String) -> void:
	Settings.set(prop, v)
	Settings.save()
	if what != "":
		settings_changed.emit(what)
	if _preview:
		_preview.queue_redraw()

## a choice bound to a setting
func _opt(parent: Node, title: String, note: String, prop: String, options: Array, what := "") -> void:
	_row(parent, title, note, _seg(options, Settings.get(prop), func(v): _changed(prop, v, what)))

func _onoff(parent: Node, title: String, note: String, prop: String, what := "") -> void:
	_opt(parent, title, note, prop, [[true, "On"], [false, "Off"]], what)

## a slider bound to a setting, its value shown beside it (shown = how to write it)
func _slide(parent: Node, title: String, note: String, prop: String, lo: float, hi: float, step: float, shown: Callable, what := "") -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get(prop))
	s.custom_minimum_size = Vector2(230, 24)
	var val := _label(null, shown.call(s.value), 15, WHITE)
	val.custom_minimum_size.x = 56
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var whole := step >= 1.0
	s.value_changed.connect(func(v):
		val.text = shown.call(v)
		_changed(prop, int(v) if whole and typeof(Settings.get(prop)) == TYPE_INT else v, what))
	h.add_child(s)
	h.add_child(val)
	if _first == null:
		_first = s
	_row(parent, title, note, h)

func _focus() -> void:
	if _first:
		_first.grab_focus.call_deferred()

func _vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v

func _side_card(parent: Node, title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", _box(Color(1, 1, 1, 0.03), EDGE, 18))
	parent.add_child(pc)
	var v := _vbox(6)
	pc.add_child(v)
	_eyebrow(v, title)
	return v

## two-column lines: a dim key on the left, the text on the right
func _pairs(parent: Node, pairs: Array, key_w := 120) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 5)
	for p in pairs:
		var k := _label(g, String(p[0]), 14, GREY)
		k.custom_minimum_size.x = key_w
		_label(g, String(p[1]), 14, WHITE, false, true).custom_minimum_size.x = 300
	parent.add_child(g)

# ---------------------------------------------------------------- start

func show_start() -> void:
	in_game = false
	visible = true
	screen = "start"
	_dim.color = Color(0, 0, 0, 0.45)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	_set_screen(h)
	var left := _vbox(10)
	left.custom_minimum_size.x = 470
	h.add_child(left)
	_eyebrow(left, "imok", GOLD)
	_label(left, "Collection", 56, WHITE, true)
	_rule(left)
	_label(left, "8 players · The Mansion", 16, GREY)
	_label(left, "A bat, then whatever you find. Find 10 of the gold stars hidden in the house, then get outside to the open shop and cash them in: first to cash in wins.", 14, GREY, false, true)
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	left.add_child(gap)
	_eyebrow(left, "Bots")
	left.add_child(_seg([["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], Settings.bots, func(v): _changed("bots", v, "bots")))
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 6
	left.add_child(gap2)
	_first = null
	var p := _button(left, "PLAY", func(): hide_menu(); play.emit(), true, 20)
	p.custom_minimum_size.y = 52
	_button(left, "Settings  ›", func(): show_settings("start"))
	_button(left, "Controls  ›", func(): show_keys("start"))
	_button(left, "Quit", func(): get_tree().quit())
	var right := _vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var how := _side_card(right, "How it plays")
	_pairs(how, [["Stars", "10 are hidden around the house and on the roof"], ["Cash in", "Hold 10 and stand at the open shop on a lawn corner; it moves every minute"],
		["Lose them", "Go down and you drop 2; die and you drop them all"], ["Marked", "8 or more and you glow through walls and show on every minimap"],
		["Weapons", "Everyone has a bat; SMGs, a crossbow, mines, stuns and speed boosts lie around"]])
	var keys := _side_card(right, "Your keys")
	_pairs(keys, [[_short("move_forward") + _short("move_left") + _short("move_back") + _short("move_right"), "Move"], [_short("jump"), "Jump"],
		[key_name("fire"), "Attack"], [key_name("aim"), "Aim, or use your item"], [_short("weapon_melee") + " / " + _short("weapon_gun"), "Bat / gun"],
		[_short("interact"), "Swap gun"], ["Esc", "Pause"]])
	_focus()

# ---------------------------------------------------------------- pause

func show_pause() -> void:
	in_game = true
	visible = true
	screen = "pause"
	_dim.color = Color(0, 0, 0, 0.55)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 40)
	_set_screen(h)
	var left := _vbox(10)
	left.custom_minimum_size.x = 430
	h.add_child(left)
	_eyebrow(left, "Collection · The Mansion", GOLD)
	_label(left, "Paused", 48, WHITE, true)
	_rule(left)
	_label(left, _pause_meta(), 15, GREY, false, true)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	left.add_child(gap)
	_first = null
	var r := _button(left, "Resume        Esc", func(): hide_menu(); resume.emit(), true, 18)
	r.custom_minimum_size.y = 48
	_button(left, "Settings  ›", func(): show_settings("pause"))
	_button(left, "Controls  ›", func(): show_keys("pause"))
	_button(left, "Quit to menu", func(): hide_menu(); quit_to_menu.emit())
	_label(left, "Esc (or Start) pauses and resumes", 12, DIM)
	var right := _vbox(14)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	_score_card(right)
	_loadout_card(right)
	_focus()

func _pause_meta() -> String:
	if game == null or player == null:
		return ""
	var secs := int(game.clock)
	var bits: Array[String] = ["%d:%02d" % [secs / 60, secs % 60], "★ %d / %d" % [player.stars, game.STARS]]
	if game.level and game.level.get("shop_spots") and game.shop_i >= 0 and game.shop_i < game.level.shop_spots.size():
		bits.append("Shop: %s lawn, %s" % Array(String(game.level.shop_spots[game.shop_i].name).split(" ")))
	bits.append("Bots: " + String(Settings.bots).capitalize())
	return "  ·  ".join(bits)

func _score_card(parent: Node) -> void:
	var v := _side_card(parent, "Standings")
	if game == null:
		return
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 26)
	g.add_theme_constant_override("v_separation", 3)
	for t in ["Player", "★", "K", "D"]:
		_label(g, t, 12, DIM, true)
	for f in game.standings():
		var col: Color = BLUE if f == player else (Color(0.55, 0.55, 0.55) if not f.alive else WHITE)
		var n := _label(g, String(f.display_name), 14, col, f == player)
		n.custom_minimum_size.x = 210
		_label(g, str(f.stars), 14, GOLD if f.stars >= 8 else col)
		_label(g, str(f.kills), 14, col)
		_label(g, str(f.deaths), 14, col)
	v.add_child(g)

func _loadout_card(parent: Node) -> void:
	var v := _side_card(parent, "You're carrying")
	if player == null:
		return
	var gun := "—"
	if player.gun_id != "":
		gun = "%s %s  ·  %d left" % [String(player.gun_skin).capitalize(), Weapons.stat(player.gun_id).name, player.ammo]
	var items: Array[String] = []
	if player.has_mine:
		items.append("Mine")
	if player.has_stun:
		items.append("Stun")
	if player.boost_t > 0.0:
		items.append("Boost %d s" % ceili(player.boost_t))
	_pairs(v, [["Bat", String(player.bat_skin).capitalize() + " bat" + ("  ·  hits double" if player.bat_skin == "gold" else "")], ["Gun", gun],
		["Items", ", ".join(items) if not items.is_empty() else "—"]], 70)

# ---------------------------------------------------------------- settings

func show_settings(back: String, which := "") -> void:
	if back != "":
		_back_to = back
	if which != "":
		tab = which
	visible = true
	screen = "settings"
	_preview = null
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 30)
	_set_screen(h)
	# the rail: title, tabs, Controls, Reset all
	var rail := _vbox(4)
	rail.custom_minimum_size.x = 230
	h.add_child(rail)
	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 10)
	var bk := Button.new()
	bk.text = "‹"
	_style_button(bk, false, 18)
	bk.pressed.connect(_go_back)
	title.add_child(bk)
	_label(title, "Settings", 26, WHITE, true)
	rail.add_child(title)
	var gap := Control.new()
	gap.custom_minimum_size.y = 10
	rail.add_child(gap)
	var tab_btn: Button = null
	for t in TABS:
		var id: String = t[0]
		var b := Button.new()
		b.text = String(t[1])
		_style_button(b, false, 15)
		if id == tab:   # the open tab: white bar on the left, bold
			var on := _box(Color(1, 1, 1, 0.1), WHITE, 10, 3)
			on.content_margin_left = 16
			b.add_theme_stylebox_override("normal", on)
			b.add_theme_font_override("font", _bold)
			tab_btn = b
		b.pressed.connect(func(): show_settings("", id))
		rail.add_child(b)
	var gap2 := Control.new()
	gap2.custom_minimum_size.y = 8
	rail.add_child(gap2)
	var ctl := Button.new()
	ctl.text = "Controls  ›"
	_style_button(ctl, false, 14)
	ctl.pressed.connect(func(): show_keys(_back_to))
	rail.add_child(ctl)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail.add_child(fill)
	var rst := Button.new()
	rst.text = "Reset all settings"
	_style_button(rst, false, 13)
	rst.tooltip_text = "Everything on this menu, and your keys"
	rst.pressed.connect(func():
		Settings.reset_all()
		for act in defaults:
			_bind(act, defaults[act], false)
		settings_changed.emit("all")
		show_settings("", tab))
	rail.add_child(rst)
	# the body: heading, options, Back / Resume
	var body := _vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(body)
	for t in TABS:
		if t[0] == tab:
			_eyebrow(body, String(t[1]))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.y = 470
	body.add_child(sc)
	var rows := _vbox(9)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(rows)
	_first = null
	match tab:
		"gfx": _tab_graphics(rows)
		"display": _tab_display(rows)
		"sound": _tab_sound(rows)
		"input": _tab_input(rows)
		"xh": _tab_crosshair(rows)
		"game": _tab_game(rows)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(foot)
	var first := _first
	_button(foot, "‹  Back", _go_back)
	if in_game:
		_button(foot, "Resume", func(): hide_menu(); resume.emit(), true)
	_first = tab_btn if tab_btn else first
	_focus()

func _pct(v: float) -> String:
	return "%d%%" % roundi(v)

func _tab_graphics(p: Node) -> void:
	_row(p, "Quality", "Low is plain and fast; High adds bounce and indirect light, reflections and light shafts",
		_seg([["low", "Low"], ["medium", "Medium"], ["high", "High"]], Settings.quality, func(v):
			Settings.aa = "off" if v == "low" else "msaa2"   # a preset sets anti-aliasing too; change it below after
			_changed("quality", v, "quality")
			show_settings("", "gfx")))
	_opt(p, "Anti-aliasing", "smooths jagged edges; MSAA is the sharpest, TAA the smoothest", "aa",
		[["off", "Off"], ["fxaa", "FXAA"], ["msaa2", "MSAA 2×"], ["msaa4", "MSAA 4×"], ["taa", "TAA"]], "display")
	_opt(p, "Resolution", "the 3D view drawn at a lower resolution and sharpened back up (FSR): faster", "render_scale",
		[[50, "50%"], [67, "67%"], [77, "77%"], [85, "85%"], [100, "100%"]], "display")
	_slide(p, "Field of view", "how wide you see, in degrees", "fov", 60, 110, 1, func(v): return "%d°" % int(v), "view")
	_slide(p, "Brightness", "", "brightness", 50, 150, 5, _pct, "display")
	_opt(p, "Camera", "V switches in a match", "camera_mode", [["third", "Third person"], ["first", "First person"]], "view")

func _tab_display(p: Node) -> void:
	_opt(p, "Window", "borderless fills the screen and switches away quickly", "window_mode",
		[["windowed", "Windowed"], ["borderless", "Borderless"], ["fullscreen", "Full screen"]], "display")
	_onoff(p, "V-sync", "matches the screen's refresh: no tearing, a little more input lag", "vsync", "display")
	_opt(p, "Frame rate limit", "", "max_fps", [[30, "30"], [60, "60"], [120, "120"], [144, "144"], [240, "240"], [0, "None"]], "display")
	_opt(p, "HUD and menu size", "", "ui_scale", [[80, "80%"], [90, "90%"], [100, "100%"], [110, "110%"], [125, "125%"]], "display")
	_onoff(p, "Show FPS", "frames a second, top right", "show_fps")
	_onoff(p, "Controls line", "the keys along the bottom of the screen", "show_help")

func _tab_sound(p: Node) -> void:
	for vol in [["Master", "vol_master", ""], ["Weapons", "vol_weapons", "shots, swings and hits"], ["Effects", "vol_sfx", "footsteps, glass, water, the Mansion"],
			["Music", "vol_music", ""], ["Voice", "vol_voice", ""]]:
		_slide(p, String(vol[0]) + " volume", String(vol[2]), String(vol[1]), 0, 10, 1, func(v): return "%d%%" % (int(v) * 10), "audio")
	_onoff(p, "Hit sound", "a tick when you land a hit (a sharper one for a headshot)", "hit_sound")
	_onoff(p, "Mute in the background", "quiet while you're in another window", "mute_unfocused")

func _tab_input(p: Node) -> void:
	_slide(p, "Mouse sensitivity", "", "sensitivity", 0, 10, 0.5, func(v): return "%.1f" % v)
	_slide(p, "Aim sensitivity", "how fast you look while aiming down sights, against the hip", "ads_sensitivity", 30, 150, 5, _pct)
	_onoff(p, "Invert mouse", "push the mouse forward to look down", "invert_y")
	_opt(p, "Aim", "hold the aim button, or press it once to aim and again to stop", "aim_toggle", [[false, "Hold"], [true, "Toggle"]])
	_opt(p, "Crouch", "", "crouch_hold", [[false, "Toggle"], [true, "Hold"]])
	_slide(p, "Controller look speed", "the right stick", "pad_sensitivity", 0, 10, 0.5, func(v): return "%.1f" % v)
	_onoff(p, "Invert controller", "", "pad_invert_y")
	_opt(p, "Aim assist", "controller only: your aim drifts onto anyone close to it", "aim_assist", [["off", "Off"], ["easy", "Easy bots only"], ["on", "On"]])

func _tab_crosshair(p: Node) -> void:
	# a preview of it on a dark and a light patch, with a hit marker
	var pv := Control.new()
	pv.custom_minimum_size = Vector2(0, 96)
	pv.draw.connect(func():
		var w := pv.size.x * 0.5
		pv.draw_rect(Rect2(0, 0, w, pv.size.y), Color(0.12, 0.13, 0.14))
		pv.draw_rect(Rect2(w, 0, w, pv.size.y), Color(0.78, 0.8, 0.82))
		Crosshair.draw(pv, Vector2(w * 0.5, pv.size.y * 0.5), Settings, 6.0, false, false)
		Crosshair.draw(pv, Vector2(w * 1.5, pv.size.y * 0.5), Settings, 6.0, false, false)
		if Settings.hit_marker:
			Crosshair.draw_hit(pv, Vector2(w * 1.5, pv.size.y * 0.5), Settings, 0.8, false, false))
	p.add_child(pv)
	_preview = pv
	var cols: Array = []
	for c in Crosshair.COLOURS:
		cols.append([c[0], c[1]])
	_opt(p, "Style", "", "xh_style", Crosshair.STYLES)
	_opt(p, "Colour", "", "xh_color", cols)
	_opt(p, "Size", "", "xh_size", [["s", "Small"], ["m", "Medium"], ["l", "Large"]])
	_opt(p, "Thickness", "", "xh_thick", [["s", "Thin"], ["m", "Normal"], ["l", "Thick"]])
	_slide(p, "Opacity", "", "xh_opacity", 30, 100, 5, _pct)
	_onoff(p, "Outline", "a thin dark edge so it shows on bright walls", "xh_outline")
	_onoff(p, "Opens with spread", "the arms move out as your shots spread (moving, jumping, firing)", "xh_dynamic")
	_onoff(p, "Red on target", "turns red when an enemy is under it and in reach", "xh_red")
	_onoff(p, "Hit marker", "an X round it when you land a hit: red for a headshot, bigger when they go down", "hit_marker")
	_onoff(p, "Damage numbers", "how much each hit did, over the player you hit", "dmg_numbers")

func _tab_game(p: Node) -> void:
	_opt(p, "Bots", "Easy: slower to react, wider aim, no headshots; Hard: quick and accurate", "bots",
		[["easy", "Easy"], ["normal", "Normal"], ["hard", "Hard"]], "bots")

func _keys_back() -> void:
	if _keys_from_settings:
		show_settings("")
	else:
		_go_back()

func _go_back() -> void:
	if _back_to == "pause":
		show_pause()
	else:
		show_start()

# ---------------------------------------------------------------- controls

func show_keys(back := "") -> void:
	if screen == "settings":
		_keys_from_settings = true
	elif back != "":
		_keys_from_settings = false
	if back != "":
		_back_to = back
	visible = true
	screen = "keys"
	var v := _vbox(10)
	_set_screen(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	_first = null
	_button(head, "‹  Back", _keys_back)
	var t := _label(head, "Controls", 26, WHITE, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "Reset keys", func():
		Settings.keys = {}
		Settings.save()
		for act in defaults:
			_bind(act, defaults[act], false)
		show_keys())
	_eyebrow(v, "Keys · click one, then press the new key or mouse button (Esc cancels)")
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 36)
	v.add_child(cols)
	var keys_col := _vbox(6)
	keys_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(keys_col)
	var first_key: Button = null
	for g in GROUPS:
		_eyebrow(keys_col, String(g[0]), GOLD)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 18)
		grid.add_theme_constant_override("v_separation", 4)
		for a in g[1]:
			var act: String = a[0]
			var l := _label(grid, String(a[1]), 14, WHITE)
			l.custom_minimum_size.x = 260
			var b := Button.new()
			_style_button(b, false, 14)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.custom_minimum_size.x = 170
			b.text = key_name(act)
			b.pressed.connect(func():
				_waiting = act
				_wait_btn = b
				b.text = "Press a key…")
			grid.add_child(b)
			if first_key == null:
				first_key = b
		keys_col.add_child(grid)
	var pad_col := _side_card(cols, "Controller")
	pad_col.custom_minimum_size.x = 330
	_pairs(pad_col, PAD, 110)
	_key_msg = _label(v, "Picking a key that's already used by something else swaps the two.", 12, DIM)
	_first = first_key
	_focus()

## the first keyboard key or mouse button bound to an action, as text
func key_name(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
		if ev is InputEventMouseButton:
			return ["", "Left mouse", "Right mouse", "Middle mouse", "Wheel up", "Wheel down"][clampi(ev.button_index, 0, 5)] if ev.button_index <= 5 else "Mouse %d" % ev.button_index
	return "—"

func _short(action: String) -> String:
	var k := key_name(action)
	return k.replace("Left mouse", "LMB").replace("Right mouse", "RMB")

func _kb_event(action: String) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null

func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	return false

## replace an action's keyboard/mouse binding (controller bindings stay); if another action already uses that key,
## it gets this action's old one (the two swap)
func _bind(action: String, ev: InputEvent, save := true) -> void:
	var old := _kb_event(action)
	if save and old:
		for g in GROUPS:
			for a in g[1]:
				var other: String = a[0]
				var oe := _kb_event(other)
				if other != action and oe and _same(oe, ev):
					_set_event(other, old, true)
	_set_event(action, ev, save)

func _set_event(action: String, ev: InputEvent, save: bool) -> void:
	for o in InputMap.action_get_events(action):
		if o is InputEventKey or o is InputEventMouseButton:
			InputMap.action_erase_event(action, o)
	InputMap.action_add_event(action, ev)
	if save:
		Settings.keys[action] = ("k:%d" % ev.physical_keycode) if ev is InputEventKey else ("m:%d" % ev.button_index)
		Settings.save()

func _input(e: InputEvent) -> void:
	if _waiting == "":
		if visible and e.is_action_pressed("ui_cancel") and screen in ["settings", "keys"]:
			get_viewport().set_input_as_handled()
			if screen == "keys":
				_keys_back()
			else:
				_go_back()
		return
	var ev: InputEvent = null
	if e is InputEventKey and e.pressed and not e.echo:
		if e.physical_keycode == KEY_ESCAPE:
			_waiting = ""
			show_keys()
			get_viewport().set_input_as_handled()
			return
		var k := InputEventKey.new()
		k.physical_keycode = e.physical_keycode
		ev = k
	elif e is InputEventMouseButton and e.pressed:
		var m := InputEventMouseButton.new()
		m.button_index = e.button_index
		ev = m
	if ev:
		_bind(_waiting, ev)
		_waiting = ""
		get_viewport().set_input_as_handled()
		show_keys.call_deferred()
