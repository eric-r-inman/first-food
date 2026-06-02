//! Raw terminal mode and keyboard input using only the standard library plus
//! `stty`.
//!
//! No terminal-handling crate is available offline here, so raw mode is toggled
//! by shelling out to `stty` and input is parsed from raw bytes.  [`RawTerminal`]
//! restores the terminal and leaves the alternate screen on drop, including
//! after a panic.

use std::io::{self, Read, Write};
use std::process::Command;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Key {
  Up,
  Down,
  Left,
  Right,
  Enter,
  Esc,
  Backspace,
  CtrlC,
  Char(char),
  Other,
}

/// Switches the terminal to raw mode and the alternate screen for the lifetime
/// of the value, restoring both on drop.
pub struct RawTerminal {
  saved: Option<String>,
}

impl RawTerminal {
  pub fn enter() -> io::Result<Self> {
    // Capture the current settings so they can be restored verbatim.
    let probe = Command::new("stty").arg("-g").output()?;
    // A non-zero exit (e.g. stdin is not a terminal) leaves `saved` as None,
    // and the terminal mode is then restored with `stty sane` on drop.
    let saved = if probe.status.success() {
      Some(
        String::from_utf8(probe.stdout)
          .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?
          .trim()
          .to_string(),
      )
    } else {
      None
    };
    Command::new("stty").args(["raw", "-echo"]).status()?;
    let mut stdout = io::stdout();
    // Enter the alternate screen, hide the terminal's own cursor, and select
    // normal (not application) cursor-key mode so arrows arrive as `ESC [ A`.
    stdout.write_all(b"\x1b[?1049h\x1b[?25l\x1b[?1l")?;
    stdout.flush()?;
    Ok(Self { saved })
  }
}

impl Drop for RawTerminal {
  fn drop(&mut self) {
    let mut stdout = io::stdout();
    if let Err(e) = stdout
      .write_all(b"\x1b[?25h\x1b[?1049l")
      .and_then(|()| stdout.flush())
    {
      eprintln!("first-food-dev: could not restore screen: {e}");
    }
    let restored = self.saved.as_ref().map_or_else(
      || Command::new("stty").arg("sane").status(),
      |settings| Command::new("stty").arg(settings).status(),
    );
    if let Err(e) = restored {
      eprintln!("first-food-dev: could not restore terminal mode: {e}");
    }
  }
}

/// Clear the screen and draw a frame.  Newlines are expanded to CR-LF because
/// raw mode disables the terminal's own translation.
pub fn draw(frame: &str) -> io::Result<()> {
  let mut stdout = io::stdout();
  stdout.write_all(b"\x1b[2J\x1b[H")?;
  stdout.write_all(frame.replace('\n', "\r\n").as_bytes())?;
  stdout.flush()
}

/// Block until input is available and decode it into keys.  A single read may
/// yield several keys (e.g. pasted text).
pub fn read_keys() -> io::Result<Vec<Key>> {
  let mut buf = [0u8; 16];
  let read = io::stdin().read(&mut buf)?;
  Ok(parse(&buf[..read]))
}

fn parse(bytes: &[u8]) -> Vec<Key> {
  // Arrow keys arrive as either the normal (`ESC [ A`) or the application
  // (`ESC O A`) cursor sequence depending on the terminal's mode; accept both.
  match bytes {
    [0x1b, b'[', b'A', ..] | [0x1b, b'O', b'A', ..] => return vec![Key::Up],
    [0x1b, b'[', b'B', ..] | [0x1b, b'O', b'B', ..] => return vec![Key::Down],
    [0x1b, b'[', b'C', ..] | [0x1b, b'O', b'C', ..] => return vec![Key::Right],
    [0x1b, b'[', b'D', ..] | [0x1b, b'O', b'D', ..] => return vec![Key::Left],
    [0x1b] => return vec![Key::Esc],
    _ => {}
  }
  std::str::from_utf8(bytes).map_or_else(
    |_| vec![Key::Other],
    |text| text.chars().map(key_for).collect(),
  )
}

fn key_for(c: char) -> Key {
  match c {
    '\r' | '\n' => Key::Enter,
    '\u{7f}' | '\u{8}' => Key::Backspace,
    '\u{3}' => Key::CtrlC,
    '\u{1b}' => Key::Esc,
    other if other.is_control() => Key::Other,
    other => Key::Char(other),
  }
}
