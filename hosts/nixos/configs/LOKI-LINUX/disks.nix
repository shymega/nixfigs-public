# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  boot.zfs = {
    requestEncryptionCredentials = true;
    forceImportAll = true;
  };

  fileSystems = {
    "/" = {
      device = "ztank/crypt/nixos/local/root";
      fsType = "zfs";
    };

    "/data/Development" = {
      device = "ztank/crypt/shared/dev";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/home/dzrodriguez/dev" = {
      depends = ["/data/Development"];
      device = "/data/Development";
      fsType = "none";
      neededForBoot = false;
      options = ["bind"];
    };

    "/home" = {
      device = "ztank/crypt/shared/home";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/etc/nixos" = {
      device = "ztank/crypt/shared/nixos-config";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/nix" = {
      device = "ztank/crypt/nixos/local/nix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/gnu" = {
      device = "ztank/crypt/nixos/local/guix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/persist" = {
      device = "ztank/crypt/nixos/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/var" = {
      device = "ztank/crypt/nixos/safe/var-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/home/dzrodriguez/.local/share/atuin" = {
      device = "/dev/zvol/ztank/crypt/shared/homes/atuin/nixos/linux"; # Replace with by-label.
      fsType = "ext4";
      neededForBoot = false;
      options = ["x-systemd.automount"];
    };

    "/boot/efi" = {
      device = "/dev/disk/by-label/ESP";
      fsType = "vfat";
      neededForBoot = false;
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };

    "/etc/ssh" = {
      depends = ["/persist"];
      device = "/persist/etc/ssh";
      fsType = "none";
      neededForBoot = true;
      options = ["bind"];
    };
  };
}
