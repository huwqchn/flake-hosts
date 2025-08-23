# NixOS host with pure option enabled
{
  class = "nixos";
  arch = "x86_64";
  pure = true;
  modules = [ 
    ({ pkgs, ... }: {
      # Add a marker to verify this configuration is used
      environment.etc."pure-test".text = "This host uses pure configuration";
      # Basic configuration without external dependencies
      system.stateVersion = "25.11";
      boot.loader.grub.device = "/dev/vda";
      fileSystems."/".device = "/dev/vda1";
    })
  ];
}