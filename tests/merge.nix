# Build-time tests for agent-mcp-merge (pkgs/agent-mcp/merge.py).
{
  pkgs,
  merge,
}:
pkgs.runCommand "agent-mcp-merge-tests" {nativeBuildInputs = [merge pkgs.jq];} ''
  set -euo pipefail
  # `! cmd` never trips `set -e`, so negative assertions go through this
  fails() { if "$@"; then echo "expected failure: $*" >&2; return 1; fi; }
  echo '{"new": {"command": "new"}, "kept": {"command": "kept-v2"}}' > servers.json

  # TOML with state: managed servers replaced/pruned, everything else kept
  cat > config.toml <<'EOF'
  # my codex config
  model = "gpt-6" # inline comment

  [mcp_servers.mine]
  command = "mine"

  [mcp_servers.stale]
  command = "stale"

  [mcp_servers.kept]
  command = "kept-v1"
  EOF
  echo '["stale", "kept"]' > state.json
  agent-mcp-merge config.toml mcp_servers servers.json state.json
  grep -q '^# my codex config$' config.toml
  grep -q '^model = "gpt-6" # inline comment$' config.toml
  grep -q '^\[mcp_servers.mine\]$' config.toml
  fails grep -q stale config.toml
  grep -q 'command = "kept-v2"' config.toml
  grep -q '^\[mcp_servers.new\]$' config.toml
  [ "$(jq -c . state.json)" = '["kept","new"]' ]

  # No servers with state (target turned off): managed servers removed, others kept
  echo '{"mcpServers": {"mine": {}, "kept": {}}}' > off.json
  echo '["kept"]' > off-state.json
  echo '{}' > none.json
  agent-mcp-merge off.json mcpServers none.json off-state.json
  [ "$(jq -c .mcpServers off.json)" = '{"mine":{}}' ]

  # JSON without state: the key is replaced entirely, other keys kept
  echo '{"model": "x", "mcp": {"old": {}}}' > opencode.json
  chmod 600 opencode.json
  agent-mcp-merge opencode.json mcp servers.json
  [ "$(jq -c . opencode.json)" = '{"model":"x","mcp":{"new":{"command":"new"},"kept":{"command":"kept-v2"}}}' ]
  [ "$(stat -c %a opencode.json)" = 600 ]

  # Missing file and parent directory are created
  agent-mcp-merge sub/dir/.mcp.json mcpServers servers.json
  [ "$(jq -c '.mcpServers | keys' sub/dir/.mcp.json)" = '["kept","new"]' ]

  # A symlinked file is updated through the link
  echo '{"other": 1}' > real.json
  ln -s real.json link.json
  agent-mcp-merge link.json mcpServers servers.json
  [ -L link.json ]
  [ "$(jq -c '[.other, (.mcpServers | keys)]' real.json)" = '[1,["kept","new"]]' ]

  # Unwritable target (e.g. a stale store symlink): non-zero exit, no traceback
  mkdir ro && echo '{}' > ro/c.json && chmod 555 ro && chmod 444 ro/c.json
  fails agent-mcp-merge ro/c.json mcpServers servers.json 2> err
  grep -q '^agent-mcp-merge: ' err

  # Unparseable file: non-zero exit, file untouched
  echo '{broken' > broken.json
  fails agent-mcp-merge broken.json mcpServers servers.json 2>/dev/null
  [ "$(cat broken.json)" = '{broken' ]

  touch $out
''
