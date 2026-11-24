# DESIGN.md — Collection (Godot rebuild) spec

The single source of truth for what gets built. Code follows this file; if they disagree, this file wins until Pete changes it.

**Origin:** the Collection mode from imok 1v1 (browser/three.js), rebuilt as its own Godot game. Numbers come from the last working code: `PostWorkCulture/1v1`, branch `collection-v1`, commit `76738cc`, `index.html`. Items marked **(Pete)** are Pete's design decisions and must not change without him. Everything else is how it was built and can be improved.

Units: metres, seconds. Y is up.

## 1. Pitch
8 players in a big two-floor mansion. Everyone spawns outside on the lawns with only their fists. Gold stars are hidden around the inside of the house, and guns (20 bullets, no reload) and bats are lying about. Find 10 stars, then get back outside to the shop on the front lawn and stand at it to cash in. The first player to cash in wins. Getting knocked down costs you 2 stars, and dying loses all of them. Anyone holding 8 or more stars glows through walls and shows on everyone's minimap, so the leader is hunted.

## 2. Rules
| Rule | Value |
|---|---|
| Players | 8, always (you plus 7 bots; online later) **(Pete)** |
| Map | The Mansion only **(Pete)** |
| Start | First spawn of the match is on the front and back lawns, spread out, facing the house **(Pete)** |
| Starting kit | Fists only: no loadout, no lethals/grenades, no build walls, no armour plates **(Pete)** |
| Stars to win | 10 stars held, then cash in at the shop outside; first to cash in wins **(Pete, final: 10 replaced an earlier 5)** |
| Going down (knocked) | Lose 2 stars immediately |
| Dying (bled out or finished) | Lose all stars |
| Revealed | 8+ stars: outlined through walls (x-ray) for everyone, plus a gold star on every minimap, pinned to the rim when out of range **(Pete, final: 8 replaced an earlier 4)** |
| Bot targeting | Bots lean slightly towards whoever has the most stars; anyone close still comes first **(Pete)** |
| Time limit | None: the clock counts up |
| Respawn | 3 s after death, anywhere on the map (like free for all), fists only again |
| Effects | No particle bursts or confetti on pickups (studio rule) **(Pete)** |

## 3. Stars
- 14 on the map at all times (`ON_MAP = 14`).
- Spawn only inside the house: both floors, never the roof, never outside.
- Spawn spot: random walkable floor spot in the main connected nav area that a body fits in (no deep water), at least 7 m from every other star, visible pickup and living player. Vertical separation over 3 m also counts as clear.
- Pick-up: within 1.2 m horizontally and 1.6 m vertically. Not while downed, dead, doing a finisher, or already holding 10.
- Replacement: when a star is taken, a new one appears at least 12 m from where it was taken. Backup: if fewer than 14 are on the map, one more appears every 4 s.
- Look: chunky gold 5-point star, extruded ~0.07 m with bevelled edges, ~0.85 m across. Metal: colour `#ffc83a`, metalness 0.85, roughness 0.22, emissive `#a8700a` at 0.55. Floats 1.05 m up, spins ~1.6 rad/s, bobs ±0.08 m. Nothing on the floor under it **(Pete, 24 Nov: no circles under stars)**.
- Sound: "bing" pitched ×1.25, audible ~14 m.

## 4. Weapon pickups
- 8 pickups: 6 guns + 2 bats (`GUN_PICKS = 6`, `BAT_PICKS = 2`).
- Gun pool (random each time): MP5, Uzi, Vector, P90, UMP, Sting (SMGs) and Dual Pistols.
- 20 bullets, no reloading. Empty → automatically back to fists ("out of bullets: back to fists").
- Can't grab a new gun while the current one has 10+ bullets. Can't take a bat if you already have one.
- Placement: 80% inside the house, 20% on the lawns, at least 6 m from other stars, pickups and players.
- Respawn: 15 s after being taken, somewhere new (`PICK_BACK = 15`).
- Look: weapon model floating, turning slowly, over a thin white ring (torus r 0.62 m) whose opacity pulses.
- Feed text: "You picked up a Vector (20 bullets)" / "picked up a bat".
- Bats go in the fists slot (a gun stays in the gun slot). Bots always hold a found gun when they have one.

### Weapon stats
dmg = damage per hit (100 HP players); rate = seconds between shots; fall = full damage up to the first distance, falling off by the second.

| Weapon | dmg | head × | rate (s) | fall (m) | Notes |
|---|---|---|---|---|---|
| Fists | 34 | 1 | 0.36 | reach 2.7 | 3 punches to down; small lunge (3) |
| Bat | 50 | 1 | 0.55 | reach 3.0 | 2 hits to down; big knockback (lunge 5) |
| MP5 | 16 | 1.6 | 0.055 | 8–26 | shreds up close |
| Uzi | 18 | 1.7 | 0.07 | 10–30 | punchy close range |
| Vector | 14 | 1.6 | 0.045 | 7–22 | fastest SMG, empties in ~1 s |
| P90 | 15 | 1.5 | 0.06 | 9–26 | near-perfect hip fire |
| UMP | 18 | 1.6 | 0.095 | 20–48 | longer range |
| Sting | 8 | 1.5 | 0.036 | 6–18 | machine pistol, quickest swap |
| Dual Pistols | 30 | 1.8 | 0.16 | 10–28 | alternate fire |

SMGs: iron sights only, aim-down-sights in 0.07 s. With fists or a bat out you run 20% faster. Aiming with fists or a bat does nothing.

## 5. Players
- 100 HP; regen after 3 s without being hit, 10 HP/s.
- Run ~12.7 m/s (11.25 × 1.125); jump 12 m/s **(Pete)**; gravity 36; double jump. Players and bots share one speed. Weapon weight: SMGs +3–6%, Dual Pistols +8%.
- Downed: at 0 HP you go down instead of dying. Crawl slowly with 30 downed HP; enemies can shoot you to death or finish you. Otherwise you get up on your own after 5 s **(Pete)** with the downed HP you had left. 15 s bleed-out timer exists only as a backstop. Downed players give off faint dark-red smoke, never green. A downed player must never visibly pass through walls.
- Finishers on a downed enemy (**not in the first build (Pete)**; a downed player is finished by shooting or hitting them): random, 25% each: Pancake, Heartbreaker, Roast, Combat. Can't be interrupted. "Eliminated" shows at the top as soon as one starts.
- Boxing gloves in each character's colours when fists are out.
- Characters **(Pete, 24 Nov: the same cast as imok 1v1)**: Wednesday, Lil Pink, North West, Johnny Rotten, Emo Bunny, Glitch, Kitty, Puffa, Raven, Toxic — the 10 playable characters in 1v1's `CHARS` (main, commit `879f706`), each with its colour from there. Tripo models (same blocky style and six-part rig) are in the 1v1 repo's `chars/` and come in with the art pass; until then everyone is a grey capsule with a band and gloves in their character's colour (you: blue). Each match the 7 bots are drawn at random from the 10. The dev-only Shadow (roboid) isn't in the cast.

## 6. Shop / cash-in point
- One shop on the front lawn facing the front door: x 9, z −33 (house centred at 0,0; front = −z).
- Same neon vending machine as the main game (~1.5× character height, glowing SHOP lightbox, pulsing pad). Sells nothing; it's only the cash-in point.
- Cash in: hold 10 stars and stand within its use radius (~2–3 m). Win is instant.
- With 10 stars the HUD says "Cash in at the shop outside", and a centre message shows "10 stars / Get outside to the shop and cash them in" for 2.6 s.

## 7. Bots (8-player AI)
- Search like a person: a bot only knows about a star or weapon it has actually seen (line of sight, within 9 m Easy / 15 m Normal / 20 m Hard, under 4 m height difference, checked every 0.3 s). It remembers it until the item is taken.
- Priority each think:
  1. Holding 10 stars → run to the shop.
  2. Enemy in its face (under 7 m with fists/bat, under 13 m with a gun) → fight.
  3. Nearest known star or weapon. Distance = horizontal + 3 × vertical. Weapons count 4 m closer when unarmed. Ignore gun pickups while armed, and bats if it has one.
  4. Nothing known → explore room to room: random indoor spot 8–32 m away; re-pick after 10–16 s or on arrival.
- Keeps shooting at anyone further off while moving to its goal.
- Target choice: usual scoring (visible, recently shot by, downed, current target, revenge) plus a lean of 1.5 × stars (max 10) towards players with more stars. Marked players (8+) are always "seen" for tracking.
- Styles: melee/Rumble pool (rush, flank, etc.), not sniper/camper.
- Difficulty Easy/Normal/Hard. Easy: slower reactions, wider aim, no headshots, 30% less damage, no revenge hunts.
- Browser build bots spent ~30% of their time on the lawns. Keep them mostly indoors (bias goals inside), and let them use portals, the launch trampoline and lifts.

## 8. HUD and menus
- Standalone game: Collection is the whole game (no mode picker). Hidden: player count, map picker, teams, loadout, match length.
- Menu blurb: "Fists, then whatever you find. 8 players in The Mansion: everyone starts on the lawns with just fists. SMGs and pistols (20 bullets each, no reloads) and bats lie around the house. Find 10 of the gold stars hidden inside, then get outside to the shop on the front lawn to cash them in: first to cash in wins. Go down and you lose 2 stars; die and you lose them all. Anyone holding 8 or more glows through walls and shows on every minimap."
- Loading card: "Collection · 8 players · The Mansion" / "Start with fists · find 10 hidden stars · cash them in at the shop outside · first to cash in wins".
- Goal text: "Cash in 10 stars".
- Star counter: centred under the scoreboard: gold ★, "n / 10"; panel gets a gold border at 10.
- Leaderboard: all 8 sorted by stars, then kills. Columns: Players · ★ · K · D. You in blue, others red; dead players dimmed.
- Kill feed: "You found a star (n/10)", "X has 8 stars: they're marked", "X has 10 stars and is heading for the shop", "You lost 2 stars (n/10)", "X lost 2 stars".
- Minimap: circular. Marked players = gold 5-point star with dark outline, clamped to the rim when off-range. Floor label: GROUND / 1ST FLOOR / ROOF.
- End: "Victory" / "X wins" with "cashed in 10 stars", then the results scoreboard.
- Style: monochrome UI (black cards, thin grey edges, white Arial type), colour only as a highlight. Gold `#ffc83a` is the Collection accent.

## 9. The Mansion
Full map: 1v1 repo README, "The Mansion". Key points:
- Plot 120 × 90 m; house ~80 × 54 m, red brick, two floors plus a walkable roof and roof terrace. Clipped-hedge grounds; fountain and lamp-lit drive out front.
- 15 rooms per floor on a 5 × 3 grid, each with its own colours, lighting and props, doorways in every wall so there are loops everywhere.
- Ground floor: kitchen, dining room, foyer (front door, porch with 2 outer pillars), library, conservatory, games room, cinema, grand hall (double height, 4.4 m grand staircase), indoor pool (wadeable, springboard), gym (trampolines, launch trampoline up to the trophy room), bar (mostly smashable glass), ballroom (disco floor, moving lights, own music), gallery, music room, garage (black textured walls, flickering lights, 2 dirt bikes on wall racks).
- Upstairs: master bedroom, dressing room, landing, study, observatory, playroom (ball pit), spa (hot tub), atrium walkway round the hall void, guest room, trophy room, panic room, kids' room, hall of mirrors, lab, roof terrace.
- Vertical links: grand staircase, kitchen back stairs, garage stairs to the terrace, 2 lifts, fireman's pole (both ways), launch trampoline, 2 portal pairs linking opposite corners, 3 outside ladders to the roof (2 front, 1 back) plus a terrace-to-roof ladder.
- Glass: glass walls between many rooms, windows all round (all jump-through, ground-floor ones breakable), 6 bulletproof glass floor panels upstairs, one-shot glass skylights in the roof.
- Lawns: only front and back are open; sides closed with invisible walls up past the roof edge.

Mansion rules **(Pete)**:
- Nothing covers windows or glass ceilings.
- Disco lights stay inside the ballroom.
- Stairs clear at top and bottom, with low guardrails.
- No black poles in doorways.
- Hot tubs: white stone surround, jets only, on a wooden deck, no ducks.
- Ball pit balls fly everywhere when you walk or jump in.
- Must run smoothly with 8 players: only light the room you're in, cull rooms you can't see, batch static meshes.

## 10. Studio rules (apply to everything) (Pete)
- Keep the design as minimal and clean as possible (24 Nov): no decoration a rule doesn't need.
- No confetti, coloured particle squares or over-the-top sparks; hits use a red spray with a mist puff.
- No black zig-zag cracks or smoke on damaged buildings.
- All upright glass breaks with one hit and shatters into tiny shards that settle on surfaces; floor/roof glass is tougher.
- White ladders, not crate hop-ups.
- Realistic, premium look, never toy-like.
- Show Pete preview images before publishing anything new.
- End every reply with "Published" or "Unpublished".

## 11. Original code reference (port, don't copy)
`index.html` at `PostWorkCulture/1v1` branch `collection-v1`:

| Part | What's there |
|---|---|
| `CO` | Config: `{STARS:10, LOSE:2, AMMO:20, MARK:8, ON_MAP:14, GUN_PICKS:6, BAT_PICKS:2, PICK_BACK:15}` |
| `coCands()` | Indoor and lawn spawn candidates |
| `coPick()` | Spaced random pick |
| `coAddStar()` | Star placement |
| `coPlacePick()` / `coTake()` | Weapon pickups |
| `coSpawns()` | Lawn start spawns |
| `coStar()` / `coLose()` | Gaining and losing stars |
| `updCollect()` | Per-frame loop and win check |
| `coLook()` / `coGoal()` | Bot perception and goals |
| `coLB()` / `coHUD()` | Leaderboard and star counter |
| `mansion()` | Map builder; `M.house` (footprint) and `M.coShop` (shop spot) |

## 12. Godot architecture
- **CollectionGame** (autoload): owns the config above, match state (countdown → fight → won), the count-up timer and the win check.
- **StarSpawner**: pool of 14 `Star` scenes (Area3D + mesh); candidate points baked from the NavigationMesh, filtered to the house volume.
- **PickupSpawner**: 6 gun + 2 bat `Pickup` scenes with respawn timers.
- **Fighter** script shared by Player and Bot: `stars: int`, `downed`, `alive`; signals `star_taken`, `downed`, `died`.
- **Bot AI** (`fighter/bot_brain.gd`): drives a Fighter through the same inputs you use; NavigationAgent3D on a navigation mesh baked at match start from the level's collision boxes, with a link up every ladder; sight memory by raycasts every 0.3 s; goal priority from section 7.
- **X-ray outline** for marked players: second material pass with depth test off (or stencil outline shader), shown only when stars ≥ 8.
- **Minimap**: top-down SubViewport or drawn 2D icons; gold star icons for marked players, clamped to the circle edge.

### Autoloads
| Name | Script | Purpose |
|---|---|---|
| Settings | `collection/autoload/settings.gd` | saved camera mode (third/first), FOV, mouse sensitivity |

CollectionGame is **not** an autoload: it is a node (`collection/game/collection_game.gd`) that `main.gd` creates as "Game" and hands to every fighter. It runs the match: countdown (3 s) → fight → won, the count-up clock, fighters, stars, pickups, the shop cash-in, respawns, glass and the kill feed.

## Build status
| Part | Status |
|---|---|
| Godot project skeleton | done (phase 1) |
| The Mansion | grey-box from `mansion_layout.json`, ladders, shop placeholder (phase 1); the web Mansion's own look in `level/mansion.glb` (every room's finishes, furniture, lamps, signs, ladders, the shop kiosk) over the same colliders; sunk indoor pool; fireman's pole, 2 lifts, gym trampolines (launch one up to the trophy room), 2 portal pairs, wading and springboard, ball pit, ballroom dance floor / disco ball / moving beams / music; bots use the lifts, pole, launch trampoline and portals (phase 6, first part); smooth stairs, windows you can jump through or climb over, each room's own lights (phase 6, second part) |
| Fighter / player movement | movement, jump, crouch, ladders, third/first-person camera (phase 1) |
| Weapons + pickups | fists, bat, 6 SMGs + Dual Pistols with the web stats; 20-bullet pickups (6 guns + 2 bats); first-person hands and iron-sight aiming (phase 2) |
| Health, down, death, respawn | 100 HP + regen, downed (30 HP, crawl, up after 5 s), finished = dead, respawn 3 s furthest from others, 2 s spawn shield (phase 2) |
| Effects + sound | red spray + mist on hits, muzzle flash, thin tracers, dust, dark-red downed wisps (phase 2); glass breaks into shards that bounce and settle (pooled, 360 max); sounds on Weapons / SFX / Music / Voice buses, muffled through walls (duller behind one wall, more behind two or a floor), room echo (hall rings, ground floor some, upstairs soft, outside dry), footsteps and landings from 1v1, menu and match-end music from 1v1 (phase 5) |
| Look | AgX tonemapping, sun shadows, colour grading; Medium adds bounce light (SDFGI), ambient occlusion, glow; High adds indirect light (SSIL), screen-space reflections, a reflection probe per room, light shafts / haze (volumetric fog); Low is plain and fast (phase 5) |
| Stars + cash-in | 14 indoor stars with the spacing and replacement rules, 3D hum, down −2 / death all dropped as 20 s pickups, marked at 8 (red X-ray through walls), 2 s cash-in at the shop, win and results, Enter to play again (phase 3) |
| Bots | 7 bots picked from 1v1's ten characters with the web game's Easy/Normal/Hard numbers and Rumble styles; sight memory, hearing (shots and punches), §7 priorities and target scoring, ladders, unsticking; F3 debug view (phase 4) |
| HUD / minimap / menus | combat HUD (phase 2); leaderboard, clock, ★ counter, minimap, cash-in bar, edge flash, loading card, win and results (phase 3); start screen (Play, Bots, Settings, Quit), pause (Resume, Settings, Quit to menu), settings (graphics, FOV, camera, sensitivity, five volumes in 10% steps), key and mouse rebinding with reset, controller navigation, aim assist on Easy with a controller (phase 5) |

## Approved improvements (Pete, 23 Nov 2026)
Agreed with Pete in the rebuild plan ([`docs/collection/plan.md`](docs/collection/plan.md), which also holds the visuals, sound, HUD and phase-gate plan). Built so far: the spawn shield (phase 2), third person as default, dropped stars, the 8-star cue and edge flash, star hum, and the 2 s cash-in (phase 3).
- Lost stars drop where you fell as pickups for 20 s (instead of vanishing).
- 2 s spawn shield, broken by attacking.
- Sound cue and screen-edge flash when someone reaches 8 stars. With the reveal also at 8, this is the cue for a player becoming marked.
- Stars hum quietly in 3D, so you can find one by ear through a wall.
- Cash-in takes 2 s standing still at the shop (interruptible), replacing the instant win in section 6.
- Default camera is third person; first person is a setting.

## Known issues
- Match pace (24 Nov, for Pete to judge): with 8 bots a match lasts about 30–90 s (Normal/Hard often under a minute, Easy 1–2 minutes). Every number involved (14 stars, 10 to win, 12.7 m/s running, 15 m sight) is the web game's, so nothing was changed; if it's too quick, the levers are fewer stars out, more to win, or shorter bot sight.
- Aiming down sights needs refining (Pete, 24 Nov): details to agree with Pete.
- Matches have got quicker since phase 6 (24 Nov, headless 8-bot runs): Normal about 25 s, Easy about 40 s (Easy was 1–2 minutes). Smooth stairs, lifts and short cuts get bots to stars faster. For Pete to judge with the match pace note above.
- Still to come in phase 6: smashable props (trophy cups, bar bottles, crates; all solid for now), hot tub jets, hiding rooms you can't see.

## Open questions
- Target platforms (PC / Web / Android) and publishing method: not decided.

## Decision log
Newest first. Date — decision — why.
- 2026-11-24 — Phase 6, second part, waiting for Pete. Stairs (Pete: felt rough): an invisible ramp over each of the three staircases touches the front edge of every step, so you glide up and down (biggest climb in one frame 0.06 m, was a 0.34–0.39 m pop per step), and the view eases up any other step instead of jumping. Windows (Pete: too tight): jumping at a window crashes through the glass (as on the web), and once it's open you climb over the 0.8 m sill just by walking into it. Lights: the even grid of lamps is replaced by each room's own, from the web room table: four ceiling fittings in the room's tint, plus a stronger mood light in eleven rooms (library, games room, cinema, hall, pool, bar, panic room, kids' room, hall of mirrors, lab, observatory) that pulses, shimmers or changes colour as on the web; the garage strip lights stutter, one badly. Only your room and the rooms next to it on your floor are lit, and only your own room's mood light casts shadows (Medium and High), which keeps 150–165 fps; the cinema, panic room and observatory are dim but never black.
- 2026-11-24 — Phase 6, first part, waiting for Pete. The Mansion's look is the web game's own, exported from 1v1 `collection-v1` as one glTF file (`level/mansion.glb`, 10.5 MB, tool in `tools/mansion_export/`) from the same build as `mansion_layout.json`, so walls, floors and furniture line up with the colliders box for box; Godot draws the glass itself so it can still break. Choices made while building, all easy to change: lifts take you when you step into the car from any side (the web only took you walking one way, which the pool lift's wall blocked); the pole, trampolines, portals, springboard, ball pit and dance floor use the web numbers (14 m/s lifts and pole, launch 7.2 m, wading 20% slower, springboard 13 m/s); the bouncy trampolines hit the gym ceiling at about 3.3 m, as on the web; the web's light beams and glows were additive, glTF can't store that, so faint unlit see-through materials are drawn additive at half strength; the ballroom plays 1v1's disco track (Music bus, heard through its doors) and its coloured light has shadows on so it stays in the room; the ball pit's balls are reset at each countdown; sprites, outline edges and the web's lights aren't exported (the house keeps phase 5's lighting for now).
- 2026-11-24 — Phase 5 (look and sound) built, waiting for Pete. Choices made while building, all easy to change: no vignette (the plan had a slight one; dropped to keep the design minimal and clean); graphics default to High; volumes default Master 100%, Weapons / Effects / Voice 80%, Music 60%; room echo follows the 5 × 3 room grid (centre-middle is the double-height hall) until phase 6 gives each real room its own; one set of footsteps for every floor, softer and lower on the lawns (1v1 has no per-surface steps), quieter crouched and crawling, and bots hear every fourth running step within 10 m; the start screen plays 1v1's first menu track and the results play its match-end track (the other two menu tracks and the rounds track stay in 1v1 for now); aim assist pulls gently (up to about 1.2 rad/s) towards anyone within 8° and 40 m, only on Easy and only while you're using a controller; the bat now visibly swings in first and third person (Pete's note); Esc on the results goes back to the start screen, Enter plays again straight away; the B difficulty key is gone (it's on the start screen now).
- 2026-11-24 — Cast replaced with 1v1's current 10 characters (Pete); the old list (Anti Hero, Starscreen, Crusty, Dracz, Gorillaz, Jet, Murda Medic, Spacebot) is retired.
- 2026-11-24 — Phase 4 (bots) built, waiting for Pete. Choices made while building, all easy to change: the bots' difficulty and style numbers are the web game's own tables (Easy: 2.2 s reaction, 10° aim error, no headshots, 70% damage; Hard: 0.4 s, 1.6°, 26% headshot aim); styles are picked at random each match from the Rumble pool (rusher, lurker, flanker, duelist, hunter, breacher) with no repeats until all six are used; hearing covers gunshots (40 m) and punches (12 m), footsteps come with the phase 5 footstep sounds; bots climb ladders and drop down from the top (no fall damage); a bot that can't reach a goal gives it up, and a stuck bot wriggles and hops before choosing again; respawns skip the 3 roof spawns (they always measured furthest, which put a third of all bot time on the roof); players are never a moving platform for each other (standing on someone who respawned used to launch you); B during the countdown or on the results screen cycles the difficulty (saved) until the phase 5 menu; F3 shows each bot's state, style, what it has seen, its target and its route. Lifts, the pole, portals and trampolines aren't in the grey box yet, so bots will learn them in phase 6.
- 2026-11-24 — **Collection is a standalone Godot game** (Pete): the Godot rebuild carries on past phase 5 rather than being judged against the web game, and the Mansion gets built out in full after the grey box (phase 6). Stars lose their floor glow disc and the design stays minimal and clean (Pete).
- 2026-11-24 — Phase 3 (Collection rules) built, waiting for Pete. Choices made while building, all easy to change: 7 test dummies so there are 8 players on the leaderboard (they don't collect stars until the bots in phase 4); the shop's cash-in spot is 1.7 m in front of it with a pulsing white pad, within 2.2 m counts; cash-in restarts if you move faster than 2 m/s, get hurt or go down; lost stars drop in a ring about 1 m round where you fell, so whoever gets there can scoop several at once; the minimap is 60 m across, turns with you, and shows only you and marked players (nothing else is in the spec); the X-ray is red (the plan's "red outline, as on the web") using Godot 4.7's built-in X-ray material, and you can see your own glow when you're marked; the star hum is a soft two-note tone made in code (the web game has no hum file); marked and 10-star feed lines also show for you ("You have 8 stars: you're marked"); the gong plays when anyone becomes marked; the G test-gun key is gone. Star spots come from the floor grid, not a nav mesh yet, so a star could land somewhere hard to reach until phase 4 bakes one.
- 2026-11-24 — Phase 2 (combat) built, waiting for Pete's play-through. Choices made while building, all easy to change: a bat dropped by a downed player lies where they fell for 20 s (the plan says "dropped" but not for how long; 20 s matches dropped stars); all upright glass and roof skylights break in one hit, upstairs glass floor panels don't (studio rule + Mansion "bulletproof floor panels"); shards fall and vanish rather than settle (settling comes with the phase 5 glass pass); fighters are solid to each other, downed ones aren't (so you can walk over them); first-person hands push out as the view zooms so the gun keeps its size on screen; 6 test dummies stand on the lawn and in the house (2 strafe) and go back to their spot when they respawn; **G** cycles through every gun and the bat (test aid, removed in phase 3); sounds play from where they happen, but muffling through walls and room echo wait for phase 5.
- 2026-11-24 — CollectionGame is a node made by `main.gd`, not an autoload; scripts load each other with `preload` instead of `class_name` — the open editor rewrites project.godot, and command-line runs (Godot MCP, headless checks) don't have the editor's class list, so both keep the game runnable either way.
- 2026-11-24 — Pete settled the four open questions: reveal at 8 stars; jump 12 m/s (the web fighter's real value); downed players get up on their own after 5 s (30 downed HP, 15 s bleed-out only as a backstop); finishers left out of the first build. Star loss confirmed as down = −2, death = all (Pete's instruction in the 1v1 chat, 23 Nov).
- 2026-11-24 — Rebuild plan from Pete's 1v1 chat added as `docs/collection/plan.md`, with its approved improvements recorded above — the plan was agreed before this repo existed.
- 2026-11-24 — Phase 1 committed: Godot project lives in `/collection/`, grouped by feature; `Settings` autoload added — matches the build already started.
- 2026-11-24 — DESIGN.md replaced with the Collection build spec; repo is one Godot game, not a set of games — Pete supplied the spec.
- 2026-11-24 — Repo set up with CLAUDE.md + DESIGN.md as the anti-drift source of truth.

## Parking lot
Ideas not yet approved. Nothing here gets built until moved into a section above.
- Online multiplayer (8 players; bots fill empty slots).
