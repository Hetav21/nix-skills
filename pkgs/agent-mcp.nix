# `agent-mcp sync [MCP_JSON]`: renders a project's canonical mcp.json into the
# project-level config of every agent, using the same renderers as the Home
# Manager module (evaluated with the caller's nix-instantiate).
{
  lib,
  path,
  writeShellApplication,
  jq,
  remarshal,
}: let
  # Only nixpkgs' self-contained lib/, not the whole nixpkgs source
  nixpkgsLib = builtins.path {
    path = path + "/lib";
    name = "nixpkgs-lib";
  };
in
  writeShellApplication {
    name = "agent-mcp";
    runtimeInputs = [jq remarshal];
    text = ''
      usage() {
        cat <<'EOF'
      Usage: agent-mcp sync [MCP_JSON]

      Renders MCP_JSON (default: ./mcp.json) into the project-level MCP config of
      every agent, in the same directory:
        .mcp.json                 Claude Code
        opencode.json             OpenCode   (only the "mcp" key is replaced)
        .codex/config.toml        Codex      (only [mcp_servers] is replaced)
        .agents/mcp_config.json   Antigravity
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
        in (import ${../lib/mcp.nix} { inherit lib; }).render (lib.importJSON source).mcpServers
      ')

      # write FILE: stdin -> FILE, creating parent directories
      write() {
        mkdir -p "$(dirname "$1")"
        cat > "$1"
        echo "agent-mcp: wrote ''${1#"$root"/}"
      }

      jq '{mcpServers: .claude}' <<<"$rendered" | write "$root/.mcp.json"
      jq '{mcpServers: .antigravity}' <<<"$rendered" | write "$root/.agents/mcp_config.json"

      opencode="$root/opencode.json"
      if [ -e "$opencode" ]; then existing=$(cat "$opencode"); else existing='{}'; fi
      jq --argjson mcp "$(jq .opencode <<<"$rendered")" '
        if . == {} then {"$schema": "https://opencode.ai/config.json"} end | .mcp = $mcp
      ' <<<"$existing" | write "$opencode"

      codex="$root/.codex/config.toml"
      if [ -e "$codex" ]; then existing=$(toml2json "$codex"); else existing='{}'; fi
      jq --argjson servers "$(jq .codex <<<"$rendered")" '.mcp_servers = $servers' <<<"$existing" | json2toml | write "$codex"
    '';
  }
