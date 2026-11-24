# Collection – Godot rebuild plan

Written 23 Nov 2026 with Pete; moved into this repo 24 Nov 2026 (original: claude.ai doc "imok Collection – Godot rebuild plan").
The rules and numbers live in `/DESIGN.md` (the spec, which wins if the two disagree). This file keeps the agreed plan: improvements, visuals, sound, HUD and the phase gates.

## Goal and scope

Build Collection as its own Godot 4.7 project: a playable grey-box Mansion with every current rule, real lighting, positional sound and smarter bots, so we can judge Godot against the web game before going further. The web game at postworkculture.github.io/1v1 keeps running untouched.

**In the first build**

- One mode (Collection), one map (a grey-box Mansion with the same layout and scale), 8 players: you plus 7 bots.
- First person and third person cameras, fists, the SMG family, Dual Pistols and the bat as pickups.
- Stars, the cash-in shop, going down, dying, respawning, the x-ray outline and minimap marker for leaders.
- Proper lighting, shadows, reflections, post effects and 3D sound (sections below).
- Keyboard and mouse, plus an Xbox/PlayStation controller.

**Not in the first build**

- Other modes, other maps, finishers, lethals, the shop's lucky dip, detailed character models and skins (everyone is a grey capsule figure with a coloured band).
- Online multiplayer, mobile touch controls and the web export. All three are designed for, so nothing blocks them later.

**Where it runs:** a Windows desktop build on Pete's PC "bakes" (Godot 4.7.2). Agents write and run it through the Godot MCP connection.

## Rules

The Godot version keeps every Collection rule from the web game, plus the five improvements below.

**Kept as they are now**

| Rule | Value in the web game |
| --- | --- |
| Players | 8 (you + 7 bots), free for all |
| Map | The Mansion only: 120 × 90 m grounds, 80 × 54 m house, 2 floors, sides fenced off |
| First spawn | Everyone on the front and back lawns, spread out, facing the house |
| Respawn | 3 s after dying, anywhere on the map, furthest from other players |
| Start kit | Fists only: no loadout, lethals, walls, armour or shop items |
| Fists | 3 punches to down someone, 20% faster movement while fists are out |
| Gun pickups | 6 at a time: a random SMG (MP5, Uzi, Vector, P90, UMP, Sting) or Dual Pistols, 20 bullets, no reload; back to fists when empty; respawn elsewhere 15 s after being taken |
| Bat pickups | 2 at a time, replace fists, 2 hits to down, dropped when you go down |
| Stars | 14 hidden inside the house (both floors, never the roof); each one taken is replaced at once by a new one at least 12 m away |
| Win | Hold 10 stars, reach the shop on the front lawn, stand at it: first to cash in wins |
| Going down | Lose 2 stars on the spot |
| Dying | Lose every star you hold |
| Leaders | 8+ stars: outlined through walls for everyone and pinned on every minimap (Pete, 24 Nov; the web game used 4) |
| Time | No limit; the clock counts up |
| Health | 100, no armour; downed players crawl with 30 downed HP and get up on their own after 5 s unless finished off (Pete, 24 Nov) |

**Improvements (approved by Pete, all five)**

- Stars you lose are dropped where you fell as pickups for 20 s, so a kill is worth chasing (today they just vanish).
- A short spawn shield (2 s, broken by attacking) so respawns are never instant deaths.
- A sound cue and screen-edge flash when someone reaches 8 stars, so the endgame has tension.
- Stars hum quietly in 3D, so you can find one by ear through a wall.
- The cash-in takes 2 s standing still at the shop (interruptible), so a last-second defence is possible.

## Player systems

Every player, you and the bots, is the same `Fighter` scene, so bots obey exactly the same physics, weapons and rules you do.

- **Movement:** `CharacterBody3D` with walk, sprint (stamina), crouch, jump and double jump, step-up onto stairs and kerbs, and ladder climbing. Speeds and jump heights copied from the web game's numbers (jump 12 m/s), so it feels the same before we tune it.
- **Camera:** third person over the shoulder by default, as on the web; first person as a setting, with the hands and weapon drawn in front. Third person returns automatically while downed, as on the web.
- **Fists and bat:** a short sphere-cast in front on each swing; damage, swing rate and the 20% fists speed boost as now. Boxing-glove hands in first person.
- **Guns:** hitscan with spread and recoil per gun, aim down sights, 20-bullet pickups, empty = back to fists. Muzzle flash, tracer, shell casing and impact decal per shot.
- **Health and going down:** 100 HP, then downed (crawl with 30 downed HP, get up on your own after 5 s, can be finished by a punch or shots; 15 s bleed-out only as a backstop). Down costs 2 stars; death costs all.
- **Pickups:** one `Pickup` scene for stars, guns and bats, an `Area3D` that triggers on touch, with the spin and bob of the web version.
- **Respawn:** 3 s later at the spawn point furthest from other players; your first spawn is on the lawns.

## Project structure

Split into small scenes and scripts instead of one 14,000-line file, so a change to bots can't break the HUD. You and the bots drive the same Fighter scene; everything a Fighter does (a hit, going down, touching a star) is sent as an event to the game rules, which keep scores and decide the win.

Target layout inside `collection/` (phase 1 has `autoload/settings.gd`, `fighter/fighter.gd`, `level/` and `main.gd` so far):

```
collection/
  project.godot
  autoload/   game.gd  audio.gd  settings.gd
  fighter/    fighter.tscn  fighter.gd  player_input.gd  bot_brain.gd
  weapons/    fists.gd  gun.gd  bat.gd  guns.tres (stats per gun)
  pickups/    pickup.tscn  star.tscn  shop.tscn
  level/      level_builder.gd  mansion_layout.json (exported from the web game)
  ui/         hud.tscn  menus.tscn
  audio/      sfx/ (copied from the web game)  reverb presets
  tests/      headless checks run before each build
```

## Grey-box Mansion

The grey box copies the web Mansion's floor plan to the metre (room, door, window and stair positions exported straight from the web game's code into `level/mansion_layout.json`), built from plain blocks so the layout can be tested before any art goes in.

- **Shell:** 120 × 90 m grounds, 80 × 54 m house, ground floor and first floor, the same 30 rooms, doors, windows you can jump through, stairs with low guardrails, the lifts and the pole drop. Sides fenced off; front and back lawns open.
- **Grey-box look:** walls, floors and props in light grey with a grid texture (1 m squares, so distances read at a glance); one muted tint per room so you can tell them apart; doorways and stairs edged in a lighter tone.
- **Breakables:** ground-floor windows and roof glass shatter in one hit, as now. Furniture starts as simple solid blocks.
- **Outside:** flat lawn, hedges and the fountain as simple shapes; the shop as a box with a lit SHOP sign on the front lawn, facing the front door.
- **Hiding spots:** star positions picked from the walkable floor inside the house, never the roof, at least 12 m from the last one taken, as on the web.
- **Navigation:** a baked `NavigationMesh` over both floors, with links for stairs, lifts, the pole drop and window jumps.

## Bots

Bots play by your information: they only go for stars and weapons they have actually seen, and they hunt by sight and sound, not by knowing where you are.

- **Pathing:** Godot's `NavigationAgent3D` on the baked mesh, with avoidance so 8 players don't bunch up in doorways.
- **Searching:** a bot remembers stars and pickups it has seen (line of sight, within 9 m on Easy, 15 m on Normal, 20 m on Hard). With nothing spotted it explores rooms it hasn't checked lately instead of wandering at random.
- **Hearing (new):** gunshots, punches and footsteps make noise; a bot that hears one may go and look, which suits the 3D sound below.
- **Fighting:** fight anyone within 7 m (fists, bat) or 13 m (guns), shoot at others while moving; aim error, reaction time and turn speed by difficulty, from the web game's Easy, Normal and Hard values.
- **Picking targets:** nearest and visible first, a slight lean towards whoever holds more stars; marked leaders are known through walls, as for you.
- **Endgame:** with 10 stars a bot runs for the shop and fights only what blocks the way.
- **Debug view:** a toggle that draws each bot's path, what it has seen and what it's doing, so tuning is quick.

## Visuals

Even in grey, the build uses Godot's full lighting, so it already looks better than the web game; the art pass later only swaps the surfaces. All of it uses the Forward+ renderer, with a Low / Medium / High setting.

| Effect | What you'll see | Godot feature |
| --- | --- | --- |
| Bounce light | Sunlight through windows lights the rooms; colour from a red wall tints the floor | SDFGI (global illumination) |
| Shadows | Soft sun shadows outside, lamp shadows inside | Directional + omni lights with soft shadows |
| Reflections | Glossy floors, glass and the pool reflect the room | Screen-space reflections + reflection probes per room |
| Light shafts | Dusty sunbeams through windows, haze in the hall | Volumetric fog |
| Ambient shading | Corners and under furniture darker | SSAO and SSIL |
| Post effects | Bloom on lamps and the SHOP sign, colour grading, slight vignette | Glow, tonemapping, adjustments |
| Stars | Gold metal stars with a soft glow, no particle bursts | Emissive material, light per star on High |
| Leader outline | Red outline through walls, as on the web | Second camera pass with depth test off |
| Glass | Thin, very clear, shatters into small falling shards | Rigid-body shards, pooled |
| Guns | Muzzle flash, light tracer, shell casings, bullet holes | GPU particles (small and quick, no confetti squares), decals |
| Hits | Red spray with a mist puff, as now | GPU particles |
| Downed | Subtle red smoke, as now | GPU particles |

What stays out: no confetti, coloured squares, block bursts, crack lines or building smoke, matching the rules already set for the web game.

## Sound

The web game's own sound files carry over (fists, guns, glass, star bing, the double-jump air puff, the gong), so it sounds familiar from day one; what changes is how they're placed in the house.

- **3D positional sound:** every sound comes from where it happened, louder close up and panned left or right (`AudioStreamPlayer3D`).
- **Through walls:** a sound in another room is muffled and quieter, judged by a quick check of what's between you; you can tell "upstairs" from "next door".
- **Room echo:** each room gets its own reverb, set by its size and surfaces: the grand hall and pool echo, carpeted bedrooms are dead, outside is open.
- **Footsteps:** per surface (wood, tile, carpet, grass), quieter when crouched, so sneaking matters.
- **Mixing:** separate buses for Weapons, SFX, Music and Voice, matching the web game's Weapons and SFX volume settings.
- **Game cues:** a distinct cue when you pick up a star, and a warning sound with the screen-edge flash when anyone reaches 8 stars and becomes marked.

## HUD, menus and controls

The HUD and menus copy the web game's monochrome look (black and white, red highlights), so both versions feel like one game.

- **HUD:** the same layout as the web: leaderboard top left (all 8 by stars, then K and D), scoreboard top centre with the count-up clock, the ★ n / 10 counter under it, circular minimap top right with gold stars for marked players, health and stamina bottom left, weapon and ammo bottom right, kill feed under the minimap.
- **Menus:** a simple start screen (Play, Bots: Easy / Normal / Hard, Settings, Quit), pause with Resume and Settings, and the results screen with W/L and the stars table.
- **Settings:** graphics quality, field of view, camera (first / third person), sensitivity 0–10, volumes in 10% steps, key rebinding.
- **Keyboard and mouse:** the web game's key bindings carried over as they are (WASD, Space jump and double jump, C crouch, 1/2/3 weapons, wheel up next weapon, wheel down fists, P or Esc pause).
- **Controller:** sticks to move and look, triggers to aim and fire, bumpers to swap, with aim assist on Easy.

## Build plan

Six phases (the sixth added 24 Nov, when Pete settled on Godot for Collection as its own game); each ends with Pete playing it, and nothing moves on until he's happy with the last. Status (24 Nov): phases 1–4 are built; phases 2 and 3 are published. Pete played phases 1 and 2 (notes in DESIGN.md → Known issues); phases 3 and 4 wait for him to play.

| Phase | What gets built | Gate: what Pete plays and checks |
| --- | --- | --- |
| 1 · Foundations | Godot project, repo, grey-box Mansion built from the web layout; one Fighter: walk, sprint, crouch, jump, ladders, both cameras | Walk the Mansion: rooms, stairs, scale feel right. **Built; waiting for Pete's walk-through.** |
| 2 · Combat | Fists, the SMG family, Dual Pistols, bat; 20-bullet pickups; health, downed, death, respawn; test dummies to hit | Fight a few dummies: punches and guns feel right. **Built; waiting for Pete.** |
| 3 · Collection rules | Stars, shop cash-in, 2 lost when downed, all lost on death; leader outline and minimap marker; HUD and leaderboard | Play a full solo match: find 10 stars and cash in. **Built; waiting for Pete.** |
| 4 · Bots | Nav mesh, searching by sight, hearing, fighting, targeting; 7 bots at Easy, Normal, Hard; a debug view of what they see | Play full 8-player matches: bots feel fair at every level. **Built; waiting for Pete.** |
| 5 · Look and sound | Lighting, reflections, fog, post effects, particles, glass; 3D sound through walls, room echo, menus, settings, controller | Play it with everything switched on (Pete decided on 24 Nov to carry on in Godot regardless) |
| 6 · The Mansion in full | The grey box built out into the real Mansion: every room's look, props, glass, lifts, pole, portals, trampolines, ball pit, pool, lighting per room (DESIGN §9) | Walk every room and play full matches |

How each phase is checked before it reaches Pete:

- **Headless checks** run on every change: the project opens without errors, a scripted match plays for 2 minutes with 8 bots, stars spawn inside the house, nobody falls through the floor, and the win triggers at the shop.
- **Screenshots and a short clip** from fixed spots (lawn, hall, upstairs, shop) sent with each phase. Phase 1 shots are in `docs/screenshots/`.
- **A playable build** on the PC at every gate; Pete's notes go straight into the next phase.

### Phase 4 results (24 Nov 2026)

- The navigation mesh bakes at match start (2,011 polygons) with all 7 ladders linked; paths run lawn → front door → hall, room to room, and up the stairs to the first floor.
- 8-bot matches (you on autopilot as an eighth bot), run headless at 3× speed: Easy 71–126 s, Normal 27–49 s, Hard 26–40 s; at normal speed on the PC, Normal took 65 s with 26 eliminations.
- No bot stood still at any 15 s check in the last 11 matches; after the opening run in from the lawns, bots spend 1–4% of their time outside and none on the roof.
- The leader runs for the shop with 10 stars and cashes in; stars change hands constantly as players go down.
- Screenshots in `docs/screenshots/phase4/`.

### Phase 3 results (24 Nov 2026)

- 14 stars out at once, all inside the house, closest pair on the same floor 7.2–8 m apart; a taken star comes back straight away 13–47 m away.
- With 10 stars you can't take an 11th; the counter turns gold with "Cash in at the shop outside".
- 8 stars marks a player: red X-ray through walls, gold star on the minimap, gong and gold screen-edge flash, feed line.
- Going down drops 2 stars where you fell; dying drops the rest; they can be picked up for 20 s.
- Standing still at the shop with 10 stars wins after 2.0 s (2.3–2.4 s with screenshots being saved); Victory, then the results table, Enter plays again.
- Screenshots in `docs/screenshots/phase3/`.

### Phase 2 results (24 Nov 2026)

- Fists: 3 punches down a dummy (34 each); left alone it gets up after 5 s with 30 HP; one punch downs it again and one more finishes it; it respawns 3 s later with a 2 s shield.
- MP5 aimed at 10 m: 20 of 20 bullets hit, down then eliminated. Dual Pistols hip-fired at a strafing dummy 7 m away: about half hit.
- Every gun empties its 20 and drops back to fists: Sting 1.0 s, Vector 1.3, MP5 1.4, P90 1.6, Uzi 1.7, UMP 2.2, Dual Pistols 3.5 (including the 0.3 s swap).
- Pickups: 1,594 floor spots inside the house and 878 on the lawns; walking onto a gun gives it with 20 bullets; it comes back elsewhere 15 s later.
- You: going down and being finished shows the down and eliminated screens; respawn lands at the spot furthest from everyone (33 m away in the test), fists only, with the shield.
- 140–165 fps on the RTX 5060 laptop with 7 fighters. Screenshots in `docs/screenshots/phase2/`.

### Phase 1 results (23 Nov 2026)

- 165 fps on the RTX 5060 laptop at 1600×900.
- Run 10.35 m in 1 s; jump 2.05 m; double jump 3.90 m.
- Staircase climbs; front door walkable; ladder reaches the roof (y 11.35).
- `autotest.json` (`enabled: false` by default) drives a scripted walk and saves screenshots to `shots/`.

## Decisions before building (23 Nov 2026)

- **Improvements:** all five go in.
- **Where the project lives:** originally `Games\imok-godot` on the PC; moved into this repo as `collection/` on 24 Nov 2026.
- **Default camera:** third person, as on the web; first person in Settings.

Also worth knowing: online multiplayer and a phone build are designed for but not built; the art pass (real Mansion textures, Pete's Tripo models and characters) comes after he's played the grey box.
