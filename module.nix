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

    targets = {
      agents = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install resources to ~/.agents (OpenCode and open agent standards).";
      };

      claude = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install skills to ~/.claude/skills (Claude Code).";
      };

      codex = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install skills to ~/.codex/skills (Codex CLI).";
      };

      gemini = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install skills to ~/.gemini/skills (Antigravity / agy).";
      };
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
      targets = cfg.targets;
    };
  };
}
