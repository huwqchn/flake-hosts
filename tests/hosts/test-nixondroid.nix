# Test nix-on-droid host
{
  class = "nixOnDroid";
  arch = "aarch64";
  modules = [
    ({ hostName, ... }: {
      _module.args.hostName = hostName;
      # Basic nix-on-droid config
      user.shell = "${hostName}-shell";
    })
  ];
}