{ pkgs, config, ... }:
{
  # Darwin-specific test configuration
  _module.args.darwinSpecific = true;
  
  services.nix-daemon.enable = true;
  environment.systemPackages = (config.environment.systemPackages or []) ++ (with pkgs; [ htop ]);
  
  # Required minimal darwin configuration
  system.stateVersion = 4;
}

