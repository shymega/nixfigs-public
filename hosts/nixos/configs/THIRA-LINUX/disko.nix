# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
#
# Declarative reference for THIRA-LINUX's disk layout. Not wired into
# `imports`; run manually before install with:
#   nix run github:nix-community/disko -- --mode disko ./disko.nix
#
# Replace the `REPLACE_ME_*` by-id paths below with the real
# `/dev/disk/by-id/...` identifiers (`ls -l /dev/disk/by-id/`) before running.
{
  disko.devices = {
    disk = {
      # 2TB NVMe (2280) -- OS storage, pool `ztank`.
      os = {
        type = "disk";
        device = "/dev/disk/by-id/REPLACE_ME_NVME_2280";
        content = {
          type = "gpt";
          partitions = {
            esp = {
              size = "2G";
              type = "EF00";
              label = "ESP";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot/efi";
                mountOptions = [
                  "fmask=0022"
                  "dmask=0022"
                ];
              };
            };
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

      # 2TB 2.5" SATA SSD -- half of the data pool, pool `zdata` (striped).
      data_sata = {
        type = "disk";
        device = "/dev/disk/by-id/REPLACE_ME_SATA_SSD";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              type = "8309";
              label = "DATA_SATA";
              content = {
                type = "luks";
                name = "DATA_SATA";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "zdata";
                };
              };
            };
          };
        };
      };

      # 2TB NVMe (2242) -- other half of the data pool, pool `zdata` (striped).
      data_nvme = {
        type = "disk";
        device = "/dev/disk/by-id/REPLACE_ME_NVME_2242";
        content = {
          type = "gpt";
          partitions = {
            luks = {
              size = "100%";
              type = "8309";
              label = "DATA_NVME";
              content = {
                type = "luks";
                name = "DATA_NVME";
                settings.allowDiscards = true;
                content = {
                  type = "zfs";
                  pool = "zdata";
                };
              };
            };
          };
        };
      };
    };

    zpool = {
      # Single-disk OS pool.
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

      # Two-disk data pool. No `mode` set, so disko stripes the member
      # vdevs (SATA SSD + NVMe 2242) for combined ~4TB capacity -- there is
      # no redundancy here, by choice; a single-disk failure loses the pool.
      zdata = {
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
          "crypt/shared" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/shared/virtual" = {
            type = "zfs_fs";
            mountpoint = "/data/VMs";
            options.canmount = "on";
          };
          "crypt/shared/ai" = {
            type = "zfs_fs";
            mountpoint = "/data/AI";
            options.canmount = "on";
          };
          "crypt/shared/dev" = {
            type = "zfs_fs";
            mountpoint = "/data/Development";
            options.canmount = "on";
          };
          "crypt/shared/games" = {
            type = "zfs_fs";
            mountpoint = "/data/Games";
            options.canmount = "on";
          };
          "crypt/shared/homes" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/shared/homes/nixos" = {
            type = "zfs_fs";
            mountpoint = "/home";
            options.canmount = "on";
          };
          "crypt/shared/homes/atuin" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/shared/homes/atuin/nixos" = {
            type = "zfs_fs";
            options.canmount = "off";
          };
          "crypt/shared/homes/atuin/nixos/linux" = {
            type = "zfs_volume";
            size = "4G";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };
        };
      };
    };
  };
}
