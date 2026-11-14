#!/usr/bin/env bash
# Runs a Nix command for this repository, wherever it is built:
# - on an x86_64 Linux with Nix (the Yoga L13, under WSL2): Nix itself;
# - on the Mac, which has no Nix: the official nixos/nix container under
#   OrbStack (x86_64, through Rosetta), bounded (8 Go of memory, 6 processors).
# Never on the prodesk2021: a production server.
#
#   scripts/nix.sh build .#charpentier
#   scripts/nix.sh --out dist/installer build .#installer
#   scripts/nix.sh flake update charpentier     # move to the app's latest pushed commit
#   scripts/nix.sh --clean                      # give the disk back
#
# The app comes from GitHub (flake.nix). To try an app not pushed yet:
#   scripts/nix.sh build .#installer --override-input charpentier path:../charpentier-writer
# (in the container, the app's repository, CHARPENTIER_APP or ../charpentier-writer,
# is mounted read-only at ../charpentier-writer as well).
#
# `--out <path>`, first: after the command, copies `result` (dereferenced) to
# <path>, relative to this repository, writable.
#
# In the container: the Docker volume `charpentier-nix` keeps /nix between runs
# (10 to 15 Go at most); under Rosetta the kernel is aarch64 and Nix cannot load
# its x86_64 seccomp filter (« unable to load seccomp BPF program »), hence
# filter-syscalls false; the sandbox is off as well, the container is the boundary.
set -euo pipefail
cd "$(dirname "$0")/.."
here=$(pwd)

out=''
if [ "${1:-}" = '--out' ]; then
  out=$2
  shift 2
fi

# ─── Linux with Nix: directly ───
if [ "$(uname -s)" = Linux ] && command -v nix >/dev/null; then
  [ "$(uname -m)" = x86_64 ] || { echo "le X250 est en x86_64 : construisez sur une machine x86_64" >&2; exit 1; }
  if [ "${1:-}" = '--clean' ]; then
    rm -f result
    nix store gc
    exit 0
  fi
  nix --extra-experimental-features 'nix-command flakes' "$@"
  if [ -n "$out" ]; then
    # The store's files are read-only: the copy is made writable, so the next
    # run (or the author) can replace it.
    # (Under set -e: no copy yet on the first run, so chmod may fail.)
    chmod -R u+w "$out" 2>/dev/null || true
    rm -rf "$out"
    mkdir -p "$out"
    cp -rL result/. "$out/"
    chmod -R u+w "$out"
  fi
  exit 0
fi

# ─── The Mac: the container under OrbStack ───
image=nixos/nix:latest
volume=charpentier-nix
# OrbStack puts docker in ~/.orbstack/bin, on the PATH of shells opened after
# its first launch only.
command -v docker >/dev/null || PATH="$HOME/.orbstack/bin:$PATH"
command -v docker >/dev/null || {
  echo 'ni nix ni docker : sur le Mac, installez OrbStack (brew install orbstack), puis lancez-le' >&2
  exit 1
}

if [ "${1:-}" = '--clean' ]; then
  docker volume rm "$volume" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  echo "cache Nix et image supprimés"
  exit 0
fi

app_mount=()
app=${CHARPENTIER_APP:-../charpentier-writer}
[ -d "$app" ] && app_mount=(-v "$(cd "$app" && pwd):/src/charpentier-writer:ro")

args=$(printf ' %q' "$@")
copy=''
if [ -n "$out" ]; then
  dest=/src/charpentier-os/$(printf '%q' "$out")
  copy=" && { chmod -R u+w $dest 2>/dev/null; rm -rf $dest; } && mkdir -p $dest && cp -rL result/. $dest/ && chmod -R u+w $dest"
fi

docker run --rm --platform linux/amd64 --memory=8g --memory-swap=8g --cpus=6 \
  -v "$volume:/nix" \
  ${app_mount[@]+"${app_mount[@]}"} \
  -v "$here:/src/charpentier-os" \
  -w /src/charpentier-os \
  "$image" sh -c "git config --global --add safe.directory '*' && nix --extra-experimental-features 'nix-command flakes' --option sandbox false --option filter-syscalls false$args$copy"
