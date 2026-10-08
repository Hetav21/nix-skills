{
  description = "A decoupled library and Home Manager modules for managing skills and MCP servers across AI agents (Claude Code, OpenAI Codex, OpenCode, Antigravity).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: let
    lib = nixpkgs.lib;
    forAllSystems = lib.genAttrs ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
  in {
    lib = import ./lib { inherit lib; };
    homeManagerModules = {
      default = { imports = [ ./module.nix ./mcp-module.nix ]; };
      agent-skills = ./module.nix;
      agent-mcp = ./mcp-module.nix;
    };

    packages = forAllSystems (system: rec {
      agent-mcp = nixpkgs.legacyPackages.${system}.callPackage ./pkgs/agent-mcp {};
      default = agent-mcp;
    });

    checks = forAllSystems (system: {
      inherit (self.packages.${system}) agent-mcp;
      agent-mcp-merge = import ./tests/merge.nix {
        pkgs = nixpkgs.legacyPackages.${system};
        inherit (self.packages.${system}.agent-mcp) merge;
      };
      mcp-lib = import ./tests/mcp.nix {
        inherit lib;
        pkgs = nixpkgs.legacyPackages.${system};
      };
    });
  };
}
