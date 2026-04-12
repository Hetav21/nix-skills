{lib, ...}: rec {
  parseGithubUrl = url: let
    # Regex to match: https://github.com/Owner/Repo/blob/Ref/Path/To/File
    match = builtins.match "https?://github.com/([^/]+)/([^/]+)/(blob|tree)/([^/]+)/(.*)" url;
  in
    if match == null
    then null
    else {
      owner = builtins.elemAt match 0;
      repo = builtins.elemAt match 1;
      type = builtins.elemAt match 2; # blob or tree
      ref = builtins.elemAt match 3;
      path = builtins.elemAt match 4;
    };

  resolveSource = pkgs: inputs: urlStr: let
    parsed = parseGithubUrl urlStr;
  in
    if parsed == null
    then throw "Invalid GitHub URL: ${urlStr}"
    else let
      # Try to find input by Repo name first, then Owner-Repo
      inputName =
        if inputs ? "${parsed.repo}"
        then parsed.repo
        else if inputs ? "${parsed.owner}-${parsed.repo}"
        then "${parsed.owner}-${parsed.repo}"
        else throw "Input not found for ${parsed.owner}/${parsed.repo}. Checked '${parsed.repo}' and '${parsed.owner}-${parsed.repo}'. Please add it to your flake inputs: `inputs.${parsed.repo}.url = \"github:${parsed.owner}/${parsed.repo}\";`";

      src = inputs.${inputName};
    in
      extract pkgs src parsed.path {};

  # Helper to extract a subdirectory from a package with filtering
  # Usage: extract pkgs source "subdirectory" { includes = ["*"]; excludes = []; }
  extract = pkgs: src: path: {
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
  in
    pkgs.runCommand "extract-${builtins.replaceStrings ["/"] ["-"] path}" {nativeBuildInputs = [pkgs.rsync];} ''
      mkdir -p $out
      if [ -d "${src}/${path}" ]; then
        rsync -av --copy-links ${argsStr} "${src}/${path}/" "$out/"
      elif [ -f "${src}/${path}" ]; then
        cp -a "${src}/${path}" "$out/"
      else
        echo "Warning: ${path} not found in ${src}"
      fi
    '';

  # Flattens a directory of skills based on SKILL.md presence
  # Recursively finds directories containing SKILL.md and moves them to root with flattened names (path/to/skill -> path-to-skill)
  flattenSkills = pkgs: src:
    pkgs.runCommand "flatten-skills" {nativeBuildInputs = [pkgs.rsync];} ''
      mkdir -p $out

      # Find directories containing SKILL.md, excluding hidden directories
      find "${src}" -name "SKILL.md" -not -path '*/.*' -printf "%h\n" | sort -u | while read -r skill_dir; do
        # Calculate relative path
        rel_path="''${skill_dir#${src}}"
        rel_path="''${rel_path#/}" # Remove leading slash

        if [ -z "$rel_path" ]; then
           flat_name="root"
        else
           # Replace / with -
           flat_name="''${rel_path//\//-}"
        fi

        echo "Flattening: $rel_path -> $flat_name"
        mkdir -p "$out/$flat_name"
        rsync -a --copy-links "$skill_dir/" "$out/$flat_name/"
      done
    '';

  # Helper to merge directories with priority (Last item in list = Highest Priority)
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

  buildAssets = {
    pkgs,
    inputs ? null,
    skills ? [],
    agents ? [],
    commands ? [],
    hooks ? [],
  }: let
    resolveMaybe = item:
      if (builtins.isString item) && (lib.hasPrefix "http" item) && (inputs != null)
      then resolveSource pkgs inputs item
      else item;

    resolvedSkills = map resolveMaybe skills;
    resolvedAgents = map resolveMaybe agents;
    resolvedCommands = map resolveMaybe commands;
    resolvedHooks = map resolveMaybe hooks;

    flattenedSkills = map (s: flattenSkills pkgs s) resolvedSkills;

    skillsMerged = merge pkgs "claude-skills" flattenedSkills;
    agentsMerged = merge pkgs "claude-agents" resolvedAgents;
    commandsMerged = merge pkgs "claude-commands" resolvedCommands;
    hooksMerged = merge pkgs "claude-hooks" resolvedHooks;
  in
    pkgs.runCommand "claude-assets" {} ''
      mkdir -p $out/skills $out/agents $out/commands $out/hooks

      echo "Copying skills..."
      cp -a "${skillsMerged}/." "$out/skills/"
      echo "Copying agents..."
      cp -a "${agentsMerged}/." "$out/agents/"
      echo "Copying commands..."
      cp -a "${commandsMerged}/." "$out/commands/"
      echo "Copying hooks..."
      cp -a "${hooksMerged}/." "$out/hooks/"
      chmod -R u+w "$out"
    '';

  mkProjectEnv = {
    pkgs,
    inputs ? null,
    skills ? [],
    agents ? [],
    commands ? [],
    hooks ? [],
    ...
  } @ args: let
    assets = buildAssets {inherit pkgs inputs skills agents commands hooks;};
    shellArgs = builtins.removeAttrs args ["pkgs" "inputs" "skills" "agents" "commands" "hooks"];
  in
    pkgs.mkShell (shellArgs
      // {
        shellHook =
          (args.shellHook or "")
          + ''

            # Claude Project Bootstrap
            mkdir -p .claude
            cp -rn ${assets}/* ./.claude/
            chmod -R u+w ./.claude
          '';
      });

  # Creates the ~/.claude environment by merging sources
  mkEnvironment = pkgs: {
    inputs ? null,
    skills ? [],
    commands ? [],
    agents ? [],
    hooks ? [],
  }: let
    assets = buildAssets {inherit pkgs inputs skills agents commands hooks;};
  in {
    ".claude/skills".source = "${assets}/skills";
    ".claude/commands".source = "${assets}/commands";
    ".claude/agents".source = "${assets}/agents";
    ".claude/hooks".source = "${assets}/hooks";
  };
}
