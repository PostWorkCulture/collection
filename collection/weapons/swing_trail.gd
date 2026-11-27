extends MeshInstance3D
## A faint streak behind a swung bat (Pete, 27 Nov: "a more obvious swing"): a ribbon between the bat's tip and the
## middle of its barrel over the last few frames, white and see-through, fading out towards the oldest end. It is
## drawn in the world, so everyone sees it, and it's gone 0.12 s after the swing ends.

const KEEP := 0.12          # seconds of the swing the streak shows
const ALPHA := 0.28

var _pts: Array = []        # [tip, mid, time]
var _clock := 0.0
var _im := ImmediateMesh.new()

func _init() -> void:
	top_level = true
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = m

## call every frame: swinging, and where the tip and the middle of the barrel are now
func track(dt: float, swinging: bool, tip: Vector3, mid: Vector3) -> void:
	_clock += dt
	if swinging:
		_pts.append([tip, mid, _clock])
	while not _pts.is_empty() and _clock - float(_pts[0][2]) > KEEP:
		_pts.pop_front()
	_im.clear_surfaces()
	global_transform = Transform3D.IDENTITY
	if _pts.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in _pts:
		var a := ALPHA * clampf(1.0 - (_clock - float(p[2])) / KEEP, 0.0, 1.0)
		_im.surface_set_color(Color(1, 1, 1, a))
		_im.surface_add_vertex(p[0])
		_im.surface_set_color(Color(1, 1, 1, 0.0))
		_im.surface_add_vertex(p[1])
	_im.surface_end()

func clear() -> void:
	_pts.clear()
	_im.clear_surfaces()
