extends Node3D
## A gun pickup: the gun floats and turns slowly over a thin white ring whose brightness pulses. Walk within 1.2 m
## (and 1.6 m up or down) to take it, unless your current gun still has 10+ bullets: then, if it's a different gun,
## you can swap (interact): yours drops here with the bullets it has left and you take this one. Taken pickups come
## back somewhere new after 15 s (the match picks where); a swapped-out gun is temporary: it lies there for 20 s.
## (Bat pickups are still supported but no longer placed: everyone carries a bat.)
## Gadget pickups (Pete, 26 Nov) work the same way: a proximity mine or a stun grenade (you carry one of each at most, so
## you can't take another while you hold one) or a speed boost (taken at once: half as fast again for 10 s).

const Weapons := preload("res://weapons/weapons.gd")
const WeaponModel := preload("res://weapons/weapon_model.gd")
const Sfx := preload("res://audio/sfx.gd")
const GadgetModel := preload("res://gadgets/gadget_model.gd")
const GADGETS := ["mine", "stun", "boost"]

const TAKE_R := 1.2
const TAKE_H := 1.6
const PICK_BACK := 15.0

var game: Node = null
var kind := "gun"           # "gun", "bat", or a gadget: "mine", "stun", "boost"
var id := ""                # which gun
var ammo := Weapons.AMMO    # bullets in it (a swapped-out gun keeps what it had left)
var active := false
var temporary := false
var life := 0.0
var _back := 0.0
var _spin: Node3D
var _model: Node3D
var _ring_mat: StandardMaterial3D
var _t := randf() * 10.0

func _ready() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.6
	tm.outer_radius = 0.64
	tm.rings = 48
	tm.ring_segments = 6
	ring.mesh = tm
	ring.position.y = 0.03
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(1, 1, 1, 0.55)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = _ring_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	visible = false

func show_at(p: Vector3, new_id: String) -> void:
	global_position = p
	id = new_id
	if _model:
		_model.queue_free()
	if kind in GADGETS:
		_model = GadgetModel.make(kind)
		_model.scale = Vector3.ONE * (2.4 if kind == "mine" else 2.2)
	else:
		_model = WeaponModel.make("bat" if kind == "bat" else id)
		_model.scale = Vector3.ONE * 1.5
	if kind == "bat":
		_model.rotation.x = 1.05   # stand the bat up
	_spin.add_child(_model)
	active = true
	visible = true

func wait(secs: float) -> void:
	active = false
	visible = false
	_back = secs

func _physics_process(dt: float) -> void:
	if game == null:
		return
	if not active:
		if temporary:
			return
		_back -= dt
		if _back <= 0.0:
			game.place_pickup(self)
		return
	_t += dt
	_spin.rotation.y += dt * 0.9
	_spin.position.y = 0.35 + 0.45 + sin(_t * 2.4) * 0.08
	_ring_mat.albedo_color.a = 0.55 + sin(_t * 4.0) * 0.2
	if temporary:
		life -= dt
		if life <= 0.0:
			_remove()
			return
	for f in game.fighters:
		if not f.alive or f.downed:
			continue
		var d: Vector3 = f.global_position - global_position
		if Vector2(d.x, d.z).length() < TAKE_R and absf(d.y) < TAKE_H:
			if _take(f):
				return
			if kind == "gun" and f.gun_id != "" and f.gun_id != id:   # could swap: offer it while they stand here
				f.swap_offer = self
				f.swap_offer_t = 0.15

func _take(f: Node) -> bool:
	if kind in GADGETS:
		match kind:
			"mine":
				if f.has_mine:
					return false
				f.has_mine = true
			"stun":
				if f.has_stun:
					return false
				f.has_stun = true
			"boost":
				f.boost_t = f.BOOST_T
		Sfx.play(game, "bing", global_position, -4.0, 1.2, 10.0)
	elif kind == "bat":
		if not f.can_take_bat():
			return false
		f.give_bat()
		Sfx.play(game, "batswing", global_position, -2.0, 1.0, 10.0)
	else:
		if not f.can_take_gun():
			return false
		f.give_gun(id, ammo)
		Sfx.play(game, "bing", global_position, -4.0, 1.0, 10.0)
	game.feed_pickup(f, self)
	if temporary:
		_remove()
	else:
		wait(PICK_BACK)
	return true

## swap: the fighter's gun drops here (20 s, with its bullets) and they take this one
func swap(f: Node) -> void:
	if not active or kind != "gun" or f.gun_id == "" or f.gun_id == id or not f.alive or f.downed:
		return
	var old_id: String = f.gun_id
	var old_ammo: int = f.ammo
	f.give_gun(id, ammo)
	f.swap_offer = null
	Sfx.play(game, "bing", global_position, -4.0, 1.0, 10.0)
	game.feed_pickup(f, self)
	game.drop_gun(f.global_position, old_id, old_ammo)
	if temporary:
		_remove()
	else:
		wait(PICK_BACK)
	ammo = Weapons.AMMO

func _remove() -> void:
	active = false
	game.forget_pickup(self)
	queue_free()
