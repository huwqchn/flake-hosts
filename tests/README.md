# flake-hosts Tests

Manual test harness to validate flake-hosts functionality across different scenarios.

## Test Goals

- Exercise auto discovery with hosts and class modules
- Test all supported system classes (nixos, darwin, home, nixOnDroid)
- Validate both file and directory host forms
- Test pure hosts (no shared config merging)
- Test mixed auto/explicit host configurations
- Test system filtering functionality
- Ensure class-specific modules are properly loaded

## Test Structure

### Basic Tests (`flake.nix`)
- **test-nixos**: NixOS host as `.nix` file
- **test-darwin**: Darwin host as directory with `default.nix`
- **test-pure**: Pure NixOS host (no shared config)
- **test-home**: Home Manager configuration
- **test-nixondroid**: Nix-on-Droid configuration

### Basic Configuration Tests
- Auto discovery of hosts from filesystem
- Multiple system classes with different architectures  
- Pure hosts without shared configuration merging

### Module Structure
- `modules/shared.nix`: Shared across all hosts
- `modules/darwin.nix`: Darwin-specific modules (auto-loaded)
- `modules/nixos.nix`: NixOS-specific modules (auto-loaded)
- `modules/home.nix`: Home Manager-specific modules (auto-loaded)
- `modules/nixOnDroid.nix`: Nix-on-Droid-specific modules (auto-loaded)

## Running Tests

### Basic Test Suite
```bash
cd tests
nix flake show              # Should show all configurations
nix flake check             # May show errors for incomplete system configs (expected)
```


### Optional Test Builds
```bash
# Note: These builds may fail due to incomplete system configurations
# The tests are focused on evaluation correctness, not buildability

# NixOS configurations (require complete hardware config)
nix build .#nixosConfigurations.test-nixos.config.system.build.toplevel
nix build .#nixosConfigurations.test-pure.config.system.build.toplevel

# Darwin configurations (on Darwin systems)
nix build .#darwinConfigurations.test-darwin.system

# Home Manager configurations (require complete user config)
nix build .#homeConfigurations.test-home.activationPackage
```

## Test Coverage

- ✅ Auto host discovery from filesystem
- ✅ Directory and file host forms
- ✅ All system classes (nixos, darwin, home, nixOnDroid)
- ✅ Class-specific module loading
- ✅ Shared configuration merging
- ✅ Pure hosts (no shared merging)
- ✅ Mixed auto/explicit hosts
- ✅ System filtering
- ✅ Special arguments passing

## Notes

- Tests reference the library via `path:..` so local changes are picked up immediately
- Network access required to fetch `nixpkgs` and other inputs
- Some builds may require appropriate system types (Darwin builds on Darwin, etc.)
- All tests focus on evaluation correctness rather than runtime functionality

