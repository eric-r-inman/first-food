# Darwin (macOS/launchd) module for the first-food-server service.
# Thin wrapper around the foundation's mkDarwinService helper.  See
# mkNixosService for the Linux/systemd equivalent.  Cross-platform
# declarations live in `./common.nix`, which is imported below so
# anything added there merges into both platform modules via the
# module-merge system.
#
# This file is the seam where nix-darwin-only declarations (e.g.
# launchd drop-ins, defaults.NSGlobalDomain entries) belong.  Adding
# to the `imports` list or declaring `config.launchd.…` here merges
# with the foundation-generated service module — no restructuring
# needed to introduce a platform-specific bit.
#
# Minimal usage (defaults to Unix domain socket):
#
#   inputs.first-food.darwinModules.server
#
#   services.first-food-server = {
#     enable = true;
#   };
#
# To use TCP instead:
#
#   services.first-food-server = {
#     enable = true;
#     socket = null;
#     port   = 8080;
#   };
#
# To enable health checking (requires a reachable health endpoint):
#
#   services.first-food-server = {
#     enable = true;
#     healthCheck.enable = true;
#     healthCheck.url = "http://127.0.0.1:3000/health";
#   };
{
  self,
  foundation,
}: {
  imports = [
    ./common.nix
    (foundation.lib.mkDarwinService {
      name = "first-food-server";
      inherit self;
    })
  ];
}
