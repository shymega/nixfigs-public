# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only

{ inputs, self, ... }:
let
  genPkgs =
    system: overlays:
    import inputs.nixpkgs {
      inherit system;
      overlays = builtins.attrValues self.overlays ++ overlays;
      config = self.nixpkgs-config;
    };
  genConfiguration =
    hostname:
    {
      address,
      hostPlatform,
      type,
      extraModules,
      username,
      deployable,
      monolithConfig,
      overlays,
      embedHm,
      hostRoles,
      hardwareModules,
      baseModules,
      ...
    }:
    let
      libx = inputs.nixfigs-helpers.libx.${hostPlatform};
      inherit (inputs.nixpkgs) lib;
    in
    inputs.nixpkgs.lib.nixosSystem rec {
      system = hostPlatform;
      pkgs = genPkgs hostPlatform overlays;
      modules =
        baseModules
        ++ [
          (./configs + "/${hostname}")
          ../../modules/nixos/generators.nix
          inputs.agenix.nixosModules.default
          inputs.auto-cpufreq.nixosModules.default
        ]
        ++ extraModules
        ++ hardwareModules
        ++ (lib.optional embedHm inputs.home-manager.nixosModules.home-manager)
        ++ (lib.optional embedHm {
          home-manager = {
            useGlobalPkgs = true;
            backupFileExtension = "hm.bak";
            useUserPackages = true;
            users.${username} = inputs.nixfigs-homes.homeModules.default;
            extraSpecialArgs = {
              inherit
                self
                inputs
                embedHm
                username
                hostRoles
                specialArgs
                deployable
                hostname
                libx
                hostPlatform
                ;
              system = hostPlatform;
            };
          };
        })
        ++ (lib.optional monolithConfig (import ./monolith.nix));
      specialArgs = {
        hostAddress = address;
        hostType = type;
        pkgs = genPkgs hostPlatform overlays;
        system = hostPlatform;
        inherit
          self
          inputs
          lib
          libx
          embedHm
          username
          hostRoles
          specialArgs
          deployable
          hostname
          hostPlatform
          ;
      };
    };
in
inputs.nixpkgs.lib.mapAttrs genConfiguration (
  inputs.nixpkgs.lib.filterAttrs (_: host: host.type == "nixos") self.hosts
)
