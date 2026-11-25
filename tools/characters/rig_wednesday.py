"""Rig a six-part imok character (torso, head, armL, armR, legL, legR) as one skinned humanoid.

Run with Blender's Python (bpy):  python3 rig_wednesday.py <in.glb> <out.glb> [out.blend]
- Puts the arms in a T-pose (rotated about each shoulder pivot), joins the parts into one mesh.
- Builds a 22-bone humanoid skeleton with Mixamo's bone names (no prefix), fitted to the parts' sizes.
- Weights each part to its own bones with smooth blends at the shoulders, elbows, wrists, hips, knees, ankles and spine.
Game axes: Y up, +Z forward. Blender: Z up, -Y forward. The part at game +x is the character's LEFT (it faces +Z).
"""
import sys, math
import bpy, bmesh
from mathutils import Vector, Matrix
import numpy as np

src, dst = sys.argv[-3], sys.argv[-2]
blend_out = sys.argv[-1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
parts = {o.name: o for o in bpy.context.scene.objects if o.type == 'MESH'}
assert set(parts) >= {'torso', 'head', 'armL', 'armR', 'legL', 'legR'}, list(parts)

# pivots (each part's own origin) in Blender coords
piv = {n: o.matrix_world.translation.copy() for n, o in parts.items()}

def side_of(n):  # game armR / legR sit at +x = character's left
    return 'Left' if piv[n].x > 0 else 'Right'

# --- T-pose the arms: rotate about the shoulder pivot round the front-back axis
for n in ('armL', 'armR'):
    o = parts[n]
    p = piv[n]
    ang = -math.pi / 2 if p.x > 0 else math.pi / 2      # +x arm swings out to +x
    R = Matrix.Translation(p) @ Matrix.Rotation(ang, 4, 'Y') @ Matrix.Translation(-p)
    o.matrix_world = R @ o.matrix_world

# bake transforms into the meshes, tag each part with a vertex group
for n, o in parts.items():
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    vg = o.vertex_groups.new(name='part_' + n)
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')

def verts(n):
    o = parts[n]
    return np.array([v.co[:] for v in o.data.vertices])

V = {n: verts(n) for n in parts}

# texture luminance per vertex (to find where the white glove / hand begins)
def vertex_lum(n):
    o = parts[n]
    me = o.data
    mat = me.materials[0]
    img = None
    for node in mat.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image:
            img = node.image
            break
    if img is None:
        return None
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    uvl = me.uv_layers.active.data
    lum = np.zeros(len(me.vertices))
    cnt = np.zeros(len(me.vertices))
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            u, v = uvl[li].uv
            c = px[int((v % 1) * (h - 1)), int((u % 1) * (w - 1))]
            lum[vi] += 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
            cnt[vi] += 1
    return lum / np.maximum(cnt, 1)

# ---------------------------------------------------------------- skeleton layout
tor, hd = V['torso'], V['head']
hips_z = float(tor[:, 2].min())               # bottom of the torso block (top of the legs)
neck_z = float(tor[:, 2].max())
head_top = float(hd[:, 2].max())
legs = {side_of(n): n for n in ('legL', 'legR')}
arms = {side_of(n): n for n in ('armL', 'armR')}

J = {}
J['Hips'] = Vector((0, 0, hips_z + 0.02))
span = neck_z - J['Hips'].z
J['Spine'] = Vector((0, 0, J['Hips'].z + span * 0.18))
J['Spine1'] = Vector((0, 0, J['Hips'].z + span * 0.42))
J['Spine2'] = Vector((0, 0, J['Hips'].z + span * 0.66))
J['Neck'] = Vector((0, 0, neck_z - 0.06))
J['Head'] = Vector((0, 0, neck_z + 0.08))
J['HeadTop_End'] = Vector((0, 0, head_top))

arm_info = {}
for s, n in arms.items():
    a = V[n]
    sx = 1 if s == 'Left' else -1
    p = piv[n]
    t = (a[:, 0] - p.x) * sx                   # distance out along the T-posed arm
    length = float(t.max())
    lum = vertex_lum(n)
    wrist_t = length * 0.76
    if lum is not None:
        far = t > length * 0.45
        bright = far & (lum > 0.55)
        if bright.sum() > 10:
            wrist_t = float(np.percentile(t[bright], 3))
    elbow_t = wrist_t * 0.52
    cz = float(np.median(a[:, 2]))
    cy = float(np.median(a[:, 1]))
    J[s + 'Shoulder'] = Vector((sx * 0.14, cy, J['Spine2'].z + 0.04))
    J[s + 'Arm'] = Vector((p.x + sx * 0.04, cy, cz))
    J[s + 'ForeArm'] = Vector((p.x + sx * elbow_t, cy, cz))
    J[s + 'Hand'] = Vector((p.x + sx * wrist_t, cy, cz))
    J[s + 'HandEnd'] = Vector((p.x + sx * length, cy, cz))
    arm_info[s] = dict(t0=p.x, sx=sx, elbow=elbow_t, wrist=wrist_t, length=length)

leg_info = {}
for s, n in legs.items():
    l = V[n]
    cx = float(np.median(l[:, 0]))
    top = float(l[:, 2].max())
    foot_front = float(l[:, 1].min())          # forward is -Y
    heel = float(l[:, 1].max())
    ankle_z = top * 0.13
    knee_z = ankle_z + (top - ankle_z) * 0.47
    cy = float(np.median(l[l[:, 2] > top * 0.5][:, 1]))
    J[s + 'UpLeg'] = Vector((cx, cy, top - 0.08))
    J[s + 'Leg'] = Vector((cx, cy, knee_z))
    J[s + 'Foot'] = Vector((cx, cy, ankle_z))
    J[s + 'ToeBase'] = Vector((cx, cy + (foot_front - cy) * 0.6, 0.06))
    J[s + 'Toe_End'] = Vector((cx, foot_front, 0.06))
    leg_info[s] = dict(top=top, knee=knee_z, ankle=ankle_z, toe_y=J[s + 'ToeBase'].y, cy=cy)

# ---------------------------------------------------------------- armature
arm_data = bpy.data.armatures.new('Armature')
rig = bpy.data.objects.new('Armature', arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
eb = arm_data.edit_bones

def bone(name, head, tail, parent=None, roll=0.0):
    b = eb.new(name)
    b.head, b.tail = head, tail
    b.roll = roll
    if parent:
        b.parent = eb[parent]
        b.use_connect = False
    return b

bone('Hips', J['Hips'], J['Spine'])
bone('Spine', J['Spine'], J['Spine1'], 'Hips')
bone('Spine1', J['Spine1'], J['Spine2'], 'Spine')
bone('Spine2', J['Spine2'], J['Neck'], 'Spine1')
bone('Neck', J['Neck'], J['Head'], 'Spine2')
bone('Head', J['Head'], J['HeadTop_End'], 'Neck')
for s in ('Left', 'Right'):
    bone(s + 'Shoulder', J[s + 'Shoulder'], J[s + 'Arm'], 'Spine2')
    bone(s + 'Arm', J[s + 'Arm'], J[s + 'ForeArm'], s + 'Shoulder')
    bone(s + 'ForeArm', J[s + 'ForeArm'], J[s + 'Hand'], s + 'Arm')
    bone(s + 'Hand', J[s + 'Hand'], J[s + 'HandEnd'], s + 'ForeArm')
    bone(s + 'UpLeg', J[s + 'UpLeg'], J[s + 'Leg'], 'Hips')
    bone(s + 'Leg', J[s + 'Leg'], J[s + 'Foot'], s + 'UpLeg')
    bone(s + 'Foot', J[s + 'Foot'], J[s + 'ToeBase'], s + 'Leg')
    bone(s + 'ToeBase', J[s + 'ToeBase'], J[s + 'Toe_End'], s + 'Foot')
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- join + weights
bpy.ops.object.select_all(action='DESELECT')
for o in parts.values():
    o.select_set(True)
bpy.context.view_layer.objects.active = parts['torso']
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = 'Body'
me = body.data
co = np.array([v.co[:] for v in me.vertices])
nv = len(co)
part_of = np.empty(nv, dtype=object)
for g in body.vertex_groups:
    if g.name.startswith('part_'):
        for v in me.vertices:
            for ge in v.groups:
                if ge.group == g.index and ge.weight > 0.5:
                    part_of[v.index] = g.name[5:]

def ss(x):  # smoothstep 0..1
    x = np.clip(x, 0.0, 1.0)
    return x * x * (3 - 2 * x)

def chain(param, cuts, names, widths):
    """param along a chain; cuts = joint positions between consecutive bones; blend +-width at each cut."""
    w = {n: np.zeros_like(param) for n in names}
    prev = np.ones_like(param)
    for i, c in enumerate(cuts):
        f = ss((param - (c - widths[i])) / (2 * widths[i]))   # 0 before the joint, 1 after
        w[names[i]] += prev * (1 - f)
        prev = prev * f
    w[names[-1]] += prev
    return w

W = {}
def add(names_w, mask):
    for n, arr in names_w.items():
        W.setdefault(n, np.zeros(nv))
        W[n][mask] += arr[mask] if hasattr(arr, '__len__') else arr

# head: rigid, a little neck at the very bottom
m = part_of == 'head'
z = co[:, 2]
add(chain(z, [J['Head'].z + 0.04], ['Neck', 'Head'], [0.06]), m)
# torso: spine chain by height
m = part_of == 'torso'
add(chain(z, [J['Spine'].z, J['Spine1'].z, J['Spine2'].z, J['Neck'].z + 0.02],
          ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck'], [0.06, 0.08, 0.08, 0.04]), m)
# arms: along the T-pose
for s, n in arms.items():
    ai = arm_info[s]
    m = part_of == n
    t = (co[:, 0] - ai['t0']) * ai['sx']
    add(chain(t, [0.06, ai['elbow'], ai['wrist']], [s + 'Shoulder', s + 'Arm', s + 'ForeArm', s + 'Hand'],
              [0.08, 0.09, 0.035]), m)
# legs: by height, toes by how far forward
for s, n in legs.items():
    li = leg_info[s]
    m = part_of == n
    w = chain(-z, [-(li['top'] - 0.05), -li['knee'], -li['ankle']], ['Hips', s + 'UpLeg', s + 'Leg', s + 'Foot'],
              [0.06, 0.09, 0.05])
    # split the foot into foot / toes along the forward axis
    toe = ss((li['toe_y'] + 0.04 - co[:, 1]) / 0.08) * (z < li['ankle'])
    w[s + 'ToeBase'] = w[s + 'Foot'] * toe
    w[s + 'Foot'] = w[s + 'Foot'] * (1 - toe)
    add(w, m)

for n, arr in W.items():
    vg = body.vertex_groups.get(n) or body.vertex_groups.new(name=n)
    for i in np.nonzero(arr > 0.002)[0]:
        vg.add([int(i)], float(arr[i]), 'REPLACE')
for g in list(body.vertex_groups):
    if g.name.startswith('part_'):
        body.vertex_groups.remove(g)

body.parent = rig
mod = body.modifiers.new('Armature', 'ARMATURE')
mod.object = rig

# normalise
bpy.context.view_layer.objects.active = body
bpy.ops.object.vertex_group_normalize_all(lock_active=False)

missing = [n for n in range(nv) if part_of[n] is None]
print('RIG verts', nv, 'unassigned', len(missing), 'bones', len(arm_data.bones))
print('RIG joints', {k: tuple(round(c, 3) for c in v) for k, v in J.items()})
print('RIG arms', arm_info)
print('RIG legs', leg_info)

bpy.ops.wm.save_as_mainfile(filepath=blend_out)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_skins=True, export_animations=False,
                          export_yup=True, export_apply=False)
print('RIG wrote', dst)
