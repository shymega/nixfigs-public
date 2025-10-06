# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  zfs_arc_max = toString (8 * 1024 * 1024 * 1024);
  zfs_arc_min = toString (8 * 1024 * 1024 * 1024 - 1);
  myZfsCompatibleStockKernelPackages =
    lib.filterAttrs
    (
      name: kernelPackages:
        (builtins.match "linux_[0-9]+_[0-9]+" name)
        != null
        && (builtins.tryEval kernelPackages).success
        && (!kernelPackages.${pkgs.zfs.kernelModuleAttribute}.meta.broken)
    )
    pkgs.linuxKernel.packages;
  latestStockKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues myZfsCompatibleStockKernelPackages
    )
  );
in {
  imports = with inputs; [
    ./hardware-configuration.nix
    # ucodenix.nixosModules.default
    nur-xddxdd.nixosModules.setupOverlay
    nur-xddxdd.nixosModules.nix-cache-attic
    nixfigs-virtual-private.virtual.all
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    chaotic.nixosModules.nyx-cache
    chaotic.nixosModules.nyx-overlay
    chaotic.nixosModules.nyx-registry
  ];

  lantian.qemu-user-static-binfmt.enable = true;

  networking = {
    hostName = "DEUSEX-LINUX";
    hostId = "aa1cf1f3";
    usePredictableInterfaceNames = false;
    firewall.trustedInterfaces = ["ztrfyirq6a"];
  };
  boot = {
    binfmt = {
      emulatedSystems = [
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
        # Add FIDO2 support.
      };
      systemd.services = {
        rollback = {
          description = "Rollback ZFS datasets to a pristine state";
          wantedBy = ["initrd.target"];
          after = ["zfs-import-ztank.service"];
          before = ["sysroot.mount"];
          path = with pkgs; [zfs];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            zfs rollback -r ztank/crypt/nixos/linux/local/root@blank || true
          '';
        };
        create-needed-for-boot-dirs = {
          after = pkgs.lib.mkForce ["zfs-import-ztank.service"];
          wants = pkgs.lib.mkForce ["zfs-import-ztank.service"];
        };
      };
    };
    zfs = {
      extraPools = ["ztank" "zdata"];
      devNodes = "/dev/disk/by-uuid";
    };

    kernelParams = [
      "nohibernate"
      "zfs.zfs_arc_max=${toString zfs_arc_max}"
      "zfs.zfs_arc_min=${toString zfs_arc_min}"
      "zfs.l2arc_write_boost=33554432"
      "zfs.l2arc_write_max=16777216"
      "microcode.amd_sha_check=off"
      "iomem=relaxed"
    ];
    extraModprobeConfig = ''
      options kvm_amd nested=1
      options kvm ignore_msrs=1 report_ignored_msrs=0
    '';
    kernelPackages = latestStockKernelPackage;
    crashDump.enable = true;
    extraModulePackages = [config.boot.kernelPackages.${config.boot.zfs.package.kernelModuleAttribute}];

    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
      "kernel.core_pattern" = "/var/crash/core.%t.%p";
      "kernel.panic" = "10";
      "kernel.unknown_nmi_panic" = "1";
    };

    plymouth = {
      enable = true;
      theme = "Win2K";
      themePackages = [
        (inputs.win2k-plymouth.packages.${pkgs.system}.default)
      ];
    };

    lanzaboote = {
      enable = false; # TODO: Reenable once `extraEntries` available upstream.
      enrollKeys = false;
      configurationLimit = 3;
      pkiBundle = "/var/lib/sbctl";
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

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "powersave";
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
        vaapiVdpau

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
    # ucodenix = {
    #   enable = true;
    #   cpuModelId = "00B20F40";
    # };
    auto-cpufreq = {
      enable = true;
      settings = {
        battery = {
          governor = "powersave";
          turbo = "never";
        };
        charger = {
          governor = "performance";
          turbo = "auto";
        };
      };
    };
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
      videoDrivers = ["modesetting "];
    };
    ollama = {
      enable = true;
      package = pkgs.ollama;
      acceleration = "rocm";
      models = "/var/lib/ollama";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.2"; # 890M-like.
      };
    };
    fstrim.enable = true;
    smartd = {
      enable = true;
      autodetect = true;
    };
    tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

        CPU_MIN_PERF_ON_AC = 0;
        CPU_MAX_PERF_ON_AC = 100;
        CPU_MIN_PERF_ON_BAT = 0;
        CPU_MAX_PERF_ON_BAT = 20;
      };
    };
    input-remapper.enable = false;
    thermald.enable = true;
    power-profiles-daemon.enable = lib.mkForce false;
    udev = {
      packages = with pkgs; [gnome-settings-daemon];
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
      lidSwitchExternalPower = "ignore";
      lidSwitchDocked = "ignore";
      extraConfig = ''
        LidSwitchIgnoreInhibited=no
      '';
    };
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    package = pkgs.steam.override {
      extraPkgs = pkgs:
        with pkgs; [
          steamtinkerlaunch
        ];
    };
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };

  system.stateVersion = "25.05";

  specialisation = {
    stock-latest-nixpkgs-kernel.configuration = {
      system.nixos.tags = ["stock-kernel"];
      boot.kernelPackages = lib.mkForce latestStockKernelPackage;
    };
  };

  environment.systemPackages = with pkgs; [
    (writeShellScriptBin "reset-gpu" ''
      cat /sys/kernel/debug/dri/1/amdgpu_gpu_recover
    '')
  ];
}
