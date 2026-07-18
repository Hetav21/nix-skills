# Nix Skills Documentation

This repository provides a decoupled library and Home Manager module for setting up Agent skills and resources in Nix flakes. It declaratively manages the `~/.agents` directory to ensure a consistent environment for Claude Code, OpenCode, and other AI agents.

## Directory Structure

When activated, the module writes to `~/.agents` with the following structure:

| Path                  | Description                          | Strategy                              |
| --------------------- | ------------------------------------ | ------------------------------------- |
| `~/.agents/commands/` | Custom slash commands (`/cmd`)       | Flat merge of all inputs              |
| `~/.agents/skills/`   | Skill definitions (`skill/SKILL.md`) | Flattened merge (nested dirs -> flat) |
| `~/.agents/agents/`   | Agent definitions (`agent.md`)       | Flat merge of all inputs              |
| `~/.agents/hooks/`    | Hooks configuration                  | Flat merge of all inputs              |

## Getting Started

### 1. Adding to your Flake

Add the repository to your inputs:

```nix
inputs = {
  nix-skills.url = "github:Hetav21/nix-skills";
};
```

### 2. Home Manager Configuration

Import the module directly in your Home Manager configuration tree:

```nix
imports = [
  inputs.nix-skills.homeManagerModules.default
];
```

Enable and configure the resources (for example, in your personal environment config):

```nix
programs.agent-resources = {
  enable = true;
  sources = {
    agents = [
      "https://github.com/owner/repo/blob/main/agents/coder.md"
    ];
    skills = [
      "https://github.com/owner/repo/tree/main/skills"
    ];
  };
  # Example manual cherry-picking of custom extensions with the library helper
  commands = [
    (inputs.nix-skills.lib.extract pkgs pkgs.custom.superpowers "commands" {})
  ];
};
```

## Library Functions (`lib/default.nix`)

The library is exposed natively via `inputs.nix-skills.lib`. Available helpers include:

- **`mkEnvironment pkgs { inputs, agents, skills, commands, hooks }`**: Evaluates sources and builds the `home.file` attribute mapping pointing directly to `~/.agents`.
- **`extract pkgs src path { includes, excludes }`**: Extracts a subdirectory from a package. Supports filtering with glob strings.
- **`merge pkgs name paths`**: Merges directories using `rsync`, resolving conflicts with right-sided priority.
- **`flattenSkills pkgs src`**: Recursively finds `SKILL.md` files and flattens the directory structure into single-depth folders formatting the hyphenated paths.
- **`parseGithubUrl url` / `resolveSource pkgs inputs url`**: Resolves GitHub string URLs directly against your flake inputs for rapid declarative mappings.
- **`toClaudeMcpServers mcpServers`**: Converts an opencode-style `mcpServers` attrset to a Claude Code compatible one, rewriting `"type": "remote"` to `"type": "http"` and adding `"type": "http"` to bare `url` entries that omit it.
