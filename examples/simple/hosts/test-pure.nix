# NixOS host with pure option enabled
{
  class = "nixos";
  arch = "x86_64";
  pure = true;
  modules = [ 
    ../modules/nixos-host.nix 
    ({ pkgs, ... }: {
      # Add a marker to verify this configuration is used
      environment.etc."pure-test".text = "This host uses pure configuration";
    })
  ];
}