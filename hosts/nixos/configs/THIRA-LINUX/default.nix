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
    ../../../../modules/nixos/brightness-reset.nix
    ../../../../modules/nixos/restic-backup.nix
    ../../../../modules/nixos/window-managers.nix
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.setupOverlay
  ];

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

  lantian.qemu-user-static-binfmt.enable = true;

  nixfigs.alarm-clock = {
    enable = true;
    # Wakes on schedule, but stays silent: no alarm should go off here.
    wakeOnly = true;
    bedtime.enable = true;
  };

  networking = {
    hostName = "THIRA-LINUX";
    hostId = "1393030b";
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
      extraPools = [
        "ztank"
        "zdata"
      ];
      package = config.boot.kernelPackages.zfs_cachyos;
    };

    kernelParams = let
      # 96 GiB RAM - 16 GiB assumed iGPU VRAM carve-out (Arrow Lake H's Xe2
      # UMA allocation isn't confirmed yet -- re-check against the real BIOS
      # setting post-install) = 80 GiB usable; cap ARC at half of that,
      # floor high enough it won't collapse to near-zero under memory
      # pressure from VMs/AI workloads.
      zfs_arc_max = 40 * 1024 * 1024 * 1024;
      zfs_arc_min = 8 * 1024 * 1024 * 1024;
    in
      lib.mkAfter [
        "nohibernate"
        "zfs.zfs_arc_max=${toString zfs_arc_max}"
        "zfs.zfs_arc_min=${toString zfs_arc_min}"
        "iomem=relaxed"
        "video=eDP-1:3000x2000"
      ];
    extraModprobeConfig = ''
      options kvm_intel nested=1
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
    i2c.enable = false;
    sensor.iio = {
      enable = false;
    };
  };

  # Intel AI Boost NPU (Core Ultra 9 285H) -- first Intel NPU setup in this
  # repo, unlike the AMD `hardware.amd-npu` hosts. Verify /dev/accel0
  # permissions and driver functionality once installed.
  environment.systemPackages = with pkgs; [
    intel-npu-driver
    level-zero
    openvino
  ];

  services = {
    fwupd.enable = true;
    # nixos-hardware's common/pc/laptop enables TLP whenever power-profiles-daemon
    # is off, and TLP's stock defaults kill turbo on battery and runtime-park the
    # NVMe. Disable it explicitly so it can never conflict with PPD.
    tlp.enable = pkgs.lib.mkForce false;
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
      videoDrivers = ["modesetting"];
    };
    ollama = {
      enable = true;
      package = pkgs.ollama-vulkan;
      models = "/data/AI/LLMs/Ollama/models";
      user = "ollamad-ai";
    };
    fstrim.enable = true;
    smartd = {
      enable = true;
      autodetect = true;
    };
    power-profiles-daemon.enable = true;
    udev = {
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
        SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # Office mouse/keyboard
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="045e", ATTRS{idProduct}=="00cb", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTRS{idVendor}=="046d", ATTRS{idProduct}=="c31c", ATTR{power/autosuspend}="-1"

        # Thinkpad dock (WFH)
        SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="30b4", SYMLINK+="docked", TAG+="systemd"

        # Thinkpad dock (office)
        SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="30a9", SYMLINK+="docked", TAG+="systemd"
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
        GAMEMODERUN = "1";
        MANGOHUD = "1";
        MANGOHUD_CONFIG = "read_cfg,no_display";
        MESA_GLSL_CACHE_MAX_SIZE = "16G";
        MESA_SHADER_CACHE_MAX_SIZE = "16G";
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
}
