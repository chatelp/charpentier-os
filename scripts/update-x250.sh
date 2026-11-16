#!/usr/bin/env bash
# update-x250.sh [--boot] [--app <ref>] <host> : updates a development X250
# (or its VM) from this checkout, over SSH, from the home network (docs/PLAN.md
# phase 5.10).
#   scripts/update-x250.sh 192.168.1.42
#   NIX_SSHOPTS="-p 2222" scripts/update-x250.sh localhost      # the VM
# Only the development variant listens to SSH (hosts/x250/dev.nix); the
# keyboard installed there picks its system (x250-dev or x250-dev-qwerty), so an
# update never takes SSH away from the X250 it reaches.
# --boot : the new version for the next start only (nothing changes now).
# --app <ref> : another app than flake.lock's, not written there
#   (github:chatelp/charpentier/<commit>, path:../charpentier).
# A switch never restarts the session (greetd's X-RestartIfChanged=false):
# when it changed (the app, Sway), it is started again here, closing the app.
set -euo pipefail
cd "$(dirname "$0")/.."

action=switch
app=()
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --boot) action=boot ;;
    --app)
      [ $# -ge 2 ] || { echo "--app attend une référence" >&2; exit 2; }
      app=(--override-input charpentier "$2")
      shift
      ;;
    -*) echo "option inconnue : $1" >&2; exit 2 ;;
    *) args+=("$1") ;;
  esac
  shift
done
[ ${#args[@]} -eq 1 ] || { sed -n '2,14p' "$0" >&2; exit 2; }
host=${args[0]}
target="auteur@$host"

# shellcheck disable=SC2086 # NIX_SSHOPTS is a list of ssh options
remote() { ssh -n $NIX_SSHOPTS -o BatchMode=yes "$target" "$@"; }
export NIX_SSHOPTS=${NIX_SSHOPTS:-}

variant=$(remote cat /etc/charpentier/variant 2>/dev/null || true)
[ "$variant" = developpement ] || {
  echo "$host n'est pas un X250 en version développement : rien d'envoyé." >&2
  exit 1
}
keyboard=$(remote cat /etc/charpentier/keyboard)
case "$keyboard" in
  azerty) config=x250-dev ;;
  qwerty) config=x250-dev-qwerty ;;
  *) echo "clavier inconnu sur $host : $keyboard" >&2; exit 1 ;;
esac

before=$(remote readlink -f /run/current-system)
echo "$host : $config, $action"
nix run --inputs-from . nixpkgs#nixos-rebuild -- "$action" \
  --flake ".#$config" "${app[@]}" --target-host "$target" --sudo --no-reexec
after=$(remote readlink -f /nix/var/nix/profiles/system)
if [ "$before" = "$after" ]; then
  echo "déjà à jour : $after"
else
  echo "mis à jour : $after"
fi

# The session greetd runs against the one the system now has: its
# greetd.toml names Sway's configuration, which names the app.
[ "$action" = switch ] || exit 0
toml() { grep -o '/nix/store/[^ ]*-greetd\.toml' | head -1; }
# shellcheck disable=SC2016 # expanded on the X250
running=$(remote 'tr "\0" " " </proc/$(systemctl show greetd -p MainPID --value)/cmdline' | toml)
wanted=$(remote cat "$after/etc/systemd/system/greetd.service" | toml)
if [ -n "$wanted" ] && [ "$running" != "$wanted" ]; then
  remote sudo systemctl restart greetd
  echo "session relancée (nouvelle app ou nouveau sway)"
fi
