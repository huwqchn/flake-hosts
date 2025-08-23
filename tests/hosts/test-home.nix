# Test home-manager host
{
  class = "home";
  arch = "x86_64";
  modules = [
    ({ hostName, ... }: {
      _module.args.hostName = hostName;
      home.username = "testuser";
      home.homeDirectory = "/home/testuser";
      home.stateVersion = "23.11";
    })
  ];
}