//! Rendering the editor to a frame of colored Unicode text.
//!
//! This is a pure function of the editor state plus a prompt/status line, so it
//! can be tested without a terminal.  The map is drawn first and the cursor
//! coordinates sit on the last line, so cursor movement is visible even when the
//! window is too short to show the whole frame.

use first_food_lib::MapEditor;

/// Build the full editor frame.  `prompt` is `Some` while capturing text input;
/// otherwise the `status` line is shown.
pub fn render(
  editor: &MapEditor,
  prompt: Option<&str>,
  status: &str,
) -> String {
  let data = editor.data();
  let map = &editor.world().map;
  let (cursor_x, cursor_y) = editor.cursor();

  let mut frame = String::new();

  for y in 0..map.height {
    for x in 0..map.width {
      let key = map.key_at(x, y).unwrap_or(' ');
      let glyph = data
        .terrain_by_key(key)
        .map_or_else(|| key.to_string(), |terrain| terrain.glyph.clone());
      if x == cursor_x && y == cursor_y {
        // Inverted block so the cursor stands out regardless of terrain color.
        frame.push_str(&format!("\x1b[7m{glyph}\x1b[0m"));
      } else {
        let color = data.terrain_by_key(key).map_or("white", |t| &t.color);
        frame.push_str(&colorize(&glyph, color));
      }
    }
    frame.push('\n');
  }

  frame.push_str("\nterrain palette:\n");
  data
    .terrain
    .iter()
    .enumerate()
    .for_each(|(index, terrain)| {
      let marker = if index == editor.selected_index() {
        '>'
      } else {
        ' '
      };
      frame.push_str(&format!(
        "{marker} {} {} (key {})\n",
        colorize(&terrain.glyph, &terrain.color),
        terrain.id,
        terrain.key
      ));
    });

  if let Some(terrain) = editor.selected_terrain() {
    frame.push_str(&format!("\nproperties of {}:\n", terrain.id));
    if editor.property_keys().is_empty() {
      frame.push_str("  (none — press p to add a universal property)\n");
    }
    editor.property_keys().iter().for_each(|key| {
      let value = terrain.props.get(key).map_or("null", |v| v.as_str());
      frame.push_str(&format!("  {key} = {value}\n"));
    });
  }

  frame.push_str(
    "\nkeys: arrows move · space paint · x erase · [ ] select · \
     n new · d delete · p add-prop · P del-prop · e set-prop · \
     u undo · r redo · s save · q quit\n",
  );

  // Last line: always visible, carries cursor position and either the active
  // prompt or the status message.
  let unsaved = if editor.dirty() { " · [unsaved]" } else { "" };
  let tail = prompt
    .map_or_else(|| format!("· {status}"), |line| format!("> {line}\u{2588}"));
  frame.push_str(&format!(
    "first-food map editor · cursor {cursor_x},{cursor_y}{unsaved}  {tail}"
  ));
  frame
}

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

#[cfg(test)]
mod tests {
  use super::*;
  use first_food_lib::{GameData, World};
  use std::path::Path;

  fn editor() -> MapEditor {
    let data =
      GameData::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data"))
        .unwrap();
    let world = World::new(&data);
    MapEditor::new(data, world)
  }

  #[test]
  fn frame_contains_map_palette_and_status() {
    let frame = render(&editor(), None, "ready");
    assert!(frame.contains("first-food map editor"));
    assert!(frame.contains("terrain palette:"));
    assert!(frame.contains("≈")); // river glyph from the committed data
    assert!(frame.contains("cursor ")); // cursor coordinates on the last line
    assert!(frame.contains("· ready"));
  }

  #[test]
  fn prompt_line_replaces_status() {
    let frame = render(&editor(), Some("new terrain name: For"), "ignored");
    assert!(frame.contains("> new terrain name: For"));
    assert!(!frame.contains("· ignored"));
  }
}
