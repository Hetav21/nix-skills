# The npx a bare `npx` command resolves to. Nearly every npm package's bin
# starts with `#!/usr/bin/env node`, so node must be on PATH as well as npx,
# or the server exits at once and the agent only reports a connect timeout.
{
  lib,
  writeShellScriptBin,
  nodejs,
}:
writeShellScriptBin "npx" ''
  PATH=${lib.makeBinPath [nodejs]}''${PATH:+:$PATH} exec ${lib.getExe' nodejs "npx"} "$@"
''
