# Renders one canonical `mcpServers` attrset into each agent's MCP config shape.
#
# Canonical server:
#   local:  { type = "local";  command, args ? [], env ? {}, disabled ? false }
#   remote: { type = "remote"; url, headers ? {}, disabled ? false }
# Environment references use `{env:VAR}` in any string; each renderer translates
# them to the client's own syntax, or skips the server with a warning when the
# client cannot express them.
{lib}: let
  allowedKeys = {
    local = ["type" "command" "args" "env" "disabled"];
    remote = ["type" "url" "headers" "disabled"];
  };
  varName = "[A-Za-z_][A-Za-z0-9_]*";
  ref = "\\{env:(${varName})}";

  # "{env:VAR}" -> "VAR"; anything else -> null
  wholeRef = s: let
    m = builtins.match ref s;
  in
    if m == null
    then null
    else builtins.head m;

  hasRef = s: builtins.match ".*${ref}.*" s != null;
  anyRef = values: lib.any hasRef (lib.filter builtins.isString values);

  # Rewrites every "{env:VAR}" in s to `f "VAR"`
  mapRefs = f: s:
    lib.concatMapStrings (part:
      if builtins.isList part
      then f (builtins.head part)
      else part)
    (builtins.split ref s);

  # Names of env entries that forward the same variable (`X = "{env:X}"`), or
  # null if some entry references a variable any other way.
  forwardedEnv = env: let
    refs = lib.filterAttrs (_: hasRef) env;
  in
    if lib.all (n: wholeRef refs.${n} == n) (builtins.attrNames refs)
    then builtins.attrNames refs
    else null;

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
    fail = msg: throw "nix-skills mcp: server '${name}': ${msg}";
    type = server.type or null;
    unknown = lib.subtractLists allowedKeys.${type} (builtins.attrNames server);
  in
    if !(builtins.elem type ["local" "remote"])
    then fail "set `type` to \"local\" or \"remote\", got ${builtins.toJSON type}"
    else if unknown != []
    then fail "unknown keys ${builtins.toJSON unknown} for a ${type} server (allowed: ${builtins.toJSON allowedKeys.${type}})"
    else if type == "local" && !(server ? command)
    then fail "a local server needs `command`"
    else if type == "remote" && !(server ? url)
    then fail "a remote server needs `url`"
    else {
      remote = type == "remote";
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
  # Claude Code: `.mcp.json` / `~/.claude.json`. References become `${VAR}`,
  # which it expands. Has no per-server disable flag, so disabled servers are
  # omitted.
  toClaude = renderWith "claude" (s:
    if s.disabled
    then null
    else
      mapStrings (mapRefs (v: "\${${v}}")) (
        if s.remote
        then
          {
            type = "http";
            inherit (s) url;
          }
          // optionalNonEmpty "headers" s.headers
        else
          {
            type = "stdio";
            inherit (s) command;
          }
          // optionalNonEmpty "args" s.args
          // optionalNonEmpty "env" s.env
      ));

  # OpenCode: `opencode.json` `mcp`. Understands `{env:VAR}` natively.
  toOpencode = renderWith "opencode" (s:
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
    ));

  # OpenAI Codex: `config.toml` `mcp_servers`. Codex never interpolates and
  # passes local servers only a minimal environment, so `{env:VAR}` must map
  # onto its env-forwarding keys:
  #   env.X = "{env:X}"                        -> env_vars = [ "X" ]
  #   headers.Authorization = "Bearer {env:X}" -> bearer_token_env_var = "X"
  #   headers.H = "{env:X}"                    -> env_http_headers.H = "X"
  toCodex = renderWith "codex" (s: let
    bearer = builtins.match "Bearer ${ref}" (s.headers.Authorization or "");
    headers = removeAttrs s.headers (lib.optional (bearer != null) "Authorization");
    refHeaders = lib.filterAttrs (_: hasRef) headers;
    forwarded = forwardedEnv s.env;
  in
    if anyRef ([s.command s.url] ++ s.args)
    then {skip = "Codex does not expand {env:VAR} in command, args or url";}
    else if lib.any (h: wholeRef h == null) (builtins.attrValues refHeaders)
    then {skip = "header values must be a literal, \"{env:VAR}\" or \"Bearer {env:VAR}\" for Codex";}
    else if forwarded == null
    then {skip = "env values must be a literal or \"{env:SAME_NAME}\" for Codex";}
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
  # interpolates, but local servers inherit its environment, so `X = "{env:X}"`
  # env entries are simply dropped.
  toAntigravity = renderWith "antigravity" (s: let
    forwarded = forwardedEnv s.env;
  in
    if anyRef ([s.command s.url] ++ s.args ++ builtins.attrValues s.headers)
    then {skip = "Antigravity does not expand {env:VAR} in command, args, url or headers";}
    else if forwarded == null
    then {skip = "env values must be a literal or \"{env:SAME_NAME}\" for Antigravity";}
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
