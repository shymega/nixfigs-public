# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only

{ self, inputs, ... }:
let
  genPkgs =
    system: overlays:
    import inputs.nixpkgs {
      inherit system;
      overlays = builtins.attrValues self.overlays ++ overlays;
      config = self.nixpkgs-config;
    };

  inherit (inputs) darwin;
  genConfiguration =
    hostname:
    {
      address,
      hostPlatform,
      type,
      username,
      deployable,
      overlays,
      embedHm,
      hostRoles,
      ...
    }:
    let
      libx = inputs.nixfigs-helpers.libx.${hostPlatform};
      inherit (inputs.nixpkgs) lib;
    in
    darwin.lib.darwinSystem {
      system = hostPlatform;
      pkgs = libx.genPkgs hostPlatform overlays;
      modules = [ (../hosts/darwin + "/${hostname}") ];
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
          deployable
          hostname
          hostPlatform
          ;
      };
    };
in
inputs.nixpkgs.lib.mapAttrs genConfiguration (
  inputs.nixpkgs.lib.filterAttrs (_: host: host.type == "darwin") self.hosts
)
