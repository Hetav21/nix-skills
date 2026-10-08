{
  description = "A decoupled library and Home Manager module for managing skills across AI agents (Claude Code, OpenAI Codex, OpenCode, Antigravity).";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: let
    lib = nixpkgs.lib;
  in {
    lib = import ./lib { inherit lib; };
    homeManagerModules.default = ./module.nix;
    homeManagerModules.agent-skills = ./module.nix;
  };
}
