# Nix Skills Documentation

This repository provides a decoupled library and Home Manager module for setting up Agent skills and resources in Nix flakes. It declaratively manages agent skills across Claude Code, OpenAI Codex, OpenCode, and Antigravity (agy).

## Directory Structure

When activated, the module writes to target directories based on `programs.agent-resources.targets`:

| Path                  | Agent Target                  | Description                          | Strategy                              |
| --------------------- | ----------------------------- | ------------------------------------ | ------------------------------------- |
| `~/.agents/commands/` | OpenCode / Universal (`agents`) | Custom slash commands (`/cmd`)       | Flat merge of all inputs              |
| `~/.agents/skills/`   | OpenCode / Universal (`agents`) | Skill definitions (`skill/SKILL.md`) | Flattened merge (nested dirs -> flat) |
| `~/.agents/agents/`   | OpenCode / Universal (`agents`) | Agent definitions (`agent.md`)       | Flat merge of all inputs              |
| `~/.agents/hooks/`    | OpenCode / Universal (`agents`) | Hooks configuration                  | Flat merge of all inputs              |
| `~/.claude/skills/`   | Claude Code (`claude`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive links)     |
| `~/.codex/skills/`    | OpenAI Codex (`codex`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive links)     |
| `~/.gemini/skills/`   | Antigravity (`gemini`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive links)     |

## Getting Started

### 1. Adding to your Flake

Add the repository to your inputs:

```nix
inputs = {
  nix-skills.url = "github:Hetav21/nix-skills";
  # or local path:
  # nix-skills.url = "git+file:///path/to/nix-skills";
};
```

### 2. Home Manager Configuration

Import the module directly in your Home Manager configuration tree:

```nix
imports = [
  inputs.nix-skills.homeManagerModules.default
];
```

Enable and configure the resources:

```nix
programs.agent-resources = {
  enable = true;
  targets = {
    agents = true;  # ~/.agents
    claude = true;  # ~/.claude/skills
    codex = true;   # ~/.codex/skills
    gemini = true;  # ~/.gemini/skills
  };
  skills = [
    (inputs.nix-skills.lib.extract pkgs pkgs.custom.mattpocock-skills "skills/engineering" {})
    (inputs.nix-skills.lib.extract pkgs pkgs.custom.emilkowalski-skills "skills" {})
  ];
};
```

## Library Functions (`lib/default.nix`)

The library is exposed natively via `inputs.nix-skills.lib`. Available helpers include:

- **`mkEnvironment pkgs { inputs, agents, skills, commands, hooks, targets }`**: Evaluates sources and builds the `home.file` attribute mapping across target directories (`.agents`, `.claude/skills`, `.codex/skills`, `.gemini/skills`).
- **`extract pkgs src path { includes, excludes }`**: Extracts a subdirectory from a package. Supports filtering with glob strings.
- **`merge pkgs name paths`**: Merges directories using `rsync`, resolving conflicts with right-sided priority.
- **`flattenSkills pkgs src`**: Recursively finds `SKILL.md` files and flattens the directory structure into single-depth folders based on skill folder basenames.
- **`parseGithubUrl url` / `resolveSource pkgs inputs url`**: Resolves GitHub string URLs directly against your flake inputs for rapid declarative mappings.
- **`toClaudeMcpServers mcpServers`**: Converts an opencode-style `mcpServers` attrset to a Claude Code compatible one, rewriting `"type": "remote"` to `"type": "http"` and adding `"type": "http"` to bare `url` entries that omit it.
