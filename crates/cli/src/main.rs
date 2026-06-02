//! first-food-cli — entry point.
//!
//! The `#[foundation_main]` macro handles CLI parsing, config resolution, and
//! logging init.  This file only dispatches the parsed subcommand; the work
//! lives in `commands`.

mod commands;
mod config;
mod render;

use config::Config;
use rust_template_foundation::main as foundation_main;
use std::process::ExitCode;

#[foundation_main]
pub fn main(config: Config) -> Result<ExitCode, commands::AppError> {
  commands::run(config)
}
