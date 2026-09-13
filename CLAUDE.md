# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`YooBoxAdventure` is a **2D precision platformer** (Super Meat Boy lineage) in Godot 4.7 / GDScript, targeting an **RK3566 handheld running Linux with no Vulkan**. Built on Maaack's Game Template: the plugin's `examples/` were copied to the project root during setup and then edited in place, so `scenes/`, `scripts/`, `resources/`, and `assets/` look like the plugin's examples but live outside `addons/`.

The Godot binary on this machine is `/Applications/Godot.app/Contents/MacOS/Godot`.

Two constraints follow from the target hardware and should not be regressed:

- **No Vulkan.** `project.godot` uses `renderer/rendering_method = "gl_compatibility"` with `textures/vram_compression/import_etc2_astc = true`. Do not switch to Forward+ or Mobile, and prefer ETC2/ASTC-compressed textures.
- **Weak mobile GPU (Mali-G52).** Fill rate and per-frame 2D physics are the budget. Keep collision shape counts low (the tile builder merges tiles into runs for this reason), avoid large transparent overdraw, and avoid per-frame allocations in `_physics_process`.

`addons/**` is vendored third-party code. Prefer editing the project-root copies.

## Commands

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot

# Run the game (main scene = res://scenes/opening/opening.tscn)
$GODOT --path .

# Run a specific level or scene
$GODOT --path . res://scenes/game/levels/level_1.tscn

# Reimport assets; surfaces parse errors and broken resource references
$GODOT --headless --path . --import
```

### Checks (run these after touching levels, physics, or save data)

There is no CI. Five scripts under `tools/` are the test suite; each exits non-zero on failure and prints what went wrong.

```bash
# 1. The movement envelope, and whether level 1's geometry is actually playable
python3 tools/verify_level_geometry.py

# 2. The direction-toggle control scheme (auto-run, flipping, wall-jump turn)
$GODOT --headless --path . --script res://tools/test_control_scheme.gd

# 3. Every level bakes terrain, spawns a player, places a goal
$GODOT --headless --path . --script res://tools/smoke_test_levels.gd

# 4. Save/progression behaviour (unlocks, best times, persistence, reset)
$GODOT --headless --path . --script res://tools/test_progression.gd
```

`tools/measure_jump_arc.gd` measures the real jump arc by running the actual scene headless. `verify_level_geometry.py` mirrors the same physics in Python, which is much faster; when a number looks wrong, run the measurement and compare. (They should agree: 1.84 tiles held, 3.86 tiles range.)

Level scenes are **generated** — see "Level authoring" below. Regenerating and re-verifying is the normal loop:

```bash
python3 tools/build_level_maps.py                                          # rewrite the ASCII maps
python3 tools/verify_level_geometry.py                                     # check they are playable
$GODOT --headless --path . --script res://tools/generate_levels.gd         # write the .tscn files
$GODOT --headless --path . --script res://tools/smoke_test_levels.gd       # check they load
```

`tools/generate_placeholder_art.gd` regenerates the flat-color PNGs in `assets/placeholder/`. It is a `SceneTree` script, run the same way; delete it once real art replaces it.

## Architecture

### Autoloads

Four singletons in `project.godot`, three from the plugin suite:

- `SceneLoader` — threaded scene loading with a loading screen.
- `ProjectMusicController` — keeps music playing across scene changes, cross-fading `AudioStreamPlayer`s on the `Music` bus.
- `ProjectUISoundController` — auto-attaches UI SFX project-wide.
- `_mcp_game_helper` — Godot AI MCP bridge; not game code.

Plus class-based globals, reachable without being autoloads:

- `GlobalState` (`addons/maaacks_game_template/base/nodes/state/global_state.gd`) — static save/load of a `GlobalStateData` resource to `user://global_state.tres`.
- `GameState` / `LevelState` (`scripts/`) — the game's layer over `GlobalState`.

### Save data (`scripts/`)

- `GameState` is a `Resource` of static helpers. `get_level_state(path)` returns the per-level `LevelState`, creating it on first access. **`GlobalState.save()` is manual — nothing auto-saves.** Forgetting it is the most common bug here; `mark_level_reached`, `record_level_completed`, and `set_checkpoint_level_path` all save for you, but direct field writes do not.
- `LevelState` holds `reached`, `completed`, `best_time`, `deaths`, `tutorial_read`, `color`. `reached` gates level select and is set when a level actually loads — deliberately *not* by `set_checkpoint_level_path`, so that finding a level does not reveal the next one.
- Level keys are scene paths passed through `ResourceUID.ensure_path()`.
- `scripts/level_and_state_manager.gd` extends the template's `LevelManager` and overrides its path setters so template-driven progression mirrors into the save file. It is attached to the `LevelManager` node in `game.tscn` and is why Continue and Level Select work.

### Scene flow

`opening.tscn` → `main_menu.tscn` → `game.tscn` (persistent shell) → `end_credits.tscn`.

`game.tscn` is a shell, not a level. Levels load into `LevelContainer`:

- `LevelLoader` — loads level scenes into the container and drives `LevelLoadingScreen`.
- `LevelManager` (with `level_and_state_manager.gd`) — owns progression and the win/lose windows. Linear mode: a child `SceneLister` supplies the ordered 1–9 list.
- `PauseMenuController` — opens `pause_menu.tscn` on `ui_cancel`, restores prior focus on close.
- `GameTimer` — accumulates `play_time` / `total_time` into `GameState` on exit.

### Level contract (`scenes/game/levels/level.gd`)

Every level is a `Node2D` using `level.gd` and must contain a `%SpawnPoint` Marker2D and a child `LevelTileBuilder`. On `_ready` the level bakes the builder's ASCII map, moves the spawn marker to the `P` cell, spawns the player, places the goal, and clamps the player's camera to the map bounds.

- Progression signals: `level_lost`, `level_won(level_path)`, `level_changed(level_path)`. `LevelManager` connects these by duck-typing, so a level only declares what it uses.
- `kill_player()` handles death: it respawns the player at the checkpoint (or spawn), waits `respawn_delay`, and increments `LevelState.deaths`. Extra calls during the delay are ignored.
- `win_level()` records the completion and elapsed time, then emits `level_won`.
- `kill_plane_y` catches falls out of the world.

### Level authoring — levels are generated, not hand-edited

A level's layout is **ASCII text**, not hand-placed nodes. Editing level geometry means editing a map, not a `.tscn`.

- `tools/build_level_maps.py` is the authoring tool: it draws each map with a small `Grid` helper and rewrites the literals in `tools/generate_levels.gd`, padded to a uniform width. **Edit maps here** — hand-editing a level `.tscn` will be clobbered on the next regeneration.
- Legend: `#` solid, `^` spikes, `P` spawn, `G` goal, `.` empty.
- `LevelTileBuilder` bakes the map into a `TileMapLayer`, merges horizontally adjacent solid tiles into merged `RectangleShape2D` runs on a `StaticBody2D`, and creates one `Area2D` per spike.
- **The terrain collision container must be a `StaticBody2D`.** `CollisionShape2D` nodes parented to a plain `Node2D` are silently inert — the symptom is the player falling through the floor with no error. The builder validates this and refuses to bake otherwise.
- Levels deliberately do **not** instance a shared template scene: Godot cannot override a child node's property through a scene instance, so a per-level map could never reach the `TileBuilder` child. `generate_levels.gd` emits the full node tree for each level instead.

Tiles are **32×32**. Level 1 is a real tutorial; levels 2–9 are runnable skeletons meant to be replaced one at a time.

### Player (`scenes/game/player/`)

`CharacterBody2D` with a state enum (IDLE/RUN/JUMP/FALL/WALL_SLIDE/DEAD) and the forgiveness mechanics that make a precision platformer feel fair: variable jump height, coyote time, jump buffering, wall slide, and wall jump with a brief input lockout so the player cannot steer straight back into the wall.

**Control scheme: the player always runs.** `toggle_direction_control` (default on) makes the direction keys choose *which way to face* rather than whether to move; the player then accelerates there on its own. This suits a handheld D-pad, where holding a direction for a whole level is tiring. The persistent `facing` value is the single source of truth for horizontal direction under both schemes, so `_get_move_direction()` is scheme-agnostic. Set `toggle_direction_control = false` on the player to get the traditional hold-to-move feel (a wall slide then requires pushing into the wall, which auto-run cannot detect).

Two consequences to keep in mind:

- **A wall jump flips `facing` away from the wall.** Without that, auto-run would immediately steer the player back into the wall they just launched off.
- **Levels must give the player runway.** They arrive at hazards at full speed, unable to stop except by turning around. `verify_level_geometry.py` asserts at least `AUTO_RUN_REACTION_MARGIN` (0.6s) of clear ground between the spawn and the first hazard. Level 1 has 1.35s.

Every tunable is an `@export`, so feel can be dialled in from the inspector while the game runs. **The level designs depend on these numbers** — if you change them, re-run `tools/verify_level_geometry.py`, which mirrors the constants and checks the levels are still playable. Collision layers: player is layer 2; terrain is layer 1; spikes mask layer 2.

### Menus and settings

Menus build on the template's inheritable `OptionControl` scenes, persisting through `PlayerConfig` / `AppSettings` (`addons/maaacks_game_template/base/nodes/config/`). Player-changeable settings belong there, not in a bespoke system. The project theme is `resources/themes/gravity.tres`.

`scenes/menus/level_select_menu/level_select_menu.gd` lists **every** level from `SceneLister.files`, not just reached ones, so players can see what is ahead and re-challenge unlocked levels. Locked rows are disabled. Rows are formatted `"3. Level 3   [done]  0:42.115"`.

`scenes/credits/credits_label.tscn` parses the root `ATTRIBUTION.md` at runtime — update `ATTRIBUTION.md`, not the credits scene.

### Input

Actions live in `project.godot` (`ui_accept`, `ui_cancel`, `ui_page_up/down`, `move_forward/backward/left/right`, `jump`, `interact`) and are **redeclared in `override.cfg`** to layer gamepad bindings onto the built-in `ui_*` actions. **Update both files when adding or rebinding an action**, or the gamepad binding silently will not apply.

## Gotchas

- `.godot/`, `export_presets.cfg`, and `exports/` are gitignored; a fresh clone needs an import pass first.
- Save data is at `user://global_state.tres`. Delete it for a first-run state; the in-game reset control calls `GameState.reset()`.
- `New Game` confirms before wiping progress whenever `GameState.has_progress()` — do not narrow that back to "the Continue button is visible", which would let a mid-progress player erase their save in one click.
- Reflection-based tab lookup in `master_options_menu_with_tabs.gd` matches the literal tab titles `"Controls"` and `"Inputs"`. Renaming those tabs breaks it.
- Levels 2–9 are placeholders. Each is expected to be replaced with a real design; only level 1's geometry has been validated against the movement envelope in detail.
