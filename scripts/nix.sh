#!/usr/bin/env bash
# Runs a Nix command on this Mac, in the official nixos/nix container under
# OrbStack (x86_64, through Rosetta): the Mac has no Nix, and the X250 is an
# x86_64 machine. Nothing is installed on the Mac but OrbStack.
#
#   scripts/nix.sh build .#charpentier
#   scripts/nix.sh --out dist/installer build .#installer
#   scripts/nix.sh flake update charpentier     # move to the app's latest commit
#   scripts/nix.sh --clean                      # give the disk back
#
# The app's repository (CHARPENTIER_APP, by default ../charpentier-writer) is
# mounted read-only at /src/charpentier-writer, where flake.nix expects it; this
# one at /src/charpentier-os, so that flake.lock is written in place. The Docker
# volume `charpentier-nix` keeps /nix between runs: 10 to 15 Go at most, on the
# Mac's internal disk; `--clean` removes it (the next run downloads it again).
# The container is bounded (8 Go of memory, 6 processors): the Mac stays usable.
#
# Under Rosetta the kernel is aarch64: Nix cannot load its x86_64 seccomp
# filter (« unable to load seccomp BPF program »), hence filter-syscalls false;
# the sandbox is off as well, the container is the boundary.
#
# `--out <path>`, first: after the command, copies `result` (dereferenced) to
# <path>, relative to this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
here=$(pwd)
app=$(cd "${CHARPENTIER_APP:-../charpentier-writer}" && pwd)
image=nixos/nix:latest
volume=charpentier-nix

# OrbStack puts docker in ~/.orbstack/bin, on the PATH of shells opened after
# its first launch only.
command -v docker >/dev/null || PATH="$HOME/.orbstack/bin:$PATH"
command -v docker >/dev/null || {
  echo 'docker introuvable : installez OrbStack (brew install orbstack), puis lancez-le' >&2
  exit 1
}

if [ "${1:-}" = '--clean' ]; then
  docker volume rm "$volume" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  echo "cache Nix et image supprimés"
  exit 0
fi

out=''
if [ "${1:-}" = '--out' ]; then
  out=$2
  shift 2
fi

args=$(printf ' %q' "$@")
copy=''
if [ -n "$out" ]; then
  copy=" && rm -rf /src/charpentier-os/$(printf '%q' "$out") && mkdir -p /src/charpentier-os/$(printf '%q' "$out") && cp -rL result/. /src/charpentier-os/$(printf '%q' "$out")/"
fi

docker run --rm --platform linux/amd64 --memory=8g --memory-swap=8g --cpus=6 \
  -v "$volume:/nix" \
  -v "$app:/src/charpentier-writer:ro" \
  -v "$here:/src/charpentier-os" \
  -w /src/charpentier-os \
  "$image" sh -c "git config --global --add safe.directory '*' && nix --extra-experimental-features 'nix-command flakes' --option sandbox false --option filter-syscalls false$args$copy"
