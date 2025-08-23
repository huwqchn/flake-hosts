{
  # Shared config merged into all auto-constructed hosts
  modules = [ ../modules/shared.nix ];
  specialArgs.testShared = true;
}

