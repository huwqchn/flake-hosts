{
  # Shared config merged into all auto-constructed hosts
  modules = [ ../modules/shared.nix ];
  specialArgs = {
    testShared = true;
    testOverride = "default-value";  # This should be overridden by host-specific configs
    testDefaultOnly = "only-in-default";
  };
}

