extends RefCounted
## Plays the web game's own sound files (copied into audio/sfx/) from where they happen in the world.
## Phase 2: plain 3D positional sound. Muffling through walls, room echo and the audio buses come in phase 5.

const DIR := "res://audio/sfx/"

static var _streams := {}

static func _stream(name: String) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var path := DIR + name + ".mp3"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	elif FileAccess.file_exists(path):   # not imported yet (new file, editor closed): read the mp3 directly
		s = AudioStreamMP3.load_from_file(path)
	_streams[name] = s
	return s

## play `name` at `pos`; range = distance where it fades out, rate = pitch, jitter = random pitch spread
static func play(world: Node, name: String, pos: Vector3, vol_db := 0.0, rate := 1.0, range := 30.0, jitter := 0.0) -> void:
	var s := _stream(name)
	if s == null or world == null or not world.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = maxf(0.1, rate + (randf() - 0.5) * 2.0 * jitter)
	p.max_distance = range
	p.unit_size = range * 0.18
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	world.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()

## a flat (non-positional) sound for things that happen to you: hurt, hit markers
static func play_ui(world: Node, name: String, vol_db := 0.0, rate := 1.0) -> void:
	var s := _stream(name)
	if s == null or world == null or not world.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = rate
	world.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
