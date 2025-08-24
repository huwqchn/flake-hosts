# flake-hosts library implementation
#
# This file contains the core implementation of the flake-hosts library,
# which provides utilities for managing NixOS and Darwin system configurations
# in Nix flakes. It implements an "input-less" architecture pattern inspired
# by easy-hosts, allowing consuming flakes to control their own input versions.
#
# Key Features:
#   - Automatic host discovery from filesystem structure
#   - Flexible system/class/architecture resolution
#   - Class-specific module loading (nixos, darwin, home, nixOnDroid)
#   - Layered configuration system with shared, per-class, and per-arch configs
#   - Support for both explicit and auto-discovered host definitions
#   - Input-less architecture for maximum flexibility
#
# Architecture Overview:
#   The library is organized into several functional areas:
#   1. System Utilities: Handle system string parsing and resolution
#   2. Path Utilities: Implement filesystem discovery and path resolution
#   3. Module Loading: Load and resolve Nix modules from various sources
#   4. Host Building: Construct individual system configurations
#   5. Configuration Merging: Combine multiple configuration sources
#   6. Collection Processing: Handle bulk operations on host collections
#
# This file is designed to be imported by flake-module.nix and provides
# the core functions (mkHosts, buildHosts) used to implement the flake-parts module.
{
  lib,
  inputs,
  withSystem,
  ...
}:
let
  inherit (inputs) self;
  inherit (builtins)
    readDir
    map
    foldl'
    elem
    ;
  inherit (lib)
    pathExists
    foldAttrs
    pipe
    optionals
    singleton
    concatLists
    recursiveUpdate
    attrValues
    mapAttrs
    filterAttrs
    mkDefault
    mergeAttrs
    mapAttrs'
    hasSuffix
    removeSuffix
    ;

  # =============================================================================
  # SYSTEM UTILITIES
  # =============================================================================
  # These utilities handle the conversion between different system representations:
  # - system strings (e.g., "x86_64-linux", "aarch64-darwin")
  # - class + arch pairs (e.g., { class = "nixos"; arch = "x86_64"; })
  # They support the input-less architecture pattern by allowing flexible
  # system specification and automatic inference.

  # Constructs a Nix system string from architecture and class components.
  # This is the inverse operation of splitSystem and handles the mapping between
  # flake-hosts' semantic class names and Nix's system conventions.
  #
  # Parameters:
  #   arch (string): System architecture ("x86_64", "aarch64", etc.)
  #   class (string): System class ("nixos", "darwin", "home", "nixOnDroid")
  #
  # Returns:
  #   string | null: Nix system string, or null for classes that don't need one
  #
  # Examples:
  #   constructSystem "x86_64" "nixos" => "x86_64-linux"
  #   constructSystem "aarch64" "darwin" => "aarch64-darwin"
  #   constructSystem "x86_64" "home" => null (home-manager doesn't use system)
  #
  # Related Functions:
  #   - Used by flake-module.nix to construct system strings for internal system option
  constructSystem =
    arch: class:
    if class == "darwin" then
      "${arch}-darwin"
    else if class == "nixos" then
      "${arch}-linux"
    else
      null; # home and nixOnDroid don't need system strings for their builders

  # Note: splitSystem function removed - no longer needed with internal system option

  # Note: resolveSystemConfig function removed - system is now computed in flake-module.nix

  # =============================================================================
  # PATH UTILITIES
  # =============================================================================
  # These utilities handle filesystem path resolution and module discovery.
  # They implement the auto-discovery logic that allows flake-hosts to
  # automatically find host configurations and class-specific modules
  # from standard directory structures.

  # Note: checkModulePath function removed - in Nix, paths can be:
  # - .nix files directly
  # - directories containing default.nix
  # Nix's import system handles this resolution automatically.

  # Extracts and validates filesystem paths from configuration.
  # Paths must be explicitly set by users - no automatic fallback searching.
  #
  # Parameters:
  #   cfg (attrset): The flake-hosts configuration from flake-module.nix
  #
  # Returns:
  #   { hostsDir: string?, systemsFilter: list? }: Resolved paths
  #
  # Path Resolution Logic:
  #   - hostsDir: Required when auto.enable=true, must be explicitly set
  #   - systemsFilter: Copy of cfg.auto.systems for filtering built hosts
  #
  # Error Handling:
  #   - hostsDir throws error if not set when auto.enable=true
  #   - All paths return null when auto.enable=false
  inferPaths = cfg: {
    # Hosts directory is required for auto-discovery and must be explicitly set
    hostsDir =
      if cfg.auto.enable then
        (
          if cfg.auto.hostsDir != null then
            cfg.auto.hostsDir
          else
            throw "flake-hosts.auto.hostsDir is required when auto.enable = true"
        )
      else
        null;

    # Systems filter for selective building
    systemsFilter = if cfg.auto.enable then (cfg.auto.systems or null) else null;
  };

  # =============================================================================
  # HOST BUILDING
  # =============================================================================
  # These functions handle the construction of individual host configurations.
  # They bridge the gap between flake-hosts' high-level configuration and
  # the specific system builders (nixosSystem, darwinSystem, etc.) required
  # by each class. This includes setting up standard modules, special arguments,
  # and ensuring consistent behavior across all system types.

  # Selects the appropriate system builder function for a given host class.
  # Each class requires a different builder from its respective input,
  # with nixosSystem as the default fallback for the "nixos" class.
  #
  # Parameters:
  #   class (string): Host class ("nixos", "darwin", "home", "nixOnDroid")
  #   inputs (attrset): Available flake inputs with their lib functions
  #
  # Returns:
  #   function: The appropriate system builder function
  #
  # Builder Mapping:
  #   - "darwin" -> nix-darwin.lib.darwinSystem
  #   - "home" -> home-manager.lib.homeManagerConfiguration
  #   - "nixOnDroid" -> nixOnDroid.lib.nixOnDroidConfiguration
  #   - "nixos" (and fallback) -> nixpkgs.lib.nixosSystem
  #
  # Error Handling:
  #   - Throws descriptive errors if required inputs are missing
  #   - This ensures clear feedback when flake inputs aren't properly configured
  #
  # Note: This function implements the input-less architecture pattern by
  # accepting inputs as parameters rather than accessing them globally.
  #
  # Related Functions:
  #   - mkHost: Uses this function to get the appropriate system builder
  #   - makeStandardModules: Creates compatible modules for the selected builder
  getSystemBuilder =
    class:
    {
      nixpkgs,
      nix-darwin ? null,
      home-manager ? null,
      nixOnDroid ? null,
    }:
    if class == "darwin" then
      nix-darwin.lib.darwinSystem or (throw "nix-darwin input required for darwin hosts")
    else if class == "home" then
      home-manager.lib.homeManagerConfiguration or (throw "home-manager input required for home hosts")
    else if class == "nixOnDroid" then
      nixOnDroid.lib.nixOnDroidConfiguration or (throw "nixOnDroid input required for nixOnDroid hosts")
    else
      nixpkgs.lib.nixosSystem; # Default for "nixos" class

  # Generates the standard modules that all flake-hosts managed systems receive.
  # These modules provide consistent behavior across all host classes and handle
  # the integration between flake-hosts and the underlying system builders.
  #
  # Parameters:
  #   name (string): Host name for networking configuration
  #   class (string): Host class for conditional module inclusion
  #   system (string?): Nix system string (null for classes that don't need it)
  #   nixpkgs (flake): Nixpkgs input for configuration
  #
  # Returns:
  #   list: List of NixOS/Darwin/Home-Manager modules
  #
  # Generated Modules:
  #   1. System-specific args: Provides self'/inputs' from withSystem (if system != null)
  #   2. Hostname: Sets networking.hostName with mkDefault priority
  #   3. Nixpkgs config: Configures hostPlatform and flake source (if system != null)
  #   4. Darwin nixpkgs: Additional Darwin-specific nixpkgs configuration
  #
  # Module Keys:
  #   All modules use "flake-hosts#..." keys to avoid conflicts with user modules.
  #   The _file attribute points to this lib.nix for debugging/tracing.
  #
  # Conditional Logic:
  #   - System-specific features only apply when system != null (excludes home/nixOnDroid)
  #   - Darwin gets additional nixpkgs.source configuration
  makeStandardModules =
    {
      name,
      class,
      system,
      nixpkgs,
    }:
    concatLists [
      # System-specific arguments (only for classes that need system strings)
      # Provides self' and inputs' from withSystem for accessing system-specific outputs
      (optionals (system != null) (singleton {
        key = "flake-hosts#specialArgs";
        _file = "flake-hosts/lib.nix";
        _module.args = withSystem system (
          {
            self',
            inputs',
            ...
          }:
          {
            inherit self' inputs';
          }
        );
      }))

      # Hostname configuration with default priority (can be overridden)
      (singleton {
        key = "flake-hosts#hostname";
        _file = "flake-hosts/lib.nix";
        networking.hostName = mkDefault name;
      })

      # Nixpkgs platform and source configuration (only for system-based classes)
      (optionals (system != null) (singleton {
        key = "flake-hosts#nixpkgs";
        _file = "flake-hosts/lib.nix";
        nixpkgs = {
          hostPlatform = mkDefault system; # Ensures correct platform targeting
          flake.source = nixpkgs.outPath; # Enables flake-aware nixpkgs features
        };
      }))

      # Darwin-specific nixpkgs source configuration
      # nix-darwin requires nixpkgs.source in addition to nixpkgs.flake.source
      (optionals (class == "darwin") (singleton {
        key = "flake-hosts#nixpkgs-darwin";
        _file = "flake-hosts/lib.nix";
        nixpkgs.source = mkDefault nixpkgs;
      }))
    ];

  # Constructs a single host configuration using the appropriate system builder.
  # This is the core function that transforms flake-hosts configuration into
  # the final NixOS/Darwin/Home-Manager system that can be built and deployed.
  #
  # Parameters:
  #   name (string): Host name
  #   class (string): System class ("nixos", "darwin", "home", "nixOnDroid")
  #   system (string?): Nix system string (may be null for some classes)
  #   modules (list): Additional modules to include (default: [])
  #   specialArgs (attrset): Additional special arguments (default: {})
  #   ...args: Other arguments including potential input overrides
  #
  # Returns:
  #   Derivation: Built system configuration ready for deployment
  #
  # Module Assembly Logic:
  #   1. Standard modules: flake-hosts integration modules (hostname, nixpkgs, etc.)
  #   2. User modules: Additional modules specified in configuration
  #
  # Input Resolution:
  #   - Supports host-level input overrides (args.nixpkgs, args.nix-darwin, etc.)
  #   - Falls back to flake inputs with multiple name variations for compatibility
  #   - Throws clear errors for missing required inputs
  #
  # Special Arguments:
  #   - Always includes `inputs` and `self` for module access to flake
  #   - Merges host-specific specialArgs with recursiveUpdate (host takes precedence)
  mkHost =
    {
      name,
      class,
      system,
      modules ? [ ],
      specialArgs ? { },
      ...
    }@args:
    let
      # Get the appropriate system builder for this class
      builder = getSystemBuilder class {
        # Input resolution with multiple fallback names for compatibility
        nixpkgs = args.nixpkgs or inputs.nixpkgs or (throw "nixpkgs input required"); # Required for all classes
        nix-darwin = args.nix-darwin or inputs.nix-darwin or inputs.darwin or null; # darwin/nix-darwin variants
        home-manager = args.home-manager or inputs.home-manager or null; # Optional for home class
        nixOnDroid = args.nixOnDroid or inputs.droid or inputs.nixOnDroid or null; # nixOnDroid/droid variants
      };

      # Assemble all modules in priority order (later modules can override earlier ones)
      allModules = concatLists [
        # Standard flake-hosts integration modules (essential functionality)
        # These provide hostname, nixpkgs config, and system-specific arguments
        (makeStandardModules {
          inherit name class system;
          nixpkgs = args.nixpkgs or inputs.nixpkgs;
        })

        # User-specified additional modules (host-specific and from config layers)
        modules
      ];
    in
    builder {
      # Merge standard special arguments with host-specific ones
      # Standard args (inputs, self) are provided to all modules for flake access
      # Host-specific args take precedence via recursiveUpdate
      specialArgs = recursiveUpdate { inherit inputs self; } specialArgs;
      modules = allModules; # Pass assembled module list to system builder
    };

  # =============================================================================
  # HOST COLLECTION PROCESSING
  # =============================================================================
  # These functions handle the bulk processing of host collections, implementing
  # both explicit host definition (mkHosts) and automatic filesystem discovery (buildHosts).
  # They coordinate the various configuration sources and apply filtering/transformation
  # logic to produce the final host collections ready for system builders.

  # Helper function for merging attribute sets with the same structure.
  # Used to combine multiple host collections (e.g., nixosConfigurations, darwinConfigurations)
  # from different processing phases into a single unified collection.
  #
  # This is equivalent to: foldl' (acc: x: mergeAttrs acc x) {} listOfAttrsets
  # but more efficient for the common case of merging many attribute sets.
  foldAttrsMerge = foldAttrs mergeAttrs { };

  # Filters a host collection to only include hosts matching specified systems.
  # This implements the auto.systems filtering feature that allows users to build
  # only a subset of their configured hosts (e.g., only Linux or only Darwin).
  #
  # Parameters:
  #   systemsFilter (list?): List of system strings to include, or null for no filtering
  #   hosts (attrset): Host configurations to filter
  #
  # Returns:
  #   attrset: Filtered host configurations
  #
  # Filtering Logic:
  #   - If systemsFilter is null, return all hosts unchanged
  #   - For each host, check if its system string is in the systemsFilter list
  #   - Always include hosts with system=null (home/nixOnDroid) regardless of filter
  #
  # Use Cases:
  #   - CI/CD: Build only Linux systems on Linux runners
  #   - Development: Build only local architecture during development
  #   - Deployment: Build specific systems for particular deployment phases
  filterBySystem =
    systemsFilter: hosts:
    if systemsFilter == null then
      hosts # No filtering - include all hosts
    else
      filterAttrs (
        name: hostConfig:
        # Always include hosts without system strings (home-manager, nixOnDroid)
        # These don't have meaningful system strings to filter on
        if hostConfig.system == null then
          true
        # For system-based hosts, check if system is in the allowed list
        else
          elem hostConfig.system systemsFilter # Only include if system matches filter
      ) hosts;

  # Processes explicitly configured hosts from the flake-hosts.hosts configuration.
  # This handles hosts defined directly in the flake configuration rather than
  # discovered from the filesystem, allowing for precise control over host settings.
  #
  # Parameters:
  #   cfg (attrset): Complete flake-hosts configuration from flake-module.nix
  #
  # Returns:
  #   attrset: System configurations grouped by class (nixosConfigurations, etc.)
  #
  # Processing Pipeline:
  #   1. Infer paths and settings from configuration
  #   2. Process each host individually with full configuration merging
  #   3. Filter by system if auto.systems is specified
  #   4. Transform to class-specific configuration collections
  #   5. Merge all collections into final output structure
  #
  # Configuration Sources (in merge priority order):
  #   - hostConfig: The explicit host definition
  #   - classConfig: Result of cfg.perClass.${class} function
  #   - archConfig: Result of cfg.perArch.${arch} function
  #   - sharedConfig: cfg.hosts.default (skipped if host is pure)
  #
  # Special Handling:
  #   - cfg.hosts.default is treated as shared config for explicit hosts
  #   - System/class/arch resolution happens before merging
  #   - Results are grouped by class for proper flake output structure
  mkHosts =
    cfg:
    let
      paths = inferPaths cfg;

      # Process a single explicitly configured host
      processHost =
        name: hostConfig:
        let
          # Extract system configuration (class, arch, system are guaranteed to be present due to defaults)
          class = hostConfig.class;
          arch = hostConfig.arch;

          # Gather configuration sources following easy-hosts pattern
          sharedConfig =
            cfg.hosts.default or {
              modules = [ ];
              specialArgs = { };
            };
          classConfig = cfg.perClass class; # Call function with class parameter
          archConfig = cfg.perArch arch; # Call function with arch parameter

          # Combine all sources like easy-hosts does
          sources = [
            sharedConfig
            hostConfig
            classConfig
            archConfig
          ];

          # Apply pure logic: if host is pure, only use hostConfig
          filteredSources = if hostConfig.pure or false then [ hostConfig ] else sources;

          # Prepare final arguments for mkHost by combining all configuration layers
          hostArgs = hostConfig // {
            inherit name;
            modules = concatLists (map (x: x.modules or [ ]) filteredSources);
            specialArgs = foldl' recursiveUpdate { } (map (x: x.specialArgs or { }) filteredSources);
          };
        in
        {
          # Group by class for proper flake output structure
          # This creates the standard flake outputs: nixosConfigurations, darwinConfigurations, etc.
          "${class}Configurations".${name} = mkHost hostArgs;
        };
      # Pipeline: filter -> process -> merge
      # This transforms the hosts attrset through a series of operations
    in
    pipe cfg.hosts [
      (filterAttrs (name: _: name != "default")) # Remove special shared config entry (not a real host)
      (filterBySystem paths.systemsFilter) # Apply system filtering if specified
      (mapAttrs processHost) # Process each host individually into class collections
      attrValues # Convert attrset to list for folding
      foldAttrsMerge # Merge all class collections into single output
    ];

  # Processes hosts automatically discovered from filesystem structure.
  # This implements the "convention over configuration" approach where hosts
  # are inferred from directory/file structure rather than explicit configuration.
  # Based on easy-hosts pattern but adapted for flake-hosts configuration schema.
  #
  # Parameters:
  #   cfg (attrset): Complete flake-hosts configuration from flake-module.nix
  #
  # Returns:
  #   attrset: Host configurations keyed by hostname, compatible with flake-module.nix hosts schema
  #
  # The result can be merged with explicit hosts and processed by mkHosts.
  buildHosts =
    cfg:
    let
      paths = inferPaths cfg;
      hostsDir = readDir paths.hostsDir;

      # Filter directory entries to only valid host configurations
      validHosts = filterAttrs (
        name: type:
        # Filter out default directory but allow default.nix for shared config
        (type == "regular" && hasSuffix ".nix" name)
        # .nix files are valid
        || (type == "directory" && pathExists "${paths.hostsDir}/${name}/default.nix") # directories with default.nix are valid
      ) hostsDir;

      # Process each discovered host into host configuration
      processHost =
        origName: type:
        let
          # Normalize filesystem names to host names
          hostName =
            if type == "regular" && hasSuffix ".nix" origName then removeSuffix ".nix" origName else origName;

          # Construct full path to host file/directory
          basePath = "${paths.hostsDir}/${origName}";

          # Load and normalize host configuration
          rawConfig = import basePath;
          class = rawConfig.class or "nixos";
          arch = rawConfig.arch or "x86_64";
          system = constructSystem arch class;

          # Create host configuration compatible with flake-module.nix hosts schema
          hostConfig = rawConfig // {
            inherit class arch system;
          };
        in
        {
          name = hostName;
          value = hostConfig;
        };
    in
    # Process all valid hosts (system filtering will be done later in mkHosts)
    mapAttrs' processHost validHosts;
  # =============================================================================
  # PUBLIC API EXPORTS
  # =============================================================================
  # These functions form the public API of the flake-hosts library.
  # They are designed to be called by flake-module.nix to implement
  # the flake-parts integration.
in
{
  # Core system utilities - useful for advanced configurations
  inherit constructSystem;

  # Primary host processing functions - the main library interface
  inherit mkHost mkHosts buildHosts;

  # Note: Internal utilities are intentionally not exported to maintain
  # a clean API and allow for internal refactoring without breaking changes.
}
