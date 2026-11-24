extends CanvasLayer
## Menus (phase 5), in the HUD's monochrome look (black cards, thin grey edges, white Arial):
## - Start screen: PLAY, BOTS (Easy / Normal / Hard), SETTINGS, QUIT, over the Mansion.
## - Pause (Esc / Start): RESUME, SETTINGS, QUIT TO MENU.
## - Settings: graphics quality, field of view, camera, sensitivity 0–10, volumes in 10% steps, KEYS…
## - Keys: every action with its key or mouse button; click one, press the new key (Esc cancels); RESET.
## Works with mouse, keyboard or a controller (D-pad / stick to move, A to choose, B to go back).
## Runs while the game is paused.

signal play
signal resume
signal quit_to_menu
signal settings_changed(what: String)

const WHITE := Color(1, 1, 1)
const GREY := Color(0.62, 0.62, 0.62)
const EDGE := Color(0.42, 0.42, 0.42)
const GOLD := Color("#ffc83a")

## actions you can rebind, in the order shown, with their names
const ACTIONS := [
	["move_forward", "Forward"], ["move_back", "Back"], ["move_left", "Left"], ["move_right", "Right"],
	["jump", "Jump"], ["crouch", "Crouch"], ["fire", "Attack"], ["aim", "Aim"],
	["weapon_melee", "Fists / bat"], ["weapon_gun", "Gun"], ["camera_toggle", "Camera"],
]

var defaults := {}        # action -> its first keyboard/mouse event as set up by main.gd (for RESET)
var screen := ""
var in_game := false      # pause menu vs start screen
var _font: SystemFont
var _dim: ColorRect
var _box: VBoxContainer
var _card: PanelContainer
var _waiting := ""        # action waiting for a new key
var _wait_btn: Button
var _back_to := ""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans"])
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_card = PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0, 0, 0, 0.78)
	st.border_color = EDGE
	st.set_border_width_all(1)
	st.set_corner_radius_all(3)
	st.set_content_margin_all(28)
	_card.add_theme_stylebox_override("panel", st)
	_card.custom_minimum_size.x = 460
	center.add_child(_card)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_card.add_child(_box)
	hide_menu()

func hide_menu() -> void:
	screen = ""
	visible = false

# ---------------------------------------------------------------- building blocks

func _clear() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()

func _label(text: String, size: int, col: Color, center := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(l)
	return l

func _style(b: Button) -> void:
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.08) if state != "normal" else Color(0, 0, 0, 0.0)
		s.border_color = WHITE if state in ["hover", "focus", "pressed"] else EDGE
		s.set_border_width_all(1)
		s.set_corner_radius_all(2)
		s.set_content_margin_all(9)
		b.add_theme_stylebox_override(state, s)
	b.add_theme_color_override("font_color", WHITE)
	b.add_theme_color_override("font_hover_color", WHITE)
	b.add_theme_color_override("font_focus_color", WHITE)

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	_style(b)
	b.pressed.connect(cb)
	_box.add_child(b)
	return b

## a row: name on the left, a control on the right
func _row(name: String, ctrl: Control) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = name
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", GREY)
	l.custom_minimum_size.x = 170
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ctrl)
	_box.add_child(h)

func _slider(lo: float, hi: float, step: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(180, 24)
	s.value_changed.connect(cb)
	return s

func _cycle(options: Array, current: String, cb: Callable) -> Button:
	var b := Button.new()
	_style(b)
	b.text = String(current).capitalize()
	b.pressed.connect(func():
		var i := (options.find(b.text.to_lower()) + 1) % options.size()
		b.text = String(options[i]).capitalize()
		cb.call(options[i]))
	return b

func _focus_first() -> void:
	for c in _box.get_children():
		var b: Control = c if c is Button else null
		if b == null and c is HBoxContainer:
			b = c.get_child(1)
		if b and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus.call_deferred()
			return

# ---------------------------------------------------------------- screens

func show_start() -> void:
	in_game = false
	visible = true
	screen = "start"
	_dim.color = Color(0, 0, 0, 0.45)
	_clear()
	_label("COLLECTION", 46, WHITE)
	_label("8 players · The Mansion", 15, GREY)
	_label("Start with fists, find 10 hidden stars, cash them in at the shop outside. First to cash in wins.", 14, GREY)
	_box.add_child(HSeparator.new())
	_button("PLAY", func(): hide_menu(); play.emit())
	var bots := _cycle(["easy", "normal", "hard"], Settings.bots, func(v):
		Settings.bots = v
		Settings.save()
		settings_changed.emit("bots"))
	_row("Bots", bots)
	_button("SETTINGS", func(): show_settings("start"))
	_button("QUIT", func(): get_tree().quit())
	_focus_first()

func show_pause() -> void:
	in_game = true
	visible = true
	screen = "pause"
	_dim.color = Color(0, 0, 0, 0.55)
	_clear()
	_label("PAUSED", 34, WHITE)
	_box.add_child(HSeparator.new())
	_button("RESUME", func(): hide_menu(); resume.emit())
	_button("SETTINGS", func(): show_settings("pause"))
	_button("QUIT TO MENU", func(): hide_menu(); quit_to_menu.emit())
	_focus_first()

func show_settings(back: String) -> void:
	_back_to = back
	visible = true
	screen = "settings"
	_clear()
	_label("SETTINGS", 30, WHITE)
	_box.add_child(HSeparator.new())
	_row("Graphics", _cycle(["low", "medium", "high"], Settings.quality, func(v):
		Settings.quality = v
		Settings.save()
		settings_changed.emit("quality")))
	_row("Field of view", _slider(60, 100, 1, Settings.fov, func(v):
		Settings.fov = v
		Settings.save()
		settings_changed.emit("view")))
	_row("Camera", _cycle(["third", "first"], Settings.camera_mode, func(v):
		Settings.camera_mode = v
		Settings.save()
		settings_changed.emit("view")))
	_row("Sensitivity", _slider(0, 10, 1, Settings.sensitivity, func(v):
		Settings.sensitivity = v
		Settings.save()))
	for vol in [["Master", "vol_master"], ["Weapons", "vol_weapons"], ["Effects", "vol_sfx"], ["Music", "vol_music"], ["Voice", "vol_voice"]]:
		var prop: String = vol[1]
		_row(vol[0] + " volume", _slider(0, 10, 1, float(Settings.get(prop)), func(v):
			Settings.set(prop, int(v))
			Settings.save()
			settings_changed.emit("audio")))
	_button("KEYS…", func(): show_keys())
	_button("BACK", func(): _go_back())
	_focus_first()

func _go_back() -> void:
	if _back_to == "pause":
		show_pause()
	else:
		show_start()

func show_keys() -> void:
	screen = "keys"
	_clear()
	_label("KEYS", 30, WHITE)
	_label("Click one, then press the new key or mouse button (Esc cancels)", 13, GREY)
	_box.add_child(HSeparator.new())
	for a in ACTIONS:
		var act: String = a[0]
		var b := Button.new()
		_style(b)
		b.text = key_name(act)
		b.pressed.connect(func():
			_waiting = act
			_wait_btn = b
			b.text = "Press a key…")
		_row(a[1], b)
	_button("RESET TO DEFAULTS", func():
		Settings.keys = {}
		Settings.save()
		for act2 in defaults:
			_bind(act2, defaults[act2], false)
		show_keys())
	_button("BACK", func(): show_settings(_back_to))
	_focus_first()

## the first keyboard key or mouse button bound to an action, as text
func key_name(action: String) -> String:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			return OS.get_keycode_string(ev.physical_keycode)
		if ev is InputEventMouseButton:
			return ["", "Left mouse", "Right mouse", "Middle mouse", "Wheel up", "Wheel down"][clampi(ev.button_index, 0, 5)] if ev.button_index <= 5 else "Mouse %d" % ev.button_index
	return "—"

## replace an action's keyboard/mouse binding (controller bindings stay)
func _bind(action: String, ev: InputEvent, save := true) -> void:
	for old in InputMap.action_get_events(action):
		if old is InputEventKey or old is InputEventMouseButton:
			InputMap.action_erase_event(action, old)
	InputMap.action_add_event(action, ev)
	if save:
		Settings.keys[action] = ("k:%d" % ev.physical_keycode) if ev is InputEventKey else ("m:%d" % ev.button_index)
		Settings.save()

func _input(e: InputEvent) -> void:
	if _waiting == "":
		if visible and e.is_action_pressed("ui_cancel") and screen in ["settings", "keys"]:
			get_viewport().set_input_as_handled()
			if screen == "keys":
				show_settings(_back_to)
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
