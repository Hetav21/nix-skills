# Build-time test for the npx bare `npx` commands resolve to (pkgs/npx).
{
  pkgs,
  npx,
}:
pkgs.runCommand "npx-tests" {} ''
  set -euo pipefail
  # Like an agent started outside a shell: a PATH without node
  if command -v node; then exit 1; fi
  export HOME=$PWD npm_config_update_notifier=false

  # A package bin with a node shebang (the sandbox has no /usr/bin/env)
  mkdir -p node_modules/.bin
  cat > node_modules/.bin/hello <<'EOF'
  #!${pkgs.coreutils}/bin/env node
  console.log("hello")
  EOF
  chmod +x node_modules/.bin/hello
  [ "$(${pkgs.lib.getExe npx} --offline hello)" = hello ]

  touch $out
''
