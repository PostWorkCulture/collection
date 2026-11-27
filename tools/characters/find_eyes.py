# Find a rigged character's eyes for blinking, and write them into its game json as "_eyes".
#   python3 find_eyes.py <rig.blend> <collection/characters/<id>/<id>.json> [x,z x,z]
# Looks at the face straight on (rays from the front over a 0.9 m square around the head, rest pose), reads the
# colour texture where each ray lands, and takes the dark blobs ringed by skin above the mouth as the eyes. If only one
# eye shows (the other under the hair) it is mirrored across the face. Eyes the search can't separate from a fringe
# can be given by hand as x,z centres (Blender units, as the json). Positions are Godot model space (x, y up, z front).
# Also writes the face's skin colour and the texture spot (uv) of a skin texel just under the eyes: the game draws
# the lids with the body's own material at that uv, so they match the face exactly.
import sys, json, bpy, numpy as np
from mathutils import Vector
from mathutils.geometry import barycentric_transform, intersect_point_tri
from scipy import ndimage

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
blend, out_json, manual = args[0], args[1], args[2:]
bpy.ops.wm.open_mainfile(filepath=blend)
rig = bpy.data.objects['Armature']
if rig.animation_data: rig.animation_data.action = None
for pb in rig.pose.bones:
    pb.rotation_quaternion = (1, 0, 0, 0); pb.rotation_euler = (0, 0, 0); pb.location = (0, 0, 0)
body = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.name != 'Plane'][0]
dg = bpy.context.evaluated_depsgraph_get()
me = bpy.data.meshes.new_from_object(body.evaluated_get(dg)); me.calc_loop_triangles()
tmp = bpy.data.objects.new('eyes_tmp', me); bpy.context.scene.collection.objects.link(tmp)
tmp.matrix_world = body.matrix_world; bpy.context.view_layer.update()
img = None
for m in body.data.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == 'TEX_IMAGE' and n.image and 'emiss' not in n.image.name.lower(): img = n.image
W, H = img.size; px = np.array(img.pixels[:]).reshape(H, W, 4)
uvl = me.uv_layers.active.data
tris = {}
for t in me.loop_triangles: tris.setdefault(t.polygon_index, []).append(t)
inv = tmp.matrix_world.inverted()

N = 240; X0 = -0.45; Z0 = 2.95; st = 0.9 / (N - 1)
O = np.zeros((N, N, 3)); Y = np.full((N, N), np.nan); UV = np.zeros((N, N, 2))
for i in range(N):
    for j in range(N):
        ok, loc, nor, fi = tmp.ray_cast(inv @ Vector((X0 + j * st, -8, Z0 - i * st)), Vector((0, 1, 0)))
        if not ok: continue
        uv = None
        for t in tris[fi]:
            a, b, c = [me.vertices[v].co for v in t.vertices]
            ua, ub, uc = [Vector((uvl[l].uv[0], uvl[l].uv[1], 0)) for l in t.loops]
            uv = barycentric_transform(loc, a, b, c, ua, ub, uc)
            if intersect_point_tri(loc, a, b, c): break
        O[i, j] = px[int(np.clip(uv[1], 0, .9999) * H), int(np.clip(uv[0], 0, .9999) * W), :3]
        Y[i, j] = (tmp.matrix_world @ loc).y; UV[i, j] = (uv[0], uv[1])

def gx(x): return int(round((x - X0) / st))
def gz(z): return int(round((Z0 - z) / st))

def blobs(min_skin):
    lab, n = ndimage.label((O.mean(2) < 0.12) & ~np.isnan(Y))
    found = []
    for k in range(1, n + 1):
        ys, xs = np.where(lab == k)
        if not 12 <= len(ys) <= 700: continue
        y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
        h, w = y1 - y0 + 1, x1 - x0 + 1
        if h < w * 0.9 or h > w * 4: continue          # eyes are upright ovals; the mouth is wide
        ring = np.zeros(lab.shape, bool); ring[max(0, y0 - 4):y1 + 5, max(0, x0 - 4):x1 + 5] = True; ring &= lab != k
        rp = O[ring]; skin = (rp.mean(1) > 0.45) & (rp.max(1) - rp.min(1) < 0.35)
        if skin.mean() < min_skin: continue
        cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
        # depth: the face under the eye itself (not the box round it, where a fringe can stand well in front)
        found.append({'pos': [X0 + cx * st, Z0 - cy * st, float(-np.nanmedian(Y[lab == k])) + 0.006],
                      'w': (w + 3) * st, 'h': (h + 3) * st})
    found.sort(key=lambda e: -e['pos'][1])
    found = found[:3]
    return [e for e in found if e['pos'][1] > found[0]['pos'][1] - 0.06] if found else []

if manual:
    eyes = []
    for m in manual:
        x, z = map(float, m.split(','))
        d = -np.nanmedian(Y[gz(z) - 2:gz(z) + 3, gx(x) - 2:gx(x) + 3])
        eyes.append({'pos': [x, z, float(d) + 0.006], 'w': 0.047, 'h': 0.095})
else:
    eyes = blobs(0.8) or blobs(0.5)
if len(eyes) == 1:   # the other one is under the hair: mirror it (the hair in front hides that lid in the game)
    e = eyes[0]; eyes.append({'pos': [-e['pos'][0], e['pos'][1], e['pos'][2]], 'w': e['w'], 'h': e['h']})
if not eyes:
    sys.exit('no eyes found: give them by hand as x,z')
ys = gz(min(e['pos'][1] - e['h'] * 0.5 for e in eyes) - 0.02)
box = O[ys:ys + 6, gx(-0.06):gx(0.06)].reshape(-1, 3); uvb = UV[ys:ys + 6, gx(-0.06):gx(0.06)].reshape(-1, 2)
lum = box.mean(1); med = np.median(box[lum > np.percentile(lum, 40)], 0)
uv = uvb[np.argmin(((box - med) ** 2).sum(1))]
# each eye in texture space too: the game draws the blink on the face itself (a skin-coloured lid and the closed-eye
# line painted over the eye in the texture's own coordinates), so the hair stays in front and the light is the face's.
# The texture under an eye that hair covers is found by casting on through the hair to the face's depth.
def uv_at(x, z, depth):
    o = inv @ Vector((x, -8, z))
    dirn = Vector((0, 1, 0))
    for _ in range(6):
        ok, loc, nor, fi = tmp.ray_cast(o, dirn)
        if not ok: return None
        if abs((tmp.matrix_world @ loc).y + depth) < 0.035:
            for t in tris[fi]:
                a, b, c = [me.vertices[v].co for v in t.vertices]
                if intersect_point_tri(loc, a, b, c) or t is tris[fi][-1]:
                    ua, ub, uc = [Vector((uvl[l].uv[0], uvl[l].uv[1], 0)) for l in t.loops]
                    u = barycentric_transform(loc, a, b, c, ua, ub, uc)
                    return np.array([u[0], 1.0 - u[1]])   # glTF flips v
        o = loc + dirn * 0.002
    return None
uv_eyes = []
for e in eyes:
    x, z, dpt = e['pos'][0], e['pos'][1], e['pos'][2] - 0.006
    hw, hh = e['w'] * 0.5, e['h'] * 0.5
    c = uv_at(x, z, dpt)
    if c is None:
        continue
    def grad(dx, dz):   # texture change per metre across the face, one-sided where a UV seam is near
        de = 0.006
        p, m = uv_at(x + dx * de, z + dz * de, dpt), uv_at(x - dx * de, z - dz * de, dpt)
        g = [v for v in ((p - c) / de if p is not None else None, (c - m) / de if m is not None else None) if v is not None]
        return min(g, key=lambda v: np.linalg.norm(v)) if g else None
    gr, gu = grad(1, 0), grad(0, 1)
    if gr is None or gu is None:
        continue
    uv_eyes.append({'c': [round(float(v), 5) for v in c], 'r': [round(float(v), 5) for v in gr * hw],
                    'u': [round(float(v), 5) for v in gu * hh]})
d = json.load(open(out_json))
d['_eyes'] = {'eyes': [{'pos': [round(float(v), 4) for v in e['pos']], 'w': round(float(e['w']), 4), 'h': round(float(e['h']), 4)} for e in eyes],
              'skin': [round(float(c), 3) for c in med], 'uv': [round(float(uv[0]), 5), round(float(1 - uv[1]), 5)],   # glTF flips v
              'uv_eyes': uv_eyes}
json.dump(d, open(out_json, 'w'), indent=1)
print('EYES', out_json, json.dumps(d['_eyes']))
