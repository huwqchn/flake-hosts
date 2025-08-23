# NixOS host defined as a .nix file
{
  class = "nixos";
  arch = "x86_64";
  modules = [ 
    ({ lib, pkgs, ... }: {
      # Basic configuration without external dependencies
      system.stateVersion = lib.mkDefault "25.11";
      boot.loader.grub.device = "/dev/vda";
      fileSystems."/".device = "/dev/vda1";
    })
  ];
}