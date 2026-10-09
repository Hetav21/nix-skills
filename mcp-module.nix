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

  mkTargetOption = description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };

  cli = pkgs.callPackage ./pkgs/agent-mcp {};

  # Agents rewrite their own config at runtime (Claude Code's ~/.claude.json,
  # `codex mcp add`, `agy mcp disable`, ...), so instead of a read-only store
  # symlink the servers are merged into the file on activation. Servers managed
  # by the previous generation but no longer declared are removed; everything
  # else in the file, including servers added by hand, is kept.
  mergeStep = name: file: key: servers:
    lib.hm.dag.entryAfter ["linkGeneration"] ''
      run ${lib.getExe cli.merge} ${lib.escapeShellArgs [
        file
        key
        (jsonFormat.generate "${name}-mcp-servers.json" servers)
        "${config.xdg.stateHome}/nix-skills/mcp/${name}.json"
      ]} \
        || warnEcho "agent-mcp: could not update the MCP servers in ${file}"
    '';
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
            type = "remote";
            url = "https://mcp.context7.com/mcp";
            headers.CONTEXT7_API_KEY = "{env:CONTEXT7_API_KEY}";
          };
          playwright = {
            type = "local";
            command = "bunx";
            args = [ "-y" "@playwright/mcp@latest" ];
            disabled = true;
          };
        }
      '';
      description = ''
        Canonical MCP servers (the `mcpServers` of an `mcp.json`), rendered for
        every enabled target. Every server sets `type`: `"local"` servers take
        `command`, `args` and `env`; `"remote"` servers take `url` and `headers`.
        Any server may set `disabled = true`. Reference environment variables
        as `{env:VAR}`.
      '';
    };

    targets = {
      claude = mkTargetOption "Merge the servers into Claude Code's user scope ({file}`~/.claude.json`).";
      opencode = mkTargetOption ''
        Add the servers to OpenCode's global config: {option}`programs.opencode.settings`
        when that module is enabled, else merged into {file}`~/.config/opencode/opencode.json`.
      '';
      codex = mkTargetOption ''
        Add the servers to Codex's global config: {option}`programs.codex.settings`
        when that module is enabled, else merged into {file}`~/.codex/config.toml`.
      '';
      antigravity = mkTargetOption ''
        Add the servers to Antigravity's global config (shared by the IDE and `agy`):
        {option}`programs.antigravity-cli.mcpServers` when that module is enabled,
        else merged into {file}`~/.gemini/config/mcp_config.json`.
      '';
    };
  };

  config = lib.mkIf cfg.enable (let
    t = cfg.targets;
    home = config.home.homeDirectory;
    # Whether Home Manager's own module for the agent exists (it depends on the
    # Home Manager release) and is enabled, so its config file is owned there
    hasHm = name: options.programs ? ${name};
    viaHm = name: hasHm name && config.programs.${name}.enable;
  in {
    home.packages = [cli];

    home.activation = {
      agentMcpClaude = lib.mkIf t.claude (mergeStep "claude" "${home}/.claude.json" "mcpServers" rendered.claude);
      agentMcpOpencode =
        lib.mkIf (t.opencode && !viaHm "opencode")
        (mergeStep "opencode" "${config.xdg.configHome}/opencode/opencode.json" "mcp" rendered.opencode);
      agentMcpCodex =
        lib.mkIf (t.codex && !viaHm "codex")
        (mergeStep "codex" "${home}/.codex/config.toml" "mcp_servers" rendered.codex);
      agentMcpAntigravity =
        lib.mkIf (t.antigravity && !viaHm "antigravity-cli")
        (mergeStep "antigravity" "${home}/.gemini/config/mcp_config.json" "mcpServers" rendered.antigravity);
    };

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
  });
}
