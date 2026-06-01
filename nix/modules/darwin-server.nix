# Darwin (macOS/launchd) module for the first-food-server service.
# Thin wrapper around the foundation's mkDarwinService helper.
# See mkNixosService for the Linux/systemd equivalent.
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
}:
foundation.lib.mkDarwinService {
  name = "first-food-server";
  inherit self;
}
