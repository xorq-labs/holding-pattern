{
  description = "hello world application using uv2nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
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
          uvLib = import ./nix/uvLib.nix {
            inherit
              pkgs
              uv2nix
              pyproject-nix
              pyproject-build-systems
              ;
          };
          python = pkgs.python312;
          sharedArgs = {
            workspaceRoot = ./.;
            inherit python;
          };
          pythonSet = uvLib.mkPythonSet sharedArgs;
          virtualenv-all = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "all";
              name = "holding-pattern-env-all";
            }
          );
          virtualenv-default = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "default";
              name = "holding-pattern-env-default";
            }
          );
          virtualenv-all-editable = uvLib.mkVirtualEnv (
            sharedArgs
            // {
              which-deps = "all";
              useEditableOverlay = true;
              name = "holding-pattern-env-editable-all";
            }
          );
        in
        {
          inherit
            pkgs
            python
            uvLib
            pythonSet
            virtualenv-all
            virtualenv-default
            virtualenv-all-editable
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
            program = "${virtualenv-all}/bin/python";
          };
          celery = {
            type = "app";
            program = "${virtualenv-all}/bin/celery";
          };
          flask = {
            type = "app";
            program = "${virtualenv-all}/bin/flask";
          };
          default = self.apps.${system}.python;
        }
      );
      lib = forAllSystems (system: perSystem.${system});
      devShells = forAllSystems (
        system: with perSystem.${system}; {
          nonEditable = uvLib.mkUvShell {
            virtualenv = virtualenv-all;
            inherit pythonSet;
          };
          editable = uvLib.mkUvShell {
            virtualenv = virtualenv-all-editable;
            inherit pythonSet;
          };
          default = self.devShells.${system}.editable;
        }
      );
      packages = forAllSystems (
        system: with perSystem.${system}; {
          inherit
            virtualenv-all
            virtualenv-default
            virtualenv-all-editable
            ;
          default = virtualenv-default;
        }
      );
    };
}
