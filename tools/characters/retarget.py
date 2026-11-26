"""Retarget Mixamo clips (FBX, any Mixamo character, T-pose rest) onto our rig and export one GLB with all clips.

python3 retarget.py <rig.blend> <out.glb> <clip.fbx>=<name>[:flag,flag] ...
flags: inplace (remove travel across the floor, keep sway), novert (hips keep their rest height: for clips in the air,
where the game moves the body), loop, grip (two-handed holds: the left hand is put back where the source has it
relative to the right hand, by two-bone IK on the left arm, so a gun or bat held in both hands stays in both hands
on our shorter arms and wider shoulders; it fades out when the source lets go), turn (the source faces backwards:
turn it round 180 degrees). A <out>.json next to the GLB records each clip's frames, loop and the speed it
travelled in the source (model units per second), so the game can match the feet to its own speed.
World-space rotation transfer: for each mapped bone, the rotation the source bone has made away from its T-pose rest
is applied to our bone's T-pose rest. The hips' height is scaled by the ratio of hip heights. With ':inplace' the hips'
travel across the floor is removed (the sway is kept), so the game moves the character itself.
"""
import sys, math
import bpy
from mathutils import Matrix, Quaternion, Vector

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
rig_blend, out_glb, clips = args[0], args[1], args[2:]

bpy.ops.wm.open_mainfile(filepath=rig_blend)
D = bpy.data.objects['Armature']
BONES = ['Hips', 'Spine', 'Spine1', 'Spine2', 'Neck', 'Head']
for s in ('Left', 'Right'):
    BONES += [s + n for n in ('Shoulder', 'Arm', 'ForeArm', 'Hand', 'UpLeg', 'Leg', 'Foot', 'ToeBase')]
# parents first
order = []
def walk(b):
    if b.name in BONES:
        order.append(b.name)
    for c in b.children:
        walk(c)
for b in D.data.bones:
    if b.parent is None:
        walk(b)

def rest_q(arm, name):
    return (arm.matrix_world.to_3x3().normalized() @ arm.data.bones[name].matrix_local.to_3x3().normalized()).to_quaternion()

d_rest = {n: D.data.bones[n].matrix_local.to_3x3().normalized().to_quaternion() for n in BONES}
d_hips_head = D.data.bones['Hips'].head_local.copy()
ml = {n: D.data.bones[n].matrix_local.copy() for n in BONES}
lrel = {}
for n in BONES:
    p = D.data.bones[n].parent
    if p is not None and p.name in BONES:
        lrel[n] = (ml[p.name].inverted() @ ml[n]).translation.copy()

def fk(world, hp):
    """armature-space head of every bone for these armature-space rotations and hips offset"""
    pos = {}
    for n in order:
        p = D.data.bones[n].parent
        if p is None or p.name not in BONES:
            pos[n] = ml[n].translation + hp
        else:
            pos[n] = pos[p.name] + world[p.name] @ lrel[n]
    return pos

def arm_ik(world, pos, side, target):
    """two-bone IK: turn the upper arm and forearm so the wrist reaches target; the elbow keeps its side"""
    A, F, H = side + 'Arm', side + 'ForeArm', side + 'Hand'
    S, E, W = pos[A], pos[F], pos[H]
    a, b = (E - S).length, (W - E).length
    d = target - S
    L = min(max(d.length, abs(a - b) + 1e-4), (a + b) * 0.999)
    dn = d.normalized()
    pole = (E - S) - dn * (E - S).dot(dn)
    if pole.length < 1e-5:
        pole = Vector((0, 0, -1)) - dn * dn.z
    pole.normalize()
    ca = (a * a + L * L - b * b) / (2 * a * L)
    E2 = S + dn * (a * ca) + pole * (a * math.sqrt(max(0.0, 1 - ca * ca)))
    T2 = S + dn * L
    r1 = (E - S).rotation_difference(E2 - S)
    world[A] = r1 @ world[A]
    r2 = (r1 @ (W - E)).rotation_difference(T2 - E2)
    world[F] = r2 @ r1 @ world[F]

made = []
meta = {}
for spec in clips:
    path, rest = spec.split('=')
    name, _, flagstr = rest.partition(':')
    flags = set(flagstr.split(',')) if flagstr else set()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    S = [o for o in new if o.type == 'ARMATURE'][0]
    sact = S.animation_data.action
    f0, f1 = int(sact.frame_range[0]), int(sact.frame_range[1])
    pre = 'mixamorig:' if 'mixamorig:Hips' in S.data.bones else ''
    s_rest = {n: rest_q(S, pre + n) for n in BONES}
    s_hips_rest = S.matrix_world @ S.data.bones[pre + 'Hips'].head_local
    scale = d_hips_head.z / s_hips_rest.z

    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    D.animation_data_create()
    D.animation_data.action = act
    frames = list(range(f0, f1 + 1))
    hips_pos = []
    poses = []
    grips = []
    for f in frames:
        bpy.context.scene.frame_set(f)
        mw = S.matrix_world
        world = {}
        for n in BONES:
            pq = (mw.to_3x3().normalized() @ S.pose.bones[pre + n].matrix.to_3x3().normalized()).to_quaternion()
            world[n] = pq @ s_rest[n].inverted() @ d_rest[n]       # our bone's armature-space rotation (D is unrotated)
        hp = mw @ S.pose.bones[pre + 'Hips'].head
        if 'grip' in flags:
            Rs = mw @ S.pose.bones[pre + 'RightHand'].head
            Ls = mw @ S.pose.bones[pre + 'LeftHand'].head
            dR = world['RightHand'] @ d_rest['RightHand'].inverted()
            gap = (Ls - Rs).length
            grips.append((dR.inverted() @ (Ls - Rs) * scale, gap))
        hips_pos.append(Vector(((hp.x - s_hips_rest.x) * scale, (hp.y - s_hips_rest.y) * scale, (hp.z - s_hips_rest.z) * scale)))
        poses.append(world)
    if 'turn' in flags:   # the source faces backwards (Mixamo's ladder climb): turn the whole clip round to face the way the rest do
        R = Quaternion((0.0, 0.0, 1.0), math.pi)
        for k, world in enumerate(poses):
            for n in world:
                world[n] = R @ world[n]
            hips_pos[k] = R @ hips_pos[k]
    travel = (Vector((hips_pos[-1].x, hips_pos[-1].y, 0)) - Vector((hips_pos[0].x, hips_pos[0].y, 0))).length
    secs = max(1, len(hips_pos) - 1) / 30.0
    meta[name] = {'frames': len(hips_pos), 'loop': 'loop' in flags, 'speed': round(travel / secs, 4)}
    if 'novert' in flags:
        for p in hips_pos:
            p.z = 0.0
    if 'inplace' in flags and len(hips_pos) > 1:
        a, b = hips_pos[0].copy(), hips_pos[-1].copy()   # copies: the loop below changes hips_pos[0] itself
        for i, p in enumerate(hips_pos):
            t = i / (len(hips_pos) - 1)
            p.x -= a.x + (b.x - a.x) * t
            p.y -= a.y + (b.y - a.y) * t
    if grips:
        s_h = s_hips_rest.z            # source hips height: hands closer than 0.55 of it are holding the same thing
        def reach(pos, side):
            return ((pos[side + 'ForeArm'] - pos[side + 'Arm']).length + (pos[side + 'Hand'] - pos[side + 'ForeArm']).length) * 0.97
        for i in range(len(frames)):
            world = poses[i]
            rel, gap = grips[i]
            w = min(1.0, max(0.0, (0.7 * s_h - gap) / (0.15 * s_h)))
            if w <= 0.0:
                continue
            pos = fk(world, hips_pos[i])
            dR = world['RightHand'] @ d_rest['RightHand'].inverted()
            off = dR @ rel
            # both hands meet around their midpoint, drawn in towards the chest until both arms can reach
            mid = (pos['RightHand'] + pos['LeftHand']) * 0.5
            for _ in range(12):
                gr, gl = mid - off * 0.5, mid + off * 0.5
                if (gr - pos['RightArm']).length <= reach(pos, 'Right') and (gl - pos['LeftArm']).length <= reach(pos, 'Left'):
                    break
                mid = mid.lerp(pos['Spine2'], 0.15)
            arm_ik(world, pos, 'Right', pos['RightHand'].lerp(gr, w))
            pos = fk(world, hips_pos[i])
            arm_ik(world, pos, 'Left', pos['LeftHand'].lerp(gl, w))
    for i, f in enumerate(frames):
        world = poses[i]
        for n in order:
            pb = D.pose.bones[n]
            pb.rotation_mode = 'QUATERNION'
            par = D.data.bones[n].parent
            if par is None or par.name not in BONES:
                basis = d_rest[n].inverted() @ world[n]
                pb.location = d_rest[n].inverted() @ hips_pos[i]
                pb.keyframe_insert('location', frame=f - f0 + 1)
            else:
                pn = par.name
                basis = d_rest[n].inverted() @ d_rest[pn] @ world[pn].inverted() @ world[n]
            # keep quaternions continuous
            prev = pb.rotation_quaternion.copy()
            if i > 0 and prev.dot(basis) < 0:
                basis.negate()
            pb.rotation_quaternion = basis
            pb.keyframe_insert('rotation_quaternion', frame=f - f0 + 1)
    tr = D.animation_data.nla_tracks.new()
    tr.name = name
    tr.strips.new(name, 1, act)
    D.animation_data.action = None
    for pb in D.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
    made.append((name, len(frames)))
    # drop the source
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    if sact.users == 0:
        bpy.data.actions.remove(sact)
print('RETARGET', made)
bpy.ops.wm.save_as_mainfile(filepath=out_glb.replace('.glb', '.blend'))
bpy.ops.export_scene.gltf(filepath=out_glb, export_format='GLB', export_skins=True, export_animations=True,
                          export_animation_mode='NLA_TRACKS', export_force_sampling=True, export_yup=True)
import json
json.dump(meta, open(out_glb.replace('.glb', '.json'), 'w'), indent=1)
print('RETARGET wrote', out_glb)
