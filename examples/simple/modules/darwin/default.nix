# Common Darwin configuration
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    vim
  ];
  
  services.nix-daemon.enable = true;
}