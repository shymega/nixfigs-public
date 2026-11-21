# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
#
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: {
  imports = with inputs; [
    ./hardware-configuration.nix
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.setupOverlay
  ];

  lantian.qemu-user-static-binfmt.enable = true;

  # /home lives on the 2TB 2.5" SSD, LUKS-encrypted, unlocked here rather
  # than in initrd -- the keyfile lives under /persist, which isn't mounted
  # yet at that point. Mirrors the decommissioned NEO-LINUX's `homecrypt`.
  environment.etc."crypttab".text = ''
    homecrypt /dev/disk/by-label/HOMECRYPT /persist/etc/.homecrypt.bin
  '';

  networking = {
    hostName = "MIMIR-LINUX";
    hostId = "9c59cc48";
    usePredictableInterfaceNames = false;
  };
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  boot = {
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "armv6l-linux"
        "armv7l-linux"
        "riscv64-linux"
        "wasm32-wasi"
        "wasm64-wasi"
      ];
    };
    supportedFilesystems = [
      "ntfs"
      "zfs"
    ];
    initrd = {
      supportedFilesystems = [
        "ntfs"
        "zfs"
      ];
      luks.devices = {
        OS_CRYPTO = {
          device = "/dev/disk/by-label/OS_CRYPTO";
          preLVM = true;
          allowDiscards = true;
        };
      };
      systemd.services = {
        rollback = {
          description = "Rollback ZFS datasets to a pristine state";
          wantedBy = ["initrd.target"];
          after = ["zfs-import-ztank.service"];
          before = ["sysroot.mount"];
          path = [config.boot.zfs.package];
          serviceConfig.Type = "oneshot";
          script = ''
            zfs rollback -r ztank/crypt/nixos/linux/local/root@blank || true
          '';
        };
      };
    };
    zfs = {
      extraPools = ["ztank"];
      package = config.boot.kernelPackages.zfs_cachyos or pkgs.zfs;
    };

    kernelParams = [
      "nohibernate"
    ];
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
    };

    loader = {
      # Libreboot provides no UEFI on the X220T -- Limine runs in BIOS mode
      # against the whole mSATA disk instead of an ESP.
      limine = {
        enable = true;
        biosSupport = true;
        biosDevice = "/dev/disk/by-id/REPLACE_ME_MSATA";
        efiSupport = false;
        maxGenerations = 3;
      };
      generationsDir.copyKernels = true;
      timeout = 6;
    };
  };

  systemd.shutdownRamfs = {
    storePaths = ["${config.boot.zfs.package}/bin/zfs"];
    contents."/etc/systemd/system-shutdown/zfs-rollback" = {
      source = pkgs.writeShellScript "zfs-rollback-shutdown" ''
        #!/bin/sh
        ${config.boot.zfs.package}/bin/zfs rollback -r ztank/crypt/nixos/linux/local/root@blank || true
      '';
    };
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "powersave";
  };

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-vaapi-driver
      ];
    };
    i2c.enable = false;
    sensor.iio.enable = false;
  };

  services = {
    fwupd.enable = true;
    tlp.enable = lib.mkForce false;
    zfs = {
      trim = {
        enable = true;
        interval = "Sun *-*-* 03:00:00";
      };
      autoScrub = {
        enable = true;
        interval = "Sun *-*-* 02:00:00";
      };
      autoSnapshot.enable = true;
    };
    xserver = {
      enable = true;
      videoDrivers = ["modesetting"];
    };
    fstrim.enable = false;
    smartd = {
      enable = true;
      autodetect = true;
    };
    power-profiles-daemon.enable = true;
  };

  system.stateVersion = "26.05";
}
