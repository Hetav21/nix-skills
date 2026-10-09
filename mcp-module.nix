{
  config,
  options,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.agent-mcp;

  fileServers = lib.optionalAttrs (cfg.file != null) (lib.importJSON cfg.file).mcpServers;
  # A bare `command` named in `commands` (e.g. "bunx") runs that executable
  resolveCommand = server:
    if builtins.isString (server.command or null) && cfg.commands ? ${server.command}
    then server // {command = cfg.commands.${server.command};}
    else server;
  rendered =
    (import ./lib/mcp.nix {inherit lib;}).render
    (lib.mapAttrs (_: resolveCommand) (fileServers // cfg.servers));
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
  # else in the file, including servers added by hand, is kept. With the
  # target off, the servers a previous generation added are removed instead.
  mergeStep = name: enabled: file: key: let
    state = "${config.xdg.stateHome}/nix-skills/mcp/${name}.json";
    merge = servers: "${lib.getExe cli.merge} ${lib.escapeShellArgs [
      file
      key
      (jsonFormat.generate "${name}-mcp-servers.json" servers)
      state
    ]}";
  in
    lib.hm.dag.entryAfter ["linkGeneration"] (
      if enabled
      then ''
        run ${merge rendered.${name}} \
          || warnEcho "agent-mcp: could not update the MCP servers in ${file}"
      ''
      else ''
        if [[ -e ${lib.escapeShellArg state} ]]; then
          if [[ ! -e ${lib.escapeShellArg file} ]] || run ${merge {}}; then
            run rm ${lib.escapeShellArg state}
          else
            warnEcho "agent-mcp: could not remove the MCP servers from ${file}"
          fi
        fi
      ''
    );
in {
  options.programs.agent-mcp = {
    enable = lib.mkEnableOption "one MCP server definition shared by every AI agent";

    file = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = lib.literalExpression "./mcp.json";
      description = ''
        A canonical {file}`mcp.json` (the same file `agent-mcp sync` reads in a
        project) whose `mcpServers` are rendered for every enabled target.
        {option}`servers` are added on top; a server defined in both is taken
        from {option}`servers`.
      '';
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf jsonFormat.type;
      default = {};
      example = lib.literalExpression ''
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
        Canonical MCP servers (shaped like the `mcpServers` of an `mcp.json`),
        rendered for every enabled target. Every server sets `type`: `"local"` servers take
        `command`, `args` and `env`; `"remote"` servers take `url` and `headers`.
        Any server may set `disabled = true`. Reference environment variables
        as `{env:VAR}`.
      '';
    };

    commands = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = lib.literalExpression ''{ pnpm = lib.getExe pkgs.pnpm; }'';
      description = ''
        Executables for bare `command` names: a local server whose `command`
        is a key here runs that executable instead, so agents don't depend on
        {env}`PATH`. `npx`, `bunx` and `uvx` resolve to nixpkgs by default.
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
      agentMcpClaude = mergeStep "claude" t.claude "${home}/.claude.json" "mcpServers";
      agentMcpOpencode =
        lib.mkIf (!viaHm "opencode")
        (mergeStep "opencode" t.opencode "${config.xdg.configHome}/opencode/opencode.json" "mcp");
      agentMcpCodex =
        lib.mkIf (!viaHm "codex")
        (mergeStep "codex" t.codex "${home}/.codex/config.toml" "mcp_servers");
      agentMcpAntigravity =
        lib.mkIf (!viaHm "antigravity-cli")
        (mergeStep "antigravity" t.antigravity "${home}/.gemini/config/mcp_config.json" "mcpServers");
    };

    programs =
      {
        agent-mcp.commands = lib.mapAttrs (_: lib.mkDefault) {
          npx = lib.getExe' pkgs.nodejs "npx";
          bunx = lib.getExe' pkgs.bun "bunx";
          uvx = lib.getExe' pkgs.uv "uvx";
        };
      }
      // lib.optionalAttrs (hasHm "opencode") {
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
