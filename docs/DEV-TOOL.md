# first-food dev tool

`first-food-dev` is the development tool for building the game. It opens in its
own terminal window and is driven entirely by the keyboard with minimal Unicode
graphics. Its first feature is a **map editor**.

This document is the living reference for the dev tool — its features and its
commands/keys are kept up to date here as the tool grows.

## Launching

From the project root, in a plain terminal:

```sh
just dev-tool
```

This builds the tool and opens it in a **new macOS Terminal window**. It reads
and writes:

- `world.json` — the starting map (the terrain tiles). Created from the scenario
  if it does not exist yet.
- `data/terrain.toml` — the terrain palette and the universal terrain property
  keys.

On other systems (or to run it in the current terminal), build once with
`nix develop --command cargo build --package first-food-dev` and run
`./target/debug/first-food-dev` from the project root.

## Features

### Map editor

- Move a cursor over the map and **paint** or **erase** terrain tiles.
- **Create terrain**: choose a name and a Unicode glyph; a unique internal
  storage key is assigned automatically.
- **Delete terrain**: any tiles using it revert to the background terrain so the
  map stays valid.
- **Universal terrain properties**: add or remove a property key that applies to
  every terrain (null until given a value), and set each terrain's value
  individually.
- **Undo / redo** of edits.
- **Save** to disk, with an unsaved-changes guard when quitting.

The screen shows the colored map (cursor highlighted), the terrain palette (the
selected terrain marked), and the selected terrain's properties (each universal
key with its value or `null`).

## Commands / keys

| Key       | Action                                                          |
| --------- | --------------------------------------------------------------- |
| arrows    | Move the cursor on the map                                      |
| space     | Paint the selected terrain at the cursor                        |
| `x`       | Erase — reset the tile to the background terrain                |
| `[` / `]` | Select the previous / next terrain in the palette               |
| `n`       | New terrain (prompts for a name, then a glyph)                  |
| `d`       | Delete the selected terrain                                     |
| `p`       | Add a universal property key (null on every terrain)            |
| `P`       | Remove a universal property key (cleared from all terrain)      |
| `e`       | Set a property on the selected terrain: type `key=value`        |
|           | (an empty value clears it back to null)                         |
| `u` / `r` | Undo / redo                                                     |
| `s`       | Save (`data/terrain.toml` + `world.json`)                       |
| `q`       | Quit (asks once to confirm if there are unsaved changes)        |

While a text prompt is active: type to enter text, `Backspace` to delete,
`Enter` to confirm, `Esc` to cancel.

## Notes

- The launcher opens macOS Terminal; the tool itself works in any terminal.
- The UI is hand-rolled on the standard library plus `stty` for raw mode, since
  no terminal-UI crate is available in this offline build environment.
- Property values are strings; an unset key is null for that terrain.
- New terrain defaults to the color white. Per-terrain glyphs, colors, and the
  property values can also be edited by hand in `data/terrain.toml`.
- The map editor shows terrain only, not the settlement's inhabitants.

---

_As of 2026-06-02, the dev tool's only feature is the map editor._
