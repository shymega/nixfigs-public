# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  self,
  inputs,
  ...
}: let
  genPkgs = system:
    import inputs.nixpkgs {
      inherit system;
      overlays = builtins.attrValues self.overlays;
      config = self.nixpkgs-config;
    };
  inherit (inputs.nixpkgs.lib.strings) hasSuffix;
  mkHost = {
    type ? "nixos",
    address ? null,
    hostname ? null,
    hostPlatform ? "x86_64-linux",
    username ? "dzrodriguez",
    baseModules ? [
      {
        environment.systemPackages = [
          inputs.agenix.packages.${hostPlatform}.default
          # inputs.nix-alien.packages.${hostPlatform}.nix-alien
        ];
      }
      (import inputs.nixfigs-common.common.core {
        inherit inputs;
        inherit hostname;
        pkgs = genPkgs hostPlatform;
        inherit (inputs.nixpkgs) lib;
      })
      inputs.nixfigs-secrets.system
    ],
    monolithConfig ? true,
    overlays ? [],
    hostRoles ? ["workstation"],
    hardwareModules ? [],
    extraModules ? [],
    pubkey ? null,
    remoteBuild ? true,
    deployable ? false,
    embedHm ? false,
  }:
    if type == "nixos"
    then
      assert address != null;
      assert (hasSuffix "linux" hostPlatform); {
        inherit
          address
          baseModules
          deployable
          embedHm
          extraModules
          hardwareModules
          hostPlatform
          hostRoles
          hostname
          monolithConfig
          overlays
          pubkey
          remoteBuild
          type
          username
          ;
      }
    else if type == "darwin"
    then
      assert address != null;
      assert (hasSuffix "darwin" hostPlatform); {
        inherit
          address
          baseModules
          deployable
          extraModules
          hardwareModules
          hostPlatform
          hostname
          monolithConfig
          pubkey
          remoteBuild
          type
          username
          ;
      }
    else throw "unknown host type '${type}'";
in {
  NEO-LINUX = mkHost rec {
    type = "nixos";
    address = "NEO-LINUX.dzr.devices.rnet.rodriguez.org.uk";
    hostname = "NEO-LINUX";
    hostPlatform = "x86_64-linux";
    hostRoles = [
      "workstation"
      "gaming"
      "personal"
    ];
    hardwareModules = [
      inputs.hardware.nixosModules.common-cpu-amd
      inputs.hardware.nixosModules.common-gpu-amd
      inputs.hardware.nixosModules.common-pc-ssd
      inputs.hardware.nixosModules.common-pc
    ];
    extraModules = [
      inputs.lanzaboote.nixosModules.lanzaboote
      {environment.systemPackages = [inputs.nixpkgs.legacyPackages.${hostPlatform}.sbctl];}
    ];
    pubkey = "";
    embedHm = true;
    remoteBuild = true;
    deployable = true;
  };

  MORPHEUS-LINUX = mkHost rec {
    type = "nixos";
    address = "MORPHEUS-LINUX.dzr.devices.rnet.rodriguez.org.uk";
    hostname = "MORPHEUS-LINUX";
    hostPlatform = "x86_64-linux";
    hostRoles = [
      "workstation"
      "gaming"
      "personal"
    ];
    embedHm = true;
    hardwareModules = [inputs.hardware.nixosModules.gpd-win-max-2-2023];
    extraModules = [
      inputs.lanzaboote.nixosModules.lanzaboote
      {environment.systemPackages = [inputs.nixpkgs.legacyPackages.${hostPlatform}.sbctl];}
    ];
    pubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBqOAfNq3lGPElJ0L6qAqQLDykRWsN9dE4sMZkD6YVKu";
    remoteBuild = true;
    deployable = true;
  };

  DEUSEX-LINUX = mkHost rec {
    type = "nixos";
    address = "DEUSEX-LINUX.dzr.devices.rnet.rodriguez.org.uk";
    hostname = "DEUSEX-LINUX";
    hostPlatform = "x86_64-linux";
    hostRoles = [
      "workstation"
      "gaming"
      "personal"
    ];
    embedHm = true;
    extraModules = [
      inputs.lanzaboote.nixosModules.lanzaboote
      inputs.hardware-shymega.nixosModules.gpd-duo
      {environment.systemPackages = [inputs.nixpkgs.legacyPackages.${hostPlatform}.sbctl];}
    ];
    pubkey = "";
    remoteBuild = true;
    deployable = true;
  };

  TWINS-LINUX = mkHost rec {
    type = "nixos";
    address = "TWINS-LINUX.dzr.devices.rnet.rodriguez.org.uk";
    hostname = "TWINS-LINUX";
    hostPlatform = "x86_64-linux";
    hostRoles = [
      "workstation"
      "personal"
    ];
    hardwareModules = [inputs.hardware.nixosModules.lenovo-thinkpad-x270];
    extraModules = [
      inputs.lanzaboote.nixosModules.lanzaboote
      {environment.systemPackages = [inputs.nixpkgs.legacyPackages.${hostPlatform}.sbctl];}
    ];
    pubkey = "";
    remoteBuild = true;
    deployable = false;
    embedHm = true;
  };

  #   SMITH-LINUX = mkHost rec {
  #     type = "nixos";
  #     address = "SMITH-LINUX.dzr.devices.rnet.rodriguez.org.uk";
  #     hostname = "SMITH-LINUX";
  #     hostPlatform = "aarch64-linux";
  #     monolithConfig = false;
  #     hostRoles = ["minimal"];
  #     hardwareModules = [inputs.hardware.nixosModules.raspberry-pi-4];
  #     extraModules = [
  #       {
  #         environment.systemPackages = [
  #           inputs.agenix.packages.${hostPlatform}.default
  #         ];
  #       }
  #       "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
  #     ];
  #     pubkey = "";
  #     remoteBuild = true;
  #     deployable = false;
  #   };

  ### Experimental Device Ports ###
  ## ClockworkPi uConsole (CM4) ##
  # Received, Debian installed. Work ongoing to upstream DTB and driver patches. #
  CLOCKWORK-UC-CM4 = mkHost rec {
    type = "nixos";
    address = "dial-in.rnet.rodriguez.org.uk";
    username = "dzrodriguez";
    hostPlatform = "aarch64-linux";
    hostname = "CLOCKWORK-UC-CM4";
    remoteBuild = true;
    deployable = false;
    monolithConfig = false;
    hostRoles = ["minimal"];
    hardwareModules = [inputs.hardware.nixosModules.raspberry-pi-4];
    extraModules = [
      {
        environment.systemPackages = [
          inputs.agenix.packages.${hostPlatform}.default
          # inputs.nix-alien.packages.${hostPlatform}.nix-alien
        ];
      }
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ];
  };

  ## End ClockworkPi uConsole (CM4) ##

  ## ClockworkPi DevTerm (CM4) ##
  CLOCKWORK-DT-CM4 = mkHost rec {
    type = "nixos";
    address = "dial-in.rnet.rodriguez.org.uk";
    username = "dzrodriguez";
    hostPlatform = "aarch64-linux";
    hostname = "CLOCKWORK-DT-CM4";
    hostRoles = ["minimal"];
    remoteBuild = true;
    deployable = false;
    monolithConfig = false;
    hardwareModules = [inputs.hardware.nixosModules.raspberry-pi-4];
    extraModules = [
      {
        environment.systemPackages = [
          inputs.agenix.packages.${hostPlatform}.default
          # inputs.nix-alien.packages.${hostPlatform}.nix-alien
        ];
      }
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
    ];
  };
  ## End ClockworkPi DevTerm (CM4) ##
}
