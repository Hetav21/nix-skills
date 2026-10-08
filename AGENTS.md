# Nix Skills Documentation

`nix-skills` is a decoupled Nix library and Home Manager module for managing skills declaratively across AI agents: **OpenCode**, **Claude Code**, **OpenAI Codex**, and **Google Antigravity (`agy`)**.

## Directory Structure

When activated, `nix-skills` manages skills across the supported agent targets:

| Path                  | Agent Target                  | Description                          | Strategy                              |
| --------------------- | ----------------------------- | ------------------------------------ | ------------------------------------- |
| `~/.agents/skills/`   | OpenCode / Universal (`agents`) | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks)  |
| `~/.claude/skills/`   | Claude Code (`claude`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks)  |
| `~/.codex/skills/`    | OpenAI Codex (`codex`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks)  |
| `~/.gemini/skills/`   | Antigravity (`gemini`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks)  |

All targets use `recursive = true` so individual skills are symlinked without overwriting runtime data (such as Codex's `.system` folder or unmanaged local skills).

## Getting Started

### 1. Adding to your Flake

```nix
inputs = {
  nix-skills.url = "github:Hetav21/nix-skills";
};
```

### 2. Home Manager Configuration

Import the module in your Home Manager configuration:

```nix
imports = [
  inputs.nix-skills.homeManagerModules.default
];
```

Configure `programs.agent-skills`:

```nix
programs.agent-skills = {
  enable = true;

  # Target agents (all enabled by default)
  targets = {
    agents = true;  # ~/.agents/skills
    claude = true;  # ~/.claude/skills
    codex = true;   # ~/.codex/skills
    gemini = true;  # ~/.gemini/skills
  };

  # Declarative skill sources
  skills = [
    # 1. Direct package: auto-discovers and flattens all SKILL.md recursively
    pkgs.custom.emilkowalski-skills

    # 2. Filtered source with excludes
    {
      source = pkgs.custom.mattpocock-skills;
      path = "skills";
      excludes = [ "deprecated" "in-progress" ];
    }

    # 3. Filtered source with cherry-picked includes
    {
      source = pkgs.custom.anthropic-skills;
      includes = [ "docx" "pdf" "pptx" "xlsx" ];
    }
  ];
};
```

## Library Functions (`lib/default.nix`)

The library is exposed via `inputs.nix-skills.lib`:

- **`buildSkills pkgs [skills]`**: Builds a single consolidated derivation containing all flattened and merged skills.
- **`mkEnvironment pkgs { skills, targets }`**: Generates the `home.file` attribute set for Home Manager across active agent targets.
- **`flattenSkills pkgs src`**: Recursively finds `SKILL.md` files and flattens the directory structure into single-depth folders based on skill folder basenames.
- **`extract pkgs src path { includes, excludes }`**: Extracts and filters subdirectories from packages.
- **`withPkgs pkgs`**: Returns a curried record of helper functions pre-bound to `pkgs`.
- **`toClaudeMcpServers mcpServers`**: Converts an opencode-style `mcpServers` attrset to Claude Code format.
