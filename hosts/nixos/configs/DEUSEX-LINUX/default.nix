# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
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
    ucodenix.nixosModules.default
  ];

  lantian.qemu-user-static-binfmt.enable = true;

  networking = {
    hostName = "DEUSEX-LINUX";
    hostId = "aa1cf1f3";
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
      luks = {
        devices = {
          OS_CRYPTO = {
            device = "/dev/disk/by-label/OS_CRYPTO";
            preLVM = true;
            allowDiscards = true;
          };
          DATA = {
            device = "/dev/disk/by-label/DATA";
            preLVM = true;
            allowDiscards = true;
          };
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
      extraPools = [
        "ztank"
        "zdata"
      ];
      package = config.boot.kernelPackages.zfs_cachyos;
    };

    kernelParams = let
      zfs_arc_max = 8 * 1024 * 1024 * 1024;
      zfs_arc_min = zfs_arc_max - 1;
    in [
      "nohibernate"
      "zfs.zfs_arc_max=${toString zfs_arc_max}"
      "zfs.zfs_arc_min=${toString zfs_arc_min}"
      "zfs.l2arc_write_boost=33554432"
      "zfs.l2arc_write_max=16777216"
      "microcode.amd_sha_check=off"
      "iomem=relaxed"
      "initcall_blacklist=algif_aead_init"
    ];
    extraModprobeConfig = ''
      options kvm_amd nested=1
      options kvm ignore_msrs=1 report_ignored_msrs=0
    '';
    kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
    };

    plymouth = {
      enable = true;
      theme = "Win2K";
      themePackages = with inputs;
      with pkgs; [win2k-plymouth.packages.${pkgs.stdenv.hostPlatform.system}.default];
    };

    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        netbootxyz.enable = true;
        extraFiles = {
          "efi/shell/shellx64.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
        };
        extraEntries = {
          "shell.conf" = ''
            title UEFI shell
            efi /EFI/SHELL/SHELLX64.EFI
          '';
        };
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
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
        /bin/zfs rollback -r ztank/crypt/nixos/linux/local/root@blank || true
      '';
    };
  };

  powerManagement = {
    enable = true;
  };

  hardware = {
    gpd.duo = {
      audioEnhancement.enable = true;
    };
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        # VA-API and VDPAU
        libva-vdpau-driver

        # AMD ROCm OpenCL runtime
        rocmPackages.clr
        rocmPackages.clr.icd
      ];
    };
    i2c.enable = false;
    sensor.iio = {
      enable = false;
    };
  };

  services = {
    fwupd.enable = true;
    hardware.bolt.enable = true;
    zfs = {
      trim = {
        enable = true;
        interval = "Sun *-*-* 02:00:00";
      };
      autoScrub = {
        enable = true;
        interval = "Sun *-*-* 02:00:00";
      };
      autoSnapshot.enable = true;
    };
    xserver = {
      enable = true;
      videoDrivers = ["modesetting "];
    };
    ollama = {
      enable = true;
      package = pkgs.ollama-rocm;
      models = "/data/AI/LLMs/Ollama/models";
      rocmOverrideGfx = "11.5.0"; # 890M-like.
      environmentVariables = {
        HSA_ENABLE_SDMA = "0";
      };
      user = "ollamad-ai";
    };
    fstrim.enable = true;
    smartd = {
      enable = true;
      autodetect = true;
    };
    input-remapper.enable = false;
    thermald.enable = true;
    power-profiles-daemon.enable = lib.mkForce false;
    udev = {
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="ACAD", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
        SUBSYSTEM=="power_supply", KERNEL=="ACAD", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # workstation - keyboard & mouse suspension.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="024f", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="1bcf", ATTRS{idProduct}=="0005", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="01e0", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="5043", ATTRS{idProduct}=="5c46", ATTR{power/autosuspend}="-1"

        # Workstation - Thinkpad Dock.
        SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="30b4", SYMLINK+="docked", TAG+="systemd"

        # KVM input - active.
        SUBSYSTEM=="usb", ACTION=="add|change|remove", ATTR{idVendor}=="13ba", ATTR{idProduct}=="0018",  SYMLINK+="currkvm", TAG+="systemd"
      '';
    };
    logind = {
      settings.Login = {
        HandleLidSwitchDocked = "ignore";
        HandleLidSwitchExternalPower = "ignore";
        LidSwitchDocked = "ignore";
        LidSwitchExternalPower = "ignore";
        LidSwitchIgnoreInhibited = "no";
      };
    };
  };

  system.stateVersion = "26.05";

  programs.gamescope.enable = true;
  programs.steam = {
    enable = true;
    package = pkgs.steam.override {
      extraEnv = {
        AMD_VULKAN_ICD = "RADV";
        GAMEMODERUN = "1";
        MANGOHUD = "1";
        MANGOHUD_CONFIG = "read_cfg,no_display";
        MESA_GLSL_CACHE_MAX_SIZE = "16G";
        MESA_SHADER_CACHE_MAX_SIZE = "16G";
        PROTON_ADD_CONFIG = "fsr4rdna3";
        PROTON_LOCAL_SHADER_CACHE = "1";
        VKD3D_CONFIG = "dxr,dxr11";
        WINEDLLOVERRIDES = "dinput8,dxgi,dsound=n,b";
        WINE_VK_VULKAN_ONLY = "1";
      };
      extraPkgs = pkgs':
        with pkgs'.python3Packages;
          [
            tkinter
            virtualenv
          ]
          ++ (with pkgs'; [
            python3
          ]);
    };
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    gamescopeSession.enable = true;
  };

  services.ucodenix = {
    enable = true;
    cpuModelId = "00B20F40";
  };

  services.open-webui.enable = config.services.ollama.enable;
}
