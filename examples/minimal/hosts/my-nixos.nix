{
  class = "nixos";
  arch = "x86_64";
  modules = [ ({ pkgs, ... }: { environment.systemPackages = with pkgs; [ vim ]; }) ];
}

