Minimal example

Usage

- Show: `nix flake show`
- Check: `nix flake check`
- Build (Linux): `nix build .#nixosConfigurations.my-nixos.config.system.build.toplevel`

Layout

- `hosts/my-nixos.nix`: single host, no class modules.
- `flake.nix`: imports this repo's module via `path:../..`.

