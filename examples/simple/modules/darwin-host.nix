# Darwin-specific host module
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    htop
  ];
}