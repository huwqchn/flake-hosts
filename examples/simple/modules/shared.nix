# Shared module for all hosts
{ config, pkgs, ... }:
{
  # Shared configuration
  environment.systemPackages = with pkgs; [
    curl
    wget
  ];
}