# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  pkgs,
  inputs,
  ...
}: let
  zfs_arc_max = 8 * 1024 * 1024 * 1024;
  zfs_arc_min = zfs_arc_max - 1;
in {
  imports = with inputs; [
    ./hardware-configuration.nix
    nur-xddxdd.nixosModules.setupOverlay
    nur-xddxdd.nixosModules.qemu-user-static-binfmt
    nur-xddxdd.nixosModules.nix-cache-attic
  ];

  networking = {
    hostName = "TWINS-LINUX";
    hostId = "c6153b29";
    usePredictableInterfaceNames = false;
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
    kernelPackages = pkgs.linuxPackages_6_18;

    zfs.devNodes = "/dev/TWINS-LINUX/ROOT";

    extraModprobeConfig = ''
      options kvm_intel nested=1
      options kvm_intel emulate_invalid_guest_state=0
      options kvm ignore_msrs=1 report_ignored_msrs=0
    '';
    kernelParams = [
      "nohibernate"
      "zfs.zfs_arc_max=${toString zfs_arc_max}"
      "zfs.zfs_arc_min=${toString zfs_arc_min}"
      "zfs.l2arc_write_boost=33554432"
      "zfs.l2arc_write_max=16777216"
      "initcall_blacklist=algif_aead_init"
    ];

    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
    };

    initrd.luks.devices = {
      nixos = {
        device = "/dev/disk/by-label/NIXOS";
        preLVM = true;
        allowDiscards = true;
      };
    };

    plymouth = {
      enable = true;
    };

    loader = {
      systemd-boot = {
        enable = false;
      };
      grub = {
        device = "nodev";
        efiSupport = true;
        default = "saved";
        enable = true;
        useOSProber = true;
      };
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
      timeout = 6;
    };

    initrd.systemd.services.rollback = {
      description = "Rollback ZFS datasets to a pristine state";
      wantedBy = ["initrd.target"];
      after = ["zfs-import-tank.service"];
      before = ["sysroot.mount"];
      path = with pkgs; [zfs];
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r tank/local/root@blank
      '';
    };
  };

  services = {
    power-profiles-daemon.enable = pkgs.lib.mkForce false;
    xserver = {
      enable = true;
      videoDrivers = [
        "modesetting"
        "i915"
      ];
    };
    fwupd.enable = true;
    hardware.bolt.enable = true;
    udev.extraRules = ''
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

      # workstation - keyboard & mouse suspension.
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="024f", ATTR{power/autosuspend}="-1"
      ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="0005", ATTR{power/autosuspend}="-1"

      # workstation - dock targets.
      SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", SYMLINK+="home-office-docked", TAG+="systemd"
      SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="3060", SYMLINK+="home-office-docked", TAG+="systemd"

      # kvm switch target.
      SUBSYSTEM=="usb", ACTION=="add|change|remove", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="0005",  SYMLINK+="kvm-active", TAG+="systemd"
    '';
    thermald.enable = true;
    logind = {
      settings.Login = {
        LidSwitchExternalPower = "ignore";
        LidSwitchDocked = "ignore";
        LidSwitchIgnoreInhibited = "no";
      };
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
      extraPackages32 = with pkgs.pkgsi686Linux; [vaapiIntel];
      extraPackages = with pkgs; [
        vaapiIntel
        libva-vdpau-driver
        libvdpau-va-gl
        intel-media-driver
        intel-compute-runtime
      ];
    };
  };
  system.stateVersion = "25.11";
}
