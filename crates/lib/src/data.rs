//! Game content loaded from data files.
//!
//! Content is theme-agnostic to the engine: a different theme ("skin") is
//! simply a different set of TOML files.  Nothing here hardcodes a particular
//! setting.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
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
/// maps; `glyph` and `color` are display only.  `props` holds this terrain's
/// values for the universal property keys (see [`GameData::terrain_property_keys`]);
/// a key absent from `props` is null for this terrain.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TerrainDef {
  pub id: String,
  pub key: char,
  pub glyph: String,
  pub color: String,
  #[serde(default, skip_serializing_if = "props_is_empty")]
  pub props: BTreeMap<String, String>,
}

fn props_is_empty(props: &BTreeMap<String, String>) -> bool {
  props.is_empty()
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
  /// The universal set of terrain property keys.  Every terrain conceptually
  /// has each of these, defaulting to null until given a value in its `props`.
  pub terrain_property_keys: Vec<String>,
  pub scenario: Scenario,
}

/// The top-level shape of `archetypes.toml`.
#[derive(Debug, Deserialize)]
struct ArchetypesFile {
  #[serde(rename = "archetype", default)]
  archetype: Vec<ArchetypeDef>,
}

/// The top-level shape of `terrain.toml`, used for both reading and writing.
#[derive(Debug, Serialize, Deserialize)]
struct TerrainFile {
  #[serde(default)]
  property_keys: Vec<String>,
  #[serde(rename = "terrain", default)]
  terrain: Vec<TerrainDef>,
}

/// The top-level shape of `resources.toml`.  Resources reuse the terrain
/// definition shape (a keyed glyph with a color and properties) and form a
/// layer placed over the terrain.
#[derive(Debug, Serialize, Deserialize)]
struct ResourceFile {
  #[serde(default)]
  property_keys: Vec<String>,
  #[serde(rename = "resource", default)]
  resource: Vec<TerrainDef>,
}

/// The top-level shape of `buildings.toml`.  Buildings reuse the terrain
/// definition shape and form a layer placed over the terrain.
#[derive(Debug, Serialize, Deserialize)]
struct BuildingFile {
  #[serde(default)]
  property_keys: Vec<String>,
  #[serde(rename = "building", default)]
  building: Vec<TerrainDef>,
}

/// The top-level shape of `units.toml`.  Units reuse the terrain definition
/// shape and form a layer placed over the terrain.
#[derive(Debug, Serialize, Deserialize)]
struct UnitFile {
  #[serde(default)]
  property_keys: Vec<String>,
  #[serde(rename = "unit", default)]
  unit: Vec<TerrainDef>,
}

/// The top-level shape of `landmarks.toml`.  Landmarks reuse the terrain
/// definition shape and form a layer placed over the terrain.
#[derive(Debug, Serialize, Deserialize)]
struct LandmarkFile {
  #[serde(default)]
  property_keys: Vec<String>,
  #[serde(rename = "landmark", default)]
  landmark: Vec<TerrainDef>,
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
  #[error("could not serialize terrain for save to {path}: {source}")]
  TerrainSerialize {
    path: PathBuf,
    source: toml::ser::Error,
  },
  #[error("could not write terrain file at {path}: {source}")]
  TerrainWrite {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not read resources file at {path}: {source}")]
  ResourcesRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse resources file at {path}: {source}")]
  ResourcesParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error("could not read buildings file at {path}: {source}")]
  BuildingsRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse buildings file at {path}: {source}")]
  BuildingsParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error("could not read units file at {path}: {source}")]
  UnitsRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse units file at {path}: {source}")]
  UnitsParse {
    path: PathBuf,
    source: toml::de::Error,
  },
  #[error("could not read landmarks file at {path}: {source}")]
  LandmarksRead {
    path: PathBuf,
    source: std::io::Error,
  },
  #[error("could not parse landmarks file at {path}: {source}")]
  LandmarksParse {
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
    let terrain_file = toml::from_str::<TerrainFile>(
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
    })?;

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
      terrain: terrain_file.terrain,
      terrain_property_keys: terrain_file.property_keys,
      scenario,
    }
    .validated()
  }

  /// Write the terrain palette and its universal property keys back to
  /// `terrain.toml` in `dir`.
  pub fn save_terrain(&self, dir: &Path) -> Result<(), GameDataError> {
    let path = dir.join("terrain.toml");
    let body = toml::to_string_pretty(&TerrainFile {
      property_keys: self.terrain_property_keys.clone(),
      terrain: self.terrain.clone(),
    })
    .map_err(|source| GameDataError::TerrainSerialize {
      path: path.clone(),
      source,
    })?;
    fs::write(&path, body)
      .map_err(|source| GameDataError::TerrainWrite { path, source })
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

/// Load the resource palette and its universal property keys from
/// `resources.toml` in `dir`.  Resources are a layer placed over the terrain.
pub fn load_resources(
  dir: &Path,
) -> Result<(Vec<String>, Vec<TerrainDef>), GameDataError> {
  let path = dir.join("resources.toml");
  let file =
    toml::from_str::<ResourceFile>(&fs::read_to_string(&path).map_err(
      |source| GameDataError::ResourcesRead {
        path: path.clone(),
        source,
      },
    )?)
    .map_err(|source| GameDataError::ResourcesParse { path, source })?;
  Ok((file.property_keys, file.resource))
}

/// Load the building palette and its universal property keys from
/// `buildings.toml` in `dir`.  Buildings are a layer placed over the terrain.
pub fn load_buildings(
  dir: &Path,
) -> Result<(Vec<String>, Vec<TerrainDef>), GameDataError> {
  let path = dir.join("buildings.toml");
  let file =
    toml::from_str::<BuildingFile>(&fs::read_to_string(&path).map_err(
      |source| GameDataError::BuildingsRead {
        path: path.clone(),
        source,
      },
    )?)
    .map_err(|source| GameDataError::BuildingsParse { path, source })?;
  Ok((file.property_keys, file.building))
}

/// Load the unit palette and its universal property keys from `units.toml` in
/// `dir`.  Units are a layer placed over the terrain.
pub fn load_units(
  dir: &Path,
) -> Result<(Vec<String>, Vec<TerrainDef>), GameDataError> {
  let path = dir.join("units.toml");
  let file = toml::from_str::<UnitFile>(&fs::read_to_string(&path).map_err(
    |source| GameDataError::UnitsRead {
      path: path.clone(),
      source,
    },
  )?)
  .map_err(|source| GameDataError::UnitsParse { path, source })?;
  Ok((file.property_keys, file.unit))
}

/// Load the landmark palette and its universal property keys from
/// `landmarks.toml` in `dir`.  Landmarks are a layer placed over the terrain.
pub fn load_landmarks(
  dir: &Path,
) -> Result<(Vec<String>, Vec<TerrainDef>), GameDataError> {
  let path = dir.join("landmarks.toml");
  let file =
    toml::from_str::<LandmarkFile>(&fs::read_to_string(&path).map_err(
      |source| GameDataError::LandmarksRead {
        path: path.clone(),
        source,
      },
    )?)
    .map_err(|source| GameDataError::LandmarksParse { path, source })?;
  Ok((file.property_keys, file.landmark))
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
  fn terrain_round_trips_through_toml_with_properties() {
    let dir = tempfile::tempdir().unwrap();
    let original = GameData::load(&workspace_data_dir()).unwrap();
    let mut edited = original.clone();
    edited.terrain_property_keys = vec!["walkable".to_string()];
    if let Some(grass) = edited.terrain.iter_mut().find(|t| t.id == "grass") {
      grass
        .props
        .insert("walkable".to_string(), "true".to_string());
    }
    edited.save_terrain(dir.path()).unwrap();

    // Reload using the edited terrain file alongside the committed
    // archetypes/scenario by copying those two in.
    for name in ["archetypes.toml", "scenario.toml"] {
      std::fs::copy(workspace_data_dir().join(name), dir.path().join(name))
        .unwrap();
    }
    let reloaded = GameData::load(dir.path()).unwrap();
    assert_eq!(reloaded.terrain_property_keys, vec!["walkable".to_string()]);
    assert_eq!(
      reloaded
        .terrain
        .iter()
        .find(|t| t.id == "grass")
        .unwrap()
        .props["walkable"],
      "true"
    );
  }

  #[test]
  fn rejects_unknown_terrain_reference() {
    let data = GameData {
      archetypes: vec![],
      terrain: vec![],
      terrain_property_keys: vec![],
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
