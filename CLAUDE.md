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
5. **One task per commit.** Don't bundle unrelated fixes.
6. If something in the code disagrees with DESIGN.md, report it; don't "fix" either side on your own.

## Structure
One Godot project in `/collection/` (open `collection/project.godot`). Folders are grouped by feature, scene and script side by side:
```
/collection/project.godot, main.tscn, main.gd   entry point
/collection/autoload/      singletons (settings.gd)
/collection/fighter/       player/bot body, movement, camera
/collection/level/         Mansion builder + mansion_layout.json
/collection/autotest.json  scripted walk/screenshot checks ("enabled": true runs them and quits)
/collection/<feature>/     new features get their own folder: stars/, pickups/, bots/, ui/ ...
/docs/screenshots/         preview images for Pete
```
Update DESIGN.md → "Build status" when a part moves forward.

## Godot conventions
- Files and folders: `snake_case` (`player_controller.gd`, `main_menu.tscn`). Classes: `class_name PascalCase`.
- Static typing everywhere (`var speed: float = 5.0`, typed function args and returns).
- One script per scene root; signals over direct node paths across scenes.
- Autoloads listed in DESIGN.md; don't add one without recording it.
- Commit `.tscn`, `.tres`, `.gd`, `.import`, `project.godot`, `export_presets.cfg`. Never commit `.godot/` or build output (see `.gitignore`).
- Large binaries (models, audio, textures over ~50 MB): ask before adding; use Git LFS if needed.

## Before committing
- Run the affected game (Godot MCP `run_project`) and check `get_debug_output`: zero errors, no new warnings.
- Commit message: `<area>: <what changed>` e.g. `stars: add spawn spacing`, `bots: add room exploring`, `docs: update DESIGN.md`.
- Studio rules (DESIGN.md §10) apply to every change: no confetti/coloured particles, red spray + mist for hits, realistic premium look, white ladders.

## Publishing
- Anything new that Pete will see (models, rooms, effects, UI): show him preview images first, then push.
- Push to `main` unless Pete says otherwise. Say what was pushed and the commit hash.
- End every reply with "Published" or "Unpublished".
- Platforms and build publishing aren't decided yet (DESIGN.md → "Open questions"); don't set up exports until Pete picks.
