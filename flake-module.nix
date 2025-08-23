{
  lib,
  inputs,
  config,
  withSystem,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption literalExpression;
  inherit (lib.modules) mkIf;
  inherit (lib) types;

  inherit
    (import ./lib.nix {
      inherit
        lib
        inputs
        withSystem
        ;
    })
    constructSystem
    mkHosts
    buildHosts
    ;

  cfg = config.flake-hosts;

  # Basic parameter type definitions
  mkBasicParams = name: {
    modules = mkOption {
      type = types.listOf types.deferredModule;
      default = [];
      description = "${name} modules to be included in the system";
      example = literalExpression ''
        [ ./hardware-configuration.nix ./networking.nix ]
      '';
    };

    specialArgs = mkOption {
      type = types.lazyAttrsOf types.raw;
      default = {};
      description = "${name} special arguments to be passed to the system";
      example = literalExpression ''
        { foo = "bar"; }
      '';
    };
  };
in {
  # flake-parts module identifier
  _class = "flake";

  options = {
    flake-hosts = {
      auto = {
        enable =
          mkEnableOption "automatic host construction from filesystem"
          // {
            default = false;
          };

        hostsDir = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "./hosts";
          description = ''
            Directory where host files are located when auto.enable is true.
            When unset and auto.enable = true, defaults to the first existing of `./hosts` or `./systems`.

            Behavior: Traverses all folders under hostsDir. If it's a nix file, the filename becomes the hostname;
            if it's a folder with default.nix inside, the folder name containing default.nix becomes the hostname.
            default.nix in the hostsDir root folder will be merged into all hosts.
            Supports recursive search for default.nix, stops recursing when default.nix is found.
          '';
        };

        modulesDir = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "./modules";
          description = ''
            Directory where class-specific module files are located when auto.enable is true.
            When null (default), the system will try to infer it as the first existing of `./modules`, `./module`, or `./classes`. If none exist, no automatic class modules are loaded.

            When set (or inferred), the system will automatically look for class-specific modules. A class module can be either
            - a file: modulesDir/<class>.nix, or
            - a directory: modulesDir/<class>/default.nix.
            For directories, the system will look for subdirectories:
            - modulesDir/nixos/ for NixOS-specific modules
            - modulesDir/darwin/ for Darwin-specific modules
            - modulesDir/home/ for Home Manager-specific modules
            - modulesDir/nixOnDroid/ for Nix-on-Droid-specific modules

            Each class directory should contain a default.nix file with the class-specific configuration.
          '';
        };

        systems = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          example = literalExpression ''[ "x86_64-linux" "aarch64-darwin" ]'';
          description = ''
            Filter to only build hosts for the specified systems.
            When null (default), builds hosts for all systems found.
            When set, only hosts matching these system strings will be constructed.
          '';
        };
      };

      hosts = mkOption {
        description = "Hosts to be defined by the flake";
        default = {};
        type = types.attrsOf (
          types.submodule (
            {
              name,
              config,
              ...
            }: {
              options =
                {
                  nixpkgs = mkOption {
                    type = types.anything;
                    default = inputs.nixpkgs or (throw "cannot find nixpkgs input");
                    defaultText = literalExpression "inputs.nixpkgs";
                    example = literalExpression "inputs.nixpkgs-unstable";
                    description = "The nixpkgs flake to be used for the host";
                  };

                  nix-darwin = mkOption {
                    type = types.anything;
                    default = inputs.darwin or inputs.nix-darwin or null;
                    defaultText = literalExpression "inputs.darwin or inputs.nix-darwin";
                    example = literalExpression "inputs.my-nix-darwin";
                    description = "The nix-darwin flake to be used for the host";
                  };

                  home-manager = mkOption {
                    type = types.anything;
                    default = inputs.home-manager or null;
                    defaultText = literalExpression "inputs.home-manager";
                    example = literalExpression "inputs.my-home-manager";
                    description = "The home-manager flake to be used for the host";
                  };

                  nixOnDroid = mkOption {
                    type = types.anything;
                    default = inputs.droid or inputs.nixOnDroid or null;
                    defaultText = literalExpression "inputs.droid or inputs.nixOnDroid";
                    example = literalExpression "inputs.my-nixOnDroid";
                    description = "The nixOnDroid flake to be used for the host";
                  };

                  arch = mkOption {
                    type = types.enum [
                      "x86_64"
                      "aarch64"
                      "armv6l"
                      "armv7l"
                      "i686"
                      "powerpc64le"
                      "riscv64"
                    ];
                    default = "x86_64";
                    example = "aarch64";
                    description = "The architecture of the host";
                  };

                  class = mkOption {
                    type = types.enum [
                      "nixos"
                      "darwin"
                      "home"
                      "nixOnDroid"
                    ];
                    default = "nixos";
                    example = "darwin";
                    description = "The class of the host";
                  };

                  system = mkOption {
                    type = types.nullOr types.str;
                    internal = true;
                    default = constructSystem config.arch config.class;
                    example = "aarch64-darwin";
                    description = ''
                      System string constructed from arch and class.
                      This is an internal option - use `arch` and `class` instead.
                    '';
                  };

                  path = mkOption {
                    type = types.nullOr types.path;
                    default = null;
                    example = literalExpression "./hosts/myhost";
                    description = "Path to the directory containing the host files";
                  };

                  deployable =
                    mkEnableOption "Is this host deployable"
                    // {
                      default = false;
                    };

                  pure =
                    mkEnableOption "Skip shared configuration merging to keep host configuration pure"
                    // {
                      default = false;
                    };
                }
                // (mkBasicParams name);
            }
          )
        );
      };

      perArch = mkOption {
        default = _: {
          modules = [];
          specialArgs = {};
        };
        defaultText = ''
          arch: {
            modules = [ ];
            specialArgs = { };
          };
        '';
        type = types.functionTo (
          types.submodule {
            options = mkBasicParams "Per arch";
          }
        );
        example = literalExpression ''
          arch: {
            modules = [
              { system.nixos.label = arch; }
            ];
            specialArgs = { };
          }
        '';
        description = "Per arch settings";
      };

      perClass = mkOption {
        default = _: {
          modules = [];
          specialArgs = {};
        };
        defaultText = ''
          class: {
            modules = [ ];
            specialArgs = { };
          };
        '';
        type = types.functionTo (
          types.submodule {
            options = mkBasicParams "Per class";
          }
        );
        example = literalExpression ''
          class: {
            modules = [
              { system.nixos.label = class; }
            ];
            specialArgs = { };
          }
        '';
        description = "Per class settings";
      };
    };
  };

  config = {
    # Auto-construction logic: only use auto.enable
    flake-hosts.hosts = mkIf cfg.auto.enable (buildHosts cfg);

    flake = mkHosts cfg;
  };
}
