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
    ../../../../modules/nixos/alarm-clock.nix
    ../../../../modules/nixos/brightness-reset.nix
    ../../../../modules/nixos/restic-backup.nix
    ../../../../modules/nixos/window-managers.nix
    nix-amd-ai.nixosModules.default
    nur-xddxdd.nixosModules.nix-cache-attic
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.setupOverlay
    ucodenix.nixosModules.default
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

  lantian.qemu-user-static-binfmt.enable = true;

  nixfigs.alarm-clock = {
    enable = true;
    # Wakes on schedule, but stays silent: no alarm should go off here.
    wakeOnly = true;
    bedtime.enable = true;
  };

  networking = {
    hostName = "HEIMDALL-LINUX";
    hostId = "aa1cf1f3";
    usePredictableInterfaceNames = false;
  };
  zramSwap.enable = true;
  zramSwap.algorithm = "zstd";
  boot = {
    crashDump = {
      enable = true;
      # Default 128M is too tight: current kernel (bzImage) is ~16M and the
      # initrd is ~83M, leaving no room for kexec_file_load's placement/
      # alignment overhead -- it was failing every boot with
      # "kexec_file_load failed: Cannot assign requested address".
      reservedMemory = "256M";
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

        rotate-edp1-fbcon = {
          description = "Rotate eDP-1 fbcon 180 degrees via sysfs";
          wantedBy = ["initrd.target"];
          after = ["systemd-udev-settle.service"];
          before = ["initrd.target"];
          serviceConfig.Type = "oneshot";
          # fbcon's rotate/rotate_all knobs are global to the console, not
          # per-connector, so gate on eDP-1 specifically being the connected
          # panel rather than blindly rotating -- keeps this a no-op if an
          # external display ever ends up driving the console instead.
          script = ''
            for c in /sys/class/drm/card*-eDP-1; do
              [ "$(cat "$c/status" 2>/dev/null)" = "connected" ] || continue
              [ -w /sys/class/graphics/fbcon/rotate_all ] || continue
              echo 2 > /sys/class/graphics/fbcon/rotate_all
            done
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
      # Let the ARC flex between the floor and the cap; pinning min to max prevents
      # it shrinking when ROCm/NPU workloads and VMs need the memory.
      # 64 GiB RAM - 16 GiB APU VRAM = 48 GiB usable; cap ARC at half.
      zfs_arc_max = 24 * 1024 * 1024 * 1024;
      zfs_arc_min = 4 * 1024 * 1024 * 1024;
    in
      lib.mkMerge [
        # gpd-duo's hardware module sets its own video=DP-3:...,panel_orientation=normal
        # via mkBefore (order 500); fb_get_options() takes the first video= match per
        # connector name, so ours needs a lower mkOrder to win. This disables DP-3 for
        # the early fbdev/fbcon console specifically, breaking DP-3/eDP-1 clone mode so
        # rotate-edp1-fbcon's sysfs rotation only ever touches eDP-1's console. DP-3
        # itself is unaffected once Hyprland does its own KMS modeset.
        (lib.mkOrder 400 ["video=DP-3:d"])
        (lib.mkAfter [
          "nohibernate"
          "zfs.zfs_arc_max=${toString zfs_arc_max}"
          "zfs.zfs_arc_min=${toString zfs_arc_min}"
          "microcode.amd_sha_check=off"
          "iomem=relaxed"

          # Reserve pstore/ramoops backing memory in a genuine e820 gap
          # (0xc7e180000-0xc7f1bffff, ~16MiB, unclaimed by System RAM or any
          # device) so a future oops/panic survives a reboot into
          # /sys/fs/pstore -> systemd-pstore.service. Re-verify this address
          # is still a free gap in `dmesg | grep BIOS-e820` if RAM/BIOS changes.
          "ramoops.mem_address=0xC7E180000"
          "ramoops.mem_size=0x400000"
          "ramoops.record_size=0x100000"
          "ramoops.console_size=0x100000"
          "ramoops.pmsg_size=0x100000"
        ])
      ];
    extraModprobeConfig = ''
      options kvm_amd nested=1
      options kvm ignore_msrs=1 report_ignored_msrs=0
      options ec_sys write_support=1
    '';
    kernelModules = ["ec_sys"];
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
        extraConfig = ''
          interface_rotation: 180
        '';
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

  systemd = {
    shutdownRamfs = {
      storePaths = ["${config.boot.zfs.package}/bin/zfs"];
      contents."/etc/systemd/system-shutdown/zfs-rollback" = {
        source = pkgs.writeShellScript "zfs-rollback-shutdown" ''
          #!/bin/sh
          ${config.boot.zfs.package}/bin/zfs rollback -r ztank/crypt/nixos/linux/local/root@blank || true
        '';
      };
    };
    services.power-thermal-snapshot = {
      description = "Log sensor/power state for crash correlation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.lm_sensors}/bin/sensors";
      };
    };
    timers.power-thermal-snapshot = {
      description = "Periodic power-thermal-snapshot logging";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "30s";
        OnUnitActiveSec = "30s";
        AccuracySec = "5s";
      };
    };
  };

  powerManagement = {
    enable = true;
  };

  hardware = {
    amdgpu.initrd.enable = true;
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
      videoDrivers = ["amdgpu" "displaylink"];
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

  environment.systemPackages = with pkgs; [
    dmidecode
  ];

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
    cpuModelId = "00B20F40";
  };

  # Keep off: this module drives ryzenadj, which doesn't correctly support the
  # AI 9 HX 370's PM table -- writes can land at the wrong offset and corrupt
  # unrelated SMU state on this exact chip.
  hardware.gpd.ppt.enable = lib.mkForce false;
}
