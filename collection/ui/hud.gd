extends CanvasLayer
## The HUD, in the web game's monochrome look: black cards, thin grey edges, white Arial, colour only as a highlight
## (gold #ffc83a for Collection). Phase 2: health and stamina bottom left, weapon and bullets bottom right, kill feed
## under the minimap, crosshair that opens with spread, hit marker, damage numbers, red flash when you're hurt, down
## and eliminated messages. Phase 3 (DESIGN §8): leaderboard top left (all 8 by stars, then kills: Players · ★ · K ·
## D, you in blue, others red, the dead dimmed), count-up clock and goal top centre with the ★ n / 10 counter under it
## (gold border at 10), circular minimap top right, the cash-in bar, a gold screen-edge flash when someone is marked,
## the loading card and countdown, and the win screen followed by the results table.

const Weapons := preload("res://weapons/weapons.gd")
const Minimap := preload("res://ui/minimap.gd")
const Sfx := preload("res://audio/sfx.gd")

const WHITE := Color(1, 1, 1)
const GREY := Color(0.62, 0.62, 0.62)
const RED := Color(0.91, 0.27, 0.23)
const EDGE := Color(0.42, 0.42, 0.42)
const GOLD := Color("#ffc83a")
const BLUE := Color(0.18, 0.5, 0.88)

const EDGE_SHADER := """
shader_type canvas_item;
uniform vec4 tint : source_color;
uniform float amount = 0.0;
void fragment() {
	float d = length((UV - vec2(0.5)) * vec2(1.6, 1.25));
	COLOR = vec4(tint.rgb, tint.a * amount * smoothstep(0.45, 0.95, d));
}
"""

var player: Node = null
var game: Node = null

var _font: SystemFont
var _help: Label
var _perf: Label
var _pf_frames := 0
var _pf_time := 0.0
var _pf_worst := 0.0
var _pf_text := ""
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
var _lb: GridContainer
var _lb_t := 0.0
var _clock: Label
var _score_card: PanelContainer
var _star_card: PanelContainer
var _star_lbl: Label
var _shop_hint: Label
var _cash_card: PanelContainer
var _cash_bar: ColorRect
var _edge_mat: ShaderMaterial
var _edge_t := 0.0
var _msg_t := 0.0
var _msg_title := ""
var _msg_sub := ""
var _load_card: PanelContainer
var _load_bots: Label
var _win: Control
var _win_title: Label
var _win_sub: Label
var _results: GridContainer
var _results_card: PanelContainer
var _again: Label
var _win_t := -1.0
var minimap: Control

func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Arial", "Helvetica", "Liberation Sans"])
	_hurt = ColorRect.new()
	_hurt.color = Color(0.75, 0.05, 0.08, 0.0)
	_hurt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurt)
	_edge_mat = ShaderMaterial.new()
	var esh := Shader.new()
	esh.code = EDGE_SHADER
	_edge_mat.shader = esh
	_edge_mat.set_shader_parameter("tint", GOLD)
	var edge := ColorRect.new()
	edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.material = _edge_mat
	add_child(edge)
	# F3: performance readout (AAA plan phase 0) under the players card
	_perf = _label(12, Color(0.85, 0.9, 0.85, 0.95))
	_pin(_perf, Control.PRESET_TOP_LEFT, 20, 96, false, false)
	_perf.visible = false
	add_child(_perf)
	_help = _label(11, Color(0.6, 0.6, 0.6, 0.8))
	_pin(_help, Control.PRESET_CENTER_BOTTOM, -400, -16, false, true)
	_help.custom_minimum_size.x = 800
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_help)
	_build_phase3()
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
	_pin(_feed, Control.PRESET_TOP_RIGHT, -20, 250, true, false)
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
## fps, average and worst frame time over the last second, and what the renderer drew (F3)
func _perf_tick(dt: float) -> void:
	var on: bool = game != null and game.debug
	_perf.visible = on
	_pf_frames += 1
	_pf_time += dt
	_pf_worst = maxf(_pf_worst, dt)
	if _pf_time >= 1.0:
		_pf_text = "%d fps · %.1f ms avg · %.1f ms worst\n%d draw calls · %.0fk triangles · %d objects\nVRAM %.0f MB" % [
			_pf_frames, 1000.0 * _pf_time / _pf_frames, 1000.0 * _pf_worst,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0]
		_pf_frames = 0
		_pf_time = 0.0
		_pf_worst = 0.0
	if on:
		_perf.text = _pf_text

func _pin(c: Control, preset: int, ox: float, oy: float, grow_h_begin: bool, grow_v_begin: bool) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if grow_h_begin else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if grow_v_begin else Control.GROW_DIRECTION_END

## leaderboard, scoreboard and star counter, minimap, cash-in bar, loading card, win screen
func _build_phase3() -> void:
	# leaderboard, top left
	var lc := _card()
	_pin(lc, Control.PRESET_TOP_LEFT, 20, 20, false, false)
	add_child(lc)
	_lb = GridContainer.new()
	_lb.columns = 4
	_lb.add_theme_constant_override("h_separation", 14)
	_lb.add_theme_constant_override("v_separation", 2)
	lc.add_child(_lb)
	# scoreboard: clock and goal, top centre; the star counter under it
	var sc := _card()
	_score_card = sc
	_pin(sc, Control.PRESET_CENTER_TOP, -80, 20, false, false)
	sc.custom_minimum_size.x = 160
	add_child(sc)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 0)
	sc.add_child(sv)
	_clock = _label(26, WHITE)
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(_clock)
	var goal := _label(11, GREY)
	goal.text = "CASH IN 10 STARS"
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sv.add_child(goal)
	_star_card = _card()
	_pin(_star_card, Control.PRESET_CENTER_TOP, -60, 100, false, false)
	_star_card.custom_minimum_size.x = 120
	add_child(_star_card)
	_star_lbl = _label(24, WHITE)
	_star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_star_card.add_child(_star_lbl)
	_shop_hint = _label(14, GOLD)
	_shop_hint.text = "Cash in at the shop outside"
	_pin(_shop_hint, Control.PRESET_CENTER_TOP, -150, 152, false, false)
	_shop_hint.custom_minimum_size.x = 300
	_shop_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_shop_hint)
	# minimap, top right (the kill feed sits under it)
	minimap = Minimap.new()
	minimap.player = player
	minimap.game = game
	minimap.level = game.level if game else null
	minimap.font = _font
	_pin(minimap, Control.PRESET_TOP_RIGHT, -220, 20, false, false)
	add_child(minimap)
	# cash-in bar, low centre
	_cash_card = _card()
	_pin(_cash_card, Control.PRESET_CENTER_BOTTOM, -130, -130, false, true)
	_cash_card.custom_minimum_size.x = 260
	add_child(_cash_card)
	var cv := VBoxContainer.new()
	_cash_card.add_child(cv)
	var ct := _label(13, GOLD)
	ct.text = "CASHING IN · STAND STILL"
	ct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(ct)
	var cb := ColorRect.new()
	cb.color = Color(1, 1, 1, 0.12)
	cb.custom_minimum_size = Vector2(230, 6)
	cv.add_child(cb)
	_cash_bar = ColorRect.new()
	_cash_bar.color = GOLD
	_cash_bar.size = Vector2(0, 6)
	cb.add_child(_cash_bar)
	# loading card during the countdown
	_load_card = _card()
	_pin(_load_card, Control.PRESET_CENTER, -330, -150, false, false)
	_load_card.custom_minimum_size.x = 660
	add_child(_load_card)
	var lv := VBoxContainer.new()
	_load_card.add_child(lv)
	var l1 := _label(22, WHITE)
	l1.text = "COLLECTION · 8 PLAYERS · THE MANSION"
	l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(l1)
	var l2 := _label(14, GREY)
	l2.text = "Start with fists · find 10 hidden stars · cash them in at the shop outside · first to cash in wins"
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(l2)
	_load_bots = _label(13, GREY)
	_load_bots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(_load_bots)
	# win screen and results
	_win = Control.new()
	_win.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win.visible = false
	add_child(_win)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_win.add_child(dim)
	_win_title = _label(64, WHITE)
	_pin(_win_title, Control.PRESET_CENTER_TOP, -400, 120, false, false)
	_win_title.custom_minimum_size.x = 800
	_win_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win.add_child(_win_title)
	_win_sub = _label(18, GOLD)
	_pin(_win_sub, Control.PRESET_CENTER_TOP, -400, 205, false, false)
	_win_sub.custom_minimum_size.x = 800
	_win_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_win.add_child(_win_sub)
	_results_card = _card()
	_pin(_results_card, Control.PRESET_CENTER, -200, -110, false, false)
	_results_card.custom_minimum_size.x = 400
	_results_card.visible = false
	_win.add_child(_results_card)
	var rv := VBoxContainer.new()
	_results_card.add_child(rv)
	var rt := _label(14, GREY)
	rt.text = "RESULTS"
	rv.add_child(rt)
	_results = GridContainer.new()
	_results.columns = 4
	_results.add_theme_constant_override("h_separation", 24)
	rv.add_child(_results)
	_again = _label(14, GREY)
	_again.text = "Enter: play again · Esc: menu"
	_again.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_again)
	if game:
		game.center_msg.connect(_on_center_msg)
		game.leader_marked.connect(func(_f): _edge_t = 1.4)
		game.won.connect(_on_won)

func _on_center_msg(title: String, sub: String, secs: float) -> void:
	_msg_title = title
	_msg_sub = sub
	_msg_t = secs

func _on_won(f: Node) -> void:
	_win.visible = true
	_win_t = 0.0
	_win_title.text = "VICTORY" if f.is_player else "%s WINS" % String(f.display_name).to_upper()
	_win_sub.text = "cashed in %d stars" % game.STARS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## fill a 4-column grid with Players · ★ · K · D for everyone, most stars first
func _fill_table(grid: GridContainer, size: int) -> void:
	for c in grid.get_children():
		c.queue_free()
	for h in ["PLAYERS", "★", "K", "D"]:
		var hl := _label(size - 2, GREY)
		hl.text = h
		grid.add_child(hl)
	for f in game.standings():
		var col: Color = BLUE if f.is_player else RED
		if not f.alive:
			col = col.darkened(0.55)
		var cells := [f.display_name, str(f.stars), str(f.kills), str(f.deaths)]
		for i in 4:
			var l := _label(size, col if i == 0 else (GOLD if i == 1 and f.marked else (WHITE if f.alive else GREY)))
			l.text = cells[i]
			if i > 0:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			grid.add_child(l)

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
	_perf_tick(dt)
	_help.text = "imok Collection · Godot · WASD move · Space jump · C crouch · V camera · LMB attack · RMB aim · 1 fists/bat · 2 gun · F3 bot view · Esc pause · %d fps" % Engine.get_frames_per_second()
	_process_phase3(dt)
	_cross.queue_redraw()

func _process_phase3(dt: float) -> void:
	if game == null:
		return
	_lb_t -= dt
	if _lb_t <= 0.0:
		_lb_t = 0.25
		_fill_table(_lb, 13)
	var secs := int(game.clock)
	_clock.text = "%d:%02d" % [secs / 60, secs % 60]
	var n: int = player.stars
	_star_lbl.text = "★ %d / %d" % [n, game.STARS]
	_star_lbl.add_theme_color_override("font_color", GOLD if n > 0 else WHITE)
	var st := _star_card.get_theme_stylebox("panel") as StyleBoxFlat
	st.border_color = GOLD if n >= game.STARS else EDGE
	st.set_border_width_all(2 if n >= game.STARS else 1)
	_shop_hint.visible = n >= game.STARS and game.state == "fight"
	var cp: float = game.cash_progress(player)
	_cash_card.visible = cp > 0.0 and game.state == "fight"
	_cash_bar.size.x = 230.0 * cp
	_edge_t = maxf(0.0, _edge_t - dt)
	_edge_mat.set_shader_parameter("amount", clampf(_edge_t / 1.4, 0.0, 1.0) * 0.9)
	_load_card.visible = game.state == "countdown"
	_load_bots.text = "Bots: %s" % String(Settings.bots).capitalize()
	_msg_t -= dt
	# centre message: down / eliminated win over timed messages; the countdown shows its number
	if player.alive and not player.downed and game.state != "won":
		if game.state == "countdown":
			_center.text = str(ceili(game.countdown))
			_center_sub.text = ""
		elif _msg_t > 0.0:
			_center.text = _msg_title
			_center_sub.text = _msg_sub
	if _win_t >= 0.0:
		_win_t += dt
		_center.text = ""
		_center_sub.text = ""
		_score_card.visible = false   # the win title takes the top of the screen
		_star_card.visible = false
		_shop_hint.visible = false
		if _win_t > 2.5 and not _results_card.visible:
			_results_card.visible = true
			_fill_table(_results, 16)

## crosshair: four ticks that open with the gun's current spread; a dot with fists or a bat; hidden when aiming
## down iron sights in first person; the hit marker is an X (red for a headshot or a down)
func _draw_cross() -> void:
	if player == null or not player.alive or (game and game.state == "won"):
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
