extends Control
## Circular minimap (DESIGN §8), top right: a floor plan of the floor you're on, drawn from the Mansion layout and
## turned so you always face up; 60 m across. Marked players (8+ stars) show as a gold 5-point star with a dark
## outline, pinned to the rim when they're out of range. A floor label under it: GROUND / 1ST FLOOR / ROOF.

const SPAN := 60.0           # metres across the circle
const PX_PER_M := 4          # floor plan resolution
const GOLD := Color("#ffc83a")

const SHADER := """
shader_type canvas_item;
uniform sampler2D map : filter_linear;
uniform vec2 me;
uniform vec2 right_v;
uniform vec2 fwd_v;
uniform float span;
uniform vec2 origin;
uniform vec2 size_m;
void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	if (r > 0.5) { discard; }
	vec2 w = me + (p.x * right_v - p.y * fwd_v) * span;
	vec2 uv = (w - origin) / size_m;
	vec3 c = vec3(0.0);
	if (uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0) {
		vec4 m = texture(map, uv);
		c = mix(c, m.rgb, m.a);
	}
	COLOR = vec4(c, 0.66 * smoothstep(0.5, 0.485, r) + 0.0);
}
"""

var player: Node = null
var game: Node = null
var level: Node = null
var font: Font

var _maps: Array[ImageTexture] = []   # ground, first floor, roof
var _rect: ColorRect
var _mat: ShaderMaterial
var _label: Label
var _x0 := -60.0
var _z0 := -45.0
var _w := 120.0
var _d := 90.0

func _ready() -> void:
	custom_minimum_size = Vector2(200, 200)
	size = Vector2(200, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bd: Dictionary = level.layout.get("bounds", {})
	_x0 = float(bd.get("x0", -60))
	_z0 = float(bd.get("z0", -45))
	_w = float(bd.get("x1", 60)) - _x0
	_d = float(bd.get("z1", 45)) - _z0
	_maps = [_plan(0.0, 0.8, 2.2, true), _plan(5.5, 6.6, 7.8, false), _plan(10.9, 11.6, 12.8, false)]
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("span", SPAN)
	_mat.set_shader_parameter("origin", Vector2(_x0, _z0))
	_mat.set_shader_parameter("size_m", Vector2(_w, _d))
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.size = size
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.show_behind_parent = true
	add_child(_rect)
	_label = Label.new()
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(0, 204)
	_label.size = Vector2(200, 16)
	add_child(_label)

## one floor as a picture: the floor slabs (tops between floor_lo and band_lo) in dark grey, then anything standing
## in the band band_lo..band_hi (walls, furniture) in light grey, glass a little darker
func _plan(floor_lo: float, band_lo: float, band_hi: float, ground: bool) -> ImageTexture:
	var img := Image.create(int(_w) * PX_PER_M, int(_d) * PX_PER_M, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var h: Dictionary = level.house
	if ground and not h.is_empty():
		img.fill_rect(_px_rect(-float(h.x), -float(h.z), float(h.x), float(h.z)), Color(0.24, 0.24, 0.24, 1))
	for b in level.layout.boxes:
		var a: Array = b.b
		var top := float(a[4])
		if not ground and top >= floor_lo and top <= band_lo and float(a[4]) - float(a[1]) < 1.0:
			img.fill_rect(_px_rect(a[0], a[2], a[3], a[5]), Color(0.24, 0.24, 0.24, 1))
	for b in level.layout.boxes:
		var a: Array = b.b
		if float(a[1]) < band_hi and float(a[4]) > band_lo:
			var glass: bool = int(b.g) == 1 or b.p == "glass"
			img.fill_rect(_px_rect(a[0], a[2], a[3], a[5]), Color(0.5, 0.55, 0.6, 1) if glass else Color(0.8, 0.8, 0.8, 1))
	return ImageTexture.create_from_image(img)

func _px_rect(x0: float, z0: float, x1: float, z1: float) -> Rect2i:
	var px0 := int((minf(x0, x1) - _x0) * PX_PER_M)
	var pz0 := int((minf(z0, z1) - _z0) * PX_PER_M)
	var px1 := int(ceilf((maxf(x0, x1) - _x0) * PX_PER_M))
	var pz1 := int(ceilf((maxf(z0, z1) - _z0) * PX_PER_M))
	return Rect2i(px0, pz0, maxi(1, px1 - px0), maxi(1, pz1 - pz0))

func floor_index(y: float) -> int:
	return 0 if y < 4.5 else (1 if y < 10.0 else 2)

func _process(_dt: float) -> void:
	if player == null:
		return
	var p: Vector3 = player.global_position
	var fl := floor_index(p.y)
	_mat.set_shader_parameter("map", _maps[fl])
	_mat.set_shader_parameter("me", Vector2(p.x, p.z))
	var r: Vector3 = player.right()
	var f: Vector3 = player.forward()
	_mat.set_shader_parameter("right_v", Vector2(r.x, r.z))
	_mat.set_shader_parameter("fwd_v", Vector2(f.x, f.z))
	_label.text = ["GROUND", "1ST FLOOR", "ROOF"][fl]
	queue_redraw()

func _draw() -> void:
	if player == null:
		return
	var c := size * 0.5
	var rad := size.x * 0.5
	draw_arc(c, rad - 0.5, 0, TAU, 64, Color(0.42, 0.42, 0.42), 1.0, true)
	var k := size.x / SPAN
	var me: Vector3 = player.global_position
	var r: Vector3 = player.right()
	var f: Vector3 = player.forward()
	if game:
		for o in game.fighters:
			if o == player or not o.alive or not o.marked:
				continue
			var d: Vector3 = o.global_position - me
			var s := Vector2(d.x * r.x + d.z * r.z, -(d.x * f.x + d.z * f.z)) * k
			if s.length() > rad - 9.0:
				s = s.normalized() * (rad - 9.0)
			_star(c + s, 8.0)
	# you: a white arrow pointing the way you face
	var tri := PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)])
	draw_colored_polygon(tri, Color(1, 1, 1))
	draw_polyline(tri + PackedVector2Array([tri[0]]), Color(0, 0, 0, 0.7), 1.0, true)

func _star(at: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var rr := r if i % 2 == 0 else r * 0.45
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(at + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, GOLD)
	pts.append(pts[0])
	draw_polyline(pts, Color(0.15, 0.1, 0.0), 1.5, true)
