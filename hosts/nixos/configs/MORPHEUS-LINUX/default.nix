# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only

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
  disabledModules = [ "hardware/video/displaylink.nix" ];
  imports = [
    ./hardware-configuration.nix
    ./displaylink.nix
  ];

  networking = {
    hostName = "MORPHEUS-LINUX";
    hostId = "2355a46c";
  };
  boot = {
    supportedFilesystems = [
      "ntfs"
      "zfs"
    ];
    zfs.extraPools = [
      "zdata"
      "zroot"
    ];
    zfs.devNodes = "/dev/disk/by-partuuid";

    initrd.supportedFilesystems = [
      "ntfs"
      "zfs"
    ];

    kernelParams = pkgs.lib.mkAfter [
      "amdgpu"
      "amd_pstate=guided"
      "nohibernate"
    ];
    extraModprobeConfig = lib.mkAfter ''
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

    kernel.sysctl = {
      "fs.inotify.max_user_watches" = "819200";
      "kernel.printk" = "3 3 3 3";
    };

    plymouth = {
      enable = true;
      theme = "spinner";
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
        efiSysMountPoint = "/boot/efi";
      };
      generationsDir.copyKernels = true;
      timeout = lib.mkForce 6;
    };

    initrd.systemd.services = {
      rollback = {
        description = "Rollback ZFS datasets to a pristine state";
        wantedBy = [ "initrd.target" ];
        after = [ "zfs-import-zroot.service" ];
        before = [ "sysroot.mount" ];
        path = with pkgs; [ zfs ];
        unitConfig.DefaultDependencies = "no";
        serviceConfig.Type = "oneshot";
        script = ''
          zfs rollback -r zroot/crypt/nixos/linux/local/root@blank
        '';
      };
      create-needed-for-boot-dirs = {
        after = pkgs.lib.mkForce [
          "zfs-import-zdata.service"
          "zfs-import-zroot.service"
        ];
        wants = pkgs.lib.mkForce [
          "zfs-import-zdata.service"
          "zfs-import-zroot.service"
        ];
      };
    };
  };

  systemd.services."apply-acpi-wakeup-fixes" = {
    description = "Apply WM2 wakeup fixes";
    wantedBy = [ "basic.target" ];
    path = with pkgs; [
      gawk
      coreutils
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      for i in $(cat /proc/acpi/wakeup|grep enabled|awk '{print $1}'|xargs); do case $i in SLPB|XHCI);; *) echo $i|tee /proc/acpi/wakeup ; esac; done
    '';
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "powersave";
  };

  hardware = {
    gpd.ppt.enable = lib.mkForce false;
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
    i2c.enable = true;
    sensor.iio = {
      enable = true;
      bmi260.enable = true;
    };
    cpu.amd.ryzen-smu.enable = true;
  };
  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "armv6l-linux"
    "armv7l-linux"
  ];

  services = {
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
      videoDrivers = [ "amdgpu" ];
    };
    ollama = {
      enable = true;
      package = pkgs.ollama;
      acceleration = "rocm";
      models = "/data/AI/LLMs/Ollama/Models/";
      environmentVariables = {
        HSA_OVERRIDE_GFX_VERSION = "11.0.0"; # 780M.
      };
    };
    fstrim.enable = false;
    smartd = {
      enable = true;
      autodetect = true;
    };
    power-profiles-daemon.enable = true;
    input-remapper.enable = true;
    thermald.enable = true;
    udev = {
      packages = with pkgs; [ gnome.gnome-settings-daemon ];
      extraRules = ''
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="0", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start battery.target"
        SUBSYSTEM=="power_supply", KERNEL=="ADP1", ATTR{online}=="1", RUN+="${pkgs.lib.getExe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # workstation - keyboard & mouse suspension.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="05ac", ATTR{idProduct}=="024f", ATTR{power/autosuspend}="-1"
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="1bcf", ATTR{idProduct}=="0005", ATTR{power/autosuspend}="-1"

        # 4g lte modem.
        ACTION=="add|change", SUBSYSTEM=="usb", ATTR{idVendor}=="2c7c", ATTR{idProduct}=="0125", ATTR{power/autosuspend}="-1"

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

        # wm2 i2c fixes.
        SUBSYSTEM=="i2c", KERNEL=="i2c-gxtp7385:00", ATTR{power/wakeup}="disabled"
      '';
    };
    ofono = {
      enable = true;
      plugins = [
        pkgs.modem-manager-gui
        pkgs.libsForQt5.modemmanager-qt
      ];
    };
    logind = {
      lidSwitchExternalPower = "ignore";
      lidSwitchDocked = "ignore";
      extraConfig = ''
        LidSwitchIgnoreInhibited=no
      '';
    };
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

  #  environment = {
  #    variables = {
  #      WLR_DRM_DEVICES = "/dev/dri/card0:/dev/dri/card1:/dev/dri/card2";
  #    };
  #  };

  system.stateVersion = "24.05";

}
