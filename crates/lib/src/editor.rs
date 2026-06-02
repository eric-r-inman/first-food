//! Interactive map-editor state and operations.
//!
//! All editing logic lives here, free of any terminal or rendering concern, so
//! it can be driven by the dev tool and tested headlessly.  The editor owns a
//! working copy of the [`GameData`] palette and the [`World`]; saving writes
//! the palette back to `terrain.toml` and the world back to its save file.

use crate::data::{GameData, GameDataError, TerrainDef};
use crate::save::SaveError;
use crate::world::{Map, World};
use std::collections::BTreeMap;
use std::path::Path;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum EditorError {
  #[error("terrain {id:?} already exists")]
  TerrainExists { id: String },
  #[error("terrain name must not be empty")]
  EmptyName,
  #[error("no free terrain key is available")]
  NoFreeKey,
  #[error(transparent)]
  Data(#[from] GameDataError),
  #[error(transparent)]
  Save(#[from] SaveError),
}

/// The editable state captured for a single undo step.
#[derive(Debug, Clone, PartialEq, Eq)]
struct Snapshot {
  terrain: Vec<TerrainDef>,
  property_keys: Vec<String>,
  map: Map,
}

/// The map editor: a working copy of the content and world plus cursor,
/// palette selection, and undo history.
#[derive(Debug)]
pub struct MapEditor {
  data: GameData,
  world: World,
  cursor_x: u32,
  cursor_y: u32,
  selected: usize,
  undo: Vec<Snapshot>,
  redo: Vec<Snapshot>,
  dirty: bool,
}

impl MapEditor {
  pub fn new(data: GameData, world: World) -> Self {
    Self {
      data,
      world,
      cursor_x: 0,
      cursor_y: 0,
      selected: 0,
      undo: Vec::new(),
      redo: Vec::new(),
      dirty: false,
    }
  }

  // --- Read access for rendering. ---

  pub fn data(&self) -> &GameData {
    &self.data
  }

  pub fn world(&self) -> &World {
    &self.world
  }

  pub fn cursor(&self) -> (u32, u32) {
    (self.cursor_x, self.cursor_y)
  }

  pub fn selected_index(&self) -> usize {
    self.selected
  }

  pub fn selected_terrain(&self) -> Option<&TerrainDef> {
    self.data.terrain.get(self.selected)
  }

  pub fn property_keys(&self) -> &[String] {
    &self.data.terrain_property_keys
  }

  pub fn dirty(&self) -> bool {
    self.dirty
  }

  // --- Navigation and selection. ---

  /// Move the cursor by a signed delta, clamped to the map bounds.
  pub fn move_cursor(&mut self, dx: i32, dy: i32) {
    let max_x = (self.world.map.width as i32 - 1).max(0);
    let max_y = (self.world.map.height as i32 - 1).max(0);
    self.cursor_x = (self.cursor_x as i32 + dx).clamp(0, max_x) as u32;
    self.cursor_y = (self.cursor_y as i32 + dy).clamp(0, max_y) as u32;
  }

  pub fn select_next(&mut self) {
    let len = self.data.terrain.len();
    if len > 0 {
      self.selected = (self.selected + 1) % len;
    }
  }

  pub fn select_prev(&mut self) {
    let len = self.data.terrain.len();
    if len > 0 {
      self.selected = (self.selected + len - 1) % len;
    }
  }

  // --- Map editing. ---

  /// Paint the selected terrain onto the cursor tile.
  pub fn paint(&mut self) {
    if let Some(key) = self.data.terrain.get(self.selected).map(|t| t.key) {
      self.snapshot();
      self.world.map.set(self.cursor_x, self.cursor_y, key);
      self.dirty = true;
    }
  }

  /// Reset the cursor tile to the background terrain.
  pub fn erase(&mut self) {
    let key = self.background_key();
    self.snapshot();
    self.world.map.set(self.cursor_x, self.cursor_y, key);
    self.dirty = true;
  }

  // --- Terrain palette CRUD. ---

  /// Create a terrain with the given name (used as its id) and display glyph;
  /// a unique storage key is assigned automatically.
  pub fn add_terrain(
    &mut self,
    name: &str,
    glyph: &str,
  ) -> Result<(), EditorError> {
    let name = name.trim();
    if name.is_empty() {
      return Err(EditorError::EmptyName);
    }
    if self.data.terrain.iter().any(|t| t.id == name) {
      return Err(EditorError::TerrainExists {
        id: name.to_string(),
      });
    }
    let key = self.free_key(glyph).ok_or(EditorError::NoFreeKey)?;
    self.snapshot();
    self.data.terrain.push(TerrainDef {
      id: name.to_string(),
      key,
      glyph: glyph.to_string(),
      color: "white".to_string(),
      props: BTreeMap::new(),
    });
    self.selected = self.data.terrain.len() - 1;
    self.dirty = true;
    Ok(())
  }

  /// Delete the selected terrain, repainting any map tiles that used it to the
  /// background so the map stays valid.
  pub fn delete_terrain(&mut self) {
    if self.selected >= self.data.terrain.len() {
      return;
    }
    self.snapshot();
    let removed = self.data.terrain.remove(self.selected);
    let background = self.background_key();
    self.world.map.rows.iter_mut().for_each(|row| {
      *row = row
        .chars()
        .map(|c| if c == removed.key { background } else { c })
        .collect();
    });
    self.selected =
      self.selected.min(self.data.terrain.len().saturating_sub(1));
    self.dirty = true;
  }

  // --- Universal property CRUD. ---

  /// Add a universal property key.  Every terrain gains it as null (absent
  /// from its values) until set individually.
  pub fn add_property_key(&mut self, key: &str) {
    let key = key.trim();
    if key.is_empty()
      || self.data.terrain_property_keys.iter().any(|k| k == key)
    {
      return;
    }
    self.snapshot();
    self.data.terrain_property_keys.push(key.to_string());
    self.dirty = true;
  }

  /// Remove a universal property key and clear it from every terrain.
  pub fn remove_property_key(&mut self, key: &str) {
    if !self.data.terrain_property_keys.iter().any(|k| k == key) {
      return;
    }
    self.snapshot();
    self.data.terrain_property_keys.retain(|k| k != key);
    self.data.terrain.iter_mut().for_each(|t| {
      t.props.remove(key);
    });
    self.dirty = true;
  }

  /// Set (or, with an empty value, clear back to null) a property on the
  /// selected terrain.  Adds the key to the universal set if it is new.
  pub fn set_selected_prop(&mut self, key: &str, value: &str) {
    let key = key.trim();
    if key.is_empty() || self.selected >= self.data.terrain.len() {
      return;
    }
    self.snapshot();
    if !self.data.terrain_property_keys.iter().any(|k| k == key) {
      self.data.terrain_property_keys.push(key.to_string());
    }
    if let Some(terrain) = self.data.terrain.get_mut(self.selected) {
      let value = value.trim();
      if value.is_empty() {
        terrain.props.remove(key);
      } else {
        terrain.props.insert(key.to_string(), value.to_string());
      }
    }
    self.dirty = true;
  }

  // --- Undo / redo / save. ---

  pub fn undo(&mut self) {
    if let Some(prior) = self.undo.pop() {
      self.redo.push(self.capture());
      self.apply(prior);
      self.dirty = true;
    }
  }

  pub fn redo(&mut self) {
    if let Some(next) = self.redo.pop() {
      self.undo.push(self.capture());
      self.apply(next);
      self.dirty = true;
    }
  }

  /// Write the palette back to `terrain.toml` in `data_dir` and the world back
  /// to `world_path`.
  pub fn save(
    &mut self,
    data_dir: &Path,
    world_path: &Path,
  ) -> Result<(), EditorError> {
    self.data.save_terrain(data_dir)?;
    self.world.save(world_path)?;
    self.dirty = false;
    Ok(())
  }

  // --- Internals. ---

  fn background_key(&self) -> char {
    self
      .data
      .terrain(&self.data.scenario.map.background)
      .map_or_else(
        || self.data.terrain.first().map_or('.', |t| t.key),
        |t| t.key,
      )
  }

  fn free_key(&self, glyph: &str) -> Option<char> {
    let used: Vec<char> = self.data.terrain.iter().map(|t| t.key).collect();
    glyph
      .chars()
      .next()
      .filter(|c| !used.contains(c))
      .or_else(|| {
        ('a'..='z')
          .chain('A'..='Z')
          .chain('0'..='9')
          .chain("!@#$%^&*+=?".chars())
          .find(|c| !used.contains(c))
      })
  }

  fn capture(&self) -> Snapshot {
    Snapshot {
      terrain: self.data.terrain.clone(),
      property_keys: self.data.terrain_property_keys.clone(),
      map: self.world.map.clone(),
    }
  }

  fn snapshot(&mut self) {
    let current = self.capture();
    self.undo.push(current);
    self.redo.clear();
  }

  fn apply(&mut self, snapshot: Snapshot) {
    self.data.terrain = snapshot.terrain;
    self.data.terrain_property_keys = snapshot.property_keys;
    self.world.map = snapshot.map;
    self.selected =
      self.selected.min(self.data.terrain.len().saturating_sub(1));
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn editor() -> MapEditor {
    let data =
      GameData::load(&Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data"))
        .unwrap();
    let world = World::new(&data);
    MapEditor::new(data, world)
  }

  #[test]
  fn paint_then_undo_restores_tile() {
    let mut ed = editor();
    ed.move_cursor(3, 3);
    let (x, y) = ed.cursor();
    let before = ed.world().map.key_at(x, y);
    // Select the water terrain so painting changes the tile.
    let water_index = ed
      .data()
      .terrain
      .iter()
      .position(|t| t.id == "water")
      .unwrap();
    while ed.selected_index() != water_index {
      ed.select_next();
    }
    ed.paint();
    assert_eq!(ed.world().map.key_at(x, y), Some('~'));
    assert!(ed.dirty());
    ed.undo();
    assert_eq!(ed.world().map.key_at(x, y), before);
    ed.redo();
    assert_eq!(ed.world().map.key_at(x, y), Some('~'));
  }

  #[test]
  fn add_terrain_assigns_unique_key_and_selects_it() {
    let mut ed = editor();
    let before = ed.data().terrain.len();
    ed.add_terrain("Forest", "♣").unwrap();
    assert_eq!(ed.data().terrain.len(), before + 1);
    let selected = ed.selected_terrain().unwrap();
    assert_eq!(selected.id, "Forest");
    let keys: Vec<char> = ed.data().terrain.iter().map(|t| t.key).collect();
    let unique: std::collections::BTreeSet<char> =
      keys.iter().copied().collect();
    assert_eq!(keys.len(), unique.len());
  }

  #[test]
  fn duplicate_terrain_is_rejected() {
    let mut ed = editor();
    assert!(matches!(
      ed.add_terrain("grass", ","),
      Err(EditorError::TerrainExists { .. })
    ));
  }

  #[test]
  fn property_key_is_universal_and_removable() {
    let mut ed = editor();
    ed.add_property_key("walkable");
    assert!(ed.property_keys().contains(&"walkable".to_string()));
    // Null for every terrain until set.
    assert!(ed
      .data()
      .terrain
      .iter()
      .all(|t| !t.props.contains_key("walkable")));
    ed.set_selected_prop("walkable", "true");
    assert_eq!(
      ed.selected_terrain().unwrap().props["walkable"],
      "true".to_string()
    );
    ed.remove_property_key("walkable");
    assert!(!ed.property_keys().contains(&"walkable".to_string()));
    assert!(ed
      .data()
      .terrain
      .iter()
      .all(|t| !t.props.contains_key("walkable")));
  }

  #[test]
  fn delete_terrain_repaints_its_tiles_to_background() {
    let mut ed = editor();
    // Paint a water tile, then delete the water terrain.
    ed.move_cursor(5, 5);
    let (x, y) = ed.cursor();
    let water_index = ed
      .data()
      .terrain
      .iter()
      .position(|t| t.id == "water")
      .unwrap();
    while ed.selected_index() != water_index {
      ed.select_next();
    }
    ed.paint();
    assert_eq!(ed.world().map.key_at(x, y), Some('~'));
    ed.delete_terrain();
    assert!(ed.data().terrain.iter().all(|t| t.id != "water"));
    // No tile should still carry the deleted key.
    assert!(ed.world().map.rows.iter().all(|r| !r.contains('~')));
  }
}
