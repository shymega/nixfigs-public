# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
{
  inputs,
  pkgs,
  lib,
  config,
  ...
}: {
  imports = with inputs; [
    ./hardware-configuration.nix
    ../../../../modules/nixos/alarm-clock.nix
    ../../../../modules/nixos/restic-backup.nix
    ../../../../modules/nixos/window-managers.nix
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    breezy-desktop.nixosModules.default
  ];

  services.breezy-desktop.enable = true;

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

  lantian.qemu-user-static-binfmt.enable = true;

  nixfigs.alarm-clock = {
    enable = true;
    # Wakes on schedule, but stays silent: no alarm should go off here.
    wakeOnly = true;
    onCalendar = "*-*-* 07:30:00";
    bedtime = {
      enable = true;
      onCalendar = "*-*-* 01:00:00";
    };
  };

  networking = {
    hostName = "MJOLNIR-LINUX";
    hostId = "588f3eab";
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
            zfs rollback -r ztank/crypt/nixos/local/root@blank || true
          '';
        };
      };
    };
    zfs = {
      # `zfs_cachyos` only exists on the CachyOS kernel's `kernelPackages`;
      # the `lts`/`lts-sway` specialisations below force `kernelPackages` to
      # `linuxPackages_6_18`, which lacks it. `?` only checks for the
      # attribute's existence without forcing it, so this stays safe to
      # evaluate under any `kernelPackages`, falling back to `pkgs.zfs` there.
      package =
        config.boot.kernelPackages.zfs_cachyos or pkgs.zfs;
      extraPools = [
        "ztank"
        "zdata"
      ];
    };

    kernelParams = let
      # Let the ARC flex between the floor and the cap; pinning min to max prevents
      # it shrinking when ROCm/NPU workloads and VMs need the memory.
      # 64 GiB RAM; cap ARC at 48 GiB with a 4 GiB floor.
      zfs_arc_max = 48 * 1024 * 1024 * 1024;
      zfs_arc_min = 4 * 1024 * 1024 * 1024;
    in [
      "nohibernate"
      "zfs.zfs_arc_max=${toString zfs_arc_max}"
      "zfs.zfs_arc_min=${toString zfs_arc_min}"
      "i915.enable_guc=3"
    ];
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
      timeout = 6;
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
    cpuFreqGovernor = "performance";
  };

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
        intel-compute-runtime
      ];
    };
    nvidia = {
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = true;
      dynamicBoost.enable = false;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.mkDriver {
        version = "610.57.04";
        sha256_64bit = "sha256-suk1xmuDuwDAyFe8jg7g/VLekoa0DJzB7sKafOfrEW0=";
        sha256_aarch64 = "sha256-QCefrMBCmpOwuOyXv1k5Gj0iB2CYlPgnG3JToUw/j54=";
        openSha256 = "sha256-rQHOOOY4KL92Ww3KDwh+j4eGU7oNAH8LutZC5wmFnPo=";
        settingsSha256 = "sha256-ZEMo8I8Zc2Tq6RVDNYpAH+f094dUaZiBqO+5f6lIjRI=";
        persistencedSha256 = "sha256-aXmD2VY1RLlgAnlHhOUMWzvMyhI6JTClcFLm4imF/mA=";
      };
      prime = {
        sync.enable = true;
        offload = {
          enable = false;
          enableOffloadCmd = false;
        };
        intelBusId = lib.mkForce "PCI:0@0:2:0";
        nvidiaBusId = lib.mkForce "PCI:0@0:0:0";
      };
    };
    i2c.enable = false;
  };

  services = {
    apcupsd = {
      enable = true;
      configText = ''
        UPSTYPE usb
        NISIP 127.0.0.1
        BATTERYLEVEL 50
        MINUTES 5
      '';
    };
    fwupd.enable = true;
    hardware.bolt.enable = true;
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
      videoDrivers = [
        "modesetting"
        "nvidia"
        "displaylink"
      ];
    };
    ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      host = "100.105.111.121";
      port = 11434;
      models = "/data/AI/LLMs/Ollama/models";
      user = "ollamad-ai";
      environmentVariables = {
        OLLAMA_CONTEXT_LENGTH = "32768";
      };
      loadModels = [
        "qwen2.5-coder:14b"
        "qwen3-coder:30b"
        "codestral:22b"
        "devstral:24b"
        "deepseek-r1:14b"
        "magistral:24b"
        "llama3.2:3b"
        "phi4-mini:3.8b"
      ];
    };
    fstrim.enable = true;
    smartd = {
      enable = true;
      autodetect = true;
    };
    input-remapper.enable = false;
    power-profiles-daemon.enable = lib.mkForce true;
    thermald.enable = true;
    logind = {
      settings.Login = {
        LidSwitchExternalPower = "ignore";
        LidSwitchDocked = "ignore";
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
  specialisation = let
    nvidiaOffloadConfig = {
      hardware.nvidia = {
        prime = {
          sync.enable = lib.mkForce false;
          offload = {
            enable = lib.mkForce true;
            enableOffloadCmd = lib.mkForce true;
          };
        };
      };
    };

    ltsKernelConfig = {
      boot.kernelPackages = lib.mkForce pkgs.linuxPackages_6_18;
      # `pkgs.zfs` is the default `boot.zfs.package` value; the NixOS zfs
      # module auto-selects the matching kernel module for whatever
      # `kernelPackages` is active via `cfgZfs.modulePackage`. Do not point
      # this at `config.boot.kernelPackages.${pkgs.zfs.kernelModuleAttribute}`
      # directly -- nixpkgs builds that attribute with `configFile = "kernel"`
      # (kernel module only, no userspace tools, no `lib/udev`), which breaks
      # activation: "failed to get symlink metadata for .../lib/udev".
      boot.zfs.package = lib.mkForce pkgs.zfs;
    };

    swayConfig = {
      nixfigs.graphical.windowManagers.selectedWindowManager = lib.mkForce "sway";
    };
  in {
    nvidia-offload = {
      inheritParentConfig = true;
      configuration = nvidiaOffloadConfig;
    };

    lts = {
      inheritParentConfig = true;
      configuration = ltsKernelConfig;
    };

    lts-sway = {
      inheritParentConfig = true;
      configuration = ltsKernelConfig // swayConfig;
    };

    lts-nvidia-offload = {
      inheritParentConfig = true;
      configuration = ltsKernelConfig // nvidiaOffloadConfig;
    };

    lts-sway-nvidia-offload = {
      inheritParentConfig = true;
      configuration = ltsKernelConfig // swayConfig // nvidiaOffloadConfig;
    };
  };

  hardware.cpu.intel.updateMicrocode = true;
}
