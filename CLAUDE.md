# CLAUDE.md — rules for any AI agent working in this repo

Read this file and `DESIGN.md` before doing anything. If a request conflicts with either, stop and ask Pete before changing code.

## What this repo is
- **Collection** (`PostWorkCulture/collection`): one Godot game — the Collection mode from imok 1v1 (8 players, The Mansion, find 10 stars, cash in at the shop) rebuilt as a standalone game. Spec: DESIGN.md.
- Engine: **Godot 4.7.x stable**, GDScript only (no C#) unless DESIGN.md says otherwise.
- Reference for porting: `PostWorkCulture/1v1`, branch `collection-v1`, commit `76738cc`, `index.html` (port the logic, don't copy three.js code). The 1v1 README has the full Mansion layout.
- Values in DESIGN.md marked **(Pete)** are locked. Other numbers are the browser build's and may be tuned, but record any change in the Decision log.
- Local working copy: `Documents\AI\Claude\Projects\Games\Collection Godot` on the "bakes" PC.
- `main` on GitHub is the source of truth. Local copies, chat history and memory are not.

## Anti-drift rules
1. **DESIGN.md is the spec.** Do not add, remove or rename features, games, characters, maps, controls or art style unless DESIGN.md already says so or Pete asks.
2. **Same-commit rule.** Any change to a design decision updates DESIGN.md (and its Decision log) in the same commit as the code.
3. **No silent scope creep.** Ideas go in DESIGN.md → "Parking lot", not into code.
4. **Start every session with:** `git pull`, read CLAUDE.md + DESIGN.md, `git status`. Say if the working tree is dirty before touching it.
   The active plan is `docs/collection/plan_aaa.md` (the finished one is `docs/collection/plan.md`); read its Status line and the phase you're working on.
   **After a context compaction** (or when unsure what was agreed), do the same before carrying on: re-read DESIGN.md (Build status, Known issues, latest Decision log entries) and the plan's Status line, and run `git status` and `git log --oneline -10`. Chat history before the compaction is not a source of truth.
   **Keep the logs current as you go:** anything agreed with Pete, tried and rejected, or left half done goes into DESIGN.md (Decision log / Known issues / Build status) in the same commit, and the plan's Status line moves when a phase does. Before a long task or a natural break, write down where things stand so nothing lives only in the chat.
5. **One task per commit.** Don't bundle unrelated fixes.
6. If something in the code disagrees with DESIGN.md, report it; don't "fix" either side on your own.

## Structure
One Godot project in `/collection/` (open `collection/project.godot`). Folders are grouped by feature, scene and script side by side:
```
/collection/project.godot, main.tscn, main.gd   entry point
/collection/autoload/      singletons (settings.gd)
/collection/game/          the match node: state and clock, fighters, stars, pickups, shop cash-in, win, respawns, glass, kill feed
/collection/characters/    rigged characters: character_model.gd (animation tree, clip speeds, emotes), spine_twist.gd and hand_ik.gd
                           (after-animation turns and hand IK), one folder per character (<id>.glb + <id>.json clip list)
/collection/fighter/       player/bot body, movement, camera, health, weapons in hand; bot_brain.gd (the bots); dummy_brain.gd for tests
/collection/weapons/       weapon stats (from the web game), block models, hit/gun effects
/collection/pickups/       weapon pickups
/collection/stars/         the gold star (mesh, hum, dropped stars)
/collection/ui/            HUD, minimap and menus (start, pause, settings, keys)
/collection/audio/         sfx.gd (buses, wall muffling) + sfx/ and music/ (1v1's own sound and music files)
/collection/level/         Mansion builder + mansion_layout.json (colliders, ladders, lifts, spawns, short cuts), mansion.glb (its look,
                           exported from the web game with /tools/mansion_export/), mansion_features.gd (lifts, pole, trampolines,
                           portals, pool, ball pit, ballroom, windows, hot tubs, Hall of Fame, star ceiling, telescope),
                           mansion_edits.gd (Pete's room changes on top of the export), hall_of_fame/ (its posters),
                           mansion_lights.gd (each room's lights), water/caustics/sky shaders
/collection/autotest.json  scripted checks ("enabled": true runs them and quits; "combat" and "stars" check fights and Collection rules on standing dummies; "bots_match" plays a whole 8-bot match, with "difficulty", "match_secs" and "speed"; "menu" walks the start screen, pause, settings and rebinding; "mansion" rides the lifts, pole, trampolines and portals and tries the pool and ball pit; "bots": false leaves the house empty for preview shots; "shots" are the 33 AAA reference spots and each run writes `shots/perf.csv` with fps, worst frame, draw calls and triangles per spot)
/collection/<feature>/     new features get their own folder
/docs/screenshots/         preview images for Pete, one folder per phase
/tools/                    helpers outside the game (mansion_export: rebuilds level/mansion.glb from the web game, then surface_pass.py adds its normal and roughness maps; characters: rigs a 1v1 model and moves the Mixamo clips onto it, see its README; hall_of_fame: makes the trophy room's posters)
```
Update DESIGN.md → "Build status" when a part moves forward.

## Godot conventions
- Files and folders: `snake_case` (`player_controller.gd`, `main_menu.tscn`).
- Scripts load each other with `const Name := preload("res://...")`, not `class_name`: runs from the command line (Godot MCP, headless checks) don't have the editor's class list. Don't add autoloads either; the open editor rewrites `project.godot`.
- Static typing everywhere (`var speed: float = 5.0`, typed function args and returns).
- One script per scene root; signals over direct node paths across scenes.
- Autoloads listed in DESIGN.md; don't add one without recording it.
- Commit `.tscn`, `.tres`, `.gd`, `.import`, `project.godot`, `export_presets.cfg`. Never commit `.godot/` or build output (see `.gitignore`).
- Large binaries (models, audio, textures over ~50 MB): ask before adding; use Git LFS if needed.

## Before committing
- Run the checks: set `collection/autotest.json` to `"enabled": true` (with `"combat"`, `"stars"` and `"mansion"` true), run it (Godot MCP `run_project`, or headless: `godot --headless --path collection`), read the results in `collection/shots/autotest.txt` and any script errors in the console (`get_debug_output`), then set it back to `false`. Headless runs skip the screenshots.
- Commit message: `<area>: <what changed>` e.g. `stars: add spawn spacing`, `bots: add room exploring`, `docs: update DESIGN.md`.
- Studio rules (DESIGN.md §10) apply to every change: no confetti/coloured particles, red spray + mist for hits, realistic premium look, white ladders.

## Publishing
- Anything new that Pete will see (models, rooms, effects, UI): show him preview images first, then push.
- Push to `main` unless Pete says otherwise. Say what was pushed and the commit hash.
- End every reply with "Published" or "Unpublished".
- Platforms and build publishing aren't decided yet (DESIGN.md → "Open questions"); don't set up exports until Pete picks.
