# Nix Skills Documentation

`nix-skills` is a decoupled Nix library and Home Manager modules for managing skills and MCP servers declaratively across AI agents: **OpenCode**, **Claude Code**, **OpenAI Codex**, and **Google Antigravity (`agy`)**.

## Directory Structure

When activated, `nix-skills` manages skills across the supported agent targets:

| Path                                  | Agent Target                         | Description                          | Strategy                             |
| ------------------------------------- | ------------------------------------ | ------------------------------------ | ------------------------------------ |
| `~/.agents/skills/`                   | OpenCode / Universal (`agents`)        | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks) |
| `~/.claude/skills/`                   | Claude Code (`claude`)               | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks) |
| `~/.codex/skills/`                    | OpenAI Codex (`codex`)               | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks) |
| `~/.gemini/skills/`                   | Gemini CLI & Antigravity (`gemini`)  | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks) |
| `~/.gemini/antigravity-cli/skills/`   | Antigravity CLI (`agy`)              | Skill definitions (`skill/SKILL.md`) | Flattened merge (recursive symlinks) |

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
    gemini = true;  # ~/.gemini/skills and ~/.gemini/antigravity-cli/skills
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
- **`mcp.render mcpServers`**: Renders a canonical `mcpServers` attrset for every agent (`{ claude, opencode, codex, antigravity }`); `mcp.toClaude`, `mcp.toOpencode`, `mcp.toCodex` and `mcp.toAntigravity` render for one. See [MCP Servers](#mcp-servers-programsagent-mcp).
- **`toClaudeMcpServers mcpServers`**: Converts an opencode-style `mcpServers` attrset to Claude Code format. Superseded by `mcp.toClaude`.

## MCP Servers (`programs.agent-mcp`)

Write MCP servers once, in one `mcp.json`, and every agent gets them: globally through Home Manager, and per project through `agent-mcp sync`. Both paths use the same renderers (`lib/mcp.nix`).

### Canonical `mcp.json`

```json
{
  "mcpServers": {
    "context7": {
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}" }
    },
    "playwright": {
      "command": "bunx",
      "args": ["-y", "@playwright/mcp@latest"],
      "env": { "DEBUG": "pw:mcp" },
      "disabled": true
    }
  }
}
```

- **stdio** servers take `command`, `args`, `env`; **remote** servers take `url`, `headers` and an optional `type` (`"http"`, the default, or `"sse"`). Any server may set `disabled`. Other keys are an evaluation error.
- Reference environment variables as `${VAR}`; each agent gets its own syntax (table below).

### Global (Home Manager)

```nix
programs.agent-mcp = {
  enable = true;
  servers = (lib.importJSON ./mcp.json).mcpServers;
  # targets = { claude = true; opencode = true; codex = true; antigravity = true; };  # defaults
};
```

| Agent       | Written to                                                                                   |
| ----------- | -------------------------------------------------------------------------------------------- |
| Claude Code | merged into the user scope of `~/.claude.json` on activation                                 |
| OpenCode    | `programs.opencode.settings.mcp` if that module is enabled, else `~/.config/opencode/opencode.json` |
| Codex       | `programs.codex.settings.mcp_servers` if that module is enabled, else `~/.codex/config.toml` |
| Antigravity | `programs.antigravity-cli.mcpServers` if that module is enabled, else `~/.gemini/config/mcp_config.json` (read by both the IDE and `agy`) |

Claude Code rewrites `~/.claude.json` constantly, so it can't be a store symlink. The activation step replaces only the servers it manages. It records their names in `$XDG_STATE_HOME/nix-skills/claude-mcp-servers.json` so servers dropped from `servers` are removed, while servers added with `claude mcp add` are kept.

The module also installs the `agent-mcp` CLI.

### Per project (`agent-mcp sync`)

Run `agent-mcp sync` in a directory with an `mcp.json` (or `agent-mcp sync path/to/mcp.json`). It writes next to it:

| Agent       | File                      | Ownership                                                     |
| ----------- | ------------------------- | ------------------------------------------------------------- |
| Claude Code | `.mcp.json`               | whole file                                                    |
| OpenCode    | `opencode.json`           | only the `mcp` key; other keys kept                           |
| Codex       | `.codex/config.toml`      | only `[mcp_servers]`; other keys kept, comments/format are not |
| Antigravity | `.agents/mcp_config.json` | whole file                                                    |

- Claude Code asks once per project before starting `.mcp.json` servers.
- Codex only reads `.codex/config.toml` in projects it trusts (`[projects."<path>"] trust_level = "trusted"`).
- Re-run after editing `mcp.json`. To automate it with direnv, add `watch_file mcp.json` and `agent-mcp sync` to `.envrc`.
- Needs `nix-instantiate` on `PATH`; the package is also exposed as `packages.<system>.agent-mcp`.

### Per-agent translation

None of OpenCode, Codex or Antigravity understands `${VAR}`, so references are translated. A server an agent cannot express is skipped for that agent with an evaluation warning naming the reason; nothing is silently dropped.

| Canonical                           | Claude Code | OpenCode         | Codex                          | Antigravity             |
| ----------------------------------- | ----------- | ---------------- | ------------------------------ | ----------------------- |
| `env.X = "${X}"`                    | as is       | `{env:X}`        | `env_vars = ["X"]`             | dropped (inherited)     |
| `headers.Authorization = "Bearer ${X}"` | as is   | `{env:X}`        | `bearer_token_env_var = "X"`   | **skipped**             |
| `headers.H = "${X}"`                | as is       | `{env:X}`        | `env_http_headers.H = "X"`     | **skipped**             |
| `${X}` in `command`/`args`/`url`, or `env.Y = "${X}"` | as is | `{env:X}` | **skipped**        | **skipped**             |
| `type = "sse"`                      | `sse`       | `remote`         | **skipped** (HTTP only)        | **skipped** (HTTP only) |
| `disabled = true`                   | omitted     | `enabled = false` | `enabled = false`             | `disabled = true`       |
