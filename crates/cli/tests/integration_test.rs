use std::path::{Path, PathBuf};
use std::process::Command;

fn binary_path() -> PathBuf {
  let mut path =
    std::env::current_exe().expect("Failed to get current executable path");
  path.pop(); // remove test executable name
  path.pop(); // remove deps dir
  path.push("first-food-cli");
  if !path.exists() {
    path.pop();
    path.pop();
    path.push("debug");
    path.push("first-food-cli");
  }
  path
}

/// The committed game data set lives at the workspace root, two levels up from
/// this crate.
fn data_dir() -> PathBuf {
  Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data")
}

#[test]
fn test_help_flag() {
  let output = Command::new(binary_path())
    .arg("--help")
    .output()
    .expect("failed to run binary");
  assert!(output.status.success());
  assert!(String::from_utf8_lossy(&output.stdout).contains("Usage:"));
}

#[test]
fn test_version_flag() {
  let output = Command::new(binary_path())
    .arg("--version")
    .output()
    .expect("failed to run binary");
  assert!(output.status.success());
  assert!(String::from_utf8_lossy(&output.stdout).contains("first-food"));
}

#[test]
fn test_new_tick_show_flow() {
  let dir = tempfile::tempdir().expect("temp dir");
  let save = dir.path().join("world.json");
  let data = data_dir();
  let data = data.to_str().expect("utf8 data path");
  let save_arg = save.to_str().expect("utf8 save path");

  let new = Command::new(binary_path())
    .args(["--data-dir", data, "new", "--out", save_arg])
    .output()
    .expect("failed to run new");
  assert!(
    new.status.success(),
    "new failed: {}",
    String::from_utf8_lossy(&new.stderr)
  );
  assert!(save.exists(), "save file was not created");

  let tick = Command::new(binary_path())
    .args([
      "--data-dir",
      data,
      "tick",
      "--file",
      save_arg,
      "--count",
      "10",
    ])
    .output()
    .expect("failed to run tick");
  assert!(
    tick.status.success(),
    "tick failed: {}",
    String::from_utf8_lossy(&tick.stderr)
  );

  let show = Command::new(binary_path())
    .args(["--data-dir", data, "show", "--file", save_arg])
    .output()
    .expect("failed to run show");
  assert!(
    show.status.success(),
    "show failed: {}",
    String::from_utf8_lossy(&show.stderr)
  );
  let stdout = String::from_utf8_lossy(&show.stdout);
  assert!(stdout.contains("Cedar Hollow"), "got: {}", stdout);
  assert!(stdout.contains("tick 10"), "got: {}", stdout);
}

#[test]
fn test_map_renders_terrain_and_characters() {
  let dir = tempfile::tempdir().expect("temp dir");
  let save = dir.path().join("world.json");
  let data = data_dir();
  let data = data.to_str().expect("utf8 data path");
  let save_arg = save.to_str().expect("utf8 save path");

  let new = Command::new(binary_path())
    .args(["--data-dir", data, "new", "--out", save_arg])
    .output()
    .expect("failed to run new");
  assert!(
    new.status.success(),
    "new failed: {}",
    String::from_utf8_lossy(&new.stderr)
  );

  let map = Command::new(binary_path())
    .args(["--data-dir", data, "map", "--file", save_arg])
    .output()
    .expect("failed to run map");
  assert!(
    map.status.success(),
    "map failed: {}",
    String::from_utf8_lossy(&map.stderr)
  );
  let stdout = String::from_utf8_lossy(&map.stdout);
  assert!(stdout.contains('≈'), "expected a river glyph, got: {}", stdout);
  assert!(stdout.contains('☺'), "expected a character glyph, got: {}", stdout);
}

#[test]
fn test_play_creates_then_resumes() {
  let dir = tempfile::tempdir().expect("temp dir");
  let save = dir.path().join("world.json");
  let data = data_dir();
  let data = data.to_str().expect("utf8 data path");
  let save_arg = save.to_str().expect("utf8 save path");

  // First run creates the world and draws it.
  let first = Command::new(binary_path())
    .args(["--data-dir", data, "play", "--file", save_arg])
    .output()
    .expect("failed to run play");
  assert!(
    first.status.success(),
    "play (create) failed: {}",
    String::from_utf8_lossy(&first.stderr)
  );
  assert!(save.exists(), "play did not create a save");
  assert!(String::from_utf8_lossy(&first.stdout).contains('☺'));

  // Second run resumes the existing world rather than failing.
  let second = Command::new(binary_path())
    .args(["--data-dir", data, "play", "--file", save_arg])
    .output()
    .expect("failed to run play again");
  assert!(
    second.status.success(),
    "play (resume) failed: {}",
    String::from_utf8_lossy(&second.stderr)
  );
}
