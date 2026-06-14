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

# Emits the terrain palette, compiles the Elm app, then serves the static files
# from a bare terminal in the project root.  The browser is opened after a short
# delay, in the background, so the static server stays in the foreground and
# Ctrl-C stops it.
# Build, serve, and open the browser map editor at http://localhost:8080.
editor:
    nix develop --command bash -c 'set -e; cd "{{justfile_directory()}}"; cargo run --quiet --package first-food-cli -- palette > frontend/public/palette.json; cargo run --quiet --package first-food-cli -- resources > frontend/public/resources.json; cargo run --quiet --package first-food-cli -- buildings > frontend/public/buildings.json; cargo run --quiet --package first-food-cli -- units > frontend/public/units.json; cargo run --quiet --package first-food-cli -- landmarks > frontend/public/landmarks.json; cargo run --quiet --package first-food-cli -- weather > frontend/public/weather.json; cargo run --quiet --package first-food-cli -- climate > frontend/public/climate.json; (cd frontend && elm make src/Main.elm --output public/elm.js && elm make src/Terrain.elm --output public/terrain.js && elm make src/Resources.elm --output public/resources.js && elm make src/Buildings.elm --output public/buildings.js && elm make src/Units.elm --output public/units.js && elm make src/Landmarks.elm --output public/landmarks.js && elm make src/Weather.elm --output public/weather.js && elm make src/Climate.elm --output public/climate.js); echo "Map editor: http://localhost:8080  (Ctrl-C to stop)"; (sleep 1 && open http://localhost:8080) & cd frontend/public && python3 -m http.server 8080'
