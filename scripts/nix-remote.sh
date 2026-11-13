#!/usr/bin/env bash
# Runs a Nix command on the Linux build machine (docs/PLAN.md phases 5.8 to
# 5.9 bis): the Mac has no Nix. The working tree (tracked and new files, not
# the ignored ones) is copied to the builder, and Nix runs there in the
# official nixos/nix container; the Docker volume `charpentier-nix` keeps /nix
# between runs. Nothing is installed on the builder itself, and the container
# is bounded (8 Go of memory, 2 processors, low priority): the builder also
# serves the sync server and other services.
#
#   CHARPENTIER_BUILDER=prodesk2021.local scripts/nix-remote.sh build .#charpentier
#
# `--out <path>`, first: after the command, copies `result` (dereferenced) to
# <path> on the Mac.
set -euo pipefail
host=${CHARPENTIER_BUILDER:?Set CHARPENTIER_BUILDER to the build machine (ssh host)}
cd "$(dirname "$0")/.."
out=''
if [ "${1:-}" = '--out' ]; then
  out=$2
  shift 2
fi

git ls-files -co --exclude-standard -z |
  COPYFILE_DISABLE=1 tar --null -T - -cf - |
  ssh "$host" 'rm -rf ~/charpentier-build/src && mkdir -p ~/charpentier-build/src && tar -xf - -C ~/charpentier-build/src'

args=$(printf ' %q' "$@")
# Bounded: the builder is someone's computer, it must stay usable.
ssh "$host" "docker run --rm --memory=8g --memory-swap=8g --cpus=2 --cpu-shares=256 -v charpentier-nix:/nix -v \$HOME/charpentier-build:/build -w /build/src \
  nixos/nix:latest sh -c $(printf '%q' "git config --global --add safe.directory '*' 2>/dev/null; nix --extra-experimental-features 'nix-command flakes' --option sandbox false$args && { [ ! -e result ] || { rm -rf /build/result && cp -rL result /build/result; }; }")"

# The versions Nix chose stay pinned in the repository.
scp -q "$host:charpentier-build/src/flake.lock" flake.lock 2>/dev/null || true

if [ -n "$out" ]; then
  mkdir -p "$out"
  rsync -a --delete "$host:charpentier-build/result/" "$out/"
fi
