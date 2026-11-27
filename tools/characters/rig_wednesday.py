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

# --- pieces the 1v1 split put in an arm part that belong to the trunk (27 Nov review: Glitch's hip straps flew out
# with the arms and hung off the forearms). Growing out from the arm's biggest piece, any loose piece of the arm part
# that touches the arm (within 6 cm) stays with it; a piece left over that is nearer the torso than the arm goes to
# the torso (marked here, moved back after the T-pose turn).
from mathutils.kdtree import KDTree
def _islands(me):
    bm = bmesh.new(); bm.from_mesh(me); bm.verts.ensure_lookup_table()
    seen = set(); out = []
    for v in bm.verts:
        if v.index in seen: continue
        st = [v]; comp = []
        while st:
            x = st.pop()
            if x.index in seen: continue
            seen.add(x.index); comp.append(x.index)
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in seen: st.append(y)
        out.append(comp)
    bm.free()
    return sorted(out, key=len, reverse=True)
def _tree(pts):
    t = KDTree(len(pts))
    for i, c in enumerate(pts): t.insert(c, i)
    t.balance()
    return t
_tw = [parts['torso'].matrix_world @ v.co for v in parts['torso'].data.vertices]
_kt = _tree(_tw)
to_trunk = {}
for n in ('armL', 'armR'):
    o = parts[n]
    W = [o.matrix_world @ v.co for v in o.data.vertices]
    isl = _islands(o.data)
    arm = list(isl[0]); left = isl[1:]
    grew = True
    while grew and left:
        grew = False
        ka = _tree([W[i] for i in arm])
        for comp in list(left):
            if min(ka.find(W[i])[2] for i in comp) < 0.06:
                arm += comp; left.remove(comp); grew = True
    ka = _tree([W[i] for i in arm])
    move = []
    for comp in left:
        if min(_kt.find(W[i])[2] for i in comp) < min(ka.find(W[i])[2] for i in comp):
            move += comp
    to_trunk[n] = move
    print('RIG', n, 'pieces to the torso', len(move), 'verts')
# and the other way: loose pieces of the torso part lying on an arm (bits of sleeve or skin the split left in the
# torso; with the arm raised they hung down the side as flaps). Most of the piece within 8 cm of the arm: it's the arm's.
# (and in the arm's colour: a jacket panel hugging the arm stays with the jacket)
def _rgb(o):
    me = o.data
    img = None
    for node in me.materials[0].node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image and 'emiss' not in node.image.name.lower():
            img = node.image
            break
    if img is None:
        return None
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    uvl = me.uv_layers.active.data
    c = np.zeros((len(me.vertices), 3)); k = np.zeros(len(me.vertices))
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            u, v = uvl[li].uv
            c[vi] += px[int((v % 1) * (h - 1)), int((u % 1) * (w - 1))][:3]; k[vi] += 1
    return c / np.maximum(k, 1)[:, None]
_ta = {n: _tree([parts[n].matrix_world @ v.co for v in parts[n].data.vertices]) for n in ('armL', 'armR')}
_tc = _rgb(parts['torso'])
_ac = {n: (np.median(_rgb(parts[n]), 0) if _tc is not None else None) for n in ('armL', 'armR')}
to_arm = {'armL': [], 'armR': []}
for comp in _islands(parts['torso'].data)[1:]:
    for n in ('armL', 'armR'):
        if np.mean([_tw[i].z for i in comp]) < piv[n].z - 0.45:   # only round the shoulder, where the flaps were
            continue
        if np.median([_ta[n].find(_tw[i])[2] for i in comp]) < 0.08 and \
                (_tc is None or np.linalg.norm(np.median(_tc[comp], 0) - _ac[n]) < 0.25):
            to_arm[n] += comp
            break
print('RIG pieces of the torso to the arms', {n: len(v) for n, v in to_arm.items()})

# --- T-pose the arms: rotate about the shoulder pivot round the front-back axis
_tpose = {}
for n in ('armL', 'armR'):
    o = parts[n]
    p = piv[n]
    ang = -math.pi / 2 if p.x > 0 else math.pi / 2      # +x arm swings out to +x
    R = Matrix.Translation(p) @ Matrix.Rotation(ang, 4, 'Y') @ Matrix.Translation(-p)
    o.matrix_world = R @ o.matrix_world
    _tpose[n] = R

# bake transforms into the meshes, tag each part with a vertex group
for n, o in parts.items():
    o.data.transform(o.matrix_world)
    o.matrix_world = Matrix.Identity(4)
    vg = o.vertex_groups.new(name='part_' + n)
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
# the arms' pieces from the torso: turned with the arm and weighted with it
for n in ('armL', 'armR'):
    if not to_arm.get(n):
        continue
    t = parts['torso']
    for i in to_arm[n]:
        t.data.vertices[i].co = _tpose[n] @ t.data.vertices[i].co
    t.vertex_groups['part_torso'].remove(to_arm[n])
    t.vertex_groups.new(name='part_' + n).add(to_arm[n], 1.0, 'REPLACE')
# the trunk's pieces: turned back to where they were and weighted with the torso
for n in ('armL', 'armR'):
    if not to_trunk.get(n):
        continue
    o = parts[n]
    back = _tpose[n].inverted()
    for i in to_trunk[n]:
        o.data.vertices[i].co = back @ o.data.vertices[i].co
    o.vertex_groups['part_' + n].remove(to_trunk[n])
    o.vertex_groups.new(name='part_torso').add(to_trunk[n], 1.0, 'REPLACE')

# --- a closed core inside the trunk (27 Nov review): the 1v1 torsos are open shells with big holes at the sides,
# hidden in 1v1 by arms hanging over them. Once the arms move (reaching, crawling, ragdolls) you could see into and
# through the jacket. A convex hull of the trunk, pulled in a little, in the jacket's own colour, fills it: a gap now
# shows more jacket, never the inside or the world behind.
def add_core(n, sel, axis_of, colour_at):
    """a closed hull of the part's vertices `sel`, pulled 4 cm inside its surface along lines out from `axis_of(p)`,
    textured with the part's own colour at the surface point nearest `colour_at`, joined into the part"""
    o = parts[n]
    me = o.data
    co_p = np.array([v.co[:] for v in me.vertices])
    gi = o.vertex_groups['part_' + n].index
    own = np.array([any(g.group == gi and g.weight > 0.5 for g in v.groups) for v in me.vertices])   # not pieces sent to the trunk
    pts = co_p[sel(co_p) & own]
    if len(pts) < 20:
        return
    bm = bmesh.new()
    for p in pts:
        bm.verts.new(p)
    res = bmesh.ops.convex_hull(bm, input=bm.verts[:])
    drop = list({g for g in res['geom_interior'] + res['geom_unused'] if isinstance(g, bmesh.types.BMVert)})
    if drop:
        bmesh.ops.delete(bm, geom=drop, context='VERTS')
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=2, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    for v in bm.verts:
        a = axis_of(v.co)
        d = v.co - a
        L = d.length
        if L < 1e-4:
            continue
        v.co = a + d * 0.9   # a little in to start with
        L *= 0.9
        hit, nrm, idx, dist = tree.ray_cast(a, d.normalized(), L + 0.3)
        if hit is not None and dist - 0.04 < L:
            v.co = a + d.normalized() * max(0.02, dist - 0.04)
    # the colour: the outermost surface near `colour_at` (the jacket, not a shirt under it)
    dd = ((co_p - np.array(colour_at)) ** 2).sum(1)
    near = np.nonzero(own & (dd < 0.2 ** 2))[0]
    if len(near):
        vi = int(max(near, key=lambda k: (Vector(co_p[k]) - axis_of(Vector(co_p[k]))).length))
    else:
        vi = int(np.argmin(dd))
    uv = None
    for poly in me.polygons:
        for li in poly.loop_indices:
            if me.loops[li].vertex_index == vi:
                uv = me.uv_layers.active.data[li].uv.copy()
                break
        if uv is not None:
            break
    core = bpy.data.meshes.new('core_' + n)
    bm.to_mesh(core)
    bm.free()
    for uvl_name in [l.name for l in me.uv_layers]:
        lay = core.uv_layers.new(name=uvl_name)
        for d in lay.data:
            d.uv = uv if uv is not None else (0.5, 0.5)
    core.materials.append(me.materials[0])
    co_obj = bpy.data.objects.new('core_' + n, core)
    bpy.context.scene.collection.objects.link(co_obj)
    bpy.ops.object.select_all(action='DESELECT')
    co_obj.select_set(True)
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    n0 = len(me.vertices)
    bpy.ops.object.join()
    o.vertex_groups['part_' + n].add(list(range(n0, len(o.data.vertices))), 1.0, 'REPLACE')
    print('CORE', n, len(o.data.vertices) - n0, 'verts, uv', tuple(uv) if uv is not None else None)

_ct = np.array([v.co[:] for v in parts['torso'].data.vertices])
_sh_z = max(piv['armL'].z, piv['armR'].z)
_z0, _z1 = _ct[:, 2].min() + 0.04, _sh_z + 0.06
_c = (_ct.min(0) + _ct.max(0)) * 0.5
add_core('torso', lambda P: (P[:, 2] > _z0) & (P[:, 2] < _z1), lambda p: Vector((_c[0], _c[1], min(max(p.z, _z0 + 0.1), _z1 - 0.1))),
         (_c[0] + (_ct[:, 0].max() - _c[0]) * 0.9, _c[1], _sh_z - 0.25))
for _n in ('armL', 'armR'):   # the top of each sleeve (its open end at the shoulder)
    _p = piv[_n]
    _sx = 1.0 if _p.x > 0 else -1.0
    add_core(_n, lambda P, _p=_p, _sx=_sx: ((P[:, 0] - _p.x) * _sx > -0.05) & ((P[:, 0] - _p.x) * _sx < 0.42),
             lambda p, _p=_p, _sx=_sx: Vector((min(max(p.x * _sx, _p.x * _sx + 0.04), _p.x * _sx + 0.38) * _sx, _p.y, _p.z)),
             (_p.x + _sx * 0.25, _p.y, _p.z + 0.15))

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

def vertex_rgb(n):
    o = parts[n]
    me = o.data
    mat = me.materials[0]
    img = None
    for node in mat.node_tree.nodes:   # the colour texture (not the emissive one)
        if node.type == 'TEX_IMAGE' and node.image and 'emiss' not in node.image.name.lower():
            img = node.image
            break
    if img is None:
        return None
    w, h = img.size
    px = np.array(img.pixels[:]).reshape(h, w, 4)
    uvl = me.uv_layers.active.data
    rgb = np.zeros((len(me.vertices), 3))
    cnt = np.zeros(len(me.vertices))
    for poly in me.polygons:
        for li in poly.loop_indices:
            vi = me.loops[li].vertex_index
            u, v = uvl[li].uv
            rgb[vi] += px[int((v % 1) * (h - 1)), int((u % 1) * (w - 1))][:3]
            cnt[vi] += 1
    return rgb / np.maximum(cnt, 1)[:, None]

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

# hair (27 Nov): what hangs off the head sways on its own bone. Hair is what lies low and out at the sides and back
# of the head (hanging locks, tails, a bob), plus anything sticking up off the top (ears, bunches) at half; the face
# and the front of the skull stay with the head. The bone pivots in the middle of the head.
hx0, hx1 = float(hd[:, 0].min()), float(hd[:, 0].max())
hy0, hy1 = float(hd[:, 1].min()), float(hd[:, 1].max())     # -y is the front
hz0, hz1 = float(hd[:, 2].min()), float(hd[:, 2].max())
hcx, hcy = (hx0 + hx1) * 0.5, (hy0 + hy1) * 0.5
hcz = hz0 + (hz1 - hz0) * 0.55
J['Hair'] = Vector((hcx, hcy, hcz))
J['HairEnd'] = Vector((hcx, hy1, hz0))
# trouser chains (27 Nov): grey metal on the front of a thigh swings from its top
chain_info = {}
for s, n in legs.items():
    l = V[n]
    rgb = vertex_rgb(n)
    li = leg_info[s]
    if rgb is None:
        continue
    mx, mn, lum = rgb.max(1), rgb.min(1), rgb.mean(1)
    front = l[:, 1] < li['cy'] - 0.02
    band = (l[:, 2] > li['knee'] - 0.05) & (l[:, 2] < li['top'] - 0.02)
    grey = (mx - mn < 0.08) & (lum > 0.36) & (lum < 0.85)
    m = front & band & grey
    if m.sum() < 12 or m.sum() > 400:
        continue
    pts = l[m]
    top = float(pts[:, 2].max())
    cx = float(np.median(pts[:, 0]))
    cy = float(np.median(pts[:, 1]))
    J[s + 'Chain'] = Vector((cx, cy, top))
    J[s + 'ChainEnd'] = Vector((cx, cy, float(pts[:, 2].min())))
    chain_info[s] = dict(top=top, bot=float(pts[:, 2].min()), x0=float(pts[:, 0].min()) - 0.02,
                         x1=float(pts[:, 0].max()) + 0.02, y1=cy + 0.06, g=grey)

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
bone('Hair', J['Hair'], J['HairEnd'], 'Head')
for s in chain_info:
    bone(s + 'Chain', J[s + 'Chain'], J[s + 'ChainEnd'], s + 'UpLeg')
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

# shoulders (27 Nov review: jackets opened and cloth flapped at the shoulder). The 1v1 parts overlap there in
# pieces (bits of sleeve in the torso part, bits of jacket in the arm part), so part-by-part weights tore them apart
# as soon as the arm moved. Round each shoulder joint every vertex, whichever part it came from, is weighted by
# where it is: chest on the body side of the joint, arm on the arm side, a smooth blend across it. Overlapping
# pieces then move together like one skin.
for s, n in arms.items():
    ja = np.array(J[s + 'Arm'][:])
    d = np.linalg.norm(co - ja, axis=1)
    sx = arm_info[s]['sx']
    side = ((part_of == 'torso') | (part_of == n)) & (co[:, 0] * sx > 0.12)
    r = ss((0.42 - d) / 0.15) * side                 # how far into the shoulder region
    t = (co[:, 0] - ja[0]) * sx                      # along the arm from the joint
    a = ss((t + 0.1) / 0.25)                         # 0 body side .. 1 arm side
    T = {'Spine2': (1 - a) * 0.7, s + 'Shoulder': 0.3 - 0.15 * a, s + 'Arm': 0.85 * a}
    for k in list(W.keys()):
        W[k] = W[k] * (1 - r)
    for k, v in T.items():
        W.setdefault(k, np.zeros(nv))
        W[k] = W[k] + v * r

# hair: low and out at the sides and back, or up off the top
m = part_of == 'head'
u = np.abs(co[:, 0] - hcx) / max(0.01, (hx1 - hx0) * 0.5)
v = (co[:, 1] - hcy) / max(0.01, (hy1 - hy0) * 0.5)         # + = back
hgt = (co[:, 2] - hz0) / max(0.01, hz1 - hz0)
rho = np.maximum(u, np.abs(v))
low_out = ss((0.6 - hgt) / 0.35) * ss((rho - 0.62) / 0.25) * np.where(v < -0.25, ss((u - 0.82) / 0.12), 1.0)
# (27 Nov review: nothing on top of the head sways any more: hats, hoods and their ears stayed jelly-like)
hw = np.clip(low_out * 0.85, 0.0, 0.85) * m
W['Hair'] = W['Head'] * hw
W['Head'] = W['Head'] * (1 - hw)
# chains: the grey links on the front of the thigh
for s, ci in chain_info.items():
    n = legs[s]
    m = part_of == n
    sel = (co[:, 0] > ci['x0']) & (co[:, 0] < ci['x1']) & (co[:, 2] > ci['bot'] - 0.02) & (co[:, 2] < ci['top'] + 0.02) & (co[:, 1] < ci['y1']) & m
    # only the grey links (by colour), not the cloth round them
    idx = np.nonzero(m)[0]
    g = ci['g']
    local = np.zeros(nv, dtype=bool)
    if len(idx) == len(g):   # the join keeps each part's vertex order
        local[idx] = g
        sel = sel & local
    cw = sel.astype(float) * ss((ci['top'] - co[:, 2]) / 0.12)   # pinned at the top, free below
    for k in list(W.keys()):
        W[k] = W[k] * (1 - cw)
    W[s + 'Chain'] = cw

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
print('RIG hair verts', int((W['Hair'] > 0.05).sum()), 'chains', {s: int((W[s + 'Chain'] > 0.05).sum()) for s in chain_info})

bpy.ops.wm.save_as_mainfile(filepath=blend_out)
bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_skins=True, export_animations=False,
                          export_yup=True, export_apply=False)
print('RIG wrote', dst)
