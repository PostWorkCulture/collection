extends RefCounted
## Simple block models for the held weapons and pickups (grey-box stage: real gun models come with the art pass).
## Every gun points down its local -Z and has a "Muzzle" marker at the barrel tip ("Muzzle2" for the second pistol).
## Sizes are real-world: an MP5 is about 0.55 m long.

const Weapons := preload("res://weapons/weapons.gd")

static var _mats := {}

static func _mat(c: Color, metal := 0.6, rough := 0.35) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f" % [c.to_html(), metal, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	_mats[key] = m
	return m

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _cyl(parent: Node3D, r: float, len: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = len
	cm.radial_segments = 12
	mi.mesh = cm
	mi.position = pos
	mi.rotation.x = PI * 0.5   # lie along Z
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func _muzzle(parent: Node3D, pos: Vector3, nm := "Muzzle") -> void:
	var m := Marker3D.new()
	m.name = nm
	m.position = pos
	parent.add_child(m)

## the six weapon skins from imok 1v1 (its BAT_SKINS): every bat and every gun gets one at random. Gold is the lucky
## one: a gold bat hits twice as hard (Pete, 26 Nov). Textures from tools/weapon_skins/make_textures.py.
const SKINS := ["classic", "gold", "toxic", "candy", "galaxy", "lava"]
const SKIN_NAMES := {"classic": "", "gold": "Gold", "toxic": "Toxic", "candy": "Candy", "galaxy": "Galaxy", "lava": "Lava"}
const SKIN_DEF := {   # part: [colour, roughness, metallic, emission colour, emission strength, texture]
	"classic": {"body": ["#f4f5f7", 0.22, 0.25], "band": ["#d81e28", 0.3, 0.35], "ring": ["#111214", 0.35, 0.0], "wire": ["#b7bcc4", 0.28, 1.0]},
	"gold": {"body": ["#ffffff", 0.14, 0.45, "#ffffff", 0.8, "gold"], "band": ["#ffffff", 0.12, 0.3, "#fff4c8", 0.75],
		"ring": ["#fff1a8", 0.1, 0.6, "#ffc21a", 0.9], "wire": ["#fff0a0", 0.15, 0.6, "#ffb000", 0.7]},
	"toxic": {"body": ["#7dff3a", 0.3, 0.1, "#3cff00", 0.45], "band": ["#9b30ff", 0.3, 0.3, "#5a00b0", 0.6],
		"ring": ["#111214", 0.35, 0.0], "wire": ["#e4ff5a", 0.25, 0.9]},
	"candy": {"body": ["#ff4fb8", 0.22, 0.15], "band": ["#ffe14d", 0.3, 0.2], "ring": ["#ffffff", 0.3, 0.0], "wire": ["#ffffff", 0.25, 0.8]},
	"galaxy": {"body": ["#ffffff", 0.45, 0.1, "#ffffff", 0.35, "galaxy"], "band": ["#29f0ff", 0.2, 0.4, "#00c8ff", 0.8],
		"ring": ["#ff4fd8", 0.3, 0.0, "#b0007a", 0.5], "wire": ["#d4c4ff", 0.2, 1.0]},
	"lava": {"body": ["#ffffff", 0.55, 0.1, "#ffffff", 1.1, "lava"], "band": ["#ff5a00", 0.35, 0.0, "#ff3c00", 1.0],
		"ring": ["#ffb020", 0.3, 0.0, "#ff7a00", 0.8], "wire": ["#3a3633", 0.45, 0.9]},
}
const GLITTER := """shader_type spatial;
// the Gold skin: polished gold with flecks of glitter that twinkle as it moves
uniform sampler2D tex : source_color, filter_linear_mipmap;
varying vec3 lp;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void vertex() { lp = VERTEX; }
void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float h = hash(floor(lp * 260.0));
	float flake = step(0.86, h);
	float tw = pow(max(0.0, sin(TIME * 3.0 + h * 50.0)), 14.0);
	ALBEDO = c;
	METALLIC = 0.35;
	ROUGHNESS = mix(0.24, 0.06, flake);
	EMISSION = c * 0.5 + vec3(1.0, 0.92, 0.7) * flake * tw * 3.0;
}"""

static func skin_mat(skin: String, part: String) -> Material:
	var key := "skin_%s_%s" % [skin, part]
	if _mats.has(key):
		return _mats[key]
	var d: Array = (SKIN_DEF.get(skin, SKIN_DEF.classic) as Dictionary)[part]
	var m: Material
	if part == "body" and d.size() > 5 and d[5] == "gold":
		var sm := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = GLITTER
		sm.shader = sh
		sm.set_shader_parameter("tex", load("res://weapons/skins/gold.png"))
		m = sm
	else:
		var st := StandardMaterial3D.new()
		st.albedo_color = Color.html(d[0])
		st.roughness = d[1]
		st.metallic = d[2]
		if d.size() > 4:
			st.emission_enabled = true
			st.emission = Color.html(d[3])
			st.emission_energy_multiplier = d[4]
		if d.size() > 5:
			var t := load("res://weapons/skins/%s.png" % d[5]) as Texture2D
			st.albedo_texture = t
			st.emission_texture = t
			st.emission = Color(1, 1, 1)
			st.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY   # (add would wash it out white)
		m = st
	_mats[key] = m
	return m

static func tape_mat(skin: String) -> Material:
	var key := "tape_" + skin
	if not _mats.has(key):
		var st := StandardMaterial3D.new()
		st.albedo_texture = load("res://weapons/skins/tape_%s.png" % skin)
		st.roughness = 0.8
		st.uv1_scale = Vector3(1, 3, 1)
		_mats[key] = st
	return _mats[key]

# ---- the bat (1v1's barbed-wire bat): a turned body, grip tape, a band and ring, and two coils of barbed wire
const BAT_LEN := 1.3     # (Pete, 27 Nov: bigger, so the swing and its reach read clearly; was 1.0, before that 0.82)
const BAT_RK := 1.55     # the web profile's radii scaled to our length
static var _bat_meshes := {}

static func _bat_prof(t: float) -> float:
	if t < 0.025:
		return 0.028
	if t < 0.04:
		return 0.026 - (t - 0.025) * 0.6
	var x := (t - 0.04) / 0.96
	if x < 0.42:
		return 0.0165 + x * 0.012
	if x < 0.72:
		var k := (x - 0.42) / 0.3
		return 0.0215 + k * k * (3.0 - 2.0 * k) * 0.0175
	if x < 0.97:
		return 0.039 + (x - 0.72) * 0.006
	return 0.0405 * sqrt(maxf(0.0, 1.0 - pow((x - 0.97) / 0.03, 2.0))) + 0.001

## a turned piece from a to b along the bat (t 0..1), padded out by pad; it runs up local +Y from the hand
static func _lathe(a: float, b: float, pad: float, n: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 24
	var z0 := 0.12
	for i in n:
		var t0 := a + (b - a) * float(i) / n
		var t1 := a + (b - a) * float(i + 1) / n
		var r0 := _bat_prof(t0) * BAT_RK + pad
		var r1 := _bat_prof(t1) * BAT_RK + pad
		var y0 := (t0 - z0) * BAT_LEN
		var y1 := (t1 - z0) * BAT_LEN
		var slope := (r0 - r1) / maxf(0.0001, y1 - y0)
		for j in seg:
			var a0 := TAU * float(j) / seg
			var a1 := TAU * float(j + 1) / seg
			var p := [Vector3(cos(a0) * r0, y0, sin(a0) * r0), Vector3(cos(a1) * r0, y0, sin(a1) * r0),
				Vector3(cos(a1) * r1, y1, sin(a1) * r1), Vector3(cos(a0) * r1, y1, sin(a0) * r1)]
			var nr := [Vector3(cos(a0), slope, sin(a0)).normalized(), Vector3(cos(a1), slope, sin(a1)).normalized()]
			var uv := [Vector2(float(j) / seg, t0), Vector2(float(j + 1) / seg, t0), Vector2(float(j + 1) / seg, t1), Vector2(float(j) / seg, t1)]
			for k in [0, 2, 1, 0, 3, 2]:
				st.set_normal(nr[0] if k == 0 or k == 3 else nr[1])
				st.set_uv(uv[k])
				st.add_vertex(p[k])
	return st.commit()

## the two coils of barbed wire, with barbs, as one mesh
static func _wire() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var z0 := 0.12
	var tube := func(pts: Array, rad: float) -> void:
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var dir := (b - a).normalized()
			var u := dir.cross(Vector3.UP).normalized() if absf(dir.y) < 0.95 else dir.cross(Vector3.RIGHT).normalized()
			var v := dir.cross(u)
			for j in 5:
				var q0 := TAU * j / 5.0
				var q1 := TAU * (j + 1) / 5.0
				var o0 := (u * cos(q0) + v * sin(q0)) * rad
				var o1 := (u * cos(q1) + v * sin(q1)) * rad
				for w in [[a + o0, o0], [b + o1, o1], [a + o1, o1], [a + o0, o0], [b + o0, o0], [b + o1, o1]]:
					st.set_normal((w[1] as Vector3).normalized())
					st.add_vertex(w[0])
	for coil in [[0.52, 0.64, 3], [0.76, 0.93, 4]]:
		var pts: Array = []
		var n: int = int(coil[2]) * 24
		for i in n + 1:
			var u := float(i) / n
			var t: float = coil[0] + (coil[1] - coil[0]) * u
			var an := u * TAU * float(coil[2])
			var r := _bat_prof(t) * BAT_RK + 0.005
			var p := Vector3(cos(an) * r, (t - z0) * BAT_LEN, sin(an) * r)
			pts.append(p)
			if i % 8 == 4:   # a barb: a little spike out each side of the wire
				for side in [-0.5, 0.5]:
					var out := Vector3(cos(an), side, sin(an)).normalized()
					tube.call([p, p + out * 0.04], 0.0018)
		tube.call(pts, 0.0035)
	return st.commit()

static func _bat(root: Node3D, skin: String) -> void:
	if _bat_meshes.is_empty():
		_bat_meshes = {"body": _lathe(0.0, 1.0, 0.0, 90), "grip": _lathe(0.04, 0.33, 0.0025, 24), "band": _lathe(0.62, 0.7, 0.0022, 8),
			"ring": _lathe(0.705, 0.725, 0.0022, 4), "cap": _lathe(0.965, 1.0, 0.001, 6), "wire": _wire()}
	var bat := Node3D.new()
	bat.name = "Bat"
	bat.rotation.x = -1.05   # angled up from the hand (fighter.gd's BAT_TILT)
	root.add_child(bat)
	for part in [["body", "body"], ["grip", "tape"], ["band", "band"], ["ring", "ring"], ["cap", "band"], ["wire", "wire"]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _bat_meshes[part[0]]
		mi.material_override = tape_mat(skin) if part[1] == "tape" else skin_mat(skin, part[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bat.add_child(mi)
	for mark in [["Tip", 0.98], ["Mid", 0.55]]:   # for the swing streak (weapons/swing_trail.gd)
		var n := Node3D.new()
		n.name = mark[0]
		n.position = Vector3(0, (float(mark[1]) - 0.12) * BAT_LEN, 0)
		bat.add_child(n)

## skin: one of SKINS (the bat's or the gun's finish)
static func make(id: String, skin := "classic") -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_" + id
	var black: Material = _mat(Color(0.07, 0.07, 0.08), 0.5, 0.45)
	var steel := _mat(Color(0.32, 0.33, 0.35), 0.9, 0.25)
	var g := Weapons.stat(id)
	var accent: Material = _mat(Color.html(g.get("color", "#888888")), 0.35, 0.3)
	if skin != "classic" and skin in SKINS:   # a skinned gun: its coloured body takes the skin, the trim its band colour
		accent = skin_mat(skin, "body")
		black = skin_mat(skin, "ring") if skin in ["gold", "galaxy", "lava"] else black
	match id:
		"fists", "":
			pass
		"bat":
			_bat(root, skin)
		"duals":
			for side in [-1.0, 1.0]:
				var p := Node3D.new()   # each pistol its own node, so a character can hold one in each hand
				p.name = "PistolR" if side > 0.0 else "PistolL"
				p.position = Vector3(0.11 * side, 0, 0)
				root.add_child(p)
				_box(p, Vector3(0.035, 0.045, 0.2), Vector3(0, 0.02, -0.06), steel)
				_box(p, Vector3(0.032, 0.11, 0.05), Vector3(0, -0.05, 0.0), black)
				_box(p, Vector3(0.036, 0.012, 0.16), Vector3(0, 0.048, -0.06), accent)
				_muzzle(p, Vector3(0, 0.02, -0.17), "Muzzle" if side < 0 else "Muzzle2")
		"crossbow":   # 1v1's crossbow (its gunModel 'crossbow' at our scale, facing -z): stock, limbs, rail, grip, string, a bolt
			_box(root, Vector3(0.066, 0.077, 0.45), Vector3(0, 0, -0.11), black)
			_box(root, Vector3(0.42, 0.028, 0.066), Vector3(0, 0.022, -0.3), accent)
			_box(root, Vector3(0.017, 0.017, 0.385), Vector3(0, 0.05, -0.25), steel)
			_box(root, Vector3(0.033, 0.088, 0.055), Vector3(0, -0.072, 0.028), black)
			_box(root, Vector3(0.05, 0.06, 0.16), Vector3(0, -0.01, 0.17), black)   # shoulder stock
			for side in [-1.0, 1.0]:   # the string, from each limb tip back to the latch
				var st := _box(root, Vector3(0.004, 0.004, 0.27), Vector3(side * 0.105, 0.04, -0.21), _mat(Color(0.85, 0.85, 0.8), 0.0, 0.6))
				st.rotation.y = side * -0.95
			_cyl(root, 0.0055, 0.4, Vector3(0, 0.062, -0.29), _mat(Color(0.14, 0.15, 0.17), 0.4, 0.45))   # the bolt on the rail
			var nock := _cyl(root, 0.008, 0.012, Vector3(0, 0.062, -0.08), _mat(Color("#3bff7a"), 0.0, 0.4))
			(nock.material_override as StandardMaterial3D).emission_enabled = true
			(nock.material_override as StandardMaterial3D).emission = Color("#3bff7a")
			(nock.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0
			_muzzle(root, Vector3(0, 0.062, -0.5))
		_:
			# SMG family: receiver, barrel, magazine, grip, stock and iron sights, sized per gun
			var length := 0.42
			var mag_len := 0.17
			var stock := true
			match id:
				"uzi": length = 0.3; mag_len = 0.2; stock = false
				"vector": length = 0.38; mag_len = 0.14
				"p90": length = 0.45; mag_len = 0.0
				"ump": length = 0.46; mag_len = 0.2
				"sting": length = 0.26; mag_len = 0.15; stock = false
			_box(root, Vector3(0.055, 0.08, length), Vector3(0, 0, -length * 0.5 + 0.08), accent)
			_box(root, Vector3(0.058, 0.025, length * 0.9), Vector3(0, 0.05, -length * 0.5 + 0.08), black)
			_cyl(root, 0.012, 0.12, Vector3(0, 0.005, -length + 0.02), steel)
			_box(root, Vector3(0.04, 0.11, 0.045), Vector3(0, -0.085, 0.03), black)
			if mag_len > 0.0:
				_box(root, Vector3(0.035, mag_len, 0.05), Vector3(0, -0.04 - mag_len * 0.5, -0.1), black)
			else:   # P90: magazine on top
				_box(root, Vector3(0.05, 0.03, 0.26), Vector3(0, 0.075, -0.12), _mat(Color(0.2, 0.22, 0.2), 0.1, 0.6))
			if stock:
				_box(root, Vector3(0.03, 0.06, 0.16), Vector3(0, -0.01, 0.17), black)
			# iron sights: rear notch and front post (SMGs are iron sights only)
			_box(root, Vector3(0.03, 0.025, 0.012), Vector3(0, 0.075, 0.04), steel)
			_box(root, Vector3(0.008, 0.03, 0.01), Vector3(0, 0.077, -length + 0.12), steel)
			_muzzle(root, Vector3(0, 0.005, -length - 0.04))
	return root
