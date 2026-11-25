# Collection: plan to AAA

**Status:** approved by Pete on 25 Nov 2026, after he signed off all six phases of `plan.md`. Phase 0 done; next: phase 1 (characters, Wednesday first).

**Goal:** the same game, which is still DESIGN.md (Collection mode, 8 players, The Mansion, 10 stars), made to look, sound and feel like a premium shooter all the way through.

Nothing new gets built until Pete approves it. The new features below were approved on 25 Nov.

## Where we start

- **What's working:** the full game loop, bots at three levels, the web Mansion's look with its moving parts, per-room lights, 3D sound and the menus. It runs at 120–165 fps on High on the RTX 5060 laptop.
- **What looks least premium:**
  1. **Characters.** Everyone is a grey capsule with a band and gloves in their character's colour: no faces, no models, no animation.
  2. **Materials.** The Mansion uses the web game's flat canvas textures, with no surface detail and no real wood, marble or carpet.
  3. **Weapons and hits.** Guns are block models, and recoil, ADS, impacts and hit feedback are basic.
  4. **Front end.** The menus are functional rather than showpieces, and there is no win moment with the characters.

## Decisions (Pete, 25 Nov)

1. **Platform: Windows PC.** The frame-rate budget is set for PC; web and Android may come later as cut-down builds.
2. **Character models: start from the 1v1 Tripo models Pete has just made.** In phase 1, one character (Wednesday) is tried first: its six parts are joined into one body and rigged, then shown to Pete in third person, first person and close up. New higher-detail versions are only made for any character that doesn't hold up close.
3. **New features: yes to all.** Character select with a 3D line-up, the win podium, the kill-cam or "who got you" card, an announcer voice and a first-run tutorial are approved and listed in DESIGN.md.
4. **Asset spend: yes, where needed.** That means Tripo or Meshy credits for characters and props, and ElevenLabs for sound and voice.

## Rules for every phase

- **The design stays as it is.** DESIGN.md rules and the values marked (Pete) hold.
- **Studio rules apply:**
  - Hits show as a red spray and mist.
  - No confetti or coloured particles.
  - White ladders.
  - A realistic premium look that stays minimal and clean.
- **The Mansion flow rules from 24 Nov apply:** wide doorways, furniture against the walls, and nothing covering a window.
- **Every phase ends with Pete playing it.** He gets preview images first, then a build on the PC. Nothing moves on until he's happy.
- **The checks must pass, and frame rate is part of the gate.** The headless checks and the 8-bot match have to pass. The frame-rate budget must hold on High at 1080p:
  - at least 120 fps on the RTX 5060 laptop
  - at least 60 fps on Medium for a mid-range card (GTX 1660 / RTX 3050 class)

## Phases

| # | Phase | What gets built | Gate: what Pete plays and checks | Needs |
|---|---|---|---|---|
| 0 | Groundwork | See below | The game opens instantly in the editor and in a build; the frame-rate readout is on in F3 | — |
| 1 | Characters | See below | Watch an 8-bot match in third person and play in first person: every character reads as themselves, moves naturally, falls and dies convincingly | Tripo credits if a character needs remaking |
| 2 | Weapons and combat feel | See below | A firing range plus a match: every gun feels distinct, ADS feels right, every hit is unmistakable | Pete's ADS notes |
| 3 | The Mansion: materials and light | See below | Walk all 30 rooms and the grounds against the reference shots: it reads as a real house in afternoon light | — |
| 4 | Props and set dressing | See below | Walk every room: each has its own character, and the flow is unchanged | Tripo or Meshy credits |
| 5 | Sound and music | See below | Play a match with headphones: you can place every shot and footstep; the music lifts and drops with the match | ElevenLabs credits |
| 6 | Front end and moments | See below | From launch to rematch, every screen feels finished | — |
| 7 | Bots 2.0 | See below | Play Easy, Normal and Hard: bots feel human, varied and fair | — |
| 8 | Performance, polish, ship | See below | A clean hour of play on the chosen platform; the build is ready to share | How to publish the PC build |

### 0 · Groundwork

- Import the Mansion into the editor once, so it stops loading from the raw file at start-up.
- Set a frame-rate budget and record it in DESIGN.md.
- Take reference shots: 30 rooms plus the lawn, from fixed spots, used to compare before and after every phase.
- Name a "vertical slice" of five rooms (hall, kitchen, bar, gym, master bedroom) to take each art change to final first.

### 1 · Characters

- **Models:** the 10 cast characters from 1v1, each joined into one body and rigged to one shared humanoid skeleton (Wednesday first, as the test); any that don't hold up close are remade at higher detail.
- **Animations:**
  - an 8-way walk and run blend
  - sprint, crouch, jump, fall and land
  - ladder, lift and pole
  - fists and bat swings
  - aiming up and down
  - hit reactions, the downed crawl, and death into a ragdoll
  - a win pose
- **Detail:**
  - feet that plant on stairs
  - heads that look where they're aiming
  - lower detail at a distance
- **First person:** arms and hands match the character you're playing.
- **Pipeline:** the humanoid template and the Mixamo animation skill, with a picture shortlist for Pete before anything is imported.

### 2 · Weapons and combat feel

- **Gun models:** the SMG family, Dual Pistols and the bat, in the 1v1 MP5 style (detailed real-gun shapes, vivid colours).
- **Per-gun handling:**
  - recoil patterns
  - ADS refined to Pete's notes
  - sway and the movement-to-aim blend
- **Effects:**
  - muzzle flash light, shell ejection and tracers
  - impacts per surface (wood, plaster, marble, metal, glass, fabric), with marks that fade
- **Feedback:**
  - hit markers and a cue showing which way damage came from
  - a light camera kick
  - the red spray and mist kept to the studio rule

### 3 · The Mansion: materials and light

- **Materials:** a PBR material library (oak, marble, tile, carpet, plaster, brick, brushed metal, leather, fabric) with real surface and roughness detail. It's mapped onto the web Mansion's surfaces automatically at import, so the layout and colliders stay as they are.
- **Detail on surfaces:** skirting, trims and wear on the walls.
- **Lighting:**
  - baked lighting inside (with real-time bounce light as the fallback)
  - reflections set up per room
  - window light shafts
- **Water:** a proper surface for the pool and hot tubs.
- **Outside:** grass, real trees and hedges, and a sky with soft clouds.

### 4 · Props and set dressing

- **Signature pieces:** 3–5 per room, made with Tripo or Meshy and picked through the picture shortlist (the triposelect skill), replacing the blockiest web props.
- **Physics:** chairs and small items that get knocked about. Smashable pieces get proper breakage, with debris in their own colours.
- **Flow:** the flow rules are kept: furniture against the walls, windows clear.

### 5 · Sound and music

- **Sound effects:** a new ElevenLabs set:
  - every gun, fists and the bat
  - glass, props and doors
  - footsteps per floor type
  - lifts, pole, portals, pool and tubs
- **Mix:** mixed properly on the existing buses.
- **Music:** dark, bass-led trap beats in layers, for the menu, the match and the final star, rising as someone nears 10. A preview goes to Pete before anything is published.
- **Announcer voice:** optional.

### 6 · Front end and moments

- **Already in the design:**
  - the start, pause and settings menus redesigned (minimal, premium)
  - a loading screen
  - HUD polish
  - the results screen
- **New (approved 25 Nov):**
  - character select with the 3D line-up
  - the win podium
  - the kill-cam or "who got you" card
  - the first-run tutorial
- **Settings:** graphics presets, accessibility options (colour-blind-safe markers, subtitles), and a pass over the controller.

### 7 · Bots 2.0

- **Smarter play:** cover and flanking, using doors and windows, and smarter cash-in runs.
- **Personalities:** each character's look matched to a play style, so bots feel human and varied.
- **Tuning:** difficulty set against the match length Pete wants.

### 8 · Performance, polish, ship

- **Rendering performance:**
  - hiding what you can't see (baked occlusion)
  - shaders prepared at load so nothing stutters mid-match
  - lower-detail versions of models at a distance
- **Stability:** an hour-long soak test with no crashes and no stuck bots.
- **Shipping** (once the platform is decided): saved settings, exports for the chosen platform, and capture for a trailer and screenshots.

## After this plan (parking lot)

- Online multiplayer. Family play by room code, one host plus friends, with bots filling the empty slots. It's a large job of its own and is best started once phase 8 is done.

## Results

### Phase 0 · Groundwork (25 Nov 2026)

- The Mansion is imported by Godot instead of read from the raw file at start-up, so the game is playable in 3.4 s instead of 4.8 s. Generated levels of detail and separate shadow meshes are off: with them on, the house drew 15% slower.
- The frame-rate budget is in DESIGN.md. On High it averages 149 fps across 33 spots. Five spots are under 120 fps: games room 99, cinema 104, lawn front 107, lawn back 116 and kitchen 117.
- F3 now shows fps, average and worst frame time, draw calls, triangles, objects and video memory.
- There are 33 reference shots (every room from a fixed spot, both lawns and the shop) with the performance at each, in `docs/screenshots/aaa_reference/` (`perf_high.csv`). The shot run writes `shots/perf.csv` every time, so any later phase can be compared spot by spot.
- The vertical slice is the hall, kitchen, bar, gym and master bedroom.

## How progress is tracked

- **This file:** each phase gets a results section, as `plan.md` did.
- **DESIGN.md:** Build status and the Decision log are updated in the same commit as the code.
- **Previews:** screenshots for each phase go in `docs/screenshots/aaa_<phase>/`.
