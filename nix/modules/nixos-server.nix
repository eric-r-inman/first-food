# NixOS (Linux/systemd) module for the first-food-server service.
# Thin wrapper around the foundation's mkNixosService helper.  See
# mkDarwinService for the macOS/launchd equivalent.  Cross-platform
# declarations live in `./common.nix`, which is imported below so
# anything added there merges into both platform modules via the
# module-merge system.
#
# This file is the seam where NixOS-only declarations (e.g. systemd
# drop-ins, tmpfiles rules, polkit hooks) belong.  Adding to the
# `imports` list or declaring `config.systemd.…` here merges with
# the foundation-generated service module — no restructuring needed
# to introduce a platform-specific bit.
#
# Minimal usage (defaults to Unix domain socket):
#
#   inputs.first-food.nixosModules.server
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
# To reference the socket from a reverse proxy (e.g. nginx):
#
#   locations."/".proxyPass =
#     "http://unix:${config.services.first-food-server.socket}";
#
# Note: when using socket mode the reverse proxy user must be a member of
# the service group (cfg.group) so it can connect to the socket.
{
  self,
  foundation,
}: {
  imports = [
    ./common.nix
    (foundation.lib.mkNixosService {
      name = "first-food-server";
      inherit self;
    })
  ];
}
