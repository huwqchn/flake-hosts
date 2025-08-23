# Test module for explicit host
{ config, pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    git
  ];
}