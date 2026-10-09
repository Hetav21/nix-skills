{ config, lib, pkgs, inputs ? null, ... }:
let
  cfg = config.programs.agent-skills;
  legacyCfg = config.programs.agent-resources;
  nix-skills-lib = import ./lib { inherit lib; };

  # Skill item submodule for structured declarations
  skillSubmodule = lib.types.submodule {
    options = {
      source = lib.mkOption {
        type = lib.types.package;
        description = "Package containing skills.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "skills";
        description = "Subdirectory inside package containing skills (default: 'skills').";
      };
      includes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of skill directories to include.";
      };
      excludes = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "List of skill directories to exclude.";
      };
    };
  };

  # Unified targets submodule
  targetsOptions = {
    agents = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install skills to ~/.agents/skills (OpenCode / open agent standard).";
    };

    claude = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install skills to ~/.claude/skills (Claude Code).";
    };

    codex = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install skills to ~/.codex/skills (OpenAI Codex CLI).";
    };

    gemini = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Install skills to ~/.gemini/skills (Antigravity / agy).";
    };
  };
in {
  options.programs = {
    agent-skills = {
      enable = lib.mkEnableOption "Agent skills installation across AI agents";

      skills = lib.mkOption {
        type = lib.types.listOf (lib.types.either lib.types.package skillSubmodule);
        default = [];
        description = "List of skill packages or declarative skill source specifications.";
      };

      targets = targetsOptions;
    };

    # Legacy alias options for backward compatibility
    agent-resources = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Deprecated: Use programs.agent-skills.enable instead.";
      };

      skills = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = "Deprecated: Use programs.agent-skills.skills instead.";
      };

      targets = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = {};
        description = "Deprecated: Use programs.agent-skills.targets instead.";
      };

      commands = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = "Deprecated: No longer supported.";
      };

      agents = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = "Deprecated: No longer supported.";
      };

      hooks = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [];
        description = "Deprecated: No longer supported.";
      };
    };
  };

  config = let
    effectiveEnable = cfg.enable || legacyCfg.enable;
    effectiveSkills = if cfg.enable then cfg.skills else legacyCfg.skills;
    effectiveTargets = if cfg.enable then cfg.targets else {
      agents = legacyCfg.targets.agents or true;
      claude = legacyCfg.targets.claude or true;
      codex = legacyCfg.targets.codex or true;
      gemini = legacyCfg.targets.gemini or true;
    };
  in lib.mkIf effectiveEnable {
    warnings =
      lib.optional legacyCfg.enable "programs.agent-resources is deprecated; use programs.agent-skills instead."
      ++ lib.optional (legacyCfg.commands != [] || legacyCfg.agents != [] || legacyCfg.hooks != [])
        "programs.agent-resources.{commands,agents,hooks} are no longer supported and are ignored."
      ++ lib.optional (cfg.enable && legacyCfg.enable && legacyCfg.skills != [])
        "programs.agent-resources.skills is ignored because programs.agent-skills is enabled."
      ++ lib.optional (cfg.enable && !lib.any lib.id (lib.attrValues cfg.targets))
        "programs.agent-skills is enabled but installs nowhere: set programs.agent-skills.targets.<agent> = true.";

    home.file = nix-skills-lib.mkEnvironment pkgs {
      skills = effectiveSkills;
      targets = effectiveTargets;
    };
  };
}
