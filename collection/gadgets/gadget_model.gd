extends RefCounted
## The three gadget pickups' looks (Pete, 26 Nov), each built from a few simple meshes like the guns in
## weapons/weapon_model.gd: a proximity mine (a dark disc with a red light), a stun grenade (a pale canister with a blue
## band, a lever and a ring pull) and a speed boost (a can with a white bolt on it).

static func _mat(col: Color, metal := 0.0, rough := 0.5, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metal
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	return m

static func _cyl(parent: Node3D, r: float, h: float, at: Vector3, m: Material, r2 := -1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r if r2 < 0.0 else r2
	c.height = h
	c.radial_segments = 24
	mi.mesh = c
	mi.position = at
	mi.material_override = m
	parent.add_child(mi)
	return mi

static func _box(parent: Node3D, size: Vector3, at: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = at
	mi.material_override = m
	parent.add_child(mi)
	return mi

## kind: "mine", "stun" or "boost"; the mine's light is named "Led" so the mine on the floor can blink it
static func make(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		"mine":
			_cyl(root, 0.2, 0.06, Vector3(0, 0.03, 0), _mat(Color(0.12, 0.13, 0.14), 0.6, 0.45), 0.22)
			_cyl(root, 0.13, 0.03, Vector3(0, 0.075, 0), _mat(Color(0.32, 0.34, 0.36), 0.8, 0.3))
			var led := _cyl(root, 0.025, 0.02, Vector3(0, 0.1, 0), _mat(Color(1.0, 0.12, 0.08), 0.0, 0.3, 4.0))
			led.name = "Led"
		"stun":
			_cyl(root, 0.055, 0.15, Vector3(0, 0.075, 0), _mat(Color(0.86, 0.88, 0.9), 0.5, 0.35))
			_cyl(root, 0.057, 0.03, Vector3(0, 0.1, 0), _mat(Color(0.2, 0.45, 1.0), 0.2, 0.4))
			_cyl(root, 0.03, 0.03, Vector3(0, 0.165, 0), _mat(Color(0.4, 0.42, 0.45), 0.8, 0.3))
			_box(root, Vector3(0.016, 0.11, 0.02), Vector3(0.05, 0.12, 0), _mat(Color(0.4, 0.42, 0.45), 0.8, 0.3))
			var ring := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.016
			tm.outer_radius = 0.024
			ring.mesh = tm
			ring.rotation.z = PI * 0.5
			ring.position = Vector3(-0.03, 0.19, 0)
			ring.material_override = _mat(Color(0.75, 0.76, 0.78), 0.9, 0.25)
			root.add_child(ring)
		"boost":
			_cyl(root, 0.065, 0.24, Vector3(0, 0.12, 0), _mat(Color(0.08, 0.09, 0.1), 0.7, 0.3))
			_cyl(root, 0.063, 0.012, Vector3(0, 0.246, 0), _mat(Color(0.8, 0.82, 0.85), 0.9, 0.2))
			# a white bolt on the front, glowing a little
			var bolt := Node3D.new()
			bolt.position = Vector3(0, 0.12, 0.066)
			root.add_child(bolt)
			var white := _mat(Color(1, 1, 1), 0.0, 0.4, 1.5)
			_box(bolt, Vector3(0.03, 0.09, 0.004), Vector3(0.012, 0.035, 0), white).rotation.z = -0.45
			_box(bolt, Vector3(0.03, 0.09, 0.004), Vector3(-0.012, -0.035, 0), white).rotation.z = -0.45
			_box(bolt, Vector3(0.05, 0.016, 0.004), Vector3(0, 0, 0), white)
	return root
