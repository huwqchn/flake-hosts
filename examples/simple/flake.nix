{
  description = "Simple flake-hosts example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    flake-hosts = {
      url = "path:../..";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.flake-hosts.flakeModule
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      flake-hosts = {
        # Modern auto configuration (recommended)
        auto = {
          enable = true;
          hostsDir = ./hosts;
          modulesDir = ./modules;
          # systems = null; # Build all systems (default)
        };
        
        # Mix auto-constructed and explicit hosts
        hosts = {
          # Shared configuration for all explicit hosts
          default = {
            modules = [ ./modules/shared.nix ];
          };
          
          # Explicit host definition
          test-explicit = {
            class = "nixos";
            arch = "x86_64";
            pure = true;  # Test pure option
            modules = [ ./modules/test.nix ];
          };
        };

        # Per-class configuration is now automatic via modulesDir
        # Class-specific modules are loaded from ./modules/{class}/default.nix
      };
    };
}