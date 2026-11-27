extends RefCounted
## The crosshair (Pete, 27 Nov: "improve the target shooting crosshair and options"; 1v1's crosshair options as the
## base): drawn by the HUD, and by the settings menu for its preview.
## - Styles: Cross + dot, Cross, T, Dot, Circle; 1v1's five colours; Small / Medium / Large; Thin / Normal / Thick;
##   opacity; a thin dark outline so it shows on bright walls.
## - With a gun its arms open with your current spread (unless that's turned off); with the bat it's a dot.
## - It turns red when an enemy is under it and in reach (guns 150 m, the bat its reach).
## - Hit marker: an X round it, white for a body hit, red for a headshot, bigger and red when the hit puts them down.

const STYLES := [["crossdot", "Cross + dot"], ["cross", "Cross"], ["tee", "T"], ["dot", "Dot"], ["circle", "Circle"]]
const COLOURS := [["#ffffff", "White"], ["#3dff6e", "Green"], ["#ffe53d", "Yellow"], ["#3de0ff", "Cyan"], ["#ff4fd8", "Pink"]]
const SIZES := {"s": 0.75, "m": 1.0, "l": 1.35}
const THICK := {"s": 1.5, "m": 2.0, "l": 3.0}
const RED := Color(0.95, 0.22, 0.2)

## settings: the Settings node (style, colour, size, thickness, opacity, outline); spread_px: how far the arms open
## (0 = closed); melee: a dot whatever the style; on_target: draw it red
static func draw(ci: CanvasItem, c: Vector2, settings: Node, spread_px: float, melee: bool, on_target: bool) -> void:
	var k: float = SIZES.get(String(settings.xh_size), 1.0)
	var w: float = THICK.get(String(settings.xh_thick), 2.0)
	var a: float = clampf(float(settings.xh_opacity) / 100.0, 0.1, 1.0)
	var col: Color = RED if on_target else Color.html(String(settings.xh_color))
	col.a = a
	var outline: bool = settings.xh_outline
	var ol := Color(0, 0, 0, 0.6 * a)
	var style: String = "dot" if melee else String(settings.xh_style)
	var gap := 4.0 * k + spread_px
	var arm := 8.0 * k
	var dot_r := maxf(1.2, w * 0.75) * (1.0 if k <= 1.0 else 1.15)
	var arms: Array = []
	match style:
		"cross", "crossdot":
			arms = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
		"tee":
			arms = [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN]
	for d in arms:
		var p0: Vector2 = c + d * gap
		var p1: Vector2 = c + d * (gap + arm)
		if outline:
			ci.draw_line(p0 - d, p1 + d, ol, w + 2.0)
		ci.draw_line(p0, p1, col, w)
	if style == "circle":
		var r := gap + arm * 0.6
		if outline:
			ci.draw_arc(c, r, 0.0, TAU, 48, ol, w + 2.0, true)
		ci.draw_arc(c, r, 0.0, TAU, 48, col, w, true)
	if style in ["crossdot", "dot", "circle", "tee"]:
		if outline:
			ci.draw_circle(c, dot_r + 1.0, ol)
		ci.draw_circle(c, dot_r, col)

## the hit marker: t runs 1 → 0 over its life; head: a headshot; down: the hit put them down or finished them
static func draw_hit(ci: CanvasItem, c: Vector2, settings: Node, t: float, head: bool, down: bool) -> void:
	var k: float = SIZES.get(String(settings.xh_size), 1.0)
	var col := RED if head or down else Color(1, 1, 1)
	col.a = clampf(t * 1.4, 0.0, 1.0)
	var big := 1.35 if down else 1.0
	var r0 := (7.0 + 3.0 * (1.0 - t)) * k * big
	var r1 := r0 + 7.0 * k * big
	var w := (2.5 if down else 2.0)
	for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var n: Vector2 = d.normalized()
		ci.draw_line(c + n * r0, c + n * r1, Color(0, 0, 0, col.a * 0.5), w + 2.0)
		ci.draw_line(c + n * r0, c + n * r1, col, w)
