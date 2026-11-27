extends RefCounted
## Weapon stats for Collection, copied from the web game (1v1 collection-v1, GUNS table; damage values are final). The
## MP5, UMP and Vector take 1v1's current hip spread and the crossbow its current stats (Pete, 27 Nov: bring the SMGs
## and crossbow over).
## dmg per hit on 100 HP players · head = headshot multiplier · rate = seconds between shots · spread / ads_spread in
## degrees · fall = full damage up to fall[0] m, down to 45% by fall[1] m · zoom = field of view while aiming ·
## kick = camera kick per shot · bloom = extra spread per shot (decays) · weight = movement multiplier while held.

const AMMO := 20            # every gun pickup holds 20 bullets, no reload
const KEEP_AT := 10         # can't swap guns while the current one still has this many
const ADS_TIME := 0.07      # SMGs aim in 0.07 s
const ADS_SPEED := 5.6 * 1.125   # walking speed while aiming (web: 5.6 x MOVE_MUL)
const CO_GUNS: Array[String] = ["mp5", "uzi", "vector", "p90", "ump", "sting", "duals", "crossbow"]
const BOLTS := 10           # a crossbow pickup holds 10 bolts (the SMGs hold AMMO)

## what a fresh pickup of this gun holds
static func full(id: String) -> int:
	return BOLTS if id == "crossbow" else AMMO

const STATS := {
	"fists": {"name": "Fists", "melee": true, "dmg": 34.0, "head": 1.0, "rate": 0.36, "reach": 2.7, "arc": 1.15, "lunge": 3.0, "knock": 5.0, "zoom": 62.0},
	"bat": {"name": "Bat", "melee": true, "dmg": 50.0, "head": 1.0, "rate": 0.55, "reach": 3.6, "arc": 1.2, "lunge": 5.0, "knock": 9.0, "zoom": 62.0},
	"mp5": {"name": "MP5", "dmg": 16.0, "head": 1.6, "rate": 0.055, "spread": 0.8, "ads_spread": 0.9, "fall": [8.0, 26.0], "zoom": 48.0, "kick": 0.006, "bloom": 0.13, "weight": 1.04, "sound": ["smgnova", 1.0], "color": "#a05ad6"},
	"uzi": {"name": "Uzi", "dmg": 18.0, "head": 1.7, "rate": 0.07, "spread": 1.5, "ads_spread": 0.75, "fall": [10.0, 30.0], "zoom": 60.0, "kick": 0.007, "bloom": 0.095, "weight": 1.06, "sound": ["smgnova", 0.9], "color": "#ffd21f"},
	"vector": {"name": "Vector", "dmg": 14.0, "head": 1.6, "rate": 0.045, "spread": 0.75, "ads_spread": 0.8, "fall": [7.0, 22.0], "zoom": 50.0, "kick": 0.004, "bloom": 0.17, "weight": 1.05, "sound": ["smgnova", 1.12], "color": "#ff2e88"},
	"p90": {"name": "P90", "dmg": 15.0, "head": 1.5, "rate": 0.06, "spread": 1.0, "ads_spread": 0.8, "fall": [9.0, 26.0], "zoom": 46.0, "kick": 0.006, "bloom": 0.08, "weight": 1.03, "sound": ["smgnova", 1.04], "color": "#3ddc84"},
	"ump": {"name": "UMP", "dmg": 18.0, "head": 1.6, "rate": 0.095, "spread": 0.75, "ads_spread": 0.35, "fall": [20.0, 48.0], "zoom": 40.0, "kick": 0.007, "bloom": 0.1, "weight": 1.03, "sound": ["smgnova", 0.9], "color": "#2f6bff"},
	"sting": {"name": "Sting", "dmg": 8.0, "head": 1.5, "rate": 0.036, "spread": 1.1, "ads_spread": 0.8, "fall": [6.0, 18.0], "zoom": 64.0, "kick": 0.004, "bloom": 0.12, "weight": 1.05, "swap": 0.2, "sound": ["smgnova", 1.22], "color": "#13c7b6"},
	# the crossbow (1v1's current GUNS table): a silent high-velocity bolt, 2x headshot, one shot then its 1.8 s reload
	"crossbow": {"name": "Crossbow", "proj": true, "semi": true, "dmg": 83.0, "head": 2.0, "rate": 1.8, "spread": 0.6, "ads_spread": 0.0, "speed": 200.0, "grav": 1.5, "zoom": 40.0, "kick": 0.03, "bloom": 0.0, "weight": 1.06, "sound": ["crossbow", 1.0], "color": "#1fd655"},
	"duals": {"name": "Dual Pistols", "dmg": 30.0, "head": 1.8, "rate": 0.16, "spread": 1.6, "ads_spread": 0.9, "fall": [10.0, 28.0], "zoom": 70.0, "kick": 0.015, "bloom": 0.18, "weight": 1.08, "sound": ["pistol", 1.08], "color": "#e9edf5"},
}

static func stat(id: String) -> Dictionary:
	return STATS.get(id, STATS["fists"])

static func is_melee(id: String) -> bool:
	return stat(id).get("melee", false)

## damage multiplier for range: full up to fall[0], 45% from fall[1] on
static func falloff(id: String, dist: float) -> float:
	var g := stat(id)
	if not g.has("fall"):
		return 1.0
	var f: Array = g.fall
	if dist <= f[0]:
		return 1.0
	if dist >= f[1]:
		return 0.45
	return lerp(1.0, 0.45, (dist - f[0]) / (f[1] - f[0]))

## a random direction inside a cone of `deg` degrees around d (same maths as the web game's spreadDir)
static func spread_dir(d: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return d
	var a := deg_to_rad(deg) * sqrt(randf())
	var t := randf() * TAU
	var up := Vector3.RIGHT if absf(d.y) > 0.95 else Vector3.UP
	var u := d.cross(up).normalized()
	var v := d.cross(u)
	return (d * cos(a) + u * sin(a) * cos(t) + v * sin(a) * sin(t)).normalized()
