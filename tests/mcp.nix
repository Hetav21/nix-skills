# Eval-time tests for lib/mcp.nix; the check fails to evaluate on any mismatch.
{
  lib,
  pkgs,
}: let
  mcp = import ../lib/mcp.nix {inherit lib;};
  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;

  servers = {
    grep.url = "https://mcp.grep.app";
    context7 = {
      url = "https://mcp.context7.com/mcp";
      headers.CONTEXT7_API_KEY = "\${CONTEXT7_API_KEY}";
    };
    github = {
      url = "https://api.example.com/mcp";
      headers = {
        Authorization = "Bearer \${GH_TOKEN}";
        X-Static = "v1";
      };
    };
    legacy = {
      type = "sse";
      url = "https://old.example.com/sse";
    };
    playwright = {
      command = "bunx";
      args = ["-y" "@playwright/mcp@latest"];
      disabled = true;
    };
    db = {
      command = "dbhub";
      env = {
        DATABASE_URL = "\${DATABASE_URL}";
        MODE = "ro";
      };
    };
    tokenArg = {
      command = "tool";
      args = ["--token" "\${TOKEN}"];
    };
  };
  r = mcp.render servers;

  failures = lib.runTests {
    testClaudeRemote = {
      expr = r.claude.context7;
      expected = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
        headers.CONTEXT7_API_KEY = "\${CONTEXT7_API_KEY}";
      };
    };
    testClaudeKeepsSse = {
      expr = r.claude.legacy.type;
      expected = "sse";
    };
    testClaudeStdio = {
      expr = r.claude.tokenArg;
      expected = {
        type = "stdio";
        command = "tool";
        args = ["--token" "\${TOKEN}"];
      };
    };
    testClaudeOmitsDisabled = {
      expr = r.claude ? playwright;
      expected = false;
    };

    testOpencodeLocal = {
      expr = r.opencode.db;
      expected = {
        type = "local";
        command = ["dbhub"];
        environment = {
          DATABASE_URL = "{env:DATABASE_URL}";
          MODE = "ro";
        };
        enabled = true;
      };
    };
    testOpencodeRemoteRefs = {
      expr = r.opencode.github.headers.Authorization;
      expected = "Bearer {env:GH_TOKEN}";
    };
    testOpencodeDisabled = {
      expr = r.opencode.playwright.enabled;
      expected = false;
    };

    testCodexHeaderRefs = {
      expr = [r.codex.context7 r.codex.github];
      expected = [
        {
          url = "https://mcp.context7.com/mcp";
          env_http_headers.CONTEXT7_API_KEY = "CONTEXT7_API_KEY";
          enabled = true;
        }
        {
          url = "https://api.example.com/mcp";
          bearer_token_env_var = "GH_TOKEN";
          http_headers.X-Static = "v1";
          enabled = true;
        }
      ];
    };
    testCodexEnvVars = {
      expr = r.codex.db;
      expected = {
        command = "dbhub";
        env.MODE = "ro";
        env_vars = ["DATABASE_URL"];
        enabled = true;
      };
    };
    testCodexSkipsUnsupported = {
      expr = builtins.attrNames r.codex;
      expected = ["context7" "db" "github" "grep" "playwright"];
    };

    testAntigravityStdioInheritsEnv = {
      expr = r.antigravity.db;
      expected = {
        command = "dbhub";
        env.MODE = "ro";
        disabled = false;
      };
    };
    testAntigravityRemote = {
      expr = r.antigravity.grep;
      expected = {
        serverUrl = "https://mcp.grep.app";
        disabled = false;
      };
    };
    testAntigravitySkipsUnsupported = {
      expr = builtins.attrNames r.antigravity;
      expected = ["db" "grep" "playwright"];
    };

    testRejectsUnknownKey = {
      expr = throws (mcp.toClaude {
        x = {
          url = "u";
          enabled = false;
        };
      });
      expected = true;
    };
    testRejectsCommandAndUrl = {
      expr = throws (mcp.toClaude {
        x = {
          url = "u";
          command = "c";
        };
      });
      expected = true;
    };
    testRejectsTypeMismatch = {
      expr = throws (mcp.toClaude {
        x = {
          type = "stdio";
          url = "u";
        };
      });
      expected = true;
    };
    testRejectsHeadersOnStdio = {
      expr = throws (mcp.toClaude {
        x = {
          command = "c";
          headers.A = "b";
        };
      });
      expected = true;
    };
  };
in
  if failures == []
  then pkgs.runCommand "mcp-lib-tests" {} "touch $out"
  else throw "lib/mcp.nix tests failed:\n${lib.generators.toPretty {} failures}"
