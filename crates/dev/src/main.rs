//! first-food-dev — the development tool.
//!
//! Its first feature is an interactive map editor.  This file only loads the
//! content and world and hands off to the editing loop in `app`.

mod app;
mod terminal;
mod ui;

use first_food_lib::{GameData, GameDataError, MapEditor, SaveError, World};
use std::path::PathBuf;
use std::process::ExitCode;
use thiserror::Error;

#[derive(Debug, Error)]
enum DevError {
  #[error(transparent)]
  Data(#[from] GameDataError),
  #[error(transparent)]
  Save(#[from] SaveError),
  #[error("terminal I/O failed: {0}")]
  Terminal(#[from] std::io::Error),
}

fn main() -> ExitCode {
  match run() {
    Ok(()) => ExitCode::SUCCESS,
    Err(e) => {
      eprintln!("first-food-dev: {e}");
      ExitCode::FAILURE
    }
  }
}

fn run() -> Result<(), DevError> {
  let data_dir = std::env::var("first_food_data_dir")
    .map_or_else(|_| PathBuf::from("data"), PathBuf::from);
  let world_path = PathBuf::from("world.json");

  let data = GameData::load(&data_dir)?;
  let world = if world_path.exists() {
    World::load(&world_path)?
  } else {
    let world = World::new(&data);
    world.save(&world_path)?;
    world
  };

  app::run(MapEditor::new(data, world), data_dir, world_path)
    .map_err(DevError::Terminal)
}
