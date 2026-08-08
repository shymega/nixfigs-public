{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixfigs.graphical.windowManagers;
in {
  options.nixfigs.graphical.windowManagers = {
    selectedWindowManager = lib.mkOption {
      type = lib.types.str;
      default = "hyprland";
    };
  };
}
