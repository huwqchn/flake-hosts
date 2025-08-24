# Simple test to verify merge default config logic
# Run with: nix eval --file test-simple-merge.nix --show-trace

let
  pkgs = import <nixpkgs> {};
  lib = pkgs.lib;
  
  # Import flake-hosts lib functions
  flakeHostsLib = import ./lib.nix {
    inherit lib;
    inputs = {
      self = {};
      nixpkgs = pkgs;
    };
    withSystem = system: f: f { self' = {}; inputs' = {}; };
  };
  
  # Test configuration
  testConfig = {
    auto = {
      enable = true;
      hostsDir = ./tests/hosts;
    };
    hosts = {
      # This is like default.nix but in explicit config
      default = {
        modules = [ ];
        specialArgs = { fromDefault = "default-value"; };
      };
      
      # Explicit host that should merge with default
      testHost = {
        class = "nixos";
        arch = "x86_64";
        modules = [ ];
        specialArgs = { fromHost = "host-value"; };
      };
      
      # Pure host that should NOT merge with default
      pureHost = {
        class = "nixos";
        arch = "x86_64";
        pure = true;
        modules = [ ];
        specialArgs = { fromPure = "pure-value"; };
      };
    };
    
    perClass = class: { modules = []; specialArgs = {}; };
    perArch = arch: { modules = []; specialArgs = {}; };
  };
  
  # Build hosts using flake-hosts logic
  builtHosts = flakeHostsLib.buildHosts testConfig;
  processedHosts = flakeHostsLib.mkHosts testConfig;
  
  # Extract results for testing
  results = {
    # Test auto-discovered hosts
    discoveredHosts = builtins.attrNames builtHosts;
    
    # Test that test-nixos has merged default config
    testNixosHasDefault = let
      testNixosConfig = builtHosts.test-nixos or null;
    in testNixosConfig != null;
    
    # Test default.nix merge behavior in discovered hosts
    defaultConfigMerged = let
      testNixosConfig = builtHosts.test-nixos or {};
      hasDefaultArgs = (testNixosConfig ? testShared) && testNixosConfig.testShared == true;
    in hasDefaultArgs;
    
    # Show what was actually discovered
    hostConfigs = builtins.mapAttrs (name: config: {
      inherit (config) class arch;
      hasDeployable = config ? deployable;
      deployableValue = config.deployable or null;
      specialArgsKeys = builtins.attrNames (config.specialArgs or {});
      modulesCount = builtins.length (config.modules or []);
    }) builtHosts;
  };
  
in {
  inherit results builtHosts;
  
  summary = {
    hostCount = builtins.length (builtins.attrNames builtHosts);
    discoveredHosts = builtins.attrNames builtHosts;
    success = results.testNixosHasDefault && results.defaultConfigMerged;
  };
}