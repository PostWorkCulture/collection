"""Render a rigged character in test poses (Cycles CPU) to check the weights.
python3 pose_test.py <in.blend> <out_prefix>"""
import sys, math
import bpy
from mathutils import Matrix, Vector, Euler

src, out = sys.argv[-2], sys.argv[-1]
bpy.ops.wm.open_mainfile(filepath=src)
sc = bpy.context.scene
rig = bpy.data.objects['Armature']

def rot(name, axis, deg):
    """rotate a bone about an armature-space axis (X right, Y back, Z up), relative to its rest"""
    pb = rig.pose.bones[name]
    b = rig.data.bones[name]
    R = Matrix.Rotation(math.radians(deg), 3, axis)
    m = b.matrix_local.to_3x3()
    q = (m.inverted() @ R @ m).to_quaternion()
    pb.rotation_mode = 'QUATERNION'
    pb.rotation_quaternion = q @ pb.rotation_quaternion

def reset():
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)

POSES = {
    'rest': [],
    'action': [
        ('LeftArm', 'Y', 70), ('RightArm', 'Y', -40), ('RightArm', 'X', -50),   # left arm down, right arm forward-down
        ('LeftForeArm', 'Z', 70), ('RightForeArm', 'Z', -90),                   # elbows bent
        ('RightUpLeg', 'X', -50), ('RightLeg', 'X', 80),                       # right leg raised, knee bent
        ('LeftUpLeg', 'X', 15), ('LeftLeg', 'X', 20), ('LeftFoot', 'X', -15),
        ('Spine1', 'Z', 12), ('Spine2', 'X', 8), ('Head', 'Z', -20), ('Neck', 'X', 10),
    ],
}

# scene: light, world, camera
world = bpy.data.worlds.new('w'); sc.world = world
world.use_nodes = True
world.node_tree.nodes['Background'].inputs[0].default_value = (0.32, 0.33, 0.36, 1)
world.node_tree.nodes['Background'].inputs[1].default_value = 0.9
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sc.collection.objects.link(sun)
sun.data.energy = 3.5
sun.rotation_euler = Euler((math.radians(50), math.radians(10), math.radians(30)))
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam)
cam.data.type = 'ORTHO'; cam.data.ortho_scale = 4.2
sc.camera = cam
sc.render.engine = 'CYCLES'
sc.cycles.device = 'CPU'; sc.cycles.samples = 24
sc.render.resolution_x = sc.render.resolution_y = 560
sc.render.film_transparent = False
sc.view_settings.view_transform = 'Standard'

VIEWS = {'front': (0, -8, 1.6, 90, 0, 0), 'side': (8, 0, 1.6, 90, 0, 90), 'three_q': (5.6, -5.6, 2.6, 80, 0, 45)}
for pose, ops in POSES.items():
    reset()
    for b, ax, d in ops:
        rot(b, ax, d)
    bpy.context.view_layer.update()
    for vname, (x, y, z, rx, ry, rz) in VIEWS.items():
        if pose == 'rest' and vname != 'front':
            continue
        cam.location = (x, y, z)
        cam.rotation_euler = Euler((math.radians(rx), math.radians(ry), math.radians(rz)))
        sc.render.filepath = f'{out}_{pose}_{vname}.png'
        bpy.ops.render.render(write_still=True)
print('POSE done')
