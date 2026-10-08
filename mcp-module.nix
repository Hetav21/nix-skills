{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.agent-mcp;
  rendered = (import ./lib/mcp.nix {inherit lib;}).render cfg.servers;
  jsonFormat = pkgs.formats.json {};
  tomlFormat = pkgs.formats.toml {};

  mkTargetOption = description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };

  claudeServers = jsonFormat.generate "claude-mcp-servers.json" rendered.claude;

  # Claude Code keeps user-scope servers in its mutable ~/.claude.json, so they
  # are merged in place. Servers managed by the previous generation but no longer
  # declared are removed; servers added by hand are kept.
  syncClaude = pkgs.writeShellApplication {
    name = "agent-mcp-sync-claude";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      claudeJson="$HOME/.claude.json"
      state="${config.xdg.stateHome}/nix-skills/claude-mcp-servers.json"

      [ -s "$claudeJson" ] || echo '{}' > "$claudeJson"
      previous=$(cat "$state" 2>/dev/null || echo '[]')
      tmp=$(mktemp "$claudeJson.XXXXXX")
      if ! jq --argjson previous "$previous" --slurpfile managed ${claudeServers} '
        .mcpServers = ((.mcpServers // {}) | with_entries(select(.key | IN($previous[]) | not))) + $managed[0]
      ' "$claudeJson" > "$tmp"; then
        rm -f "$tmp"
        echo "agent-mcp: could not update MCP servers in $claudeJson" >&2
        exit 0
      fi
      chmod --reference="$claudeJson" "$tmp"
      mv "$tmp" "$claudeJson"

      mkdir -p "$(dirname "$state")"
      jq keys ${claudeServers} > "$state"
    '';
  };
in {
  options.programs.agent-mcp = {
    enable = lib.mkEnableOption "one MCP server definition shared by every AI agent";

    servers = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = {};
      example = lib.literalExpression ''
        (lib.importJSON ./mcp.json).mcpServers
        # or inline:
        {
          context7 = {
            url = "https://mcp.context7.com/mcp";
            headers.CONTEXT7_API_KEY = "''${CONTEXT7_API_KEY}";
          };
          playwright = {
            command = "bunx";
            args = [ "-y" "@playwright/mcp@latest" ];
            disabled = true;
          };
        }
      '';
      description = ''
        Canonical MCP servers (the `mcpServers` of an `mcp.json`), rendered for
        every enabled target. Stdio servers take `command`, `args` and `env`;
        remote servers take `url`, `headers` and an optional `type`
        (`"http"` or `"sse"`). Any server may set `disabled = true`.
        Reference environment variables as `''${VAR}`.
      '';
    };

    targets = {
      claude = mkTargetOption "Merge the servers into Claude Code's user scope ({file}`~/.claude.json`).";
      opencode = mkTargetOption ''
        Write the servers to OpenCode's global config, through
        {option}`programs.opencode.settings` when that module is enabled.
      '';
      codex = mkTargetOption ''
        Write the servers to {file}`~/.codex/config.toml`, through
        {option}`programs.codex.settings` when that module is enabled.
      '';
      antigravity = mkTargetOption ''
        Write the servers to Antigravity's {file}`~/.gemini/config/mcp_config.json`
        (shared by the IDE and `agy`), through {option}`programs.antigravity-cli`
        when that module is enabled.
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    t = cfg.targets;
    # Whether Home Manager's own module for the agent exists (it depends on the
    # Home Manager release) and is enabled, so its config file is owned there
    hasHm = name: options.programs ? ${name};
    viaHm = name: hasHm name && config.programs.${name}.enable;
  in {
    home.packages = [(pkgs.callPackage ./pkgs/agent-mcp.nix {})];

    home.activation.agentMcpClaude = lib.mkIf t.claude (lib.hm.dag.entryAfter ["writeBoundary"] ''
      run ${lib.getExe syncClaude}
    '');

    programs =
      lib.optionalAttrs (hasHm "opencode") {
        opencode.settings.mcp = lib.mkIf (t.opencode && viaHm "opencode") rendered.opencode;
      }
      // lib.optionalAttrs (hasHm "codex") {
        codex.settings.mcp_servers = lib.mkIf (t.codex && viaHm "codex") rendered.codex;
      }
      // lib.optionalAttrs (hasHm "antigravity-cli") {
        antigravity-cli.mcpServers = lib.mkIf (t.antigravity && viaHm "antigravity-cli") rendered.antigravity;
      };

    xdg.configFile."opencode/opencode.json" = lib.mkIf (t.opencode && !viaHm "opencode") {
      source = jsonFormat.generate "opencode.json" {
        "$schema" = "https://opencode.ai/config.json";
        mcp = rendered.opencode;
      };
    };

    home.file = {
      ".codex/config.toml" = lib.mkIf (t.codex && !viaHm "codex") {
        source = tomlFormat.generate "codex-config.toml" {mcp_servers = rendered.codex;};
      };
      ".gemini/config/mcp_config.json" = lib.mkIf (t.antigravity && !viaHm "antigravity-cli") {
        source = jsonFormat.generate "antigravity-mcp-config.json" {mcpServers = rendered.antigravity;};
      };
    };
  });
}
