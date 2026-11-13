# SPDX-FileCopyrightText: 2023-2026 Dom 'shymega' Rodriguez <shymega@shymega.org.uk>
#
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  libx,
  pkgs,
  inputs,
  ...
}: {
  imports = [
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/roles.nix
    inputs.nixfigs-common.common.nixos
  ];
  users = {
    mutableUsers = false;
    users."root".password = "!"; # Lock account.
    users."dzrodriguez" = {
      uid = 1000;
      isNormalUser = true;
      shell = pkgs.zsh;
      description = "Dom RODRIGUEZ";
      hashedPasswordFile = config.age.secrets.dzrodriguez.path;
      linger = true;
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
      extraGroups = [
        "adbusers"
        "dialout"
        "disk"
        "docker"
        "i2c"
        "input"
        "kvm"
        "libvirt"
        "libvirtd"
        "lp"
        "lpadmin"
        "networkmanager"
        "plugdev"
        "qemu-libvirtd"
        "render"
        "scanner"
        "systemd-journal"
        "uucp"
        "video"
        "wheel"
      ];
    };
  };

  security = {
    rtkit.enable = true;
    polkit.enable = true;
    sudo.wheelNeedsPassword = false; # Very dodgy!
  };

  location.provider = "geoclue2";

  services = {
    udisks2.enable = lib.mkDefault false;
    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };
    flatpak.enable = true;
    dbus.enable = true;
    openssh.enable = true;
    upower.enable = lib.mkForce true;
    printing = lib.optionalAttrs libx.isPC {
      enable = true;
      clientConf = ''
        ServerName 192.168.1.6
      '';
      browsed.enable = false;
      drivers = with pkgs; [
        hplipWithPlugin
        gutenprint
        gutenprintBin
        samsung-unified-linux-driver
        brlaser
        brgenml1lpr
        brgenml1cupswrapper
      ];
    };
    guix.enable = true;
    zerotierone = {
      enable = true;
      joinNetworks = ["@secret@"];
    };
    geoclue2 = {
      enable = true;
      enableDemoAgent = lib.mkForce true;
      submissionUrl = "@secret@";
      geoProviderUrl = config.services.geoclue2.submissionUrl;
      enableWifi = true;
      appConfig = {
        redshift = {
          isAllowed = true;
          isSystem = false;
        };
        gammastep = {
          isAllowed = true;
          isSystem = false;
        };
        darkman = {
          isAllowed = true;
          isSystem = false;
        };
      };
    };
    localtimed.enable = true;
    resolved = {
      enable = true;
      settings.Resolve = {
        DNS = "1.1.1.1#1dot1dot1dot1.cloudflare-dns.com 1.0.0.1#1dot1dot1dot1.cloudflare-dns.com 2606:4700:4700::1111#1dot1dot1dot1.cloudflare-dns.com 2606:4700:4700::1001#1dot1dot1dot1.cloudflare-dns.com";
        DNSOverTLS = "opportunistic";
        FallbackDNS = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };
    };
  };

  networking = {
    timeServers = lib.mkForce ["uk.pool.ntp.org"];
    usePredictableInterfaceNames = lib.mkForce false;

    firewall = {
      enable = true;
      interfaces."podman+".allowedUDPPorts = [53];
      checkReversePath = false;
    };
  };

  programs = {
    zsh.enable = true;
    fish.enable = true;
    mosh.enable = true;
    dconf.enable = true;
    xwayland.enable = true;

    _1password = {
      enable = true;
      package = pkgs._1password-cli;
    };
    _1password-gui = {
      enable = true;
      package = pkgs._1password-gui;
      polkitPolicyOwners = ["dzrodriguez"];
    };
  };

  virtualisation = {
    podman = {
      autoPrune.enable = true;
      defaultNetwork.settings = {
        # Required for container networking to be able to use names.
        dns_enabled = true;
      };
      enable = true;
    };

    oci-containers.backend = "docker";
    spiceUSBRedirection.enable = true;

    waydroid.enable = true;
    docker.enable = true;
    lxc.enable = true;

    libvirtd = lib.optionalAttrs libx.isPC {
      enable = true;
      qemu = {
        package = pkgs.qemu_full;
        runAsRoot = true;
        swtpm.enable = true;
      };
      onBoot = "ignore";
      parallelShutdown = 5;
      onShutdown = "suspend";
    };
  };

  system.stateVersion = "26.05";

  fonts.enableDefaultPackages = true;
  nixfigs = {
    fonts = {
      enable = true;
      xdg.enable = true;
    };
  };

  programs.hyprland = {
    enable = true;
    # hyprnixOverlaySafe (nixfigs-pkgs/overlays/default.nix) already sources
    # hyprland/xdg-desktop-portal-hyprland from hyprwm/Hyprland's own
    # self-consistent flake, with the aquamarine dpms-crtc-churn patch and
    # wayland-protocols bump applied -- no need to redo that here.
    package = pkgs.hyprland;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;
    xwayland.enable = true; # Xwayland can be disabled.
  };

  hardware.graphics = let
    hypr-nixpkgs = inputs.hyprland.inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    package = hypr-nixpkgs.mesa;
    package32 = hypr-nixpkgs.pkgsi686Linux.mesa;
  };

  specialisation = {
    hardening = {
      inheritParentConfig = true;
      configuration = {
        imports = [../../modules/nixos/hardening.nix];
        nixfigs.meta.specialisation = "hardening";
      };
    };
  };

  environment.etc."specialisation".text = config.nixfigs.meta.specialisation;
}
