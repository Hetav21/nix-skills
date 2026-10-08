# Renders one canonical `mcpServers` attrset into each agent's MCP config shape.
#
# Canonical server (the Claude Code `.mcp.json` dialect plus `disabled`):
#   stdio:  { command, args ? [], env ? {}, disabled ? false }
#   remote: { url, type ? "http" | "sse", headers ? {}, disabled ? false }
# Environment references use `${VAR}` in any string; each renderer translates
# them to the client's own syntax, or skips the server with a warning when the
# client cannot express them.
{lib}: let
  allowedKeys = ["type" "command" "args" "env" "url" "headers" "disabled"];
  varName = "[A-Za-z_][A-Za-z0-9_]*";

  # "${VAR}" -> "VAR"; anything else -> null
  wholeRef = s: let
    m = builtins.match "\\$\\{(${varName})}" s;
  in
    if m == null
    then null
    else builtins.head m;

  hasRef = s: builtins.match ".*\\$\\{${varName}}.*" s != null;
  anyRef = values: lib.any hasRef (lib.filter builtins.isString values);

  # Names of env entries that forward the same variable (`X = "${X}"`), or null
  # if some entry references a variable any other way.
  forwardedEnv = env: let
    refs = lib.filterAttrs (_: hasRef) env;
  in
    if lib.all (n: wholeRef refs.${n} == n) (builtins.attrNames refs)
    then builtins.attrNames refs
    else null;

  # "a ${X} b" -> "a {env:X} b"
  toOpencodeRefs = s:
    lib.concatMapStrings (part:
      if builtins.isList part
      then "{env:${builtins.head part}}"
      else part)
    (builtins.split "\\$\\{(${varName})}" s);

  mapStrings = f: v:
    if builtins.isString v
    then f v
    else if builtins.isList v
    then map (mapStrings f) v
    else if builtins.isAttrs v
    then lib.mapAttrs (_: mapStrings f) v
    else v;

  # Validates a canonical server and fills defaults.
  normalize = name: server: let
    unknown = lib.subtractLists allowedKeys (builtins.attrNames server);
    fail = msg: throw "nix-skills mcp: server '${name}': ${msg}";
    isRemote = server ? url;
    type =
      server.type or (
        if isRemote
        then "http"
        else "stdio"
      );
  in
    if unknown != []
    then fail "unknown keys ${builtins.toJSON unknown} (allowed: ${builtins.toJSON allowedKeys})"
    else if (server ? command) == isRemote
    then fail "set exactly one of `command` or `url`"
    else if !(builtins.elem type ["stdio" "http" "sse"])
    then fail "type must be \"stdio\", \"http\" or \"sse\", got ${builtins.toJSON type}"
    else if isRemote == (type == "stdio")
    then
      fail "type \"${type}\" does not match the use of `${
        if isRemote
        then "url"
        else "command"
      }`"
    else if isRemote && (server ? args || server ? env)
    then fail "`args` and `env` are only valid with `command`"
    else if !isRemote && server ? headers
    then fail "`headers` is only valid with `url`"
    else {
      inherit type;
      remote = isRemote;
      disabled = server.disabled or false;
      command = server.command or null;
      args = server.args or [];
      env = server.env or {};
      url = server.url or null;
      headers = server.headers or {};
    };

  # Renders every server with `render normalizedServer`; a renderer returns
  # null to omit a server, or `{ skip = "reason"; }` to omit it with a warning.
  renderWith = client: render: servers:
    lib.filterAttrs (_: v: v != null) (lib.mapAttrs (name: server: let
      out = render (normalize name server);
    in
      if out ? skip
      then lib.warn "nix-skills mcp: skipping server '${name}' for ${client}: ${out.skip}" null
      else out)
    servers);

  optionalNonEmpty = name: value: lib.optionalAttrs (value != {} && value != []) {${name} = value;};
in rec {
  # Claude Code: `.mcp.json` / `~/.claude.json`. Expands `${VAR}` natively.
  # Has no per-server disable flag, so disabled servers are omitted.
  toClaude = renderWith "claude" (s:
    if s.disabled
    then null
    else if s.remote
    then {inherit (s) type url;} // optionalNonEmpty "headers" s.headers
    else
      {
        type = "stdio";
        inherit (s) command;
      }
      // optionalNonEmpty "args" s.args
      // optionalNonEmpty "env" s.env);

  # OpenCode: `opencode.json` `mcp`. References become `{env:VAR}`.
  toOpencode = renderWith "opencode" (s:
    mapStrings toOpencodeRefs (
      {enabled = !s.disabled;}
      // (
        if s.remote
        then
          {
            type = "remote";
            inherit (s) url;
          }
          // optionalNonEmpty "headers" s.headers
        else
          {
            type = "local";
            command = [s.command] ++ s.args;
          }
          // optionalNonEmpty "environment" s.env
      )
    ));

  # OpenAI Codex: `config.toml` `mcp_servers`. Codex never interpolates and
  # passes stdio servers only a minimal environment, so `${VAR}` must map onto
  # its env-forwarding keys:
  #   env.X = "${X}"                        -> env_vars = [ "X" ]
  #   headers.Authorization = "Bearer ${X}" -> bearer_token_env_var = "X"
  #   headers.H = "${X}"                    -> env_http_headers.H = "X"
  toCodex = renderWith "codex" (s: let
    bearer = builtins.match "Bearer \\$\\{(${varName})}" (s.headers.Authorization or "");
    headers = removeAttrs s.headers (lib.optional (bearer != null) "Authorization");
    refHeaders = lib.filterAttrs (_: hasRef) headers;
    forwarded = forwardedEnv s.env;
  in
    if s.type == "sse"
    then {skip = "Codex only supports streamable HTTP, not SSE";}
    else if anyRef ([s.command s.url] ++ s.args)
    then {skip = "Codex does not expand \${VAR} in command, args or url";}
    else if lib.any (h: wholeRef h == null) (builtins.attrValues refHeaders)
    then {skip = "header values must be a literal, \"\${VAR}\" or \"Bearer \${VAR}\" for Codex";}
    else if forwarded == null
    then {skip = "env values must be a literal or \"\${SAME_NAME}\" for Codex";}
    else
      {enabled = !s.disabled;}
      // (
        if s.remote
        then
          {inherit (s) url;}
          // lib.optionalAttrs (bearer != null) {bearer_token_env_var = builtins.head bearer;}
          // optionalNonEmpty "http_headers" (removeAttrs headers (builtins.attrNames refHeaders))
          // optionalNonEmpty "env_http_headers" (lib.mapAttrs (_: wholeRef) refHeaders)
        else
          {inherit (s) command;}
          // optionalNonEmpty "args" s.args
          // optionalNonEmpty "env" (removeAttrs s.env forwarded)
          // optionalNonEmpty "env_vars" forwarded
      ));

  # Antigravity (IDE and `agy`): `mcp_config.json`. Antigravity never
  # interpolates, but stdio servers inherit its environment, so `X = "${X}"`
  # env entries are simply dropped. Only speaks streamable HTTP.
  toAntigravity = renderWith "antigravity" (s: let
    forwarded = forwardedEnv s.env;
  in
    if s.type == "sse"
    then {skip = "Antigravity only supports streamable HTTP, not SSE";}
    else if anyRef ([s.command s.url] ++ s.args ++ builtins.attrValues s.headers)
    then {skip = "Antigravity does not expand \${VAR} in command, args, url or headers";}
    else if forwarded == null
    then {skip = "env values must be a literal or \"\${SAME_NAME}\" for Antigravity";}
    else
      {inherit (s) disabled;}
      // (
        if s.remote
        then {serverUrl = s.url;} // optionalNonEmpty "headers" s.headers
        else
          {inherit (s) command;}
          // optionalNonEmpty "args" s.args
          // optionalNonEmpty "env" (removeAttrs s.env forwarded)
      ));

  # All four renderings at once, keyed by client.
  render = servers: {
    claude = toClaude servers;
    opencode = toOpencode servers;
    codex = toCodex servers;
    antigravity = toAntigravity servers;
  };
}
