extends Node3D
## A gold star (DESIGN §3): a chunky 5-point star about 0.85 m across, 0.07 m deep with bevelled edges, gold metal
## (#ffc83a, metalness 0.85, roughness 0.22, emissive #a8700a at 0.55). Floats 1.05 m up, spins 1.6 rad/s, bobs
## ±0.08 m. Nothing under it: no glow disc (Pete, 24 Nov: minimal and clean). It hums quietly in 3D so you can find
## one by ear (approved improvement). No particle bursts when taken (studio rule).
## A `dropped` star is one a player lost: it lies where they fell for 20 s and is never replaced.

const OUTER := 0.425
const INNER := 0.18
const DEPTH := 0.07
const BEVEL := 0.025

static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D
static var _hum: AudioStreamWAV

var dropped := false
var life := 0.0
var active := true
var _spin: MeshInstance3D
var _player: AudioStreamPlayer3D
var _t := randf() * 10.0

func _ready() -> void:
	_spin = MeshInstance3D.new()
	_spin.mesh = star_mesh()
	_spin.material_override = star_material()
	_spin.position.y = 1.05
	add_child(_spin)
	_player = AudioStreamPlayer3D.new()
	_player.stream = hum_stream()
	_player.volume_db = -16.0
	_player.unit_size = 1.6
	_player.max_distance = 11.0
	_player.position.y = 1.05
	add_child(_player)
	_player.play(randf() * 1.9)

func _process(dt: float) -> void:
	_t += dt
	_spin.rotation.y += dt * 1.6
	_spin.position.y = 1.05 + sin(_t * 2.0) * 0.08

## move a map star to a new spot (map stars are reused rather than freed)
func move_to(p: Vector3) -> void:
	global_position = p
	active = true
	visible = true
	if _player and not _player.playing:
		_player.play(randf() * 1.9)

func hide_star() -> void:
	active = false
	visible = false
	if _player:
		_player.stop()

# ---------------------------------------------------------------- shared resources

static func star_material() -> StandardMaterial3D:
	if _mat:
		return _mat
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color("#ffc83a")
	_mat.metallic = 0.85
	_mat.roughness = 0.22
	_mat.emission_enabled = true
	_mat.emission = Color("#a8700a")
	_mat.emission_energy_multiplier = 0.55
	return _mat

## the star outline at a given scale: 10 points alternating outer and inner radius, point up
static func _ring(scale: float, z: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 10:
		var r := (OUTER if i % 2 == 0 else INNER) * scale
		var a := PI * 0.5 + i * PI / 5.0
		pts.append(Vector3(cos(a) * r, sin(a) * r, z))
	return pts

## extruded star with bevelled edges: front and back faces slightly smaller than the rim, joined by sloped bands
static func star_mesh() -> ArrayMesh:
	if _mesh:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat facets catch the light like cut metal
	var face_k := (OUTER - BEVEL) / OUTER
	var rings := [_ring(face_k, DEPTH * 0.5), _ring(1.0, DEPTH * 0.5 - BEVEL * 0.6), _ring(1.0, -DEPTH * 0.5 + BEVEL * 0.6), _ring(face_k, -DEPTH * 0.5)]
	# front and back faces: a fan from the centre
	for side in [0, 3]:
		var ring: PackedVector3Array = rings[side]
		var c := Vector3(0, 0, ring[0].z)
		for i in 10:
			var a: Vector3 = ring[i]
			var b: Vector3 = ring[(i + 1) % 10]
			if side == 0:
				st.add_vertex(c); st.add_vertex(b); st.add_vertex(a)
			else:
				st.add_vertex(c); st.add_vertex(a); st.add_vertex(b)
	# bevel and rim bands between consecutive rings
	for k in 3:
		var r0: PackedVector3Array = rings[k]
		var r1: PackedVector3Array = rings[k + 1]
		for i in 10:
			var j := (i + 1) % 10
			st.add_vertex(r0[i]); st.add_vertex(r0[j]); st.add_vertex(r1[j])
			st.add_vertex(r0[i]); st.add_vertex(r1[j]); st.add_vertex(r1[i])
	st.generate_normals()
	_mesh = st.commit()
	return _mesh

## a soft two-note hum (G3 + D4) with a slow swell, made in code: 2 s, looping
static func hum_stream() -> AudioStreamWAV:
	if _hum:
		return _hum
	var rate := 22050
	var n := rate * 2
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var swell := 0.75 + 0.25 * sin(TAU * 0.5 * t)
		var v := (sin(TAU * 196.0 * t) * 0.55 + sin(TAU * 294.0 * t) * 0.3 + sin(TAU * 392.0 * t) * 0.08) * swell * 0.35
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	_hum = AudioStreamWAV.new()
	_hum.format = AudioStreamWAV.FORMAT_16_BITS
	_hum.mix_rate = rate
	_hum.stereo = false
	_hum.data = data
	_hum.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_hum.loop_begin = 0
	_hum.loop_end = n
	return _hum
