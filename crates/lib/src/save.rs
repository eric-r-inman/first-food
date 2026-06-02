//! Saving and loading a [`World`] to disk as JSON.
//!
//! JSON is chosen for now because it is human-readable, which helps while the
//! save shape is still changing.

use crate::world::World;
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum SaveError {
  #[error("could not serialize world for save to {path}: {source}")]
  Serialize {
    path: PathBuf,
    source: serde_json::Error,
  },
  #[error("could not write save file at {path}: {source}")]
  Write {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not read save file at {path}: {source}")]
  Read {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse save file at {path}: {source}")]
  Parse {
    path: PathBuf,
    source: serde_json::Error,
  },
}

impl World {
  /// Write the world to `path` as pretty-printed JSON.
  pub fn save(&self, path: &Path) -> Result<(), SaveError> {
    std::fs::write(
      path,
      serde_json::to_string_pretty(self).map_err(|source| {
        SaveError::Serialize {
          path: path.to_path_buf(),
          source,
        }
      })?,
    )
    .map_err(|source| SaveError::Write {
      path: path.to_path_buf(),
      source,
    })
  }

  /// Read a world previously written by [`World::save`].
  pub fn load(path: &Path) -> Result<World, SaveError> {
    serde_json::from_str(&std::fs::read_to_string(path).map_err(|source| {
      SaveError::Read {
        path: path.to_path_buf(),
        source,
      }
    })?)
    .map_err(|source| SaveError::Parse {
      path: path.to_path_buf(),
      source,
    })
  }
}

#[cfg(test)]
mod tests {
  use super::*;
  use crate::data::{ArchetypeDef, GameData, Scenario, ScenarioIndividual};

  fn sample_data() -> GameData {
    GameData {
      archetypes: vec![ArchetypeDef {
        id: "forager".to_string(),
        name: "Forager".to_string(),
        max_satiation: 100,
        hunger_rate: 2,
      }],
      scenario: Scenario {
        settlement_name: "Cedar Hollow".to_string(),
        individuals: vec![ScenarioIndividual {
          name: "Tahoma".to_string(),
          archetype: "forager".to_string(),
        }],
      },
    }
  }

  #[test]
  fn round_trip_preserves_world() {
    let data = sample_data();
    let mut world = World::new(&data);
    world.advance_by(&data, 7);
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("world.json");
    world.save(&path).unwrap();
    assert_eq!(World::load(&path).unwrap(), world);
  }

  #[test]
  fn saving_then_resuming_matches_uninterrupted_run() {
    let data = sample_data();
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("world.json");

    let mut resumed = World::new(&data);
    resumed.advance_by(&data, 5);
    resumed.save(&path).unwrap();
    let mut resumed = World::load(&path).unwrap();
    resumed.advance_by(&data, 5);

    let mut straight = World::new(&data);
    straight.advance_by(&data, 10);

    assert_eq!(resumed, straight);
  }
}
