{
  description = "hello world application using uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        nixpkgs.follows = "nixpkgs";
      };
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      uv2nix,
      pyproject-build-systems,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems = lib.genAttrs lib.systems.flakeExposed;
      perSystem = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python312;
          uvLib = import ./nix/uvLib.nix {
            inherit
              pkgs
              uv2nix
              pyproject-nix
              pyproject-build-systems
              ;
          };
          imageLib = import ./nix/imageLib.nix { inherit pkgs uvLib; };
          cliLib = import ./nix/cliLib.nix { inherit self pkgs; };
          sharedArgs = {
            workspaceRoot = ./.;
            inherit python;
          };
          pythonSet = uvLib.mkPythonSet sharedArgs;
          virtualEnv-all = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "all";
              name = "holding-pattern-env-all";
            }
          );
          virtualEnv-default = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "default";
              name = "holding-pattern-env-default";
            }
          );
          virtualEnv-all-editable = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "all";
              useEditableOverlay = true;
              name = "holding-pattern-env-editable-all";
            }
          );
        in
        {
          inherit (imageLib)
            tgzToImage
            ;
          inherit (cliLib)
            xorq-nix-eval-raw
            xorq-docker-run-nix-build-tgz
            xorq-tgz-to-store
            xorq-tgzify-repo
            xorq-docker-volume-cat
            ;
          inherit
            pkgs
            python
            uvLib
            imageLib
            pythonSet
            virtualEnv-all
            virtualEnv-default
            virtualEnv-all-editable
            ;
        }
      );
    in
    {
      formatter = forAllSystems (system: perSystem.${system}.pkgs.nixfmt-tree);
      apps = forAllSystems (
        system: with perSystem.${system}; {
          python = {
            type = "app";
            program = "${virtualEnv-all}/bin/python";
          };
          celery = {
            type = "app";
            program = "${virtualEnv-all}/bin/celery";
          };
          flask = {
            type = "app";
            program = "${virtualEnv-all}/bin/flask";
          };
          default = self.apps.${system}.python;
        }
      );
      lib = forAllSystems (system: perSystem.${system});
      devShells = forAllSystems (
        system:
        with perSystem.${system};
        let
          commonArgs = {
            inherit pythonSet;
            otherPackages = [
              pkgs.redis
              xorq-nix-eval-raw
              xorq-docker-run-nix-build-tgz
              xorq-tgz-to-store
              xorq-tgzify-repo
              xorq-docker-volume-cat
            ];
          };
        in
        {
          editable = uvLib.mkUvShell (commonArgs // { virtualenv = virtualEnv-all-editable; });
          nonEditable = uvLib.mkUvShell (commonArgs // { virtualenv = virtualEnv-all; });
          default = self.devShells.${system}.editable;
        }
      );
      packages = forAllSystems (system: {
        inherit (perSystem.${system})
          tgzToDrv
          tgzToImage
          virtualEnv-all
          xorq-tgz-to-store
          xorq-docker-volume-cat
          ;
        default = self.packages.${system}.virtualEnv-all;
      });
    };
}
