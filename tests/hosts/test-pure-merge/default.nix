{
  # This host tests pure=true behavior - should NOT merge with default.nix
  class = "nixos"; 
  arch = "x86_64";
  pure = true;  # This should prevent merging with default.nix
  
  modules = [ 
    ({ pkgs, lib, ... }: { 
      # testShared should NOT be available since pure=true
      # This will cause an evaluation error if default.nix is incorrectly merged
      
      # Since this is pure, we should NOT have access to testShared
      # and shared.nix should NOT be loaded (no vim package)
      environment.systemPackages = with pkgs; [ wget ];
      
      # Required minimal NixOS configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = "test-pure-merge";
      system.stateVersion = "23.11";
    })
  ];
  
  # These specialArgs should be the ONLY ones available (no testShared)
  specialArgs = {
    testPureOnly = "pure-host-value";
  };
}