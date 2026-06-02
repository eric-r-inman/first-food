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
  #[serde(rename = "individual", default)]
  pub individuals: Vec<ScenarioIndividual>,
}

/// All content needed to build and simulate a world.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameData {
  pub archetypes: Vec<ArchetypeDef>,
  pub scenario: Scenario,
}

/// The top-level shape of `archetypes.toml`.
#[derive(Debug, Deserialize)]
struct ArchetypesFile {
  #[serde(rename = "archetype", default)]
  archetype: Vec<ArchetypeDef>,
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
}

impl GameData {
  /// Load and validate all content from a data directory containing
  /// `archetypes.toml` and `scenario.toml`.
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
      scenario,
    }
    .validated()
  }

  /// Look up an archetype by identifier.
  pub fn archetype(&self, id: &str) -> Option<&ArchetypeDef> {
    self.archetypes.iter().find(|a| a.id == id)
  }

  /// Reject content where a scenario individual names an archetype that does
  /// not exist, so the invalid reference surfaces at load time rather than as
  /// a silent default during simulation.
  fn validated(self) -> Result<Self, GameDataError> {
    self
      .scenario
      .individuals
      .iter()
      .try_for_each(|individual| {
        self.archetype(&individual.archetype).ok_or_else(|| {
          GameDataError::UnknownArchetype {
            name: individual.name.clone(),
            archetype: individual.archetype.clone(),
          }
        })?;
        Ok(())
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
    assert_eq!(data.scenario.settlement_name, "Cedar Hollow");
    assert_eq!(data.scenario.individuals.len(), 3);
  }

  #[test]
  fn rejects_unknown_archetype_reference() {
    let data = GameData {
      archetypes: vec![ArchetypeDef {
        id: "forager".to_string(),
        name: "Forager".to_string(),
        max_satiation: 100,
        hunger_rate: 2,
      }],
      scenario: Scenario {
        settlement_name: "Test".to_string(),
        individuals: vec![ScenarioIndividual {
          name: "Nobody".to_string(),
          archetype: "ghost".to_string(),
        }],
      },
    };
    assert!(matches!(
      data.validated(),
      Err(GameDataError::UnknownArchetype { .. })
    ));
  }
}
