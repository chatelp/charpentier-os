#!/usr/bin/env bash
# publish-dev.sh [--app <ref>] : the development variant onto its own channel
# (D-42, phase 5.12 bis), never with the releases: both systems (x250-dev,
# x250-dev-qwerty) copied, signed, into the server's cache, then the pointer
# /api/updates/dev. A development X250 takes it on its next hourly check; a
# writing X250 never reads it.
#   CHARPENTIER_CACHE_TOKEN=… NIX_SIGNING_KEY_FILE=… scripts/publish-dev.sh
# From the Yoga L13, or the CI (.github/workflows/publish-dev.yml).
# --app <ref> : another app than flake.lock's, not written there
#   (github:chatelp/charpentier/<commit>).
# Its number: the app's version, then -dev.N, N one more than the version on
# /dev when it has the same app version, else 1 (0.2.0-dev.1, 0.2.0-dev.2…).
# The server keeps the last development version only.
# The systems carry hosts/x250/dev-keys.pub's keys: without them, the X250
# that takes this version would lose SSH.
set -euo pipefail
cd "$(dirname "$0")/.."
# jq, which WSL may lack, from the flake's nixpkgs.
command -v jq >/dev/null ||
  exec nix --extra-experimental-features 'nix-command flakes' shell --inputs-from . nixpkgs#jq -c "$0" "$@"

server=${CHARPENTIER_SERVER:-https://charpentier.chatel.pm}
app=()
while [ $# -gt 0 ]; do
  case "$1" in
    --app)
      [ $# -ge 2 ] || { echo "--app attend une référence" >&2; exit 2; }
      app=(--override-input charpentier "$2")
      shift
      ;;
    *) sed -n '2,16p' "$0" >&2; exit 2 ;;
  esac
  shift
done
: "${CHARPENTIER_CACHE_TOKEN:?the token of the CI (or of the Yoga L13) on the sync server}"
: "${NIX_SIGNING_KEY_FILE:?the secret key that signs the paths (charpentier-x250-1)}"
[ -r "$NIX_SIGNING_KEY_FILE" ] || { echo "✗ $NIX_SIGNING_KEY_FILE illisible" >&2; exit 1; }

# The keys, seen by the flake (a file Git does not know is not part of it).
grep -qE '^(ssh|ecdsa)-' hosts/x250/dev-keys.pub 2>/dev/null ||
  { echo "✗ pas de clé dans hosts/x250/dev-keys.pub : le X250 perdrait SSH" >&2; exit 1; }
git ls-files --error-unmatch hosts/x250/dev-keys.pub >/dev/null 2>&1 ||
  git add --force --intent-to-add hosts/x250/dev-keys.pub

# The token never reaches a command line.
auth=$(mktemp)
trap 'rm -f "$auth" "$auth".*' EXIT
printf 'Authorization: Bearer %s\n' "$CHARPENTIER_CACHE_TOKEN" >"$auth"

nixe() { nix --extra-experimental-features 'nix-command flakes' "$@"; }

base=$(nixe eval --raw "${app[@]}" .#charpentier.version 2>/dev/null)
[[ $base =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ version de l'app illisible : « $base »" >&2; exit 1; }
code=$(curl -sS --max-time 60 -o "$auth.pointer" -w '%{http_code}' -H @"$auth" "$server/api/updates/dev") || code=000
case $code in
  200) last=$(jq -r '.version // ""' "$auth.pointer") ;;
  404) last= ;;
  *) echo "✗ pointeur /dev : $code" >&2; exit 1 ;;
esac
n=1
if [[ $last =~ ^${base//./\\.}-dev\.([0-9]+)$ ]]; then n=$((BASH_REMATCH[1] + 1)); fi
version=$base-dev.$n
echo "version : $version (sur /dev : ${last:-rien})"

# What it is made of, for « À propos ».
os=$(git rev-parse --short HEAD)
git diff --quiet HEAD -- . ':!hosts/x250/dev-keys.pub' || os="$os, modifié"
if [ ${#app[@]} -gt 0 ]; then
  from=${app[2]}
else
  from=$(jq -r '.nodes.charpentier.locked | "github:\(.owner)/\(.repo)/\(.rev[0:7])"' flake.lock)
fi

systems=()
for k in azerty qwerty; do
  case $k in azerty) c=x250-dev ;; *) c=x250-dev-$k ;; esac
  systems+=("$(nixe build --no-link --print-out-paths "${app[@]}" \
    ".#nixosConfigurations.$c.config.system.build.toplevel")")
done
printf '  %s\n' "${systems[@]}"

python3 scripts/publish.py cache "${systems[@]}"

jq -n --arg version "$version" --arg notes "Version de développement : charpentier-os $os, app $from" \
  --arg azerty "${systems[0]}" --arg qwerty "${systems[1]}" \
  '{version: $version, notes: $notes, systems: {azerty: $azerty, qwerty: $qwerty}}' >"$auth.json"
curl --fail-with-body -sS -X PUT "$server/api/updates/dev" -H @"$auth" \
  -H 'Content-Type: application/json' --data @"$auth.json"
echo
echo "✓ $version sur /api/updates/dev"
