# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
#
# Declarative reference for MIMIR-LINUX's disk layout. Not wired into
# `imports`; run manually before install with:
#   nix run github:nix-community/disko -- --mode disko ./disko.nix
#
# Replace the `REPLACE_ME_*` by-id paths below with the real
# `/dev/disk/by-id/...` identifiers (`ls -l /dev/disk/by-id/`) before running.
#
# This host (a Lenovo ThinkPad X220T) runs Libreboot, which provides no UEFI
# -- unlike every other host in this repo, which boots via Limine in EFI
# mode. Both disks below therefore use a legacy-BIOS-compatible GPT layout
# (a reserved `EF02` gap, same convention GRUB uses, kept here for Limine's
# BIOS install) plus a real `/boot` filesystem, since Limine's BIOS loader
# can't read the ZFS pool directly to find the kernel/initrd.
{
  disko.devices = {
    disk = {
      # 500GB mSATA -- OS pool `ztank`, same dataset layout as
      # HEIMDALL-LINUX's `ztank`.
      msata = {
        type = "disk";
        device = "/dev/disk/by-id/REPLACE_ME_MSATA";
        content = {
          type = "gpt";
          partitions = {
            # Reserved legacy-BIOS compatibility gap for Limine's bootstrap
            # code (same role as GRUB's "bios_grub" partition).
            bios_boot = {
              size = "1M";
              type = "EF02";
              attributes = [0]; # legacy BIOS bootable flag
            };

            # Real filesystem Limine's BIOS loader can read to find the
            # kernel/initrd/limine.cfg -- the ZFS pool below isn't natively
            # readable by Limine at this stage.
            boot = {
              size = "1G";
              type = "8300";
              label = "BOOT";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };

            # LUKS container for ZFS (NixOS root/nix/gnu/persist/var)
            luks = {
              size = "100%";
              type = "8309";
              label = "OS_CRYPTO";
              content = {
                type = "luks";
                name = "OS_CRYPTO";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "ztank";
                };
              };
            };
          };
        };
      };

      # 2TB 2.5" SATA SSD -- plain LUKS + xfs for /home, unlocked post-boot
      # via /etc/crypttab (not initrd), matching the decommissioned
      # NEO-LINUX's `homecrypt` pattern: the keyfile lives under /persist,
      # which isn't mounted yet during initrd.
      home_ssd = {
        type = "disk";
        device = "/dev/disk/by-id/REPLACE_ME_SATA_SSD_2TB";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              type = "8309";
              label = "HOMECRYPT";
              content = {
                type = "luks";
                name = "homecrypt";
                # Unlocked later via /etc/crypttab (see default.nix), not
                # boot.initrd.luks.devices -- the keyfile isn't available
                # until /persist is mounted.
                initrdUnlock = false;
                settings.allowDiscards = true;
                content = {
                  type = "filesystem";
                  format = "xfs";
                  mountpoint = "/home";
                };
              };
            };
          };
        };
      };
    };

    zpool = {
      # Single-disk OS pool. Dataset layout mirrors HEIMDALL-LINUX's `ztank`
      # exactly.
      ztank = {
        type = "zpool";
        rootFsOptions = {
          acltype = "posixacl";
          canmount = "off";
          compression = "lz4";
          dnodesize = "auto";
          normalization = "formD";
          relatime = "on";
          xattr = "sa";
        };
        datasets = {
          "crypt" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/nixos" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/nixos/linux" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/nixos/linux/local" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/nixos/linux/local/root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.canmount = "on";
          };
          "crypt/nixos/linux/local/nix-store" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options.canmount = "on";
          };
          "crypt/nixos/linux/local/guix-store" = {
            type = "zfs_fs";
            mountpoint = "/gnu";
            options.canmount = "on";
          };
          "crypt/nixos/linux/safe" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/nixos/linux/safe/persist" = {
            type = "zfs_fs";
            mountpoint = "/persist";
            options.canmount = "on";
          };
          "crypt/nixos/linux/safe/var-store" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options.canmount = "on";
          };
          "crypt/shared" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/shared/nixos-config" = {
            type = "zfs_fs";
            mountpoint = "/etc/nixos";
            options.canmount = "on";
          };
        };
      };
    };
  };
}
