{ pkgs, uvLib }:
let

  default-resolvedMatrix = {
    hatchling = [
      "hash-cache"
      "hn-fetcher"
      "xorq"
      "xorq-feature-utils"
      "xorq-weather-lib"
    ];
  };

  drvToImage =
    {
      drv,
      name ? "drvToImage-${drv.name}-image",
      copyToRoot-extraPaths ? [
        pkgs.bashInteractive
        pkgs.coreutils
        pkgs.findutils
      ],
      copyToRoot-pathsToLink ? [ "/bin" ],
      config-workingDir ? "/work",
      config-env ? [ ],
    }:
    pkgs.dockerTools.buildImage {
      inherit name;
      copyToRoot = pkgs.buildEnv {
        name = "drvToImage-${drv.name}-env";
        paths = [ drv ] ++ copyToRoot-extraPaths;
        pathsToLink = copyToRoot-pathsToLink;
      };
      config = {
        WorkingDir = config-workingDir;
        Cmd = [ "xorq" ];
        Env = config-env;
      };
    };

  tgzToImage =
    {
      tgz,
      resolvedMatrix ? default-resolvedMatrix,
      otherOverrides ? uvLib.nopOverrides,
    }:
    drvToImage {
      drv = uvLib.mkVirtualEnv {
        workspaceRoot = uvLib.tgzToDrv { src = tgz; };
        inherit resolvedMatrix otherOverrides;
      };
    };

in
{
  inherit
    drvToImage
    tgzToImage
    default-resolvedMatrix
    ;
}
