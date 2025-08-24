# flake-hosts

A composable Nix flake library for managing NixOS, nix-darwin, Home Manager, and nix-on-droid system configurations. Inspired by [easy-hosts](https://github.com/tgirlcloud/easy-hosts), flake-hosts provides a clean filesystem-based approach to organizing multiple host configurations with flake-parts integration.

## Features

- **Multi-platform support**: NixOS, macOS (nix-darwin), Home Manager, and Nix-on-Droid
- **Filesystem-based discovery**: Automatically discover hosts from your directory structure
- **Flexible configuration**: Mix auto-discovered and explicitly defined hosts
- **Class-based organization**: Apply configurations per system class (nixos, darwin, etc.)
- **Architecture-specific configs**: Per-architecture configuration support
- **Input-less architecture**: Consumer flakes control their own input versions
- **Flake-parts integration**: Native flake-parts module for easy integration

## Quick Start

### Installation

Add flake-hosts to your flake inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-hosts.url = "github:your-repo/flake-hosts";
  };
}
```

### Basic Usage

```nix
outputs = inputs@{ flake-parts, ... }:
  flake-parts.lib.mkFlake { inherit inputs; } {
    imports = [ inputs.flake-hosts.flakeModule ];

    systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

    flake-hosts = {
      # Automatic host discovery
      auto = {
        enable = true;
        hostsDir = ./hosts;  # Required when auto.enable = true
        systems = [ "x86_64-linux" ];  # Optional: filter systems to build
      };

      # Explicit host definitions
      hosts = {
        # Shared configuration for explicit hosts
        default = {
          modules = [ ./modules/shared.nix ];
        };

        # Individual host
        server = {
          class = "nixos";
          arch = "x86_64";
          modules = [ ./hosts/server/hardware.nix ];
        };
      };

      # Per-class configuration
      perClass = class: {
        modules = [
          "${inputs.self}/modules/${class}/default.nix"
        ];
      };

      # Per-architecture configuration  
      perArch = arch: {
        modules = [
          # Architecture-specific modules
        ];
      };
    };
  };
```

### Try the Examples

```bash
# Show available outputs
nix flake show

# Try the comprehensive example
cd examples/simple && nix flake show

# Try the minimal example
cd examples/minimal && nix flake show

# Validate configurations
nix flake check
```

## Configuration

### Auto Discovery

When `auto.enable = true`, flake-hosts automatically discovers hosts from your filesystem:

```nix
flake-hosts.auto = {
  enable = true;
  hostsDir = ./hosts;          # Required: directory containing host files
  systems = [ "x86_64-linux" ]; # Optional: filter systems to build
};
```

### Filesystem Layout

Organize your hosts using either approach:

```
hosts/
├── default.nix              # Shared config for auto-discovered hosts
├── server.nix              # Host as .nix file (hostname = filename)
├── desktop/                # Host as directory (hostname = directory name)
│   └── default.nix         # Host configuration
└── laptop/
    └── default.nix
```

**Important**: Only directories containing `default.nix` are treated as valid hosts. Directories without `default.nix` are ignored.

### Host Configuration Structure

Each host file should export a configuration:

```nix
# hosts/server.nix
{
  class = "nixos";      # System class
  arch = "x86_64";      # Architecture
  pure = false;         # Whether to skip shared config merging
  modules = [           # Host-specific modules
    ./server-hardware.nix
    ./server-services.nix
  ];
  specialArgs = {       # Special arguments passed to modules
    hostName = "server";
  };
}
```

### Class-Based Configuration

Use `perClass` to apply configuration based on system class:

```nix
perClass = class: {
  modules = [
    # Load class-specific modules
    "${inputs.self}/modules/${class}/default.nix"
  ];
  specialArgs = {
    isNixOS = class == "nixos";
  };
};
```

Create class-specific modules:

```
modules/
├── nixos/
│   └── default.nix          # NixOS-specific configuration
├── darwin/
│   └── default.nix          # macOS-specific configuration
├── home/
│   └── default.nix          # Home Manager configuration
└── nixOnDroid/
    └── default.nix          # Nix-on-Droid configuration
```

### Architecture-Based Configuration

Use `perArch` for architecture-specific configuration:

```nix
perArch = arch: {
  modules = 
    if arch == "x86_64" then [ ./modules/x86_64.nix ]
    else if arch == "aarch64" then [ ./modules/aarch64.nix ]
    else [];
};
```

## Configuration Options Reference

### Auto Discovery Options

- `auto.enable` (boolean, default: false): Enable automatic host discovery
- `auto.hostsDir` (path, required when auto.enable = true): Directory containing host configurations
- `auto.systems` (list of strings, optional): Filter to only build specified systems

### Host Definition Options

- `hosts` (attrset): Explicitly defined host configurations
- `hosts.default` (attrset): Shared configuration for explicit hosts

### Per-Category Configuration

- `perClass` (function): Function taking class name, returning configuration for that class
- `perArch` (function): Function taking architecture, returning configuration for that arch

### Host-Specific Options

Each host can specify:

- `class` (enum): System class - "nixos", "darwin", "home", or "nixOnDroid"
- `arch` (string): Architecture - "x86_64", "aarch64", "armv6l", "armv7l", "i686", etc.
- `system` (string, internal): Full system string, automatically computed
- `pure` (boolean, default: false): Skip shared configuration merging
- `deployable` (boolean, default: false): Mark host as deployable
- `modules` (list): NixOS/Darwin/Home Manager modules
- `specialArgs` (attrset): Special arguments passed to modules

### Input Overrides

Per-host input overrides:

- `nixpkgs`: Override nixpkgs input for this host
- `nix-darwin`: Override nix-darwin input for darwin hosts
- `home-manager`: Override home-manager input for home hosts
- `nixOnDroid`: Override nixOnDroid input for nix-on-droid hosts

## System Classes

flake-hosts supports four system classes:

| Class        | Builder                                    | Output Collection        |
|------------- |------------------------------------------- |------------------------- |
| `nixos`      | `nixpkgs.lib.nixosSystem`                 | `nixosConfigurations`    |
| `darwin`     | `nix-darwin.lib.darwinSystem`             | `darwinConfigurations`   |
| `home`       | `home-manager.lib.homeManagerConfiguration` | `homeConfigurations`    |
| `nixOnDroid` | `nixOnDroid.lib.nixOnDroidConfiguration`   | `nixOnDroidConfigurations` |

## Examples

### Minimal Setup

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-hosts.url = "github:your-repo/flake-hosts";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.flake-hosts.flakeModule ];
      systems = [ "x86_64-linux" ];

      flake-hosts.auto = {
        enable = true;
        hostsDir = ./hosts;
      };
    };
}
```

```nix
# hosts/server.nix
{
  class = "nixos";
  arch = "x86_64";
  modules = [
    ({ config, pkgs, ... }: {
      system.stateVersion = "24.05";
      environment.systemPackages = [ pkgs.vim ];
    })
  ];
}
```

### Advanced Setup with Class Modules

```nix
# flake.nix
flake-hosts = {
  auto = {
    enable = true;
    hostsDir = ./hosts;
    systems = [ "x86_64-linux" "aarch64-darwin" ];
  };

  hosts = {
    default.modules = [ ./modules/shared.nix ];
  };

  perClass = class: {
    modules = [ "${inputs.self}/modules/${class}/default.nix" ];
  };

  perArch = arch: {
    modules = lib.optionals (arch == "aarch64") [ ./modules/apple-silicon.nix ];
  };
};
```

```nix
# modules/nixos/default.nix
{ config, pkgs, ... }: {
  system.stateVersion = "24.05";
  
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];
  
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };
}
```

```nix
# modules/darwin/default.nix
{ config, pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
  ];
  
  services.nix-daemon.enable = true;
  
  homebrew = {
    enable = true;
    brews = [ "curl" "wget" ];
  };
}
```

## Building and Deployment

### Building Configurations

```bash
# Build a NixOS system
nix build .#nixosConfigurations.server.config.system.build.toplevel

# Build a Darwin system  
nix build .#darwinConfigurations.macbook.system

# Build a Home Manager configuration
nix build .#homeConfigurations.user.activationPackage
```

### Using with NixOS Rebuild

```bash
# Switch to configuration
sudo nixos-rebuild switch --flake .#server

# Test configuration
sudo nixos-rebuild test --flake .#server
```

### Using with Darwin Rebuild

```bash
# Switch to configuration
darwin-rebuild switch --flake .#macbook
```

## Best Practices

### Organization

1. **Separate concerns**: Keep hardware, software, and user configurations in separate modules
2. **Use shared modules**: Extract common configuration into shared modules
3. **Leverage class modules**: Use `perClass` for system-type-specific configuration
4. **Keep hosts minimal**: Host files should primarily import and compose modules

### Security

1. **Never commit secrets**: Use tools like sops-nix or agenix for secrets management
2. **Validate paths**: Don't use `${inputs.self}` paths in `auto.hostsDir` (causes infinite recursion)
3. **Review configurations**: Use `nix flake check` to validate configurations

### Performance

1. **Filter systems**: Use `auto.systems` to build only needed configurations
2. **Use pure hosts**: Set `pure = true` for hosts that don't need shared configuration
3. **Optimize imports**: Import only necessary modules per host

## Troubleshooting

### Common Issues

**Error: "flake-hosts.auto.hostsDir is required when auto.enable = true"**
- Solution: Set `auto.hostsDir = ./hosts;` when using auto-discovery

**Error: "Cannot reference the flake itself"**
- Problem: Using `${inputs.self}/path` in `auto.hostsDir`
- Solution: Use relative paths like `./hosts` instead

**Host not discovered**
- Check: Directory must contain `default.nix` file
- Check: Directory name matches expected hostname
- Check: File is not in reserved names (`default`, `default.nix`)

**Module evaluation errors**
- Check: All imported modules exist and are valid
- Check: Class modules exist for all used classes
- Use: `nix flake check` to validate configuration

### Debugging

```bash
# Show discovered hosts
nix flake show

# Check for evaluation errors  
nix flake check

# Evaluate specific configuration
nix eval .#nixosConfigurations.hostname.config.system.name

# Show derivation details
nix show-derivation .#nixosConfigurations.hostname.config.system.build.toplevel
```

## Migration Guide

### From auto.modulesDir to perClass

**Old approach:**
```nix
flake-hosts.auto = {
  enable = true;
  hostsDir = ./hosts;
  modulesDir = ./modules;  # Removed
};
```

**New approach:**
```nix
flake-hosts = {
  auto = {
    enable = true;
    hostsDir = ./hosts;
  };
  
  perClass = class: {
    modules = [ "${inputs.self}/modules/${class}/default.nix" ];
  };
};
```

## Related Projects

- [tgirlcloud/easy-hosts](https://github.com/tgirlcloud/easy-hosts) - Original inspiration
- [ehllie/ez-configs](https://github.com/ehllie/ez-configs) - Similar approach
- [hercules-ci/flake-parts](https://github.com/hercules-ci/flake-parts) - Flake composition framework

## Contributing

Contributions are welcome! Please:

1. Check existing issues and PRs
2. Follow the existing code style
3. Add tests for new features
4. Update documentation as needed

## License

This project is licensed under the MIT License - see the LICENSE file for details.