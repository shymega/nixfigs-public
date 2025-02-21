{ lib, libx, config, hostRoles, ... }:
with lib;
let
  cfg = config.nixfigs.meta.rolesEnabled;
in
{
  options.nixfigs.meta.rolesEnabled = mkOption {
    default = hostRoles;
    type = with types; listOf str;
  };
}
