# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.nixfigs.brightness-reset;
in
  with lib; {
    options.nixfigs.brightness-reset = {
      enable = mkEnableOption "reset display brightness to a fixed level on boot";

      percent = mkOption {
        type = types.ints.between 1 100;
        default = 100;
        description = "Brightness percentage to set via brightnessctl on boot.";
      };
    };

    config = mkIf cfg.enable {
      systemd.services.brightness-reset = {
        description = "Reset display brightness on boot";
        wantedBy = ["multi-user.target"];
        after = ["systemd-udev-settle.service"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${getExe pkgs.brightnessctl} set ${toString cfg.percent}%";
        };
      };
    };
  }
