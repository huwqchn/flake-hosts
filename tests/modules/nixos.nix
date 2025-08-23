# NixOS-specific modules
{
  # Test nixos-specific configuration
  _module.args.nixosSpecific = true;
  
  # Minimal nixos config to avoid evaluation errors
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  # Test networking
  networking.hostName = "test-nixos-class";
}