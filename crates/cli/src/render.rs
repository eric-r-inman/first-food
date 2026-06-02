//! Rendering a world to colored Unicode for the terminal.
//!
//! This is presentation, deliberately kept out of the library: it turns world
//! state plus content (glyphs and colors from [`GameData`]) into text.  An
//! inhabitant standing on a tile is drawn instead of the terrain beneath it.

use first_food_lib::{GameData, Individual, World};

/// Render the whole world — the map with inhabitants drawn on top — as a block
/// of colored Unicode text, one map row per line.
pub fn world(world: &World, data: &GameData) -> String {
  world
    .map
    .rows
    .iter()
    .enumerate()
    .map(|(y, row)| {
      row
        .chars()
        .enumerate()
        .map(|(x, key)| cell(world, data, x as u32, y as u32, key))
        .collect::<String>()
    })
    .collect::<Vec<_>>()
    .join("\n")
}

/// Draw a single tile: the inhabitant on it if any, otherwise its terrain.
fn cell(world: &World, data: &GameData, x: u32, y: u32, key: char) -> String {
  occupant(world, x, y).map_or_else(
    || {
      data
        .terrain_by_key(key)
        .map_or_else(|| key.to_string(), |t| colorize(&t.glyph, &t.color))
    },
    |individual| {
      data
        .archetype(&individual.archetype)
        .map_or_else(|| "?".to_string(), |a| colorize(&a.glyph, &a.color))
    },
  )
}

fn occupant(world: &World, x: u32, y: u32) -> Option<&Individual> {
  world
    .individuals
    .iter()
    .find(|i| i.position.x == x && i.position.y == y)
}

/// Wrap a glyph in an ANSI color escape, or return it unchanged for an
/// unrecognized color name.
fn colorize(glyph: &str, color: &str) -> String {
  ansi_code(color).map_or_else(
    || glyph.to_string(),
    |code| format!("\x1b[{code}m{glyph}\x1b[0m"),
  )
}

fn ansi_code(color: &str) -> Option<&'static str> {
  match color {
    "black" => Some("30"),
    "red" => Some("31"),
    "green" => Some("32"),
    "yellow" => Some("33"),
    "blue" => Some("34"),
    "magenta" => Some("35"),
    "cyan" => Some("36"),
    "white" => Some("37"),
    "bright_black" => Some("90"),
    "bright_red" => Some("91"),
    "bright_green" => Some("92"),
    "bright_yellow" => Some("93"),
    "bright_blue" => Some("94"),
    "bright_magenta" => Some("95"),
    "bright_cyan" => Some("96"),
    "bright_white" => Some("97"),
    _ => None,
  }
}
