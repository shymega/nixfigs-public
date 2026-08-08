{
  lib,
  ...
}:
with lib; {
  options.nixfigs.graphical.windowManagers = {
    selectedWindowManager = lib.mkOption {
      type = lib.types.str;
      default = "hyprland";
    };
  };
}
