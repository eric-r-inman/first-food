# Build both Rust and Elm.
build: build-elm build-rust

# Build the Elm frontend.
build-elm:
    cd frontend && elm make src/Main.elm --output public/elm.js

# Build all Rust workspace crates.
build-rust:
    cargo build --workspace

# Run all tests (Elm compile check + Rust test suite).
test: build-elm test-rust

# Run the Rust test suite.
test-rust:
    cargo test --workspace

# Build Elm then run via cargo, forwarding all arguments.
run *args: build-elm
    cargo run {{args}}

# Run the game.  With no arguments it launches the world; any arguments are
# forwarded to the game CLI's subcommands.  Enters the Nix shell itself, so it
# works from a bare terminal in the project root.
dev *args:
    nix develop --command cargo run --package first-food-cli -- {{ if args == "" { "play" } else { args } }}

# Open the development tool (map editor) in a separate macOS Terminal window.
dev-tool:
    nix develop --command cargo build --package first-food-dev
    osascript -e 'tell application "Terminal" to do script "cd \"{{justfile_directory()}}\" && ./target/debug/first-food-dev"'
