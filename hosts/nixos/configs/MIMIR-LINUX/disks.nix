# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
#
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

    "/etc/nixos" = {
      device = "ztank/crypt/shared/nixos-config";
      fsType = "zfs";
      neededForBoot = true;
    };

    # 2TB 2.5" SSD, unlocked post-boot via /etc/crypttab (see default.nix) --
    # not boot.initrd.luks.devices, since the keyfile lives under /persist.
    "/home" = {
      device = "/dev/mapper/homecrypt";
      fsType = "xfs";
      neededForBoot = false;
    };

    "/boot" = {
      device = "/dev/disk/by-label/BOOT";
      fsType = "vfat";
      neededForBoot = true;
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
