# Nix-on-Droid-specific modules
{
  # Test nix-on-droid-specific configuration
  _module.args.nixOnDroidSpecific = true;
  
  # Basic nix-on-droid settings
  environment.packages = [ ];
  system.stateVersion = "23.11";
}