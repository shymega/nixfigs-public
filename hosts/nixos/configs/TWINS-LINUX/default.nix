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
    fwupd.enable = true;
    udev.extraRules = ''
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
      SUBSYSTEM=="power_supply", KERNEL=="AC", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

      # workstation - keyboard & mouse suspension.
      action=="add|change", subsystem=="usb", attr{idvendor}=="05ac", attr{idproduct}=="024f", attr{power/autosuspend}="-1"
      action=="add|change", subsystem=="usb", attr{idvendor}=="1bcf", attr{idproduct}=="0005", attr{power/autosuspend}="-1"

      # workstation - dock targets.
      subsystem=="usb", action=="add|change", attr{idvendor}=="0b95", attr{idproduct}=="1790", symlink+="docked", symlink+="home-office-docked", tag+="systemd"
      subsystem=="usb", action=="add|change", attr{idvendor}=="17ef", attr{idproduct}=="3060", symlink+="docked", symlink+="home-office-docked", tag+="systemd"

      # kvm switch target.
      subsystem=="usb", action=="add|change|remove", attr{idvendor}=="1bcf", attr{idproduct}=="0005",  symlink+="kvm-active", tag+="systemd"

      # rename network interface.
      subsystem=="net", action=="add|change", drivers=="?*", env{devtype}=="wlan", kernel=="wlan*", name="wlan0"

      # my personal iphone.
      subsystem=="net", action=="add|change", drivers=="?*", env{id_model_id}=="12a8", kernel=="eth*", name="iphone0"

      # my personal op6t.
      subsystem=="net", action=="add|change", drivers=="?*", env{id_model_id}=="9024", kernel=="usb*", name="android0"

      # docking station ethernet - rename.
      subsystem=="net", action=="add|change", drivers=="?*", env{id_model_id}=="1790", kernel=="eth*", name="docketh0"
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
