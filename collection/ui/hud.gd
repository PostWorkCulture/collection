extends CanvasLayer
## Combat HUD (phase 2), in the web game's monochrome look: black cards, thin grey edges, white Arial, colour only as
## a highlight. Health and stamina bottom left, weapon and bullets bottom right, kill feed top right (under where the
## minimap goes in phase 3), crosshair that opens with spread, hit marker, floating damage numbers, a red flash when
## you're hurt, and the centre message when you're down or dead.

const Weapons := preload("res://weapons/weapons.gd")
const Sfx := preload("res://audio/sfx.gd")

const WHITE := Color(1, 1, 1)
const GREY := Color(0.62, 0.62, 0.62)
const RED := Color(0.91, 0.27, 0.23)
const EDGE := Color(0.42, 0.42, 0.42)

var player: Node = null
var game: Node = null

var _font: SystemFont
var _help: Label
var _hp_num: Label
var _hp_bar: ColorRect
var _hp_back: ColorRect
var _st_bar: ColorRect
var _hp_title: Label
var _wpn_name: Label
var _wpn_ammo: Label
var _wpn_slots: Label
var _feed: VBoxContainer
var _center: Label
var _center_sub: Label
var _hurt: ColorRect
var _cross: Control
var _hit_t := 0.0
var _hit_head := false
var _shield: Label

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans"])
	_hurt = ColorRect.new()
	_hurt.color = Color(0.75, 0.05, 0.08, 0.0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	_help = _label(12, GREY)
	_help.position = Vector2(16, 12)
	add_child(_help)
	# health card, bottom left
	var hc := _card()
	_pin(hc, Control.PRESET_BOTTOM_LEFT, 20, -20, false, true)
	add_child(hc)
	var hv := VBoxContainer.new()
	hc.add_child(hv)
	var row := HBoxContainer.new()
	hv.add_child(row)
	_hp_title = _label(12, GREY)
	_hp_title.text = "HEALTH"
	_hp_title.custom_minimum_size.x = 70
	row.add_child(_hp_title)
	_hp_num = _label(26, WHITE)
	row.add_child(_hp_num)
	_hp_back = ColorRect.new()
	_hp_back.color = Color(1, 1, 1, 0.12)
	_hp_back.custom_minimum_size = Vector2(230, 6)
	hv.add_child(_hp_back)
	_hp_bar = ColorRect.new()
	_hp_bar.color = WHITE
	_hp_bar.size = Vector2(230, 6)
	_hp_back.add_child(_hp_bar)
	var sb := ColorRect.new()
	sb.color = Color(1, 1, 1, 0.08)
	sb.custom_minimum_size = Vector2(230, 3)
	hv.add_child(sb)
	_st_bar = ColorRect.new()
	_st_bar.color = GREY
	_st_bar.size = Vector2(230, 3)
	sb.add_child(_st_bar)
	# weapon card, bottom right
	var wc := _card()
	_pin(wc, Control.PRESET_BOTTOM_RIGHT, -20, -20, true, true)
	add_child(wc)
	var wv := VBoxContainer.new()
	wv.alignment = BoxContainer.ALIGNMENT_END
	wc.add_child(wv)
	_wpn_name = _label(18, WHITE)
	_wpn_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wv.add_child(_wpn_name)
	_wpn_ammo = _label(30, WHITE)
	_wpn_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wv.add_child(_wpn_ammo)
	_wpn_slots = _label(12, GREY)
	_wpn_slots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wv.add_child(_wpn_slots)
	# kill feed, top right
	_feed = VBoxContainer.new()
	_pin(_feed, Control.PRESET_TOP_RIGHT, -20, 230, true, false)
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_feed)
	# crosshair and hit marker
	_cross = Control.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	add_child(_cross)
	_shield = _label(13, WHITE)
	_shield.text = "SPAWN SHIELD"
	_pin(_shield, Control.PRESET_CENTER, -52, 40, false, false)
	add_child(_shield)
	# centre message: down / eliminated
	_center = _label(40, WHITE)
	_pin(_center, Control.PRESET_CENTER_TOP, -300, 150, false, false)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.custom_minimum_size = Vector2(600, 0)
	add_child(_center)
	_center_sub = _label(16, GREY)
	_pin(_center_sub, Control.PRESET_CENTER_TOP, -300, 202, false, false)
	_center_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_sub.custom_minimum_size = Vector2(600, 0)
	add_child(_center_sub)
	if player:
		player.dealt_hit.connect(_on_dealt_hit)
		player.hurt.connect(_on_hurt)
	if game:
		game.feed_msg.connect(add_feed)

## anchor a control to a corner/edge, `ox, oy` px in from it; grow_*_begin makes it expand towards the screen
func _pin(c: Control, preset: int, ox: float, oy: float, grow_h_begin: bool, grow_v_begin: bool) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if grow_h_begin else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if grow_v_begin else Control.GROW_DIRECTION_END

func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _card() -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0.62)
	s.border_color = EDGE
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func add_feed(text: String, mine: bool) -> void:
	var c := _card()
	var l := _label(14, WHITE if mine else Color(0.85, 0.85, 0.85))
	l.text = text
	c.add_child(l)
	_feed.add_child(c)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tw := c.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(c, "modulate:a", 0.0, 0.6)
	tw.tween_callback(c.queue_free)

func _on_dealt_hit(target: Node, amount: int, head: bool, finished: bool) -> void:
	_hit_t = 0.18
	_hit_head = head or finished
	Sfx.play_ui(self, "headshot" if head else "hit", -6.0, 1.0 if head else 1.05)
	# a floating damage number over them
	var n := Label3D.new()
	n.text = str(amount)
	n.font = _font
	n.font_size = 44
	n.outline_size = 8
	n.modulate = RED if head else WHITE
	n.outline_modulate = Color(0, 0, 0, 0.85)
	n.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.no_depth_test = true
	n.fixed_size = true
	n.pixel_size = 0.0007
	var top: float = 1.0 if target.downed else 2.5
	game.add_child(n)
	n.global_position = target.global_position + Vector3(randf_range(-0.3, 0.3), top, randf_range(-0.3, 0.3))
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "global_position:y", n.global_position.y + 0.8, 0.7)
	tw.tween_property(n, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(n.queue_free)

func _on_hurt(amount: int, _src: Node, _head: bool) -> void:
	_hurt.color.a = clampf(0.1 + amount / 120.0, 0.12, 0.35)
	Sfx.play_ui(self, "hurt", linear_to_db(clampf(amount / 30.0, 0.45, 1.0)) - 4.0)

func _process(dt: float) -> void:
	if player == null:
		return
	_hurt.color.a = maxf(0.0, _hurt.color.a - dt * 1.2)
	_hit_t = maxf(0.0, _hit_t - dt)
	var id: String = player.current_weapon()
	var g := Weapons.stat(id)
	# health
	if player.downed:
		_hp_title.text = "DOWN"
		_hp_title.add_theme_color_override("font_color", RED)
		_hp_num.text = str(ceili(player.dhp))
		_hp_bar.color = RED
		_hp_bar.size.x = 230.0 * clampf(player.dhp / 30.0, 0.0, 1.0)
	else:
		_hp_title.text = "HEALTH"
		_hp_title.add_theme_color_override("font_color", GREY)
		_hp_num.text = str(ceili(player.hp)) if player.alive else "0"
		_hp_bar.color = WHITE if player.hp > 30.0 else RED
		_hp_bar.size.x = 230.0 * clampf(player.hp / 100.0, 0.0, 1.0) if player.alive else 0.0
	_st_bar.size.x = 230.0 * clampf(player.stamina / 100.0, 0.0, 1.0)
	# weapon
	_wpn_name.text = String(g.name).to_upper()
	if Weapons.is_melee(id):
		_wpn_ammo.text = "—"
	else:
		_wpn_ammo.text = "%d / %d" % [player.ammo, Weapons.AMMO]
	_wpn_ammo.add_theme_color_override("font_color", RED if not Weapons.is_melee(id) and player.ammo <= 5 else WHITE)
	var melee_name := "BAT" if player.has_bat else "FISTS"
	var gun_name := String(Weapons.stat(player.gun_id).name).to_upper() if player.gun_id != "" else "—"
	_wpn_slots.text = "1  %s     2  %s" % [melee_name, gun_name]
	# centre messages
	if not player.alive:
		_center.text = "ELIMINATED"
		_center_sub.text = "Respawning in %.0f" % ceilf(maxf(0.0, player.respawn_t))
	elif player.downed:
		_center.text = "YOU'RE DOWN"
		_center_sub.text = "Crawl to cover · back up in %.1f s" % maxf(0.0, 5.0 * (1.0 - player.revive))
	else:
		_center.text = ""
		_center_sub.text = ""
	_shield.visible = player.alive and player.shield_t > 0.0
	_help.text = "imok Collection · Godot grey box (phase 2: combat)\nWASD move · Space jump · C crouch · V camera · LMB attack · RMB aim · 1 fists/bat · 2 gun · wheel swap · G test gun · Esc mouse\n%d fps" % Engine.get_frames_per_second()
	_cross.queue_redraw()

## crosshair: four ticks that open with the gun's current spread; a dot with fists or a bat; hidden when aiming
## down iron sights in first person; the hit marker is an X (red for a headshot or a down)
func _draw_cross() -> void:
	if player == null or not player.alive:
		return
	var c := _cross.size * 0.5
	var id: String = player.current_weapon()
	var outline := Color(0, 0, 0, 0.6)
	var aimed_fp: bool = player.first_person() and player.ads_k > 0.8
	if Weapons.is_melee(id) or player.downed:
		_cross.draw_circle(c, 3.0, outline)
		_cross.draw_circle(c, 2.0, WHITE)
	elif not aimed_fp:
		var fov: float = player.cam.fov
		var gap := tan(deg_to_rad(player.current_spread())) / tan(deg_to_rad(fov * 0.5)) * _cross.size.y * 0.5 + 5.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var a: Vector2 = c + d * gap
			var b: Vector2 = c + d * (gap + 9.0)
			_cross.draw_line(a, b, outline, 4.0)
			_cross.draw_line(a, b, WHITE, 2.0)
	if _hit_t > 0.0:
		var col := RED if _hit_head else WHITE
		col.a = clampf(_hit_t / 0.18, 0.0, 1.0)
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_cross.draw_line(c + d * 7.0, c + d * 14.0, col, 2.0)
