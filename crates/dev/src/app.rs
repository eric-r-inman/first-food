//! The interactive editing loop: it maps keys to [`MapEditor`] operations and
//! manages text-entry prompts.  Editing logic itself lives in the library.

use crate::terminal::{self, Key, RawTerminal};
use crate::ui;
use first_food_lib::MapEditor;
use std::io;
use std::path::PathBuf;

/// What a completed text prompt should do with the entered text.
enum PromptAction {
  NewTerrainName,
  NewTerrainGlyph { name: String },
  AddPropertyKey,
  RemovePropertyKey,
  SetProp,
}

enum Mode {
  Normal,
  Prompt {
    label: String,
    buffer: String,
    action: PromptAction,
  },
}

struct App {
  editor: MapEditor,
  mode: Mode,
  status: String,
  confirming_quit: bool,
  running: bool,
  data_dir: PathBuf,
  world_path: PathBuf,
}

/// Run the editor to completion against the given world save.
pub fn run(
  editor: MapEditor,
  data_dir: PathBuf,
  world_path: PathBuf,
) -> io::Result<()> {
  // Holding the guard keeps raw mode active and restores it on drop.
  let _raw = RawTerminal::enter()?;
  let mut app = App {
    editor,
    mode: Mode::Normal,
    status: "ready".to_string(),
    confirming_quit: false,
    running: true,
    data_dir,
    world_path,
  };
  while app.running {
    terminal::draw(&app.frame())?;
    terminal::read_keys()?
      .into_iter()
      .for_each(|key| app.handle(key));
  }
  Ok(())
}

impl App {
  fn frame(&self) -> String {
    let prompt = match &self.mode {
      Mode::Prompt { label, buffer, .. } => Some(format!("{label}: {buffer}")),
      Mode::Normal => None,
    };
    ui::render(&self.editor, prompt.as_deref(), &self.status)
  }

  fn handle(&mut self, key: Key) {
    match std::mem::replace(&mut self.mode, Mode::Normal) {
      Mode::Normal => self.handle_normal(key),
      Mode::Prompt {
        label,
        buffer,
        action,
      } => self.handle_prompt(key, label, buffer, action),
    }
  }

  fn handle_normal(&mut self, key: Key) {
    if !matches!(key, Key::Char('q') | Key::CtrlC) {
      self.confirming_quit = false;
    }
    match key {
      Key::Up => self.editor.move_cursor(0, -1),
      Key::Down => self.editor.move_cursor(0, 1),
      Key::Left => self.editor.move_cursor(-1, 0),
      Key::Right => self.editor.move_cursor(1, 0),
      Key::Char(' ') | Key::Enter => self.editor.paint(),
      Key::Char('x') => self.editor.erase(),
      Key::Char('[') => self.editor.select_prev(),
      Key::Char(']') => self.editor.select_next(),
      Key::Char('u') => self.editor.undo(),
      Key::Char('r') => self.editor.redo(),
      Key::Char('d') => self.editor.delete_terrain(),
      Key::Char('n') => {
        self.start_prompt("new terrain name", PromptAction::NewTerrainName)
      }
      Key::Char('p') => {
        self.start_prompt("new property key", PromptAction::AddPropertyKey)
      }
      Key::Char('P') => self
        .start_prompt("remove property key", PromptAction::RemovePropertyKey),
      Key::Char('e') => {
        self.start_prompt("set prop (key=value)", PromptAction::SetProp)
      }
      Key::Char('s') => self.save(),
      Key::Char('q') | Key::CtrlC => self.try_quit(),
      _ => {}
    }
  }

  fn handle_prompt(
    &mut self,
    key: Key,
    label: String,
    mut buffer: String,
    action: PromptAction,
  ) {
    match key {
      Key::Esc => self.status = "cancelled".to_string(),
      Key::Enter => self.commit_prompt(buffer, action),
      Key::Backspace => {
        buffer.pop();
        self.mode = Mode::Prompt {
          label,
          buffer,
          action,
        };
      }
      Key::Char(c) => {
        buffer.push(c);
        self.mode = Mode::Prompt {
          label,
          buffer,
          action,
        };
      }
      _ => {
        self.mode = Mode::Prompt {
          label,
          buffer,
          action,
        };
      }
    }
  }

  fn commit_prompt(&mut self, buffer: String, action: PromptAction) {
    match action {
      PromptAction::NewTerrainName if buffer.trim().is_empty() => {
        self.status = "cancelled (empty name)".to_string();
      }
      PromptAction::NewTerrainName => {
        let name = buffer.trim().to_string();
        self.start_prompt(
          &format!("glyph for {name}"),
          PromptAction::NewTerrainGlyph { name },
        );
      }
      PromptAction::NewTerrainGlyph { name } => {
        let glyph = if buffer.is_empty() {
          "?".to_string()
        } else {
          buffer
        };
        match self.editor.add_terrain(&name, &glyph) {
          Ok(()) => self.status = format!("added terrain {name}"),
          Err(e) => self.status = format!("error: {e}"),
        }
      }
      PromptAction::AddPropertyKey => {
        self.editor.add_property_key(&buffer);
        self.status = format!("added property {}", buffer.trim());
      }
      PromptAction::RemovePropertyKey => {
        self.editor.remove_property_key(buffer.trim());
        self.status = format!("removed property {}", buffer.trim());
      }
      PromptAction::SetProp => match buffer.split_once('=') {
        Some((key, value)) => {
          self.editor.set_selected_prop(key, value);
          self.status = format!("set {} = {}", key.trim(), value.trim());
        }
        None => self.status = "expected key=value".to_string(),
      },
    }
  }

  fn start_prompt(&mut self, label: &str, action: PromptAction) {
    self.mode = Mode::Prompt {
      label: label.to_string(),
      buffer: String::new(),
      action,
    };
  }

  fn save(&mut self) {
    match self.editor.save(&self.data_dir, &self.world_path) {
      Ok(()) => self.status = "saved".to_string(),
      Err(e) => self.status = format!("save failed: {e}"),
    }
  }

  fn try_quit(&mut self) {
    if self.editor.dirty() && !self.confirming_quit {
      self.confirming_quit = true;
      self.status =
        "unsaved changes — press q again to quit, or s to save".to_string();
    } else {
      self.running = false;
    }
  }
}
