#!/usr/bin/env bash
# reinstall-x250.sh <host> <disk password file> : erases a development X250 (or
# its VM) and installs it again from zero, over SSH, from the home network
# (docs/PLAN.md phase 5.10 bis), with nixos-anywhere. The disk is laid out as
# installer/install.sh lays it (hosts/x250/disko.nix); its password is read
# from the file, never typed on the command line.
#   scripts/reinstall-x250.sh 192.168.1.42 ~/x250-disque.txt
#   SSH_PORT=2222 SSH_KEY=dist/dev/vm-key SSH_KNOWN_HOSTS=dist/dev/known_hosts \
#     scripts/reinstall-x250.sh 127.0.0.1 dist/dev/disque.key                # the VM
# The X250 keeps its SSH host keys (--copy-host-keys): known_hosts stays right.
# The X250 restarts on its disk's password screen: someone (or the test,
# through QEMU's monitor) types the password.
# Only a development X250 is reached: the writing one has no SSH.
set -euo pipefail
cd "$(dirname "$0")/.."

[ $# -eq 2 ] || { sed -n '2,13p' "$0" >&2; exit 2; }
host=$1
password=$2
[ -s "$password" ] || { echo "pas de mot de passe dans $password" >&2; exit 1; }
port=${SSH_PORT:-22}
key=${SSH_KEY:-}
known=${SSH_KNOWN_HOSTS:-}
ssh_opts=(-p "$port" -o BatchMode=yes)
[ -n "$key" ] && ssh_opts+=(-i "$key")
[ -n "$known" ] && ssh_opts+=(-o "UserKnownHostsFile=$known" -o StrictHostKeyChecking=accept-new)

remote() { ssh -n "${ssh_opts[@]}" "auteur@$host" "$@"; }
variant=$(remote cat /etc/charpentier/variant 2>/dev/null || true)
[ "$variant" = developpement ] || {
  echo "$host n'est pas un X250 en version développement : rien d'effacé." >&2
  exit 1
}
keyboard=$(remote cat /etc/charpentier/keyboard)
case "$keyboard" in
  azerty) config=x250-dev ;;
  qwerty) config=x250-dev-qwerty ;;
  *) echo "clavier inconnu sur $host : $keyboard" >&2; exit 1 ;;
esac

echo "$host : effacé puis réinstallé ($config)"
args=(--flake ".#$config" --target-host "auteur@$host"
  --ssh-port "$port" --post-kexec-ssh-port "$port"
  --disk-encryption-keys /tmp/disque.key "$password"
  --copy-host-keys --build-on local)
[ -n "$key" ] && args+=(-i "$key")
[ -n "$known" ] && args+=(--ssh-option "UserKnownHostsFile=$known" --ssh-option StrictHostKeyChecking=accept-new)
nix run --inputs-from . github:nix-community/nixos-anywhere -- "${args[@]}" </dev/null
