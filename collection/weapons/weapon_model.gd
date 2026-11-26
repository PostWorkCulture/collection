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

## the paint finishes a fighter's bat is given at random
const BAT_COLORS := [Color(0.75, 0.1, 0.13), Color(0.1, 0.28, 0.72), Color(0.08, 0.08, 0.09), Color(0.92, 0.91, 0.88),
		Color(0.1, 0.45, 0.22), Color(0.95, 0.72, 0.1), Color(0.42, 0.18, 0.6), Color(0.95, 0.42, 0.08),
		Color(0.93, 0.45, 0.65), Color(0.05, 0.55, 0.55), Color(0.62, 0.42, 0.24), Color(0.7, 0.72, 0.75)]

## tint: the bat's paint (default red)
static func make(id: String, tint := Color(0.75, 0.1, 0.13)) -> Node3D:
	var root := Node3D.new()
	root.name = "Weapon_" + id
	var black := _mat(Color(0.07, 0.07, 0.08), 0.5, 0.45)
	var steel := _mat(Color(0.32, 0.33, 0.35), 0.9, 0.25)
	var g := Weapons.stat(id)
	var accent := _mat(Color.html(g.get("color", "#888888")), 0.35, 0.3)
	match id:
		"fists", "":
			pass
		"bat":
			# a long tapered bat, painted (tint) with a dark grip, angled up from the hand
			var bat := Node3D.new()
			bat.rotation.x = -1.05
			root.add_child(bat)
			var shaft := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.045
			cm.bottom_radius = 0.022
			cm.height = 0.82
			shaft.mesh = cm
			shaft.position = Vector3(0, 0.41, 0)
			shaft.material_override = _mat(tint, 0.1, 0.45)
			bat.add_child(shaft)
			var grip := MeshInstance3D.new()
			var gm := CylinderMesh.new()
			gm.top_radius = 0.024
			gm.bottom_radius = 0.024
			gm.height = 0.18
			grip.mesh = gm
			grip.position = Vector3(0, 0.05, 0)
			grip.material_override = black
			bat.add_child(grip)
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
