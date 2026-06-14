use first_food_lib::{LogFormat, LogLevel};
use rust_template_foundation::MergeConfig;
use std::path::PathBuf;

/// Create a new world from the data set and write it to a save file.
#[derive(Debug, Clone, clap::Args)]
pub struct NewArgs {
  /// Path to write the new world save to.
  #[arg(long)]
  pub out: PathBuf,
}

/// Advance an existing world by a number of ticks and save it back.
#[derive(Debug, Clone, clap::Args)]
pub struct TickArgs {
  /// Path to the world save to advance.
  #[arg(long)]
  pub file: PathBuf,
  /// Number of ticks to advance.
  #[arg(long, default_value_t = 1)]
  pub count: u64,
}

/// Print the current state of a world save.
#[derive(Debug, Clone, clap::Args)]
pub struct ShowArgs {
  /// Path to the world save to display.
  #[arg(long)]
  pub file: PathBuf,
}

/// Draw a world save as a colored Unicode map.
#[derive(Debug, Clone, clap::Args)]
pub struct MapArgs {
  /// Path to the world save to draw.
  #[arg(long)]
  pub file: PathBuf,
}

/// Run the game: open the world, creating it if absent, and draw it.
#[derive(Debug, Clone, clap::Args)]
pub struct PlayArgs {
  /// Path to the world save to play.
  #[arg(long, default_value = "world.json")]
  pub file: PathBuf,
}

#[derive(Debug, Clone, clap::Subcommand)]
pub enum Commands {
  New(NewArgs),
  Tick(TickArgs),
  Show(ShowArgs),
  Map(MapArgs),
  Play(PlayArgs),
  /// Print the terrain palette as JSON (consumed by the browser map editor).
  Palette,
  /// Print the resource palette as JSON (consumed by the browser editors).
  Resources,
  /// Print the building palette as JSON (consumed by the browser editors).
  Buildings,
  /// Print the unit palette as JSON (consumed by the browser editors).
  Units,
  /// Print the landmark palette as JSON (consumed by the browser editors).
  Landmarks,
}

#[derive(Debug, Clone, MergeConfig)]
#[merge_config(app_name = "first-food")]
pub struct Config {
  #[merge_config(common)]
  pub log_level: LogLevel,
  #[merge_config(common)]
  pub log_format: LogFormat,
  /// Directory holding the game data set (archetypes, scenario).
  #[merge_config(env, default = "std::path::PathBuf::from(\"data\")")]
  pub data_dir: PathBuf,
  #[merge_config(subcommand)]
  pub command: Commands,
}
