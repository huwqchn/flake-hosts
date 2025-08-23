{
  inputs = { };

  outputs =
    { self }:
    {
      flakeModule = import ./flake-module.nix { flake-hosts = self; };
      flakeModules.default = import ./flake-module.nix { flake-hosts = self; };

      # Templates for easy project initialization
      templates = {
        minimal = {
          path = ./examples/minimal;
          description = "Minimal flake-hosts example with basic auto-discovery";
          welcomeText = ''
            # Minimal flake-hosts template
            
            This template provides a minimal setup for flake-hosts with:
            - Auto-discovery of hosts from ./hosts directory
            - Basic NixOS configuration example
            
            Get started by:
            1. Review and modify ./hosts/my-nixos.nix
            2. Run `nix flake check` to validate configuration
            3. Build with `nixos-rebuild switch --flake .#my-nixos`
          '';
        };
        
        simple = {
          path = ./examples/simple;
          description = "Complete flake-hosts example with advanced features";
          welcomeText = ''
            # Complete flake-hosts template
            
            This template demonstrates advanced flake-hosts features:
            - Auto-discovery with class-specific modules
            - Mixed auto and explicit host configurations
            - Per-class and per-architecture settings
            - Pure host configurations
            - Multiple system types (NixOS, Darwin)
            
            Get started by:
            1. Explore ./hosts/ for host configurations
            2. Check ./modules/ for class-specific modules
            3. Review flake.nix for configuration options
            4. Run `nix flake check` to validate
            5. Build any host with `nixos-rebuild switch --flake .#hostname`
          '';
        };
        
        default = {
          path = ./examples/simple;
          description = "Default flake-hosts template (same as simple)";
        };
      };
    };
}
