# Default shared configuration for all auto-constructed hosts
{
  # This configuration will be merged into all auto-constructed hosts
  modules = [ ../modules/shared.nix ];
  specialArgs = {
    shared-value = "default-from-hosts-dir";
  };
}