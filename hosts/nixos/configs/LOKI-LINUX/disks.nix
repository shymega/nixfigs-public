# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  boot.zfs = {
    requestEncryptionCredentials = true;
    forceImportAll = true;
    forceImportRoot = true;
  };

  fileSystems = {
    "/" = {
      device = "ztank/crypt/nixos/linux/local/root";
      fsType = "zfs";
    };

    "/home" = {
      device = "ztank/crypt/shared/homes/nixos";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/etc/nixos" = {
      device = "ztank/crypt/shared/nixos-config";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/nix" = {
      device = "ztank/crypt/nixos/linux/local/nix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/gnu" = {
      device = "ztank/crypt/nixos/linux/local/guix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/persist" = {
      device = "ztank/crypt/nixos/linux/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/var" = {
      device = "ztank/crypt/nixos/linux/safe/var-store";
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
