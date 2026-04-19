{ config, lib, pkgs, inputs ? null, ... }:
let
  cfg = config.programs.agent-resources;
  nix-skills-lib = import ./lib { inherit lib; };
in {
  options.programs.agent-resources = {
    enable = lib.mkEnableOption "Agent resources generation";
    
    agents = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "List of agent packages to install.";
    };
    
    skills = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "List of skill packages to install.";
    };
    
    commands = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "List of command packages to install.";
    };
    
    hooks = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "List of hook packages to install.";
    };
    
    sources = {
      agents = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of GitHub URLs to resolve as agent sources.";
      };
      
      skills = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of GitHub URLs to resolve as skill sources.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = nix-skills-lib.mkEnvironment pkgs {
      inherit inputs;
      agents = cfg.agents ++ cfg.sources.agents;
      skills = cfg.skills ++ cfg.sources.skills;
      commands = cfg.commands;
      hooks = cfg.hooks;
    };
  };
}
