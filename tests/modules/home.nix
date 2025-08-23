# Home Manager-specific modules
{
  # Test home-manager-specific configuration
  _module.args.homeSpecific = true;
  
  # Add some basic home-manager config
  programs.bash.enable = true;
  programs.direnv.enable = true;
}