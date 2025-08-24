# Basic test to verify merge default config logic
# Run with: nix eval --file test-merge-basic.nix

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
  
  # Test buildHosts function with our test directory
  testConfig = {
    auto = {
      enable = true;
      hostsDir = ./tests/hosts;
    };
  };
  
  # Build hosts using flake-hosts auto-discovery
  builtHosts = flakeHostsLib.buildHosts testConfig;
  
  # Extract just the host names and basic info
  hostSummary = builtins.mapAttrs (name: config: {
    class = config.class or "unknown";
    arch = config.arch or "unknown"; 
    hasSpecialArgs = (config.specialArgs or {}) != {};
    specialArgsKeys = builtins.attrNames (config.specialArgs or {});
    hasModules = (config.modules or []) != [];
    moduleCount = builtins.length (config.modules or []);
  }) builtHosts;
  
in {
  # Test results
  discoveredHosts = builtins.attrNames builtHosts;
  hostCount = builtins.length (builtins.attrNames builtHosts);
  
  # Show the summary for each host
  inherit hostSummary;
  
  # Specific tests for merge behavior
  tests = {
    # Check if default.nix values are merged into regular hosts
    testNixosHasDefault = let
      testNixos = builtHosts.test-nixos or {};
      args = testNixos.specialArgs or {};
    in {
      hasTestShared = args ? testShared;
      testSharedValue = args.testShared or null;
      hasDefaultOverride = args ? testOverride;
      testOverrideValue = args.testOverride or null;
    };
    
    # Check if pure hosts don't have default values
    testPureIsolated = let
      testPure = builtHosts.test-pure or {};
      args = testPure.specialArgs or {};
    in {
      hasTestShared = args ? testShared;
      isPureMarked = testPure.pure or false;
    };
  };
}