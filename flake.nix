{
  description = "Headless Helium with Chrome DevTools Protocol";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    nur-packages.url = "github:9bingyin/nur-packages";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        {
          config,
          pkgs,
          ...
        }:
        {
          packages.image = pkgs.callPackage ./nix/image.nix {
            inherit pkgs;
            helium = inputs.nur-packages.packages.${pkgs.stdenv.hostPlatform.system}.helium-bin;
          };
          packages.default = config.packages.image;

          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt.enable = true;
          };

          devShells.default = pkgs.mkShell {
            packages = [
              pkgs.bun
              config.treefmt.build.wrapper
            ];
          };
        };
    };
}
