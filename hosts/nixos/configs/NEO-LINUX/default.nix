# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
#
{
  config,
  inputs,
  pkgs,
  lib,
  ...
}: let
  zfsIsUnstable = config.boot.zfs.package == pkgs.zfsUnstable;
  myCompatibleKernelPackages =
    lib.filterAttrs (
      name: kernelPackages:
        (lib.hasInfix "_xanmod" name)
        && (builtins.tryEval kernelPackages).success
        && (
          (
            (!zfsIsUnstable && !kernelPackages.zfs.meta.broken)
            || (zfsIsUnstable && !kernelPackages.zfs_unstable.meta.broken)
          )
          && (!kernelPackages.nvidia_x11.meta.broken)
          && (!kernelPackages.evdi.meta.broken)
          && (!kernelPackages.vmware.meta.broken)
        )
    )
    pkgs.linuxKernel.packages;
  latestKernelPackage = lib.last (
    lib.sort (a: b: (lib.versionOlder a.kernel.version b.kernel.version)) (
      builtins.attrValues myCompatibleKernelPackages
    )
  );
  zfs_arc_max = toString (8 * 1024 * 1024 * 1024);
  zfs_arc_min = toString (8 * 1024 * 1024 * 1024 - 1);
in {
  imports = [
    ./hardware-configuration.nix
    inputs.ucodenix.nixosModules.default
    inputs.nur-xddxdd.nixosModules.setupOverlay
    inputs.nur-xddxdd.nixosModules.qemu-user-static-binfmt
    inputs.nur-xddxdd.nixosModules.nix-cache-attic
    inputs.nixfigs-virtual-private.virtual.all
  ];
  lantian.qemu-user-static-binfmt = {
    enable = true;
    package = pkgs.qemu;
  };
  services.ucodenix = {
    enable = true;
    cpuModelId = "00A40F41";
  };

  environment.etc."crypttab".text = ''
    homecrypt /dev/disk/by-label/HOMECRYPT /persist/etc/.homecrypt.bin
  '';
  networking = {
    hostName = "NEO-LINUX";
    hostId = "84e3e75f";
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

      luks.devices = {
        nixos = {
          device = "/dev/disk/by-label/NIXOS";
          preLVM = true;
          allowDiscards = true;
        };
      };
      systemd.services = {
        rollback = {
          description = "Rollback ZFS datasets to a pristine state";
          wantedBy = ["initrd.target"];
          after = ["zfs-import-tank.service"];
          before = ["sysroot.mount"];
          path = with pkgs; [zfs];
          unitConfig.DefaultDependencies = "no";
          serviceConfig.Type = "oneshot";
          script = ''
            zfs rollback -r tank/local/root@blank
          '';
        };
        create-needed-for-boot-dirs = {
          after = pkgs.lib.mkForce ["zfs-import-tank.service"];
          wants = pkgs.lib.mkForce ["zfs-import-tank.service"];
        };
      };
    };

    kernelParams = [
      "nohibernate"
      "zfs.zfs_arc_max=${zfs_arc_max}"
      "zfs.zfs_arc_min=${zfs_arc_min}"
      "zfs.l2arc_write_boost=33554432"
      "zfs.l2arc_write_max=16777216"
    ];
    extraModprobeConfig = ''
      options kvm_amd nested=1
      options kvm ignore_msrs=1 report_ignored_msrs=0
    '';
    kernelPackages = latestKernelPackage;

    kernelPatches = [
      {
        name = "enable RT_FULL";
        patch = null;
        extraConfig = ''
          PREEMPT y
          PREEMPT_BUILD y
          PREEMPT_VOLUNTARY n
          PREEMPT_COUNT y
          PREEMPTION y
        '';
      }
    ];

    extraModulePackages = with config.boot.kernelPackages; [zfs];

    zfs.devNodes = "/dev/NEO-LINUX/ROOT";

    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
    };

    plymouth = {
      enable = true;
    };

    lanzaboote = {
      enable = true;
      enrollKeys = true;
      configurationLimit = 3;
      pkiBundle = "/etc/secureboot";
    };
    loader = {
      systemd-boot.enable = lib.mkForce false;
      grub.enable = lib.mkForce false;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      generationsDir.copyKernels = true;
      timeout = lib.mkForce 6;
    };
  };

  hardware = {
    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        amdvlk
        # VA-API and VDPAU
        vaapiVdpau

        # AMD ROCm OpenCL runtime
        rocmPackages.clr
        rocmPackages.clr.icd
      ];
      extraPackages32 = with pkgs; [driversi686Linux.amdvlk];
    };
    amdgpu = {
      initrd.enable = true;
      amdvlk = {
        enable = true;
        support32Bit.enable = true;
      };
      opencl.enable = true;
    };
    cpu.amd.ryzen-smu.enable = true;
  };

  services.ollama = {
    enable = false;
    package = pkgs.ollama;
    acceleration = "rocm";
    models = "/data/AI/LLMs/Ollama/Models/";
    environmentVariables = {
      HSA_OVERRIDE_GFX_VERSION = "10.3.0"; # 680M.
    };
  };

  services = {
    power-profiles-daemon.enable = pkgs.lib.mkForce false;
    udev = {
      packages = with pkgs; [gnome-settings-daemon];
      extraRules = ''
        # workstation - keyboard & mouse suspension.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="024f", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="0005", ATTR{power/autosuspend}="-1"

        # KVM input - active.
        SUBSYSTEM=="usb", ACTION=="add|change|remove", ATTR{idVendor}=="13ba", ATTR{idProduct}=="0018",  SYMLINK+="currkvm", TAG+="systemd"

        # rename network interface.
        SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{DEVTYPE}=="wlan", KERNEL=="wlan*", NAME="wlan0"

        # my personal iphone.
        SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="12a8", KERNEL=="eth*", NAME="iphone0"

        # my personal op6t.
        SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="9024", KERNEL=="usb*", NAME="android0"

        # my personal Moto G.
        SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="201c", KERNEL=="usb*", NAME="android0"
      '';
    };

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
      videoDrivers = ["amdgpu"];
    };
    thermald.enable = true;
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
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

  security = {
    pam.loginLimits = [
      {
        domain = "*";
        item = "nofile";
        type = "-";
        value = "524288";
      }
      {
        domain = "*";
        item = "memlock";
        type = "-";
        value = "524288";
      }
    ];
  };
  system.stateVersion = "24.11";
}
