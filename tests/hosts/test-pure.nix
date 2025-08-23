# Test host with pure = true (no shared config merging)
{
  class = "nixos";
  arch = "x86_64";
  pure = true;
  modules = [
    ({ hostName, pkgs, ... }: {
      # Verify this host doesn't get shared config
      _module.args.isPure = true;
      _module.args.hostName = hostName;
      
      # Required minimal NixOS configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = "test-pure";
      system.stateVersion = "23.11";
      environment.systemPackages = with pkgs; [ vim ];
    })
  ];
}