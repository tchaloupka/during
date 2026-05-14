{
  description = "DPDK D development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?rev=549bd84d6279f9852cae6225e372cc67fb91a4c1";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    systems.url = "github:nix-systems/triplet";
  };
  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;
      perSystem =
        { config, pkgs, ... }:
        {
          devShells.default = pkgs.mkShell {
            packages = [
              # D toolchain
              pkgs.ldc
              pkgs.dub
              pkgs.dtools
            ];
          };
        };
    };
}
