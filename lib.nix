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
}: let
  inherit (inputs) self;
    inherit (builtins) readDir map foldl' elem;
  inherit
    (lib)
    filter
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
    head
    mapAttrs'
    hasSuffix
    removeSuffix
    nameValuePair
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
  constructSystem = arch: class:
    if class == "darwin"
    then "${arch}-darwin"
    else if class == "nixos"
    then "${arch}-linux"
    else null; # home and nixOnDroid don't need system strings for their builders

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

  # Finds the first existing path from a list of candidates.
  # Used for fallback path resolution when multiple standard locations
  # might contain the desired files (e.g., "./hosts" vs "./systems").
  #
  # Parameters:
  #   candidates (list of strings): Paths to check in order of preference
  #
  # Returns:
  #   string?: First existing path, or null if none exist
  #
  # Example:
  #   findFirstPath [ "./hosts" "./systems" ] => "./hosts" (if it exists first)
    findFirstPath = candidates: let
    existing = filter pathExists candidates;
  in
    if existing == []
    then null
    else head existing;

  # Infers standard filesystem paths from configuration with intelligent fallbacks.
  # This implements the "convention over configuration" approach - if paths aren't
  # explicitly specified, it searches for them in standard locations.
  #
  # Parameters:
  #   cfg (attrset): The flake-hosts configuration from flake-module.nix
  #
  # Returns:
  #   { hostsDir: string?, modulesDir: string?, systemsFilter: list? }: Resolved paths
  #
  # Path Resolution Logic:
  #   - hostsDir: Explicit cfg.auto.hostsDir, or first of ["./hosts", "./systems"]
  #   - modulesDir: Explicit cfg.auto.modulesDir, or first of ["./modules", "./module", "./classes", "./class"]
  #   - systemsFilter: Copy of cfg.auto.systems for filtering built hosts
  #
  # Error Handling:
  #   - hostsDir is required when auto.enable=true, throws error if not found
  #   - modulesDir is optional, returns null if not found (disables class modules)
  #   - All paths return null when auto.enable=false
  #
  # This function bridges the gap between user configuration and internal path handling.
  inferPaths = cfg: {
    # Hosts directory is required for auto-discovery
    hostsDir =
      if cfg.auto.enable
      then
        (cfg.auto.hostsDir or (
          let
            found = findFirstPath ["./hosts" "./systems"];
          in
            if found != null
            then found
            else throw "auto: no hosts directory found; set flake-hosts.auto.hostsDir or create ./hosts or ./systems"
        ))
      else null;

    # Modules directory is optional - null disables class-specific module loading
    modulesDir =
      if cfg.auto.enable
      then (cfg.auto.modulesDir or (findFirstPath ["./modules" "./module" "./classes" "./class"]))
      else null;

    # Systems filter for selective building
    systemsFilter =
      if cfg.auto.enable
      then (cfg.auto.systems or null)
      else null;
  };

  # =============================================================================
  # MODULE LOADING
  # =============================================================================
  # These functions handle the discovery and loading of Nix modules from the filesystem.
  # They implement the class-specific module system that automatically loads
  # appropriate modules based on the host's class (nixos, darwin, home, nixOnDroid).
  # This reduces boilerplate by eliminating the need for manual perClass configuration.

  # Loads class-specific modules from the modulesDir directory.
  # This implements automatic module loading based on the host's class,
  # eliminating the need for manual perClass configuration in most cases.
  #
  # Parameters:
  #   modulesDir (string?): Base directory containing class-specific modules
  #   class (string): Host class ("nixos", "darwin", "home", "nixOnDroid")
  #
  # Returns:
  #   { modules: list, specialArgs: attrset }: Module configuration for this class
  #
  # Discovery Logic:
  #   1. If modulesDir is null, return empty configuration (class modules disabled)
  #   2. Look for "${modulesDir}/${class}.nix" first (e.g., "./modules/nixos.nix")
  #   3. Fall back to "${modulesDir}/${class}" directory (e.g., "./modules/nixos/default.nix")
  #   4. If neither exists, return empty configuration (no class modules for this class)
  #
  # This function is called by mergeHostSources for every host to automatically
  # include class-appropriate modules without explicit configuration.
  #
  # Examples:
  #   - nixos host gets modules from "./modules/nixos.nix" or "./modules/nixos/"
  #   - darwin host gets modules from "./modules/darwin.nix" or "./modules/darwin/"
  #
  # Related Functions:
  #   - mergeHostSources: Calls this function to gather class-specific configuration
  #   - inferPaths: Determines the modulesDir directory from configuration
  loadClassModules = modulesDir: class: let
    resolved =
      if modulesDir == null
      then null
      else
        (
          let
            # Try .nix file first (e.g., "./modules/nixos.nix")
            # This pattern allows simpler organization for small class modules
            nixFile = "${modulesDir}/${class}.nix";
            # Fall back to directory (e.g., "./modules/nixos/default.nix")
            # This pattern supports complex class modules with multiple files
            nixDir = "${modulesDir}/${class}";
          in
            if pathExists nixFile
            then nixFile
            else if pathExists nixDir
            then nixDir
            else null # No class modules found
        );
  in {
    modules = optionals (resolved != null) [resolved];
    specialArgs = {}; # Could be extended in future for class-specific args
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
  getSystemBuilder = class: {
    nixpkgs,
    nix-darwin ? null,
    home-manager ? null,
    nixOnDroid ? null,
  }:
    if class == "darwin"
    then nix-darwin.lib.darwinSystem or (throw "nix-darwin input required for darwin hosts")
    else if class == "home"
    then home-manager.lib.homeManagerConfiguration or (throw "home-manager input required for home hosts")
    else if class == "nixOnDroid"
    then nixOnDroid.lib.nixOnDroidConfiguration or (throw "nixOnDroid input required for nixOnDroid hosts")
    else nixpkgs.lib.nixosSystem; # Default for "nixos" class

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
  makeStandardModules = {
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
        _file = "${__curPos.file}/lib.nix";
        _module.args = withSystem system ({
          self',
          inputs',
          ...
        }: {inherit self' inputs';});
      }))

      # Hostname configuration with default priority (can be overridden)
      (singleton {
        key = "flake-hosts#hostname";
        _file = "${__curPos.file}/lib.nix";
        networking.hostName = mkDefault name;
      })

      # Nixpkgs platform and source configuration (only for system-based classes)
      (optionals (system != null) (singleton {
        key = "flake-hosts#nixpkgs";
        _file = "${__curPos.file}/lib.nix";
        nixpkgs = {
          hostPlatform = mkDefault system; # Ensures correct platform targeting
          flake.source = nixpkgs.outPath; # Enables flake-aware nixpkgs features
        };
      }))

      # Darwin-specific nixpkgs source configuration
      # nix-darwin requires nixpkgs.source in addition to nixpkgs.flake.source
      (optionals (class == "darwin") (singleton {
        key = "flake-hosts#nixpkgs-darwin";
        _file = "${__curPos.file}/lib.nix";
        nixpkgs.source = mkDefault nixpkgs;
      }))
    ];

  # Constructs a single host configuration using the appropriate system builder.
  # This is the core function that transforms flake-hosts configuration into
  # the final NixOS/Darwin/Home-Manager system that can be built and deployed.
  #
  # Parameters:
  #   name (string): Host name
  #   path (string?): Path to host's main configuration file
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
  #   1. Host path modules: The host's main configuration file (if specified)
  #   2. Legacy path fallbacks: Check old standard locations for compatibility
  #   3. Standard modules: flake-hosts integration modules (hostname, nixpkgs, etc.)
  #   4. User modules: Additional modules specified in configuration
  #
  # Input Resolution:
  #   - Supports host-level input overrides (args.nixpkgs, args.nix-darwin, etc.)
  #   - Falls back to flake inputs with multiple name variations for compatibility
  #   - Throws clear errors for missing required inputs
  #
  # Special Arguments:
  #   - Always includes `inputs` and `self` for module access to flake
  #   - Merges host-specific specialArgs with recursiveUpdate (host takes precedence)
  mkHost = {
    name,
    class,
    system,
    modules ? [],
    specialArgs ? {},
    ...
  } @ args: let
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
      # Legacy path fallbacks for compatibility with existing projects
      # These are filtered to only include paths that actually exist on the filesystem
      (filter pathExists [
        "${self}/hosts/${name}/default.nix" # Traditional hosts/ directory structure
        "${self}/systems/${name}/default.nix" # Alternative systems/ directory structure
      ])

      # Standard flake-hosts integration modules (essential functionality)
      # These provide hostname, nixpkgs config, and system-specific arguments
      (makeStandardModules {
        inherit name class system;
        nixpkgs = args.nixpkgs or inputs.nixpkgs;
      })

      # User-specified additional modules (lowest priority, can be overridden by host config)
      modules
    ];
  in
    builder {
      # Merge standard special arguments with host-specific ones
      # Standard args (inputs, self) are provided to all modules for flake access
      # Host-specific args take precedence via recursiveUpdate
      specialArgs = recursiveUpdate {inherit inputs self;} specialArgs;
      modules = allModules; # Pass assembled module list to system builder
    };

  # =============================================================================
  # HOST CONFIGURATION MERGING
  # =============================================================================
  # These functions handle the complex logic of merging multiple configuration sources
  # for each host. This includes shared configuration, class-specific modules,
  # architecture-specific configuration, and automatic class modules.
  # The merging respects the "pure" flag to allow hosts to opt out of shared configuration.

  # Merges multiple configuration sources for a single host into a unified configuration.
  # This implements the layered configuration system that allows flexible host specification
  # while maintaining consistent behavior across similar hosts.
  #
  # Parameters:
  #   hostConfig (attrset): Host-specific configuration (highest priority)
  #   sharedConfig (attrset): Shared configuration for all hosts (conditional)
  #   classConfig (attrset): Class-specific configuration (perClass function result)
  #   archConfig (attrset): Architecture-specific configuration (perArch function result)
  #   classModules (attrset): Auto-loaded class modules from filesystem
  #
  # Returns:
  #   { modules: list, specialArgs: attrset }: Merged configuration
  #
  # Merging Logic:
  #   1. Always include: hostConfig, classConfig, archConfig, classModules
  #   2. Conditionally include sharedConfig (skipped if hostConfig.pure = true)
  #   3. Modules are concatenated (later sources can override earlier ones)
  #   4. SpecialArgs are deeply merged with recursiveUpdate (later takes precedence)
  #
  # Pure Hosts:
  #   Hosts with `pure = true` skip shared configuration, allowing them to have
  #   completely independent configuration. This is useful for special-purpose
  #   hosts that shouldn't inherit common settings.
  #
  # This function is central to flake-hosts' configuration system, as it implements
  # the "convention over configuration" approach while still allowing full customization.
  mergeHostSources = {
    hostConfig,
    sharedConfig,
    classConfig,
    archConfig,
    classModules,
  }: let
    # Determine which sources to include based on pure flag
    # Pure hosts opt out of shared configuration for complete independence
    sources =
      [hostConfig]
      ++ optionals (!(hostConfig.pure or false)) [classConfig archConfig classModules sharedConfig]; # Conditionally include shared

        # Combine modules from all sources (concatenation allows later modules to override earlier ones)
    combine = attr: concatLists (map (x: x.${attr} or []) sources);

    # Deeply merge special arguments (later sources take precedence via recursiveUpdate)
    combineSpecialArgs = foldl' recursiveUpdate {} (map (x: x.specialArgs or {}) sources);
  in {
    modules = combine "modules";
    specialArgs = combineSpecialArgs;
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
  foldAttrsMerge = foldAttrs mergeAttrs {};

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
  filterBySystem = systemsFilter: hosts:
    if systemsFilter == null
    then hosts # No filtering - include all hosts
    else
      filterAttrs (
        name: hostConfig:
        # Always include hosts without system strings (home-manager, nixOnDroid)
        # These don't have meaningful system strings to filter on
          if hostConfig.system == null
          then true
          # For system-based hosts, check if system is in the allowed list
          else elem hostConfig.system systemsFilter # Only include if system matches filter
      )
      hosts;

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
  #   - classModules: Auto-loaded modules from modulesDir
  #   - sharedConfig: cfg.hosts.default (skipped if host is pure)
  #
  # Special Handling:
  #   - cfg.hosts.default is treated as shared config for explicit hosts
  #   - System/class/arch resolution happens before merging
  #   - Results are grouped by class for proper flake output structure
  mkHosts = cfg: let
    paths = inferPaths cfg;

    # Process a single explicitly configured host
    processHost = name: hostConfig: let
      # Extract system configuration (class, arch, system are guaranteed to be present due to defaults)
      class = hostConfig.class;
      arch = hostConfig.arch;

      # Gather configuration sources for merging (each provides modules and specialArgs)
      explicitSharedConfig =
        cfg.hosts.default or {
          modules = [];
          specialArgs = {};
        }; # Shared config for explicit hosts
      classConfig =
        cfg.perClass.${
          class
        } or {
          modules = [];
          specialArgs = {};
        }; # Per-class configuration function result
      archConfig =
        cfg.perArch.${
          arch
        } or {
          modules = [];
          specialArgs = {};
        }; # Per-architecture configuration function result
      classModules = loadClassModules paths.modulesDir class; # Auto-loaded class-specific modules

      # Merge all configuration sources using standard logic
      merged = mergeHostSources {
        inherit classConfig archConfig classModules;
        hostConfig = hostConfig;
        sharedConfig = explicitSharedConfig;
      };

      # Prepare final arguments for mkHost by combining all configuration layers
      hostArgs = hostConfig // {inherit name;} // merged;
    in {
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
  #
  # Parameters:
  #   cfg (attrset): Complete flake-hosts configuration from flake-module.nix
  #
  # Returns:
  #   attrset: Host configurations keyed by hostname, ready for further processing
  #
  # Discovery Logic:
  #   1. Read the hostsDir directory to find potential host files/directories
  #   2. Filter to valid entries (exclude special files, include .nix files and directories)
  #   3. Normalize names ("host.nix" -> "host", "host/" -> "host")
  #   4. Load configuration from each discovered path
  #   5. Apply system filtering if specified
  #
  # Supported Host Patterns:
  #   - "hostname.nix": Single file host configuration
  #   - "hostname/default.nix": Directory-based host configuration
  #   - Mixed: Some hosts as files, others as directories
  #
  # Exclusions:
  #   - "default" and "default.nix": Reserved for shared configuration
  #   - Non-.nix regular files: Not importable as Nix modules
  #
  # The result is a flat collection of host configurations that can be further
  # processed by mkHosts or used directly for building systems.
  buildHosts = cfg: let
    paths = inferPaths cfg;
    hostsDir = readDir paths.hostsDir;

    # Filter directory entries to only valid host configurations
    # Excludes special files and unsupported formats to prevent import errors
    validHosts =
      filterAttrs (
        name: type:
          name
          != "default"
          && name != "default.nix"
          && # Reserved for shared config (not hosts)
          (type
            == "directory"
            || # Directory with default.nix (host as directory)
            (type == "regular" && hasSuffix ".nix" name)) # .nix file (host as single file)
      )
      hostsDir;
    # Processing pipeline: normalize -> load
    # This transforms the filesystem structure into host configurations
  in
    pipe validHosts [
      # First pass: normalize filesystem names to host names
      (mapAttrs (origName: type: let
        # Strip .nix extension for regular files to get clean hostname
        # "server.nix" -> "server", "server/" -> "server"
        hostName =
          if type == "regular" && hasSuffix ".nix" origName
          then removeSuffix ".nix" origName
          else origName;
      in {
        inherit type;
        hostName = hostName;
        origName = origName;
      }))

      # Second pass: load configuration from filesystem paths
      (mapAttrs' (origName: info: let
        basePath = "${paths.hostsDir}/${info.origName}"; # Full path to host file/directory
        hostConfig = import basePath; # Handles path resolution and config loading
      in
        nameValuePair info.hostName hostConfig)) # Key by clean hostname
    ];
  # =============================================================================
  # PUBLIC API EXPORTS
  # =============================================================================
  # These functions form the public API of the flake-hosts library.
  # They are designed to be called by flake-module.nix to implement
  # the flake-parts integration.
in {
  # Core system utilities - useful for advanced configurations
  inherit constructSystem;

  # Primary host processing functions - the main library interface
  inherit mkHost mkHosts buildHosts;

  # Note: Internal utilities (loadHostConfig, etc.) are intentionally not
  # exported to maintain a clean API and allow for internal refactoring
  # without breaking changes.
}
