# Darwin host defined in directory with default.nix
{
  class = "darwin";
  arch = "aarch64";
  modules = [ ../../modules/darwin-host.nix ];
}