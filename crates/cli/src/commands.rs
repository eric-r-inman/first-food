//! Subcommand handlers.
//!
//! Each handler drives `first_food_lib` and prints human-readable results to
//! stdout; diagnostics go through `tracing` to stderr.

use crate::config::{Commands, Config};
use crate::render;
use first_food_lib::{GameData, World};
use std::process::ExitCode;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
  #[error(transparent)]
  Data(#[from] first_food_lib::GameDataError),
  #[error(transparent)]
  Save(#[from] first_food_lib::SaveError),
  #[error("could not serialize the terrain palette to JSON: {0}")]
  PaletteJson(#[from] serde_json::Error),
}

/// Dispatch the parsed subcommand.
pub fn run(config: Config) -> Result<ExitCode, AppError> {
  match config.command {
    Commands::New(args) => {
      let data = GameData::load(&config.data_dir)?;
      let world = World::new(&data);
      world.save(&args.out)?;
      println!("created new world at {}", args.out.display());
      println!("{}", render::world(&world, &data));
    }
    Commands::Tick(args) => {
      let data = GameData::load(&config.data_dir)?;
      let mut world = World::load(&args.file)?;
      world.advance_by(&data, args.count);
      world.save(&args.file)?;
      println!("advanced {} to tick {}", args.file.display(), world.tick);
    }
    Commands::Show(args) => show(&World::load(&args.file)?),
    Commands::Map(args) => {
      let data = GameData::load(&config.data_dir)?;
      println!("{}", render::world(&World::load(&args.file)?, &data));
    }
    Commands::Play(args) => {
      let data = GameData::load(&config.data_dir)?;
      let world = if args.file.exists() {
        World::load(&args.file)?
      } else {
        let world = World::new(&data);
        world.save(&args.file)?;
        world
      };
      println!("{}", render::world(&world, &data));
    }
    Commands::Palette => {
      let data = GameData::load(&config.data_dir)?;
      let palette = serde_json::json!({
        "property_keys": data.terrain_property_keys,
        "terrain": data.terrain,
      });
      println!("{}", serde_json::to_string_pretty(&palette)?);
    }
  }
  Ok(ExitCode::SUCCESS)
}

fn show(world: &World) {
  println!("{} — tick {}", world.settlement_name, world.tick);
  world.individuals.iter().for_each(|individual| {
    println!(
      "  [{}] {} ({}) satiation {}",
      individual.id,
      individual.name,
      individual.archetype,
      individual.satiation
    );
  });
}
