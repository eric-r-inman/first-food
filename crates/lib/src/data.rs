//! Game content loaded from data files.
//!
//! Content is theme-agnostic to the engine: a different theme ("skin") is
//! simply a different set of TOML files.  Nothing here hardcodes a particular
//! setting.

use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};
use thiserror::Error;

/// A kind of inhabitant.  The simulation reads its tunable values rather than
/// branching on the identifier, so new archetypes need no code changes.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct ArchetypeDef {
  pub id: String,
  pub name: String,
  pub max_satiation: i32,
  pub hunger_rate: i32,
  /// Display glyph for an inhabitant of this archetype on the map.
  pub glyph: String,
  /// Display color name understood by the renderer.
  pub color: String,
}

/// A kind of terrain tile.  `key` is the compact per-tile code stored in saved
/// maps; `glyph` and `color` are display only.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct TerrainDef {
  pub id: String,
  pub key: char,
  pub glyph: String,
  pub color: String,
}

/// The shape and terrain palette of the starting map.  `background` and `river`
/// name terrain ids, so a different theme can swap, say, grass for sand without
/// code changes.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct MapSpec {
  pub width: u32,
  pub height: u32,
  pub background: String,
  pub river: String,
}

/// One inhabitant in the starting settlement, by name and archetype.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct ScenarioIndividual {
  pub name: String,
  pub archetype: String,
}

/// The starting state a new world is built from.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Scenario {
  pub settlement_name: String,
  pub map: MapSpec,
  #[serde(rename = "individual", default)]
  pub individuals: Vec<ScenarioIndividual>,
}

/// All content needed to build and simulate a world.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameData {
  pub archetypes: Vec<ArchetypeDef>,
  pub terrain: Vec<TerrainDef>,
  pub scenario: Scenario,
}

/// The top-level shape of `archetypes.toml`.
#[derive(Debug, Deserialize)]
struct ArchetypesFile {
  #[serde(rename = "archetype", default)]
  archetype: Vec<ArchetypeDef>,
}

/// The top-level shape of `terrain.toml`.
#[derive(Debug, Deserialize)]
struct TerrainFile {
  #[serde(rename = "terrain", default)]
  terrain: Vec<TerrainDef>,
}

#[derive(Debug, Error)]
pub enum GameDataError {
  #[error("could not read archetypes file at {path}: {source}")]
  ArchetypesRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse archetypes file at {path}: {source}")]
  ArchetypesParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error("could not read terrain file at {path}: {source}")]
  TerrainRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse terrain file at {path}: {source}")]
  TerrainParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error("could not read scenario file at {path}: {source}")]
  ScenarioRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse scenario file at {path}: {source}")]
  ScenarioParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error(
    "scenario individual {name:?} references unknown archetype {archetype:?}"
  )]
  UnknownArchetype { name: String, archetype: String },
  #[error("scenario map {role} references unknown terrain {id:?}")]
  UnknownTerrain { role: &'static str, id: String },
}

impl GameData {
  /// Load and validate all content from a data directory containing
  /// `archetypes.toml`, `terrain.toml`, and `scenario.toml`.
  pub fn load(dir: &Path) -> Result<Self, GameDataError> {
    let archetypes_path = dir.join("archetypes.toml");
    let archetypes = toml::from_str::<ArchetypesFile>(
      &fs::read_to_string(&archetypes_path).map_err(|source| {
        GameDataError::ArchetypesRead {
          path: archetypes_path.clone(),
          source,
        }
      })?,
    )
    .map_err(|source| GameDataError::ArchetypesParse {
      path: archetypes_path,
      source,
    })?
    .archetype;

    let terrain_path = dir.join("terrain.toml");
    let terrain = toml::from_str::<TerrainFile>(
      &fs::read_to_string(&terrain_path).map_err(|source| {
        GameDataError::TerrainRead {
          path: terrain_path.clone(),
          source,
        }
      })?,
    )
    .map_err(|source| GameDataError::TerrainParse {
      path: terrain_path,
      source,
    })?
    .terrain;

    let scenario_path = dir.join("scenario.toml");
    let scenario =
      toml::from_str::<Scenario>(&fs::read_to_string(&scenario_path).map_err(
        |source| GameDataError::ScenarioRead {
          path: scenario_path.clone(),
          source,
        },
      )?)
      .map_err(|source| GameDataError::ScenarioParse {
        path: scenario_path,
        source,
      })?;

    Self {
      archetypes,
      terrain,
      scenario,
    }
    .validated()
  }

  /// Look up an archetype by identifier.
  pub fn archetype(&self, id: &str) -> Option<&ArchetypeDef> {
    self.archetypes.iter().find(|a| a.id == id)
  }

  /// Look up a terrain type by identifier.
  pub fn terrain(&self, id: &str) -> Option<&TerrainDef> {
    self.terrain.iter().find(|t| t.id == id)
  }

  /// Look up a terrain type by its compact map key.
  pub fn terrain_by_key(&self, key: char) -> Option<&TerrainDef> {
    self.terrain.iter().find(|t| t.key == key)
  }

  /// Reject content with references that do not resolve, so the problem
  /// surfaces at load time rather than as a silent default during simulation
  /// or rendering.
  fn validated(self) -> Result<Self, GameDataError> {
    self
      .scenario
      .individuals
      .iter()
      .try_for_each(|individual| {
        self
          .archetype(&individual.archetype)
          .map(|_| ())
          .ok_or_else(|| GameDataError::UnknownArchetype {
            name: individual.name.clone(),
            archetype: individual.archetype.clone(),
          })
      })?;

    [
      ("background", &self.scenario.map.background),
      ("river", &self.scenario.map.river),
    ]
    .into_iter()
    .try_for_each(|(role, id)| {
      self.terrain(id).map(|_| ()).ok_or_else(|| {
        GameDataError::UnknownTerrain {
          role,
          id: id.clone(),
        }
      })
    })?;

    Ok(self)
  }
}

#[cfg(test)]
mod tests {
  use super::*;

  fn workspace_data_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")
  }

  #[test]
  fn loads_committed_data() {
    let data = GameData::load(&workspace_data_dir()).unwrap();
    assert!(data.archetype("forager").is_some());
    assert!(data.terrain("water").is_some());
    assert_eq!(data.scenario.settlement_name, "Cedar Hollow");
    assert_eq!(data.scenario.individuals.len(), 3);
    assert_eq!(data.scenario.map.width, 50);
  }

  #[test]
  fn rejects_unknown_terrain_reference() {
    let data = GameData {
      archetypes: vec![],
      terrain: vec![],
      scenario: Scenario {
        settlement_name: "Test".to_string(),
        map: MapSpec {
          width: 4,
          height: 4,
          background: "grass".to_string(),
          river: "water".to_string(),
        },
        individuals: vec![],
      },
    };
    assert!(matches!(
      data.validated(),
      Err(GameDataError::UnknownTerrain { .. })
    ));
  }
}
