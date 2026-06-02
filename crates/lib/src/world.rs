//! The world model, map generation, and tick rule.
//!
//! The world holds only mutable simulation state; the rules for advancing it
//! read their tunables from [`GameData`], so a saved world plus its content set
//! is enough to resume deterministically.

use crate::data::{GameData, MapSpec};
use serde::{Deserialize, Serialize};

/// A position on the map, in tile coordinates.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Position {
  pub x: u32,
  pub y: u32,
}

/// The terrain grid.  `rows` is row-major; each character is a terrain key (see
/// [`crate::data::TerrainDef`]), so the saved map is legible at a glance.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Map {
  pub width: u32,
  pub height: u32,
  pub rows: Vec<String>,
}

impl Map {
  /// The terrain key at a tile, or `None` if out of bounds.
  pub fn key_at(&self, x: u32, y: u32) -> Option<char> {
    self
      .rows
      .get(y as usize)
      .and_then(|row| row.chars().nth(x as usize))
  }

  /// Set the terrain key at a tile.  Out-of-bounds coordinates are ignored.
  /// Operates on `char`s so multi-byte glyph keys are handled correctly.
  pub fn set(&mut self, x: u32, y: u32, key: char) {
    if let Some(row) = self.rows.get_mut(y as usize) {
      let mut chars: Vec<char> = row.chars().collect();
      if let Some(cell) = chars.get_mut(x as usize) {
        *cell = key;
        *row = chars.into_iter().collect();
      }
    }
  }
}

/// A settlement, its map, and its inhabitants at a point in simulated time.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct World {
  pub tick: u64,
  pub settlement_name: String,
  pub map: Map,
  pub individuals: Vec<Individual>,
}

/// A single inhabitant.  `archetype` references content in [`GameData`] rather
/// than copying its tunables, so changing the content changes behavior without
/// rewriting saves.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Individual {
  pub id: u32,
  pub name: String,
  pub archetype: String,
  pub satiation: i32,
  pub position: Position,
}

impl World {
  /// Build the initial world described by the scenario: generate the map, seed
  /// each inhabitant's satiation from its archetype, and place them on dry
  /// ground.
  pub fn new(data: &GameData) -> Self {
    let map = generate_map(&data.scenario.map, data);
    let background_key = data
      .terrain(&data.scenario.map.background)
      .map_or('.', |t| t.key);
    Self {
      tick: 0,
      settlement_name: data.scenario.settlement_name.clone(),
      individuals: data
        .scenario
        .individuals
        .iter()
        .zip(placements(&map, background_key, data.scenario.individuals.len()))
        .enumerate()
        .map(|(index, (spec, position))| Individual {
          id: index as u32,
          name: spec.name.clone(),
          archetype: spec.archetype.clone(),
          satiation: data
            .archetype(&spec.archetype)
            .map_or(0, |a| a.max_satiation),
          position,
        })
        .collect(),
      map,
    }
  }

  /// Advance the world by one tick: every inhabitant grows hungrier at its
  /// archetype's rate, clamped at zero.
  pub fn advance(&mut self, data: &GameData) {
    self.tick += 1;
    self.individuals.iter_mut().for_each(|individual| {
      let rate = data
        .archetype(&individual.archetype)
        .map_or(0, |a| a.hunger_rate);
      individual.satiation = (individual.satiation - rate).max(0);
    });
  }

  /// Advance the world by `count` ticks.
  pub fn advance_by(&mut self, data: &GameData, count: u64) {
    (0..count).for_each(|_| self.advance(data));
  }
}

/// Generate a grassland map with a river meandering vertically through it.
fn generate_map(spec: &MapSpec, data: &GameData) -> Map {
  let background = data.terrain(&spec.background).map_or('.', |t| t.key);
  let river = data.terrain(&spec.river).map_or('~', |t| t.key);
  Map {
    width: spec.width,
    height: spec.height,
    rows: (0..spec.height)
      .map(|y| {
        let center = river_center(y as i32, spec.width as i32);
        (0..spec.width)
          .map(|x| {
            let xi = x as i32;
            if xi == center || xi == center + 1 {
              river
            } else {
              background
            }
          })
          .collect()
      })
      .collect(),
  }
}

/// A triangle wave in `[-amp, amp]` that gives the river a gentle, fully
/// deterministic meander down the map.
fn river_center(y: i32, width: i32) -> i32 {
  let amp = 4;
  let period = 4 * amp;
  let p = y.rem_euclid(period);
  let tri = if p < 2 * amp { p - amp } else { 3 * amp - p };
  (width / 2 + tri).clamp(1, (width - 3).max(1))
}

/// Choose a tile position for each inhabitant on background (dry) ground, in a
/// loose cluster inset from the left edge.  Deterministic so a fresh world is
/// always laid out the same way.
fn placements(map: &Map, background_key: char, count: usize) -> Vec<Position> {
  let y = (map.height / 3).min(map.height.saturating_sub(1));
  let inset = map.width / 8;
  let row: Vec<char> = map
    .rows
    .get(y as usize)
    .map_or_else(Vec::new, |r| r.chars().collect());
  let background_columns = |from: u32| -> Vec<u32> {
    row
      .iter()
      .enumerate()
      .filter(|(x, c)| **c == background_key && *x as u32 >= from)
      .map(|(x, _)| x as u32)
      .collect()
  };
  let columns = Some(background_columns(inset))
    .filter(|cols| !cols.is_empty())
    .unwrap_or_else(|| background_columns(0));
  (0..count)
    .map(|i| Position {
      x: columns.get(i % columns.len().max(1)).copied().unwrap_or(0),
      y,
    })
    .collect()
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::data::{ArchetypeDef, Scenario, ScenarioIndividual, TerrainDef};
  use std::collections::BTreeMap;

  fn sample_data() -> GameData {
    GameData {
      archetypes: vec![ArchetypeDef {
        id: "forager".to_string(),
        name: "Forager".to_string(),
        max_satiation: 100,
        hunger_rate: 2,
        glyph: "☺".to_string(),
        color: "bright_yellow".to_string(),
      }],
      terrain: vec![
        TerrainDef {
          id: "grass".to_string(),
          key: '.',
          glyph: ",".to_string(),
          color: "green".to_string(),
          props: BTreeMap::new(),
        },
        TerrainDef {
          id: "water".to_string(),
          key: '~',
          glyph: "≈".to_string(),
          color: "blue".to_string(),
          props: BTreeMap::new(),
        },
      ],
      terrain_property_keys: vec![],
      scenario: Scenario {
        settlement_name: "Cedar Hollow".to_string(),
        map: MapSpec {
          width: 12,
          height: 6,
          background: "grass".to_string(),
          river: "water".to_string(),
        },
        individuals: vec![
          ScenarioIndividual {
            name: "Tahoma".to_string(),
            archetype: "forager".to_string(),
          },
          ScenarioIndividual {
            name: "Kwina".to_string(),
            archetype: "forager".to_string(),
          },
        ],
      },
    }
  }

  #[test]
  fn new_seeds_from_archetype() {
    let world = World::new(&sample_data());
    assert_eq!(world.tick, 0);
    assert_eq!(world.individuals.len(), 2);
    assert!(world.individuals.iter().all(|i| i.satiation == 100));
  }

  #[test]
  fn map_has_dimensions_and_a_river() {
    let world = World::new(&sample_data());
    assert_eq!(world.map.width, 12);
    assert_eq!(world.map.rows.len(), 6);
    assert!(world.map.rows.iter().all(|r| r.chars().count() == 12));
    assert!(world.map.rows.iter().any(|r| r.contains('~')));
  }

  #[test]
  fn inhabitants_start_on_dry_ground() {
    let world = World::new(&sample_data());
    assert!(world.individuals.iter().all(|individual| {
      world.map.rows[individual.position.y as usize]
        .chars()
        .nth(individual.position.x as usize)
        == Some('.')
    }));
  }

  #[test]
  fn advance_is_deterministic() {
    let data = sample_data();
    let mut world = World::new(&data);
    world.advance_by(&data, 10);
    assert_eq!(world.tick, 10);
    assert!(world.individuals.iter().all(|i| i.satiation == 80));
  }

  #[test]
  fn satiation_clamps_at_zero() {
    let data = sample_data();
    let mut world = World::new(&data);
    world.advance_by(&data, 1000);
    assert!(world.individuals.iter().all(|i| i.satiation == 0));
  }
}
