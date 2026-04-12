{
  description = "A decoupled library for setting up Claude skills and agents in Nix flakes.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }: let
    lib = nixpkgs.lib;
  in {
    lib = import ./lib { inherit lib; };
  };
}
