#!/bin/sh
# Rebuild a character for the game: rig the six-part 1v1 model, then retarget every Mixamo clip onto it.
# sh build_character.sh <id> <1v1 chars dir> <out dir>   (needs python3 with bpy, numpy)
set -e
ID=$1; SRC=$2; OUT=$3
HERE=$(cd "$(dirname "$0")" && pwd)
M=$HERE/mixamo
mkdir -p "$OUT"
python3 "$HERE/rig_wednesday.py" "$SRC/$ID.glb" "$OUT/${ID}_rig.glb" "$OUT/${ID}_rig.blend"
python3 "$HERE/retarget.py" "$OUT/${ID}_rig.blend" "$OUT/$ID.glb" \
  "$M/idle.fbx=idle:loop" "$M/walk.fbx=walk:inplace,loop" "$M/run.fbx=run:inplace,loop" "$M/sprint.fbx=sprint:inplace,loop" \
  "$M/run_back.fbx=run_back:inplace,loop" "$M/strafe_left.fbx=strafe_left:inplace,loop" "$M/strafe_right.fbx=strafe_right:inplace,loop" \
  "$M/strafe_walk_left.fbx=strafe_walk_left:inplace,loop" "$M/strafe_walk_right.fbx=strafe_walk_right:inplace,loop" \
  "$M/crouch_idle.fbx=crouch_idle:loop" "$M/crouch_fwd.fbx=crouch_fwd:inplace,loop" "$M/crouch_back.fbx=crouch_back:inplace,loop" \
  "$M/crouch_left.fbx=crouch_left:inplace,loop" "$M/crouch_right.fbx=crouch_right:inplace,loop" \
  "$M/jump.fbx=jump:inplace,novert" "$M/fall.fbx=fall:inplace,novert,loop" "$M/land.fbx=land:inplace" \
  "$M/ladder_climb.fbx=ladder_climb:inplace,novert,loop" \
  "$M/punch_jab.fbx=punch_jab:inplace" "$M/punch_cross.fbx=punch_cross:inplace" "$M/bat_swing.fbx=bat_swing:inplace" \
  "$M/smg_idle.fbx=smg_idle:loop" "$M/pistol_idle.fbx=pistol_idle:loop" "$M/hit.fbx=hit:inplace" \
  "$M/go_down.fbx=go_down:inplace" "$M/downed_crawl.fbx=downed_crawl:inplace,loop" "$M/get_up.fbx=get_up:inplace" \
  "$M/death.fbx=death:inplace" \
  "$M/box_guard.fbx=box_guard:loop" "$M/box_jab.fbx=box_jab:inplace" "$M/box_cross.fbx=box_cross:inplace" "$M/box_hook.fbx=box_hook:inplace" \
  "$M/bat_hit.fbx=bat_hit:inplace,grip" "$M/smg_aim.fbx=smg_aim:loop,grip" \
  "$M/u_run_fwd.fbx=u_run_fwd:inplace,loop" \
  "$M/r_idle.fbx=r_idle:loop,grip" "$M/r_sprint_fwd.fbx=r_sprint_fwd:inplace,loop,grip" "$M/r_sprint_back.fbx=r_sprint_back:inplace,loop,grip" \
  "$M/r_sprint_left.fbx=r_sprint_left:inplace,loop,grip" "$M/r_sprint_right.fbx=r_sprint_right:inplace,loop,grip" \
  "$M/r_sprint_fwd_left.fbx=r_sprint_fwd_left:inplace,loop,grip" "$M/r_sprint_fwd_right.fbx=r_sprint_fwd_right:inplace,loop,grip" \
  "$M/jump2.fbx=jump2:inplace,novert" "$M/death2.fbx=death2:inplace" "$M/hit_light.fbx=hit_light:inplace" "$M/hit_medium.fbx=hit_medium:inplace" \
  "$M/crouch_idle2.fbx=crouch_idle2:loop" "$M/crouch_walk2.fbx=crouch_walk2:inplace,loop" \
  "$M/walk2.fbx=walk2:inplace,loop" "$M/jump_run.fbx=jump_run:inplace,novert" "$M/death3.fbx=death3:inplace" \
  "$M/crouch_sneak.fbx=crouch_sneak:inplace,loop" "$M/crawl2.fbx=crawl2:inplace,loop" "$M/fight_idle.fbx=fight_idle:loop" \
  "$M/bat_swing2.fbx=bat_swing2:inplace,grip" \
  "$M/cel_victory.fbx=cel_victory:inplace" "$M/cel_victory_idle_vegas.fbx=cel_victory_idle_vegas:inplace,loop" \
  "$M/cel_victory_idle_aj.fbx=cel_victory_idle_aj:inplace,loop" "$M/cel_cheer.fbx=cel_cheer:inplace" "$M/cel_flex.fbx=cel_flex:inplace" \
  "$M/cel_arms_back.fbx=cel_arms_back:inplace" "$M/dance_kick_step.fbx=dance_kick_step:inplace,loop" \
  "$M/dance_raise_roof.fbx=dance_raise_roof:inplace,loop" "$M/dance_running_man.fbx=dance_running_man:inplace,loop" \
  "$M/dance_arm_wave.fbx=dance_arm_wave:inplace,loop" "$M/dance_shimmy.fbx=dance_shimmy:inplace,loop" "$M/dance_tut.fbx=dance_tut:inplace,loop" \
  "$M/dance_step.fbx=dance_step:inplace,loop" "$M/dance_twist.fbx=dance_twist:inplace,loop" "$M/dance_salsa.fbx=dance_salsa:inplace,loop" \
  "$M/dance_side_to_side.fbx=dance_side_to_side:inplace,loop" "$M/pose_hand_hip.fbx=pose_hand_hip:inplace,loop" \
  "$M/pose_happy_idle.fbx=pose_happy_idle:inplace,loop" "$M/pose_bored.fbx=pose_bored:inplace,loop" "$M/pose_bboy.fbx=pose_bboy:inplace"
