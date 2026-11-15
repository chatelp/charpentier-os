#!/usr/bin/env bash
# update-x250.sh <host> : updates a development X250 (or its VM) from this
# checkout, over SSH, from the home network (docs/PLAN.md phase 5.10).
#   scripts/update-x250.sh 192.168.1.42
#   NIX_SSHOPTS="-p 2222" scripts/update-x250.sh localhost      # the VM
# Only the development variant listens to SSH (hosts/x250/dev.nix); the
# keyboard installed there picks its system (x250-dev or x250-dev-qwerty), so an
# update never takes SSH away from the X250 it reaches.
# --boot : the new version for the next start only (nothing changes now).
set -euo pipefail
cd "$(dirname "$0")/.."

action=switch
args=()
for a in "$@"; do
  case "$a" in
    --boot) action=boot ;;
    -*) echo "option inconnue : $a" >&2; exit 2 ;;
    *) args+=("$a") ;;
  esac
done
[ ${#args[@]} -eq 1 ] || { sed -n '2,9p' "$0" >&2; exit 2; }
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
  --flake ".#$config" --target-host "$target" --sudo --no-reexec
after=$(remote readlink -f /nix/var/nix/profiles/system)
if [ "$before" = "$after" ]; then
  echo "déjà à jour : $after"
else
  echo "mis à jour : $after"
fi
