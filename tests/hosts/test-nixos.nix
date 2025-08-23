{
  class = "nixos";
  arch = "x86_64";
  modules = [ 
    ({ pkgs, hostName, ... }: { 
      environment.systemPackages = with pkgs; [ htop ];
      _module.args.hostName = hostName;
      
      # Required minimal NixOS configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = "test-nixos";
      system.stateVersion = "23.11";
    })
  ];
}

