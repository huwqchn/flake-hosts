# Full test to verify complete merge default config logic
# Tests both buildHosts and mkHosts functions

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
  
  # Test configuration similar to what flake-module.nix does
  testConfig = {
    auto = {
      enable = true;
      hostsDir = ./tests/hosts;
    };
    hosts = {
      # This will be merged with auto-discovered hosts
    };
    perClass = class: { modules = []; specialArgs = {}; };
    perArch = arch: { modules = []; specialArgs = {}; };
  };
  
  # Step 1: Auto-discover hosts (this is what buildHosts does)
  autoDiscoveredHosts = flakeHostsLib.buildHosts testConfig;
  
  # Step 2: Merge with default.nix and process (this is what mkHosts does)
  finalConfig = testConfig // {
    hosts = testConfig.hosts // autoDiscoveredHosts;
  };
  
  processedHosts = flakeHostsLib.mkHosts finalConfig;
  
in {
  # Show what was auto-discovered
  autoDiscovered = {
    hostCount = builtins.length (builtins.attrNames autoDiscoveredHosts);
    hostNames = builtins.attrNames autoDiscoveredHosts;
    
    # Show what default.nix contains
    defaultConfig = autoDiscoveredHosts.default or {};
    
    # Show what test-nixos contains before merge
    testNixosRaw = let
      config = autoDiscoveredHosts.test-nixos or {};
      args = config.specialArgs or {};
    in {
      inherit (config) class arch;
      specialArgsKeys = builtins.attrNames args;
    };
  };
  
  # Show the final processed configurations by class
  processed = {
    nixosConfigNames = builtins.attrNames (processedHosts.nixosConfigurations or {});
    darwinConfigNames = builtins.attrNames (processedHosts.darwinConfigurations or {});
    homeConfigNames = builtins.attrNames (processedHosts.homeConfigurations or {});
  };
  
  # Test summary
  tests = {
    autoDiscoveryWorks = builtins.length (builtins.attrNames autoDiscoveredHosts) > 0;
    defaultExists = autoDiscoveredHosts ? default;
    processedHostsExist = processedHosts ? nixosConfigurations;
    
    # Check if merge logic preserves the right information
    mergeLogicSummary = {
      rawDefaultArgs = builtins.attrNames ((autoDiscoveredHosts.default or {}).specialArgs or {});
      rawTestNixosArgs = builtins.attrNames ((autoDiscoveredHosts.test-nixos or {}).specialArgs or {});
      hasProcessedConfigs = (processedHosts.nixosConfigurations or {}) != {};
    };
  };
}