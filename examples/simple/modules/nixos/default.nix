# Common NixOS configuration
{ config, pkgs, ... }:
{
  system.stateVersion = "24.05";
  
  environment.systemPackages = with pkgs; [
    vim
  ];
}