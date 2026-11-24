# DESIGN.md — Godot Collection spec

The single source of truth for what gets built. Code follows this file; if they disagree, this file wins until Pete changes it.
Items marked **TBD** are open: agents must ask, not guess.

## Vision
- **TBD** — one or two sentences on what the collection is (e.g. a set of small, polished Godot games sharing one look and menu).
- Target platforms: **TBD** (PC / Web / Android — Pete tests mobile on a Samsung S24).

## Games
| Folder | Game | Genre / one-liner | Status | Published at |
|---|---|---|---|---|
| **TBD** | | | idea / prototype / playable / done | |

Status meanings: *idea* = design only; *prototype* = runs, rough; *playable* = full loop works; *done* = polished and published.

## Shared look and feel
- Art style: **TBD**
- Colour palette: **TBD**
- UI font(s): **TBD**
- Menu layout shared across games: **TBD**

## Controls
- Keyboard/mouse: **TBD**
- Touch (mobile): **TBD**
- Controller: **TBD**

## Asset pipeline
- 3D models: Tripo (image-to-3D) → Blender clean-up → export `.glb` into the game folder.
- Animations: Mixamo → Blender → `.glb`.
- Sound effects / music: **TBD**
- Naming: `snake_case`, prefixed by type (`chr_`, `wpn_`, `env_`, `sfx_`, `mus_`).

## Autoloads (shared singletons)
| Name | Script | Purpose |
|---|---|---|
| — | — | none yet |

## Publishing
- Method per game: **TBD** (GitHub Pages web export / itch.io / APK).

## Decision log
Newest first. One line per decision: date — decision — why.
- 2026-11-24 — Repo set up with CLAUDE.md + DESIGN.md as the anti-drift source of truth.

## Parking lot
Ideas not yet approved. Nothing here gets built until moved into a section above.
- 
