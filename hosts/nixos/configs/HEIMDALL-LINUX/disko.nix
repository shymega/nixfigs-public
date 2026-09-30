{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WD_PC_SN740_SDDPNQE-2T00_25103B401386";
      content = {
        type = "gpt";
        partitions = {
          # NixOS ESP (Limine bootloader)
          esp_nixos = {
            size = "2G";
            type = "EF00";
            label = "ESP_NIXOS";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };

          # LUKS container for ZFS
          luks = {
            size = "600G";
            type = "8309";  # LUKS partition type
            label = "LUKS_ZFS";
            content = {
              type = "luks";
              name = "nixos_crypt";
              settings = {
                allowDiscards = false;  # ZFS snapshot safety
              };
              content = {
                type = "zfs";
                pool = "zpool";
              };
            };
          };

          # CachyOS ESP
          esp_cachyos = {
            size = "2G";
            type = "EF00";
            label = "ESP_CACHYOS";
            content = {
              type = "filesystem";
              format = "vfat";
            };
          };

          # CachyOS root
          root_cachyos = {
            size = "350G";
            type = "8300";
            label = "CACHYOS_ROOT";
            content = {
              type = "filesystem";
              format = "ext4";
            };
          };

          # Bazzite ESP
          esp_bazzite = {
            size = "2G";
            type = "EF00";
            label = "ESP_BAZZITE";
            content = {
              type = "filesystem";
              format = "vfat";
            };
          };

          # Bazzite root
          root_bazzite = {
            size = "350G";
            type = "8300";
            label = "BAZZITE_ROOT";
            content = {
              type = "filesystem";
              format = "btrfs";
            };
          };

          # Windows ESP
          esp_windows = {
            size = "2G";
            type = "EF00";
            label = "ESP_WINDOWS";
            content = {
              type = "filesystem";
              format = "vfat";
            };
          };

          # Windows C: drive
          root_windows = {
            size = "250G";
            type = "0700";  # Microsoft basic data
            label = "WINDOWS";
            content = {
              type = "filesystem";
              format = "ntfs";
            };
          };
        };
      };
    };

    # ZFS pool configuration
    zpool.zpool = {
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
        "crypt/nixos/local" = {
          type = "zfs_fs";
          options.canmount = "off";
        };
        "crypt/nixos/local/root" = {
          type = "zfs_fs";
          mountpoint = "/";
          options.canmount = "on";
        };
        "crypt/nixos/local/nix-store" = {
          type = "zfs_fs";
          mountpoint = "/nix";
          options.canmount = "on";
        };
        "crypt/nixos/local/guix-store" = {
          type = "zfs_fs";
          mountpoint = "/gnu";
          options.canmount = "on";
        };
        "crypt/nixos/safe" = {
          type = "zfs_fs";
          options.canmount = "off";
        };
        "crypt/nixos/safe/persist" = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.canmount = "on";
        };
        "crypt/nixos/safe/var-store" = {
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

  # Filesystem mounts
  fileSystems = {
    "/" = {
      device = "zpool/crypt/nixos/local/root";
      fsType = "zfs";
    };

    "/boot" = {
      device = "/dev/disk/by-label/ESP_NIXOS";
      fsType = "vfat";
      options = [ "umask=0077" ];
    };

    "/nix" = {
      device = "zpool/crypt/nixos/local/nix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/gnu" = {
      device = "zpool/crypt/nixos/local/guix-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/persist" = {
      device = "zpool/crypt/nixos/safe/persist";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/var" = {
      device = "zpool/crypt/nixos/safe/var-store";
      fsType = "zfs";
      neededForBoot = true;
    };

    "/etc/nixos" = {
      device = "zpool/crypt/shared/nixos-config";
      fsType = "zfs";
      neededForBoot = true;
    };
  };

  # LUKS decryption (passphrase only - no keyFile)
  boot.initrd.luks.devices.nixos_crypt = {
    device = "/dev/disk/by-label/LUKS_ZFS";
    allowDiscards = false;
  };
}
