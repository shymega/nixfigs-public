# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only

{
  pkgs,
  config,
  lib,
  ...
}:
let
  enableXanmod = true;
in
{
  imports = [ ./hardware-configuration.nix ];

  networking = {
    hostName = "TWINS-LINUX";
    hostId = "6842efa5";
  };

  boot = {
    supportedFilesystems = [
      "ntfs"
      "zfs"
    ];

    kernelPackages =
      if enableXanmod then
        pkgs.unstable.linuxPackagesFor (
          pkgs.unstable.linux_xanmod_latest.override {
            argsOverride = rec {
              modDirVersion = "${version}-${suffix}";
              suffix = "xanmod1";
              version = "6.11.2";

              src = pkgs.fetchFromGitHub {
                owner = "xanmod";
                repo = "linux";
                rev = "${version}-${suffix}";
                hash = "sha256-4BXPZs8lp/O/JGWFIO/J1HyOjByaqWQ9O6/jx76TIDs=";
              };
            };
          }
        )
      else
        config.boot.zfs.package.latestCompatibleLinuxPackages;

    kernelPatches = lib.optionals (!enableXanmod) [
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

    extraModulePackages = with config.boot.kernelPackages; [ zfs ];

    zfs.devNodes = "/dev/TWINS-LINUX/ROOT";

    extraModprobeConfig = ''
      options zfs l2arc_noprefetch=0 l2arc_write_boost=33554432 l2arc_write_max=16777216 zfs_arc_max=12884901888
      options kvm_intel nested=1
      options kvm_intel emulate_invalid_guest_state=0
      options kvm ignore_msrs=1 report_ignored_msrs=0

    '';
    kernelParams = [ "nohibernate" ];

    kernel.sysctl = {
      "dev.i915.perf_stream_paranoid" = "0";
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
      wantedBy = [ "initrd.target" ];
      after = [ "zfs-import-tank.service" ];
      before = [ "sysroot.mount" ];
      path = with pkgs; [ zfs ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r tank/local/root@blank
      '';
    };
  };

  services = {
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
      SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="0b95", ATTR{idProduct}=="1790", SYMLINK+="docked", SYMLINK+="home-office-docked", TAG+="systemd"
      SUBSYSTEM=="usb", ACTION=="add|change", ATTR{idVendor}=="17ef", ATTR{idProduct}=="3060", SYMLINK+="docked", SYMLINK+="home-office-docked", TAG+="systemd"

      # kvm switch target.
      SUBSYSTEM=="usb", ACTION=="add|change|remove", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="0005",  SYMLINK+="kvm-active", TAG+="systemd"

      # rename network interface.
      SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{DEVTYPE}=="wlan", KERNEL=="wlan*", NAME="wlan0"

      # my personal iphone.
      SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="12a8", KERNEL=="eth*", NAME="iphone0"

      # my personal op6t.
      SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="9024", KERNEL=="usb*", NAME="android0"

      # docking station ethernet - rename.
      SUBSYSTEM=="net", ACTION=="add|change", DRIVERS=="?*", ENV{ID_MODEL_ID}=="1790", KERNEL=="eth*", NAME="docketh0"
    '';
    auto-cpufreq.enable = false;
    thermald.enable = true;
    logind = {
      extraConfig = ''
        HandleLidSwitchExternalPower=ignore
        LidSwitchIgnoredInhibited=no
      '';
    };
    zfs = {
      trim = {
        enable = true;
        interval = "Sat *-*-* 04:00:00";
      };
      autoScrub = {
        enable = true;
        interval = "Sat *-*-* 05:00:00";
      };
    };
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "powersave";
  };

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv6l-linux"
    "armv7l-linux"
  ];

  hardware = {
    opengl = {
      enable = true;
      driSupport = true;
      extraPackages32 = with pkgs.pkgsi686Linux; [ vaapiIntel ];
      extraPackages = with pkgs; [
        vaapiIntel
        vaapiVdpau
        libvdpau-va-gl
        intel-media-driver
        intel-compute-runtime
      ];
    };
  };
  system.stateVersion = "24.05";

}
