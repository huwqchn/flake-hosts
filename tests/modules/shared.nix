{ pkgs, config, ... }:
{
  environment.systemPackages = (config.environment.systemPackages or []) ++ (with pkgs; [ vim ]);
}

