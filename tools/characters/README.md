# Characters: rig a 1v1 model and move Mixamo clips onto it

Needs Python 3 with `bpy` (Blender as a module, 5.x) and `numpy`.

1. **Rig** — `rig_wednesday.py <1v1 model .glb> <out_rig.glb> <out_rig.blend>` joins the six parts (torso, head,
   arms, legs) into one body, turns the arms out into a T-pose and builds a 24-bone Mixamo-named skeleton with
   smooth weights at the joints.
2. **Clips** — download from Mixamo (FBX Binary, Without Skin, 30 fps, no keyframe reduction, In Place for
   locomotion) one at a time into `mixamo/`, and note each in `mixamo/mixamo.json`. The FBX files stay on Pete's PC
   (Mixamo's terms allow them in games, not re-sharing the library); they aren't committed.
3. **Retarget** — `retarget.py <rig.blend> <out.glb> <clip.fbx>=<name>[:flags] ...` copies each clip onto the rig
   (flags: `inplace`, `novert`, `loop`, `grip` for two-handed holds, `turn` for a clip that faces backwards). It also writes `<out>.json` with each clip's
   frames, loop flag and the speed it travels, which the game uses to keep the feet on the ground.
4. **All of it** — `sh build_character.sh wednesday <1v1 chars dir> <out dir>` rigs and retargets every clip in one
   go; copy `<out>/wednesday.glb` and `wednesday.json` into `collection/characters/wednesday/`.

Checking: `anim_frames.py <anim.blend> <out dir> <clip>:<view>:<frames> ...` renders frames of clips (views front,
side, three_q, back); `pose_test.py` renders the rest pose. In the game, `autotest.json` with `"character": true`
plays every action on the lawn and saves side, front and gameplay shots to `shots/char_*.png`.
