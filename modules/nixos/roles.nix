{
  lib,
  hostRoles,
  ...
}:
with lib; {
  options.nixfigs.meta.rolesEnabled = mkOption {
    default = hostRoles;
    type = with types; listOf str;
  };
}
