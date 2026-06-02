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

#[derive(Debug, Clone, clap::Subcommand)]
pub enum Commands {
  New(NewArgs),
  Tick(TickArgs),
  Show(ShowArgs),
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
