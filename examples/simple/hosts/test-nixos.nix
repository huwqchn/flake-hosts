# NixOS host defined as a .nix file
{
  class = "nixos";
  arch = "x86_64";
  modules = [ ../modules/nixos-host.nix ];
}