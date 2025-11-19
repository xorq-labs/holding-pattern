{
  pkgs,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
let
  nopOverrides = addResolvedMatrix {
    hatchling = [ "xorq" ];
  };
  addNativeBuildInputs =
    drvs:
    (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ drvs;
    });
  addBuildInputs = drvs: old: {
    buildInputs = (old.buildInputs or [ ]) ++ drvs;
  };
  addResolved =
    final: names:
    (old: {
      nativeBuildInputs =
        (old.nativeBuildInputs or [ ])
        ++ final.resolveBuildSystem (
          pkgs.lib.listToAttrs (map (name: pkgs.lib.nameValuePair name [ ]) names)
        );
    });
  addResolvedMulti =
    toAdd: addTos: final: prev:
    let
      f = name: pkgs.lib.nameValuePair name (prev.${name}.overrideAttrs (addResolved final [ toAdd ]));
      pyprojectOverrides = builtins.listToAttrs (map f addTos);
    in
    pyprojectOverrides;
  addResolvedMatrix =
    attrs:
    let
      newAttrs = builtins.attrValues (builtins.mapAttrs addResolvedMulti attrs);
      pyprojectOverrides = pkgs.lib.composeManyExtensions newAttrs;
    in
    pyprojectOverrides;

  tgzToDrv =
    { src }:
    pkgs.stdenv.mkDerivation {
      name = "my-source-drv";
      inherit src;
      phases = [ "installPhase" ];
      installPhase = ''
        mkdir -p "$out"
        tar -C "$out" --extract --gunzip --strip-components 1 --file "$src"
      '';
    };

  mkPythonSet =
    {
      workspaceRoot,
      resolvedMatrix ? { },
      otherOverrides ? nopOverrides,
      python ? pkgs.python312,
      useWheelOverlay ? true,
      useEditableOverlay ? false,
    }:
    let
      workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
      wheelOverlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
      editableOverlay = workspace.mkEditablePyprojectOverlay {
        root = "$REPO_ROOT";
      };
      pythonSet =
        # Use base package set from pyproject.nix builders
        (pkgs.callPackage pyproject-nix.build.packages {
          inherit python;
        }).overrideScope
          (
            pkgs.lib.composeManyExtensions (
              [
                pyproject-build-systems.overlays.default
              ]
              ++ (pkgs.lib.optionals useWheelOverlay [ wheelOverlay ])
              ++ (pkgs.lib.optionals useEditableOverlay [ editableOverlay ])
              ++ [
                (addResolvedMatrix resolvedMatrix)
                otherOverrides
              ]
            )
          );
    in
    pythonSet;

  mkVirtualEnv =
    {
      workspaceRoot,
      resolvedMatrix ? { },
      otherOverrides ? nopOverrides,
      which-deps ? "all",
      python ? pkgs.python312,
      useWheelOverlay ? true,
      useEditableOverlay ? false,
      name ? "venv-${which-deps}",
    }:
    let
      pythonSet = mkPythonSet {
        inherit
          workspaceRoot
          resolvedMatrix
          otherOverrides
          python
          useWheelOverlay
          useEditableOverlay
          ;
      };
      workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
      virtualEnv = pythonSet.mkVirtualEnv name workspace.deps.${which-deps};
    in
    virtualEnv;
  mkUvShell = {
    virtualenv,
    pythonSet,
    otherPackages ? [ ],
  }:
  let
    uvShell = pkgs.mkShell {
      packages = [
        virtualenv
        pkgs.uv
      ] ++ otherPackages;
      env = {
        UV_NO_SYNC = "1";
        UV_PYTHON = pythonSet.python.interpreter;
        UV_PYTHON_DOWNLOADS = "never";
      };
      shellHook = ''
        unset PYTHONPATH
        export REPO_ROOT=$(git rev-parse --show-toplevel)
      '';
    };
  in
  uvShell;
in
{
  inherit
    nopOverrides
    addNativeBuildInputs
    addBuildInputs
    addResolved
    addResolvedMulti
    addResolvedMatrix
    tgzToDrv
    mkPythonSet
    mkVirtualEnv
    mkUvShell
    ;
}
