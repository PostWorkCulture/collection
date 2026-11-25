"""Render frames of retargeted clips for review.
python3 anim_frames.py <anim.blend> <out_dir> <clip>:<view>:<n_frames> ...   views: front, side, three_q, back"""
import sys, math, os
import bpy
from mathutils import Euler

args = sys.argv[1:]
blend, out = args[0], args[1]
os.makedirs(out, exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=blend)
sc = bpy.context.scene
rig = bpy.data.objects['Armature']
for tr in list(rig.animation_data.nla_tracks):
    tr.mute = True

world = bpy.data.worlds.new('w'); sc.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.32, 0.33, 0.36, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.9
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 3.5
sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(30)))
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0))
floor = bpy.context.active_object
fm = bpy.data.materials.new('floor'); fm.diffuse_color = (0.5, 0.5, 0.52, 1); floor.data.materials.append(fm)
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 4.4
sc.camera = cam
sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 16
sc.render.resolution_x = sc.render.resolution_y = 400
sc.view_settings.view_transform = 'Standard'
VIEWS = {'front': (0, -8, 1.7, 90, 0, 0), 'side': (8, 0, 1.7, 90, 0, 90), 'three_q': (5.6, -5.6, 2.4, 82, 0, 45),
         'back': (0, 8, 1.7, 90, 0, 180)}
for spec in args[2:]:
    clip, view, n = spec.split(':')
    act = bpy.data.actions[clip]
    rig.animation_data.action = act
    f0, f1 = act.frame_range
    x, y, z, rx, ry, rz = VIEWS[view]
    cam.location = (x, y, z)
    cam.rotation_euler = Euler((math.radians(rx), math.radians(ry), math.radians(rz)))
    n = int(n)
    for i in range(n):
        f = f0 + (f1 - f0) * i / n
        sc.frame_set(int(f))
        sc.render.filepath = os.path.join(out, f'{clip}_{view}_{i}.png')
        bpy.ops.render.render(write_still=True)
print('FRAMES done')
