# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only

#

{
  config,
  pkgs,
  lib,
  ...
}:
let
  enableXanmod = true;
in
{
  imports = [ ./hardware-configuration.nix ];

  environment.etc."crypttab".text = ''
    homecrypt /dev/disk/by-label/HOMECRYPT /persist/etc/.homecrypt.bin
  '';
  networking = {
    hostName = "NEO-LINUX";
    hostId = "971581e3";
  };
  boot = {
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
        create-needed-for-boot-dirs = {
          after = pkgs.lib.mkForce [ "zfs-import-tank.service" ];
          wants = pkgs.lib.mkForce [ "zfs-import-tank.service" ];
        };
      };
    };

    kernelParams = [ "nohibernate" ];
    extraModprobeConfig = ''
      options zfs l2arc_noprefetch=0 l2arc_write_boost=33554432 l2arc_write_max=16777216 zfs_arc_max=12884901888
      options kvm_amd nested=1
      options kvm ignore_msrs=1 report_ignored_msrs=0
    '';

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
                sha256 = "sha256-4BXPZs8lp/O/JGWFIO/J1HyOjByaqWQ9O6/jx76TIDs=";
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
      extraPackages32 = with pkgs; [ driversi686Linux.amdvlk ];
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
    enable = true;
    package = pkgs.ollama;
    acceleration = "rocm";
    sandbox = false;
    models = "/data/AI/LLMs/Ollama/Models/";
    environmentVariables = {
      HSA_OVERRIDE_GFX_VERSION = "10.3.0"; # 680M.
    };
  };

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv6l-linux"
    "armv7l-linux"
    "i686-linux"
  ];

  services = {
    udev = {
      packages = with pkgs; [ gnome.gnome-settings-daemon ];
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

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
      videoDrivers = [ "amdgpu" ];
    };
    auto-cpufreq.enable = false;
    power-profiles-daemon.enable = pkgs.lib.mkForce false;
    thermald.enable = true;
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  programs.steam = {
    enable = true;
    gamescopeSession.enable = false;
    package = pkgs.steam.override {
      extraPkgs =
        pkgs: with pkgs; [
          deckcheatz
          protontricks
          protonup-qt
          python3Full
          python3Packages.pip
          python3Packages.virtualenv
          steamcmd
          steamtinkerlaunch
          wemod-launcher
          wineWowPackages.stable
          winetricks
        ];
      extraLibraries = p: with p; [ (lib.getLib networkmanager) ];
    };
    extraPackages = with pkgs; [
      deckcheatz
      protonup-qt
      python3Full
      python3Packages.pip
      python3Packages.virtualenv
      steamcmd
      steamtinkerlaunch
      wemod-launcher
    ];
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
  system.stateVersion = "24.05";

}
