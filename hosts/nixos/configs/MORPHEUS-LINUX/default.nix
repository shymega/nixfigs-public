# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  zfs_arc_max = 8 * 1024 * 1024 * 1024;
  zfs_arc_min = zfs_arc_max - 1;
in {
  imports = with inputs; [
    ./hardware-configuration.nix
    nix-amd-ai.nixosModules.default
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.setupOverlay
    ucodenix.nixosModules.default
  ];

  hardware.amd-npu = {
    enable = true;
    enableNPU = true;
    enableFastFlowLM = true;
    enableLemonade = true;
    enableROCm = true;
    enableVulkan = true;
    enableImageGen = true;
    lemonade.user = "dzrodriguez";
  };

  networking = {
    hostName = "MORPHEUS-LINUX";
    hostId = "c4e0feaa";
    usePredictableInterfaceNames = false;
  };
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  boot = {
    zfs = {
      extraPools = [
        "ztank"
        "zdata"
      ];
      package = config.boot.kernelPackages.zfs_cachyos;
      devNodes = "/dev/disk/by-uuid";
    };
    binfmt = {
      emulatedSystems = [
        "aarch64-linux"
        "armv6l-linux"
        "armv7l-linux"
        "riscv64-linux"
        "wasm32-wasi"
        "wasm64-wasi"
      ];
      registrations."riscv64-linux" = {
        wrapInterpreterInShell = false;
        preserveArgvZero = true;
        matchCredentials = true;
        fixBinary = true;
      };
    };
    supportedFilesystems = [
      "ntfs"
      "zfs"
    ];

    initrd.luks = {
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
      # Add FIDO2 support.
    };
    initrd.supportedFilesystems = [
      "ntfs"
      "zfs"
    ];

    kernelParams = pkgs.lib.mkAfter [
      "nohibernate"
      "zfs.zfs_arc_max=${toString zfs_arc_max}"
      "zfs.zfs_arc_min=${toString zfs_arc_min}"
      "zfs.l2arc_write_boost=33554432"
      "zfs.l2arc_write_max=16777216"
      "microcode.amd_sha_check=off"
      "iomem=relaxed"
      "initcall_blacklist=algif_aead_init"
    ];
    extraModprobeConfig = lib.mkAfter ''
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
      theme = "spinner";
    };

    loader = {
      systemd-boot = {
        enable = true;
        memtest86.enable = true;
        netbootxyz.enable = true;
        edk2-uefi-shell.enable = true;
        rebootForBitlocker = true;
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      generationsDir.copyKernels = true;
      timeout = 6;
    };

    initrd.systemd.services.rollback = {
      description = "Rollback ZFS datasets to a pristine state";
      wantedBy = ["initrd.target"];
      after = ["zfs-import-ztank.service"];
      before = ["sysroot.mount"];
      path = [config.boot.zfs.package];
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r ztank/crypt/nixos/linux/local/root@blank
      '';
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

  environment.variables.AMD_VULKAN_ICD = "RADV";

  hardware = {
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
    amdgpu = {
      initrd.enable = true;
    };
    i2c.enable = true;
    sensor.iio = {
      enable = true;
      bmi260.enable = true;
    };
  };

  services = {
    power-profiles-daemon.enable = pkgs.lib.mkForce false;
    fwupd.enable = true;
    hardware.bolt.enable = true;
    handheld-daemon = {
      enable = false;
      package = pkgs.handheld-daemon;
      user = "dzrodriguez";
    };
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
      videoDrivers = ["amdgpu"];
    };
    fstrim.enable = false;
    smartd = {
      enable = true;
      autodetect = true;
    };
    input-remapper.enable = true;
    thermald.enable = true;
    udev = {
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # workstation - keyboard & mouse suspension.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="024f", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="1bcf", ATTRS{idProduct}=="0005", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="3434", ATTRS{idProduct}=="01e0", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="5043", ATTRS{idProduct}=="5c46", ATTR{power/autosuspend}="-1"

        # 4g lte modem.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="2c7c", ATTR{idProduct}=="0125", ATTR{power/autosuspend}="-1"

        # workstation - thinkpad dock (40ac).
        SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="3066", SYMLINK+="docked", TAG+="systemd"

        # kvm input - active.
        SUBSYSTEM=="usb", ACTION=="add|change|remove", ATTR{idVendor}=="13ba", ATTR{idProduct}=="0018",  SYMLINK+="currkvm", TAG+="systemd"

        # wm2 i2c fixes.
        SUBSYSTEM=="i2c", KERNEL=="i2c-gxtp7385:00", ATTR{power/wakeup}="disabled"
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
  };

  services.ucodenix = {
    enable = true;
    cpuModelId = "00A70F52";
  };
}
