# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: let
  # Let the ARC flex between the floor and the cap; pinning min to max prevents
  # it shrinking when ROCm/NPU workloads and VMs need the memory.
  zfs_arc_max = 24 * 1024 * 1024 * 1024;
  zfs_arc_min = 4 * 1024 * 1024 * 1024;
in {
  imports = with inputs; [
    ./hardware-configuration.nix
    ../../../../modules/nixos/alarm-clock.nix
    ../../../../modules/nixos/brightness-reset.nix
    ../../../../modules/nixos/restic-backup.nix
    ../../../../modules/nixos/window-managers.nix
    nix-amd-ai.nixosModules.default
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.setupOverlay
    ucodenix.nixosModules.default
    breezy-desktop.nixosModules.default
  ];

  services.breezy-desktop.enable = true;
  nixfigs.brightness-reset.enable = true;

  nixfigs.resticBackup = {
    enable = false;
    bucket = "shymega-backups";
    excludeFile = "/home/dzrodriguez/.config/restic/exclude.txt";
    paths = [
      "/home/dzrodriguez"
      "/home/dzrodriguez/Documents"
      "/home/dzrodriguez/Multimedia"
      "/home/dzrodriguez/projects"
    ];
  };

  nixfigs.alarm-clock = {
    enable = true;
    # Wakes on schedule, but stays silent: no alarm should go off here.
    wakeOnly = true;
    bedtime.enable = true;
  };

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
    hostName = "FREYR-LINUX";
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
          bypassWorkqueues = true;
        };
        DATA = {
          device = "/dev/disk/by-label/DATA";
          preLVM = true;
          allowDiscards = true;
          bypassWorkqueues = true;
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
      "microcode.amd_sha_check=off"
      "amdgpu.dcdebugmask=0x10"
      "amdgpu.sg_display=0"
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
      theme = "Win2K";
      themePackages = with inputs;
      with pkgs; [win2k-plymouth.packages.${pkgs.stdenv.hostPlatform.system}.default];
    };

    loader = {
      limine = {
        enable = true;
        secureBoot.enable = true;
        maxGenerations = 3;
        additionalFiles = {
          "efi/shell/shell.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
          "efi/memtest86/memtest86.efi" = "${pkgs.memtest86-efi}/BOOTX64.efi";
        };
        extraEntries = ''
                 /+Alt OSes
                 // Windows 11
                 protocol: efi_boot_entry
                 entry: Windows Boot Manager
                 // Universal Blue Bazzite
                 protocol: efi_boot_entry
                 entry: Fedora
                 // CachyOS
                 protocol: efi_boot_entry
                 entry: Linux Boot Manager

          /+Utilities
                 //UEFI Shell
                 protocol: efi
                 comment: Make sure secure boot is disabled before using any EFI utilites! -- Access the UEFI shell for troubleshooting and development
                 image_path: boot():/limine/efi/shell/shell.efi
                 //Memtest86
                 protocol: efi
                 comment: Make sure secure boot is disabled before using any EFI utilites! -- Diagnose system memory issues and stress-test RAM modules
                 image_path: boot():/limine/efi/memtest86/memtest86.efi
        '';
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot/efi";
      };
      generationsDir.copyKernels = true;
      timeout = 3;
    };

    initrd.systemd.services.rollback = {
      description = "Rollback ZFS datasets to a pristine state";
      wantedBy = ["initrd.target"];
      after = ["zfs-import-ztank.service"];
      before = ["sysroot.mount"];
      path = [config.boot.zfs.package];
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r ztank/crypt/nixos/local/root@blank || true
      '';
    };
  };

  systemd.shutdownRamfs = {
    storePaths = ["${config.boot.zfs.package}/bin/zfs"];
    contents."/etc/systemd/system-shutdown/zfs-rollback" = {
      source = pkgs.writeShellScript "zfs-rollback-shutdown" ''
        #!/bin/sh
        ${config.boot.zfs.package}/bin/zfs rollback -r ztank/crypt/nixos/local/root@blank || true
      '';
    };
  };

  powerManagement = {
    enable = true;
  };

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
    power-profiles-daemon.enable = true;
    # nixos-hardware's common/pc/laptop enables TLP whenever power-profiles-daemon
    # is off, and TLP's stock defaults kill turbo on battery and runtime-park the
    # NVMe. Disable it explicitly so it can never conflict with PPD.
    tlp.enable = pkgs.lib.mkForce false;
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
      # DisplayLink stays for docking, but amdgpu must lead: the DisplayLink
      # module only needs modesetting for evdi outputs, which it pins itself
      # via its own OutputClass rule.
      videoDrivers = ["amdgpu" "displaylink"];
    };
    fstrim.enable = false;
    smartd = {
      enable = true;
      autodetect = true;
    };
    input-remapper.enable = true;
    udev = {
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # 4g lte modem.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="2c7c", ATTR{idProduct}=="0125", ATTR{power/autosuspend}="-1"

        # workstation - thinkpad dock (40ac).
        SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="3066", SYMLINK+="docked", TAG+="systemd"

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

  hardware.gpd.ppt.enable = lib.mkForce false;
}
