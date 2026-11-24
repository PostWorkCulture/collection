# CLAUDE.md — rules for any AI agent working in this repo

Read this file and `DESIGN.md` before doing anything. If a request conflicts with either, stop and ask Pete before changing code.

## What this repo is
- **Godot Collection** (`PostWorkCulture/collection`): Pete's collection of Godot games.
- Engine: **Godot 4.7.x stable**, GDScript only (no C#) unless DESIGN.md says otherwise.
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
```
/                    repo root (this file, DESIGN.md, README.md)
/<game-name>/        one folder per game, each its own Godot project (project.godot inside)
/shared/             reusable scripts, shaders, UI, audio shared between games
/docs/               extra notes, screenshots
```
New game = new folder + a row in DESIGN.md → "Games".

## Godot conventions
- Files and folders: `snake_case` (`player_controller.gd`, `main_menu.tscn`). Classes: `class_name PascalCase`.
- Static typing everywhere (`var speed: float = 5.0`, typed function args and returns).
- One script per scene root; signals over direct node paths across scenes.
- Autoloads listed in DESIGN.md; don't add one without recording it.
- Commit `.tscn`, `.tres`, `.gd`, `.import`, `project.godot`, `export_presets.cfg`. Never commit `.godot/` or build output (see `.gitignore`).
- Large binaries (models, audio, textures over ~50 MB): ask before adding; use Git LFS if needed.

## Before committing
- Run the affected game (Godot MCP `run_project`) and check `get_debug_output`: zero errors, no new warnings.
- Commit message: `<game>: <what changed>` e.g. `bman: add bomb chain reaction`, `repo: update DESIGN.md`.

## Publishing
- Push to `main` unless Pete says otherwise. Say what was pushed and the commit hash.
- Web builds (if a game is published to GitHub Pages) are exported from the game's "Web" preset; see DESIGN.md → "Publishing".
