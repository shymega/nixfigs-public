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
    hardware.bolt.enable = true;
    handheld-daemon = {
      enable = true;
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
      sandbox = false;
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
      extrarules = ''
        subsystem=="power_supply", kernel=="ADP1", attr{online}=="0", run+="${pkgs.lib.getexe' pkgs.systemd "systemctl"} --no-block start battery.target"
        subsystem=="power_supply", kernel=="ADP1", attr{online}=="1", run+="${pkgs.lib.getexe' pkgs.systemd "systemctl"} --no-block start ac.target"

        # workstation - keyboard & mouse suspension.
        action=="add|change", subsystem=="usb", attr{idvendor}=="05ac", attr{idproduct}=="024f", attr{power/autosuspend}="-1"
        action=="add|change", subsystem=="usb", attr{idvendor}=="1bcf", attr{idproduct}=="0005", attr{power/autosuspend}="-1"

        # 4g lte modem.
        action=="add|change", subsystem=="usb", attr{idvendor}=="2c7c", attr{idproduct}=="0125", attr{power/autosuspend}="-1"

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

        # wm2 i2c fixes.
        subsystem=="i2c", kernel=="i2c-gxtp7385:00", attr{power/wakeup}="disabled"
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
      extraEnv = {
        LIBVA_DRIVER_NAME = "vdpau";
      };
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
