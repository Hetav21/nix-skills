{lib, ...}: rec {
  # Internal extraction worker with include/exclude filters
  extractInternal = pkgs: src: path: {
    includes ? [],
    excludes ? [],
  } @ args: let
    inc =
      if args ? includes
      then args.includes
      else ["*"];
    exc =
      if args ? excludes
      then args.excludes
      else [];
    isSelectMode = inc != [] && inc != ["*"];

    excludeArgs = map (x: "--exclude='${x}'") exc;
    includeArgs = map (x: "--include='${x}' --include='${x}/**'") inc;

    finalArgs =
      excludeArgs
      ++ includeArgs
      ++ (
        if isSelectMode
        then ["--exclude='*'"]
        else []
      );
    argsStr = builtins.concatStringsSep " " finalArgs;
    safePathName = builtins.replaceStrings ["/"] ["-"] path;
  in
    pkgs.runCommand "extract-${safePathName}" {nativeBuildInputs = [pkgs.rsync];} ''
      mkdir -p $out
      if [ -d "${src}/${path}" ]; then
        rsync -av --copy-links ${argsStr} "${src}/${path}/" "$out/"
      elif [ -f "${src}/${path}" ]; then
        cp -a "${src}/${path}" "$out/"
      elif [ -d "${src}" ] && [ "${path}" = "" -o "${path}" = "." ]; then
        rsync -av --copy-links ${argsStr} "${src}/" "$out/"
      else
        echo "Warning: ${path} not found in ${src}"
      fi
    '';

  # Extract a subdirectory or filtered subset from a package.
  # Polymorphic usage:
  #   extract pkgs src "skills" { includes = ["..."]; }       (positional / legacy)
  #   extract pkgs { source = src; includes = ["..."]; }       (attrset)
  extract = pkgs: a:
    if builtins.isAttrs a && !(a ? type && a.type == "derivation") && (a ? source)
    then
      extractInternal pkgs a.source (a.path or "skills") {
        includes = a.includes or [];
        excludes = a.excludes or [];
      }
    else
      path: args:
        extractInternal pkgs a path args;

  # Flattens a directory of skills based on SKILL.md presence.
  # Recursively finds directories containing SKILL.md and moves them to root
  # with skill directory basenames. Excludes hidden directories.
  flattenSkills = pkgs: src:
    pkgs.runCommand "flatten-skills" {nativeBuildInputs = [pkgs.rsync];} ''
      mkdir -p $out

      # Find directories containing SKILL.md, excluding hidden directories
      find "${src}" -name "SKILL.md" -not -path '*/.*' -printf "%h\n" | sort -u | while read -r skill_dir; do
        skill_name="$(basename "$skill_dir")"
        if [ "$skill_dir" = "${src}" ] || [ -z "$skill_name" ]; then
           flat_name="root"
        else
           flat_name="$skill_name"
        fi

        if [ -e "$out/$flat_name" ]; then
          echo "error: duplicate skill name '$flat_name' in ${src} ($skill_dir)" >&2
          exit 1
        fi

        echo "Flattening: $skill_dir -> $flat_name"
        mkdir -p "$out/$flat_name"
        rsync -a --copy-links "$skill_dir/" "$out/$flat_name/"
      done
    '';

  # Helper to merge directories with priority (later item in list = higher priority)
  merge = pkgs: name: paths:
    pkgs.runCommand name {} ''
      mkdir -p $out
      ${lib.concatMapStringsSep "\n" (p: ''
          echo "Merging ${p}..."
          if [ -d "${p}" ]; then
            cp -a "${p}/." "$out/"
          else
            cp -a "${p}" "$out/"
          fi
          chmod -R u+w "$out/"
        '')
        paths}
    '';

  # Builds a consolidated skills directory from a list of skill packages or specs.
  # Each entry can be:
  #   - A package / derivation: auto-flattened recursively by finding SKILL.md
  #   - An attrset with `{ source, path ? "skills", includes ? [], excludes ? [] }`
  buildSkills = pkgs: skillsList:
    let
      processItem = item:
        if builtins.isAttrs item && !(item ? type && item.type == "derivation") && (item ? source)
        then
          let
            path = item.path or "skills";
            extracted = extractInternal pkgs item.source path {
              includes = item.includes or [];
              excludes = item.excludes or [];
            };
          in
            flattenSkills pkgs extracted
        else
          flattenSkills pkgs item;

      flattened = map processItem skillsList;
    in
      merge pkgs "agent-skills" flattened;

  # Legacy alias for backward compatibility
  buildAssets = {
    pkgs,
    skills ? [],
    ...
  }:
    pkgs.runCommand "agents-assets" {} ''
      mkdir -p $out/skills $out/agents $out/commands $out/hooks
      cp -a "${buildSkills pkgs skills}/." "$out/skills/"
      chmod -R u+w "$out"
    '';

  # Creates agent environments across target directories (.agents/skills, .claude/skills, .codex/skills, .gemini/skills)
  mkEnvironment = pkgs: {
    skills ? [],
    targets ? {
      agents = true;
      claude = true;
      codex = true;
      gemini = true;
    },
    ...
  }: let
    skillsPkg = buildSkills pkgs skills;
    activeTargets = {
      agents = targets.agents or true;
      claude = targets.claude or true;
      codex = targets.codex or true;
      gemini = targets.gemini or true;
    };
  in
    lib.mkMerge [
      (lib.mkIf activeTargets.agents {
        ".agents/skills" = {
          source = "${skillsPkg}";
          recursive = true;
        };
      })
      (lib.mkIf activeTargets.claude {
        ".claude/skills" = {
          source = "${skillsPkg}";
          recursive = true;
        };
      })
      (lib.mkIf activeTargets.codex {
        ".codex/skills" = {
          source = "${skillsPkg}";
          recursive = true;
        };
      })
      (lib.mkIf activeTargets.gemini {
        ".gemini/skills" = {
          source = "${skillsPkg}";
          recursive = true;
        };
        ".gemini/antigravity-cli/skills" = {
          source = "${skillsPkg}";
          recursive = true;
        };
      })
    ];

  # Curried helper bound to a pkgs instance
  withPkgs = pkgs: {
    extract = extract pkgs;
    flattenSkills = flattenSkills pkgs;
    buildSkills = buildSkills pkgs;
    mkEnvironment = args: mkEnvironment pkgs args;
  };

  # Renders one canonical `mcpServers` attrset for Claude Code, OpenCode, Codex
  # and Antigravity (see ./mcp.nix)
  mcp = import ./mcp.nix {inherit lib;};

  # Converts an opencode-style `mcpServers` attrset to Claude Code format
  toClaudeMcpServers = mcpServers: let
    toClaudeServer = server:
      if server ? command
      then let
        cmd = server.command;
        isList = builtins.isList cmd;
        base = removeAttrs server ["type" "command" "environment"];
      in
        base
        // {
          type = "stdio";
          command = if isList then builtins.head cmd else cmd;
          args = (if isList then builtins.tail cmd else []) ++ (server.args or []);
        }
        // lib.optionalAttrs (server ? environment) {env = server.environment;}
      else if (server.type or null) == "remote"
      then (removeAttrs server ["type"]) // {type = "http";}
      else if server ? url && !(server ? type)
      then server // {type = "http";}
      else server;
  in
    lib.mapAttrs (_: toClaudeServer) mcpServers;
}
