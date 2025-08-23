# flake-hosts

A small, composable library to manage NixOS, nix-darwin, Home Manager, and nix-on-droid hosts with a clean filesystem layout. Inspired by easy-hosts, with a few quality-of-life defaults and a flake-parts interface.

## Quick Start

- Inspect module: `nix flake show`
- Try the example: `cd examples/simple && nix flake show`
- Validate options: `cd examples/simple && nix flake check`

Initialize a new repo using examples:

- Copy `examples/simple/` for a full-featured setup with hosts and modules
- Copy `examples/minimal/` for a basic single-host configuration

## Usage (flake-parts)

Add this to your flake and import the module:

```
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.flake-hosts.flakeModule ];

    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

    flake-hosts = {
      # explicit hosts
      hosts = {
        default.modules = [ ./modules/shared.nix ];

        my-explicit = {
          class = "nixos";
          arch = "x86_64";
          pure = true; # skip shared merges
          modules = [ ./modules/my.nix ];
        };
      };
    };
  };
```

## Auto Defaults

When `auto.enable = true` and a path is not explicitly set:

- hostsDir: first existing of `./hosts`, `./systems`. If neither exists, evaluation fails with a helpful message.
- modulesDir: first existing of `./modules`, `./module`, `./classes`, `./class`. If none exist, no class modules are loaded.
- systems: defaults to `null` (no filter). If set, only hosts whose `system` matches are built.

## Filesystem Layout

- Hosts live under `hostsDir` as either:
  - `hosts/<name>.nix`, or
  - `hosts/<name>/default.nix`
- Shared auto config: `hosts/default.nix` (merged into all auto hosts unless `pure = true`).
- Class modules live under `modulesDir` as either:
  - `modules/<class>.nix`, or
  - `modules/<class>/default.nix`

Supported classes: `nixos`, `darwin`, `home`, `nixOnDroid`.

## Option Surface (high level)

- `flake-hosts.auto.enable`: turn on auto discovery.
- `flake-hosts.auto.hostsDir`: override hosts directory; default as above.
- `flake-hosts.auto.modulesDir`: override class modules directory; default as above.
- `flake-hosts.auto.systems`: list of systems to include (e.g., `x86_64-linux`, `aarch64-darwin`).
- `flake-hosts.hosts`: explicit host definitions. Special `hosts.default` provides shared config for explicit hosts.

Per-host keys:

- `class`: one of `nixos` | `darwin` | `home` | `nixOnDroid`.
- `arch`: e.g., `x86_64`, `aarch64`.
- `system`: internal; derived from `(arch, class)` for nixos/darwin; `null` for home/nixOnDroid.
- `path`: optional module root/file; generally not needed with auto.
- `pure`: if true, do not merge shared auto config.
- `modules`, `specialArgs`: merged from class/arch/shared and the host (host wins on conflicts).
- Optional input overrides: `nixpkgs`, `nix-darwin`, `home-manager`, `nixOnDroid`.

## Commands

- Show module: `nix flake show`
- Run checks: `nix flake check`
- Example builds (from `examples/simple`):
  - `nix build .#nixosConfigurations.test-nixos.config.system.build.toplevel`
  - `nix build .#darwinConfigurations.test-darwin.system`

## Examples

- `examples/simple`: recommended layout with `hosts/` and `modules/`.
- `examples/minimal`: single host, no class modules.

Try:

- `cd examples/simple && nix flake show` then `nix flake check`
- `cd examples/minimal && nix flake show` then `nix flake check`

## Tests

The `tests/` directory contains comprehensive test cases covering:

- Auto host discovery with all system classes (nixos, darwin, home, nixOnDroid)
- Mixed auto/explicit host configurations
- System filtering functionality
- Pure hosts (no shared config merging)
- Class-specific module loading

### Running Tests

```bash
# Basic test suite
cd tests
nix flake show              # Should show discovered configurations
nix flake check             # May show warnings for test configs (expected)
```

See `tests/README.md` for detailed test documentation.

## Related Projects

- [ehllie/ez-configs](https://github.com/ehllie/ez-configs/tree/main)
- [tgirlcloud/easy-hosts](https://github.com/tgirlcloud/easy-hosts/tree/main)

## Notes

- Inspired by easy-hosts; behavior aligns with its simplicity goals while keeping flake-parts ergonomics.
- Keep your configuration pure when needed via `pure = true` on a host.
- Prefer small, composable modules; use `specialArgs` for values that do not need to resolve module structure.

## Migration Notes

### Templates Removal

Templates are no longer provided. Use `examples/` directory as starting points:

- Copy `examples/simple/` for full-featured setups
- Copy `examples/minimal/` for basic configurations
- Previous `nix flake init -t ...` workflows should use direct copying

### Auto Defaults

- `hostsDir` and `modulesDir` now auto-infer when `auto.enable = true`
- Explicit values still take precedence
- See Auto Defaults section for discovery logic

### Other Changes

- `getEffectiveConfig`: removed; logic inlined with simpler defaults
- Class modules: support both `modules/<class>.nix` and `modules/<class>/default.nix` formats
