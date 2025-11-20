{ self, pkgs }:
let
  xorq-nix-eval-raw = pkgs.writeShellScriptBin "nix-eval-raw" ''
    set -eux

    attr=$1
    shift 1

    ${pkgs.nix}/bin/nix eval "''${@}" --raw "${self}#$attr"
  '';

  xorq-tgz-to-store = pkgs.writeShellScriptBin "xorq-tgz-to-store" ''
    set -eux

    tgz=$1

    ${pkgs.nix}/bin/nix build \
      --no-link --print-out-paths \
      ${self}/default.nix#tgzToDrv \
      --arg src "$tgz"
  '';

  xorq-docker-run-nix-build-tgz = pkgs.writeShellScriptBin "xorq-docker-run-nix-build-tgz" ''
    set -eux

    tgz=$1
    root_cache_volume=''${2:-nixpkgs-cachix-root-cache}
    nix_volume=''${3:-nixpkgs-cachix-nix}

    # we need a path, not "just" a filename
    tgz_path=$(realpath "$tgz")

    ${pkgs.docker}/bin/docker volume create "$root_cache_volume" >/dev/null
    ${pkgs.docker}/bin/docker volume create "$nix_volume" >/dev/null
    ${pkgs.docker}/bin/docker run \
      --volume "$tgz_path":/work/tgz \
      --volume "${self}/nix.conf":/root/.config/nix/nix.conf \
      --volume "$root_cache_volume":/root/.cache \
      --volume "$nix_volume":/nix \
      --volume "${self}":/work/self \
      nixpkgs/nix \
      bash -c "nix build --no-link --print-out-paths --arg tgz /work/tgz --file /work/self/default.nix packages.x86_64-linux.tgzToImage"
  '';

  xorq-docker-volume-cat = pkgs.writeShellScriptBin "xorq-docker-volume-cat" ''
    set -eux

    from_path=$1
    root_cache_volume=''${2:-nixpkgs-cachix-root-cache}
    nix_volume=''${3:-nixpkgs-cachix-nix}

    ${pkgs.docker}/bin/docker run \
      --volume "$root_cache_volume":/root/.cache \
      --volume "$nix_volume":/nix \
      nixpkgs/cachix \
      cat "$from_path"
  '';

  xorq-tgzify-repo = pkgs.writeShellScriptBin "xorq-tgzify-repo" ''
    set -eux

    repo_path=$1
    ref=''${2:-HEAD}
    tgz_name=''${3:-$(basename "$repo_path").tar.gz}

    tgz_path=$(pwd)/$tgz_name
    git -C "$repo_path" archive --prefix=$(basename "$repo_path")/ --output="$tgz_path" "$ref"
    echo "$tgz_path"
  '';

in
{
  inherit
    xorq-nix-eval-raw
    xorq-tgz-to-store
    xorq-docker-run-nix-build-tgz
    xorq-docker-volume-cat
    xorq-tgzify-repo
    ;
}
