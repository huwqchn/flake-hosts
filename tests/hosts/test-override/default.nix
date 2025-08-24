{
  # This host tests that host-specific config can override default config
  class = "nixos";
  arch = "x86_64";
  
  modules = [ 
    ({ pkgs, lib, testShared, testOverride, hostName, ... }: { 
      # Verify both default and host-specific specialArgs are available
      assertions = [
        {
          assertion = testShared == true;
          message = "testShared from default.nix should be available";
        }
        {
          assertion = testOverride == "host-wins";
          message = "testOverride should be overridden by host-specific value";
        }
      ];
      
      # Required minimal NixOS configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = "test-override";
      system.stateVersion = "23.11";
      
      # Test package merging - should have both vim (from default) and git (from host)
      environment.systemPackages = with pkgs; [ git ];
    })
  ];
  
  # Test specialArgs override behavior
  specialArgs = {
    testOverride = "host-wins";  # This should override any value from default.nix
    testHostOnly = "only-in-host";
  };
}