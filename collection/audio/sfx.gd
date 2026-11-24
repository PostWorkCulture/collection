extends RefCounted
## Plays the web game's own sound files (audio/sfx/) from where they happen (phase 2), mixed and placed in the house
## (phase 5):
## - Buses: Weapons (guns, punches, bat), SFX (everything else), Music, Voice, each with its own volume setting,
##   plus three echo buses (Hall, Room, Soft) that the rooms send to.
## - Through walls: before a sound plays, a ray from your ears to it checks what's in between; behind one wall it's
##   quieter and duller, behind two (or a floor) more so, so you can tell "next door" from "upstairs".
## - Room echo: each room is an audio area that sends a share of every sound inside it to its echo bus (set up by
##   the match from the floor plan): the grand hall rings, ground-floor rooms have some echo, upstairs is soft,
##   outside is dry.

const DIR := "res://audio/sfx/"
const WEAPON_SOUNDS := ["smgnova", "pistol", "fistwhoosh", "fisthit", "batswing", "swordhit", "dry", "swap"]
const BUSES := ["Weapons", "SFX", "Music", "Voice"]
const AREA_LAYER := 1 << 5          # the room echo areas live on their own physics layer

static var _streams := {}
static var _setup_done := false

## make the buses once (they aren't in a project file, so the open editor can't lose them)
static func setup() -> void:
	if _setup_done:
		return
	_setup_done = true
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	for e in [["Hall", 0.85, 0.35, 0.55], ["Room", 0.45, 0.5, 0.35], ["Soft", 0.2, 0.75, 0.2]]:
		if AudioServer.get_bus_index(e[0]) < 0:
			AudioServer.add_bus()
			var j := AudioServer.bus_count - 1
			AudioServer.set_bus_name(j, e[0])
			AudioServer.set_bus_send(j, "SFX")
			var rv := AudioEffectReverb.new()
			rv.room_size = e[1]
			rv.damping = e[2]
			rv.wet = e[3]
			rv.dry = 0.0
			rv.spread = 0.8
			AudioServer.add_bus_effect(j, rv)
	apply_volumes()

## volume settings are 0-10 (10% steps)
static func apply_volumes() -> void:
	var st: Node = Engine.get_main_loop().root.get_node_or_null("Settings")
	if st == null:
		return
	var vols := {"Master": st.vol_master, "Weapons": st.vol_weapons, "SFX": st.vol_sfx, "Music": st.vol_music, "Voice": st.vol_voice}
	for b in vols:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			var v: float = clampf(float(vols[b]) / 10.0, 0.0, 1.0)
			AudioServer.set_bus_volume_db(i, linear_to_db(v) if v > 0.0 else -80.0)
			AudioServer.set_bus_mute(i, v <= 0.0)

static func _stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := name if name.begins_with("res://") else DIR + name + ".mp3"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	elif FileAccess.file_exists(path):   # not imported yet (new file, editor closed): read the mp3 directly
		s = AudioStreamMP3.load_from_file(path)
	_streams[name] = s
	return s

## how many solid things are between your ears and the sound (0, 1 or 2+), and whether a floor is one of them
static func _occlusion(world: Node, pos: Vector3) -> Array:
	var cam := world.get_viewport().get_camera_3d() if world.is_inside_tree() else null
	if cam == null or not world is Node3D:
		return [0, false]
	var space := (world as Node3D).get_world_3d().direct_space_state
	var from := cam.global_position
	var walls := 0
	var floor := false
	var exclude: Array[RID] = []
	for k in 2:
		var q := PhysicsRayQueryParameters3D.create(from, pos, 1, exclude)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		walls += 1
		if absf(hit.normal.y) > 0.7:
			floor = true
		exclude.append(hit.rid)
	return [walls, floor]

## play `name` at `pos`; range = distance where it fades out, rate = pitch, jitter = random pitch spread
static func play(world: Node, name: String, pos: Vector3, vol_db := 0.0, rate := 1.0, range := 30.0, jitter := 0.0) -> void:
	var s := _stream(name)
	if s == null or world == null or not world.is_inside_tree():
		return
	setup()
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.bus = "Weapons" if WEAPON_SOUNDS.has(name) else "SFX"
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.1, rate + (randf() - 0.5) * 2.0 * jitter)
	p.max_distance = range
	p.unit_size = range * 0.18
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.area_mask = AREA_LAYER
	var occ := _occlusion(world, pos)
	var walls: int = occ[0]
	if walls == 0:
		p.attenuation_filter_cutoff_hz = 20500.0
	elif walls == 1 and not occ[1]:
		p.attenuation_filter_cutoff_hz = 2200.0    # next door
		p.volume_db -= 4.0
	else:
		p.attenuation_filter_cutoff_hz = 700.0     # behind two walls, or upstairs / downstairs
		p.volume_db -= 9.0
	p.attenuation_filter_db = -24.0
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

## a flat (non-positional) sound for things that happen to you: hurt, hit markers, cues
static func play_ui(world: Node, name: String, vol_db := 0.0, rate := 1.0, bus := "SFX") -> void:
	var s := _stream(name)
	if s == null or world == null or not world.is_inside_tree():
		return
	setup()
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = vol_db
	p.pitch_scale = rate
	world.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
