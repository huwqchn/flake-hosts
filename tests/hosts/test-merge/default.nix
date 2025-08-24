{
  # This host tests the merge behavior with default config
  class = "nixos";
  arch = "x86_64";
  
  # This should merge with default.nix modules and specialArgs
  modules = [ 
    ({ pkgs, lib, testShared, hostName, ... }: { 
      # Verify that testShared from default.nix is available
      assertions = [
        {
          assertion = testShared == true;
          message = "testShared specialArg from default.nix should be merged";
        }
      ];
      
      environment.systemPackages = (lib.mkAfter (with pkgs; [ curl ]));
      
      # Required minimal NixOS configuration
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      networking.hostName = lib.mkDefault "test-merge";
      system.stateVersion = "23.11";
      
      # Test that both default modules (vim) and host modules (curl) are present  
      # Note: vim comes from shared.nix via default.nix, htop and curl from here
    })
  ];
  
  # Test that specialArgs merge correctly
  specialArgs = {
    testHostSpecific = "host-value";
    # This should NOT override testShared from default.nix due to merge order
  };
}