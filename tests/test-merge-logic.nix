# Test script to validate merge default config logic
# Run with: nix eval --file test-merge-logic.nix --json

let
  testFlake = import ./flake.nix;
  flakeOutputs = testFlake.outputs {
    nixpkgs = import <nixpkgs> {};
    flake-parts = import <flake-parts>;
    flake-hosts = import ../.;
  };
  
  # Extract host configurations for testing
  nixosConfigs = flakeOutputs.nixosConfigurations;
  
  # Helper to extract specialArgs from a configuration
  getSpecialArgs = config: config._module.args;
  
  # Helper to get systemPackages from a configuration  
  getSystemPackages = config: 
    map (pkg: pkg.pname or pkg.name) config.config.environment.systemPackages;
  
  # Test cases
  tests = {
    # Test 1: Normal merge behavior (test-merge host)
    test_merge_specialArgs = let
      mergeConfig = nixosConfigs.test-merge;
      args = getSpecialArgs mergeConfig;
    in {
      name = "Merge specialArgs test";
      passed = 
        args.testShared == true &&                    # From default.nix
        args.testHostSpecific == "host-value" &&     # From host
        args.testDefaultOnly == "only-in-default";   # From default.nix
      details = {
        inherit (args) testShared testHostSpecific testDefaultOnly;
      };
    };
    
    # Test 2: Override behavior (test-override host)
    test_override_behavior = let
      overrideConfig = nixosConfigs.test-override; 
      args = getSpecialArgs overrideConfig;
    in {
      name = "Override specialArgs test";
      passed = 
        args.testShared == true &&                   # From default.nix (not overridden)
        args.testOverride == "host-wins" &&         # Host overrides default
        args.testDefaultOnly == "only-in-default" && # From default.nix
        args.testHostOnly == "only-in-host";        # Only in host
      details = {
        inherit (args) testShared testOverride testDefaultOnly testHostOnly;
      };
    };
    
    # Test 3: Pure behavior (test-pure-merge host)
    test_pure_isolation = let
      pureConfig = nixosConfigs.test-pure-merge;
      args = getSpecialArgs pureConfig;
    in {
      name = "Pure host isolation test";
      passed = 
        !(args ? testShared) &&                     # Should NOT have default.nix args
        !(args ? testDefaultOnly) &&               # Should NOT have default.nix args  
        args.testPureOnly == "pure-host-value";    # Should have only host args
      details = {
        hasTestShared = args ? testShared;
        hasTestDefaultOnly = args ? testDefaultOnly;
        inherit (args) testPureOnly;
      };
    };
    
    # Test 4: Module merging behavior
    test_module_merging = let
      mergeConfig = nixosConfigs.test-merge;
      packages = getSystemPackages mergeConfig;
      pureConfig = nixosConfigs.test-pure-merge;
      purePackages = getSystemPackages pureConfig;
    in {
      name = "Module merging test";
      passed = 
        builtins.elem "vim" packages &&       # From shared.nix via default.nix
        builtins.elem "htop" packages &&      # From host config
        builtins.elem "curl" packages &&      # From host config
        !(builtins.elem "vim" purePackages) && # Pure should not have shared modules
        builtins.elem "wget" purePackages;     # Pure should have only host modules
      details = {
        mergePackages = packages;
        purePackages = purePackages;
      };
    };
  };
  
  # Summary
  summary = let
    allTests = builtins.attrValues tests;
    passedTests = builtins.filter (test: test.passed) allTests;
    failedTests = builtins.filter (test: !test.passed) allTests;
  in {
    total = builtins.length allTests;
    passed = builtins.length passedTests;
    failed = builtins.length failedTests;
    success = builtins.length failedTests == 0;
    
    results = builtins.mapAttrs (name: test: {
      inherit (test) name passed details;
    }) tests;
    
    failedTestNames = map (test: test.name) failedTests;
  };
  
in summary