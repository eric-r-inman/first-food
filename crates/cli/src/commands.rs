//! Subcommand handlers.
//!
//! Each handler drives `first_food_lib` and prints human-readable results to
//! stdout; diagnostics go through `tracing` to stderr.

use crate::config::{Commands, Config};
use first_food_lib::{GameData, World};
use std::process::ExitCode;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
  #[error(transparent)]
  Data(#[from] first_food_lib::GameDataError),
  #[error(transparent)]
  Save(#[from] first_food_lib::SaveError),
}

/// Dispatch the parsed subcommand.
pub fn run(config: Config) -> Result<ExitCode, AppError> {
  match config.command {
    Commands::New(args) => {
      World::new(&GameData::load(&config.data_dir)?).save(&args.out)?;
      println!("created new world at {}", args.out.display());
    }
    Commands::Tick(args) => {
      let data = GameData::load(&config.data_dir)?;
      let mut world = World::load(&args.file)?;
      world.advance_by(&data, args.count);
      world.save(&args.file)?;
      println!("advanced {} to tick {}", args.file.display(), world.tick);
    }
    Commands::Show(args) => show(&World::load(&args.file)?),
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
