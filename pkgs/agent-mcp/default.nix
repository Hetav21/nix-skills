# `agent-mcp sync [MCP_JSON]`: renders a project's canonical mcp.json into the
# project-level config of every agent, using the same renderers as the Home
# Manager module (evaluated with the caller's nix-instantiate).
{
  path,
  writeShellApplication,
  writers,
  python3Packages,
  jq,
}: let
  # Only nixpkgs' self-contained lib/, not the whole nixpkgs source
  nixpkgsLib = builtins.path {
    path = path + "/lib";
    name = "nixpkgs-lib";
  };

  # Sets the servers under one key of a JSON/TOML config file, keeping the
  # rest of it; also used by the Home Manager module's activation steps
  merge = writers.writePython3Bin "agent-mcp-merge" {
    libraries = [python3Packages.tomlkit];
  } (builtins.readFile ./merge.py);
in
  writeShellApplication {
    name = "agent-mcp";
    runtimeInputs = [jq merge];
    passthru = {inherit merge;};
    text = ''
      usage() {
        cat <<'EOF'
      Usage: agent-mcp sync [MCP_JSON]

      Renders MCP_JSON (default: ./mcp.json) into the project-level MCP config of
      every agent, in the same directory. Only the MCP servers key of each file
      is replaced; everything else in it is kept.
        .mcp.json                 Claude Code   (mcpServers)
        opencode.json             OpenCode      (mcp)
        .codex/config.toml        Codex         (mcp_servers)
        .agents/mcp_config.json   Antigravity   (mcpServers)
      EOF
      }

      if [ "''${1:-}" != sync ] || [ "$#" -gt 2 ]; then
        usage >&2
        exit 64
      fi

      source=$(realpath "''${2:-mcp.json}")
      root=$(dirname "$source")
      if [ ! -f "$source" ]; then
        echo "agent-mcp: $source not found" >&2
        exit 66
      fi

      rendered=$(nix-instantiate --eval --strict --json --argstr source "$source" --expr '
        { source }:
        let lib = import ${nixpkgsLib};
        in (import ${../../lib/mcp.nix} { inherit lib; }).render (lib.importJSON source).mcpServers
      ')

      # write FILE KEY CLIENT: the CLIENT rendering -> KEY of FILE
      write() {
        agent-mcp-merge "$root/$1" "$2" <(jq ".$3" <<<"$rendered")
        echo "agent-mcp: wrote $1"
      }

      write .mcp.json mcpServers claude
      write opencode.json mcp opencode
      write .codex/config.toml mcp_servers codex
      write .agents/mcp_config.json mcpServers antigravity
    '';
  }
