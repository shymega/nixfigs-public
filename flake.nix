# SPDX-FileCopyrightText: 2024 Dom Rodriguez <shymega@shymega.org.uk
#
# SPDX-License-Identifier: GPL-3.0-only
{
  description = "Private configs for my NixOS Flakes";

  outputs = inputs: let
    inherit (inputs) self;

    genPkgs = system:
      import inputs.nixpkgs {
        inherit system;
        overlays = builtins.attrValues self.overlays;
        config = self.nixpkgs-config;
      };

    systems = [
      "x86_64-linux"
      "aarch64-linux"
    ];

    treeFmtEachSystem = f: inputs.nixpkgs.lib.genAttrs systems (system: f inputs.nixpkgs.legacyPackages.${system});
    treeFmtEval = treeFmtEachSystem (
      pkgs:
        inputs.nixfigs-helpers.inputs.treefmt-nix.lib.evalModule pkgs inputs.nixfigs-helpers.helpers.formatter
    );

    forEachSystem = inputs.nixpkgs.lib.genAttrs systems;
  in {
    zfs-cachyos = self.nixosConfigurations.MJOLNIR-LINUX.config.boot.zfs.package.overrideAttrs (_: _: {
      preBuild = ''
        # force an exit with error
        exit 1
      '';

      nativeBuildInputs = [
        inputs.nixpkgs.legacyPackages.x86_64-linux.breakpointHook
      ];
    });
    inherit (inputs.nixfigs-pkgs) overlays nixpkgs-config;
    inherit (inputs.nixfigs-roles) roles utils;
    # for `nix fmt`
    formatter = treeFmtEachSystem (pkgs: treeFmtEval.${pkgs.stdenv.hostPlatform.system}.config.build.wrapper);
    # for `nix flake check`
    checks =
      treeFmtEachSystem (pkgs: {
        formatting = treeFmtEval.${pkgs}.config.build.wrapper;
      })
      // forEachSystem (system: {
        pre-commit-check = import "${inputs.nixfigs-helpers.helpers.checks}" {
          inherit self system;
          inherit (inputs.nixfigs-helpers) inputs;
          inherit (inputs.nixpkgs) lib;
        };
      });
    devShells = forEachSystem (
      system: let
        pkgs = genPkgs system;
      in
        import inputs.nixfigs-helpers.helpers.devShells {inherit pkgs self system;}
    );
    nixosModules = import ./modules/nixos;
    hosts = import ./hosts {inherit inputs self;};
    nixosConfigurations = import ./hosts/nixos {inherit inputs self;};
    darwinConfigurations = import ./hosts/darwin {inherit inputs self;};
    generators = import ./nix/generators.nix {inherit self;};
  };
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";
    nixpkgs-shymega.url = "github:shymega/nixpkgs?ref=shymega/staging";
    nixfigs-secrets.url = "github:shymega/nixfigs-secrets";
    nixfigs-networks.url = "github:shymega/nixfigs-networks";
    nixfigs-homes.url = "github:shymega/nixfigs-homes";
    nixfigs-pkgs.url = "github:shymega/nixfigs-pkgs";
    nixfigs-helpers.url = "github:shymega/nixfigs-helpers";
    nixfigs-common.url = "github:shymega/nixfigs-common";
    nixfigs-virtual-private.url = "github:shymega/nixfigs-virtual-private";
    nixfigs-virtual.url = "github:shymega/nixfigs-virtual";
    nixfigs-roles.url = "github:shymega/nixfigs-roles";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    flake-registry = {
      url = "github:NixOS/flake-registry";
      flake = false;
    };
    auto-cpufreq = {
      url = "github:AdnanHodzic/auto-cpufreq?rev=a1ac308be7b558f85c91a6a3e86cbc0cebdadbbc";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/nixos-wsl";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    devenv.url = "github:cachix/devenv/latest";
    hardware.url = "github:NixOS/nixos-hardware";
    hardware-shymega.url = "github:shymega/nixos-hardware?ref=shymega";
    impermanence.url = "github:nix-community/impermanence";
    agenix = {
      url = "github:ryantm/agenix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    nix-ld = {
      url = "github:Mic92/nix-ld";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-alien = {
      url = "github:thiagokokada/nix-alien";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-index-database.follows = "nix-index-database";
      };
    };
    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager?ref=release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote?ref=v1.0.0";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    stylix = {
      url = "github:danth/stylix?ref=release-26.05";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    base16-schemes.url = "github:SenchoPens/base16.nix";
    nix-doom-emacs-unstraightened.url = "github:marienz/nix-doom-emacs-unstraightened";
    nixfigs-doom-emacs = {
      url = "github:shymega/nixfigs-doom-emacs";
      flake = false;
    };
    srvos = {
      url = "github:nix-community/srvos";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-unstable.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    jovian-nixos = {
      url = "github:Jovian-Experiments/Jovian-NixOS?ref=development";
      inputs.nixpkgs.follows = "nixos-unstable";
    };
    shypkgs-private.url = "github:shymega/shypkgs-private";
    shypkgs-public.url = "github:shymega/shypkgs-public";
    onepassword-shell-plugins.url = "github:1Password/shell-plugins";
    nur-xddxdd = {
      url = "github:xddxdd/nur-packages";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ucodenix.url = "github:e-tho/ucodenix";
    himmelblau.url = "github:himmelblau-idm/himmelblau?ref=2.0.4";
    hyprland.follows = "nixfigs-pkgs/hyprnix/hyprland";
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins?ref=v0.55.0";
      inputs.hyprland.follows = "hyprland"; # Prevents version mismatch.
    };
    nixfigs-devenvs.url = "github:shymega/nixfigs-devenvs";
    win2k-plymouth = {
      url = "github:shymega/Win2K-Plymouth";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-amd-ai.url = "github:noamsto/nix-amd-ai";
  };
}
