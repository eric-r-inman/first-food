//! first-food-server — entry point.
//!
//! The `#[foundation_main]` macro handles CLI parsing, config
//! resolution, logging init, OIDC discovery, listener binding,
//! systemd integration, and graceful shutdown.  This file only
//! contains the application-specific setup.

use first_food_server::config::Config;
use first_food_server::web_base::AppState;
use rust_template_foundation::main as foundation_main;
use rust_template_foundation::Server;
use std::process::ExitCode;

#[foundation_main]
pub async fn main(
  config: Config,
  server: Server,
) -> Result<ExitCode, rust_template_foundation::ServerError> {
  let server = server.with_state(|base| AppState { base });
  server.listen().await?;
  Ok(ExitCode::SUCCESS)
}
