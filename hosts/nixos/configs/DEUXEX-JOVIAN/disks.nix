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
      device = "ztank/crypt/jovian/local/root";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/home" = {
      device = "zdata/crypt/shared/home/dzrodriguez";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/etc/nixos" = {
      device = "ztank/crypt/jovian/safe/nixos-config";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/persist" = {
      device = "ztank/crypt/jovian/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/nix" = {
      device = "ztank/crypt/jovian/local/nix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/boot/efi" = {
      device = "/dev/disk/by-label/EFI_DPRIM"; # DISK PRIMARY.
      fsType = "vfat";
      neededForBoot = true;
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
  };
}
