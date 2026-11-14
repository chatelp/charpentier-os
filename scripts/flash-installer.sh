#!/usr/bin/env bash
# The X250's install key, written from the Mac (docs/PLAN.md phase 5.9 bis,
# docs/DESIGN.md §4.12 « Installation », render x250/18). It lists only the
# external, physical, removable disks (never this Mac's own), asks which one,
# erases it after ⏎ ⏎ (the second within 3 s), writes the image, reads it back
# to check it, then ejects the key.
#
# The image is the latest published one (phase 5.11), downloaded from the sync
# server into dist/installer, resumed if cut, its SHA-256 checked; it needs a
# token of the account (a device's, or the CI's) in CHARPENTIER_TOKEN:
#   CHARPENTIER_TOKEN=… scripts/flash-installer.sh
# or, with --local, the newest image built here:
#   scripts/nix.sh --out dist/installer build .#installer
#   scripts/flash-installer.sh --local
set -uo pipefail
cd "$(dirname "$0")/.."
server=${CHARPENTIER_SERVER:-https://charpentier.chatel.pm}

# ─── Look: no colour; bold, dim, inverse; plain text off a terminal or with NO_COLOR ───
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  B=$'\e[1m' D=$'\e[2m' I=$'\e[7m' R=$'\e[0m' CLR=$'\r\e[2K'
else
  B='' D='' I='' R='' CLR=$'\n'
fi

say() { printf '%s\n' "$*"; }
# Sizes the French way: « 3,1 Go ».
go() { awk -v b="$1" 'BEGIN { printf "%.1f Go", b / 1e9 }' | tr . ,; }
go_whole() { awk -v b="$1" 'BEGIN { printf "%d Go", (b / 1e9) + 0.5 }'; }
mois=(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

say "${B}charpentier · clé d'installation du x250${R}"
say ''

# The latest published image: its version, size and sum, then the file, kept
# in dist/installer/published and resumed if a download was cut.
download() {
  local auth meta version sha bytes
  if [ -z "${CHARPENTIER_TOKEN:-}" ]; then
    say "${I}pas de jeton${R} · l'image se télécharge avec un jeton du compte :"
    say "${D}  CHARPENTIER_TOKEN=… scripts/flash-installer.sh${R}"
    say "${D}ou, avec une image construite ici : scripts/flash-installer.sh --local${R}"
    exit 1
  fi
  auth=(-H "Authorization: Bearer $CHARPENTIER_TOKEN")
  meta=$(curl -fsS "${auth[@]}" "$server/api/installer/latest") || {
    say "${I}le serveur ne donne pas d'image${R} · aucune publiée, ou jeton refusé"
    exit 1
  }
  field() { plutil -extract "$1" raw -o - - <<<"$meta" 2>/dev/null || sed -n "s/.*\"$1\": *\"\\{0,1\\}\\([^\",}]*\\).*/\\1/p" <<<"$meta"; }
  version=$(field version)
  sha=$(field sha256)
  bytes=$(field size)
  mkdir -p dist/installer/published
  image=dist/installer/published/charpentier-x250-$version.iso
  # Whole but wrong (a disk error, an older file): from the start, not resumed.
  if [ -f "$image" ] && [ "$(wc -c <"$image")" -ge "$bytes" ] &&
    [ "$(shasum -a 256 "$image" | cut -d' ' -f1)" != "$sha" ]; then
    rm -f "$image"
  fi
  if [ ! -f "$image" ] || [ "$(shasum -a 256 "$image" | cut -d' ' -f1)" != "$sha" ]; then
    say "téléchargement de l'image $version"
    curl -f -C - --retry 5 --progress-bar "${auth[@]}" -o "$image" "$server/api/installer/$version.iso" || {
      say "${I}téléchargement interrompu${R} · relancez : il reprendra où il s'est arrêté"
      exit 1
    }
    if [ "$(shasum -a 256 "$image" | cut -d' ' -f1)" != "$sha" ]; then
      rm -f "$image"
      say "${I}l'image téléchargée est abîmée${R} · relancez pour la télécharger à nouveau"
      exit 1
    fi
  fi
}

if [ "${1:-}" = '--local' ]; then
  image=$(ls -t dist/installer/*.iso dist/installer/iso/*.iso dist/installer/*.img 2>/dev/null | head -1)
  if [ -z "$image" ]; then
    say "${I}pas d'image d'installation${R} · construisez-la d'abord :"
    say "${D}  scripts/nix.sh --out dist/installer build .#installer${R}"
    exit 1
  fi
else
  download
fi
size=$(stat -f %z "$image")
need=$(((size + 999999999) / 1000000000))
read -r d m y <<<"$(stat -f '%Sm' -t '%e %m %Y' "$image")"
say "image  $(basename "$image") · $(go "$size") · $d ${mois[$((10#$m - 1))]} $y"
say ''

plist() { plutil -extract "$2" raw -o - - <<<"$1" 2>/dev/null; }

# Above this, a disk is never a key (an external SSD, a backup disk).
MAX_KEY=256000000000

# The keys: external, physical, removable media; this Mac's disk never, nor
# an external SSD or backup disk (fixed media, or larger than 256 Go).
keys() {
  diskutil list external physical 2>/dev/null | awk '/^\/dev\/disk[0-9]+ /{print $1}' | while read -r disk; do
    info=$(diskutil info -plist "$disk" 2>/dev/null) || continue
    [ "$(plist "$info" Internal)" = "false" ] || continue
    [ "$(plist "$info" RemovableMedia)" = "true" ] || continue
    [ "$(plist "$info" TotalSize)" -le "$MAX_KEY" ] 2>/dev/null || continue
    name=$(plist "$info" MediaName | sed 's/ Media$//')
    printf '%s\t%s\t%s\n' "$disk" "$(plist "$info" TotalSize)" "${name:-clé usb}"
  done
}

while true; do
  list=$(keys)
  if [ -z "$list" ]; then
    say "${I}aucune clé usb branchée${R}"
    say "branchez-en une ($need Go au moins), puis ⏎ · ctrl-c pour quitter"
    read -r || exit 1
    continue
  fi
  say 'clés usb branchées'
  choices=()
  n=0
  while IFS=$'\t' read -r disk bytes name; do
    if [ "$bytes" -lt "$size" ]; then
      say "${D}   $name · $(go_whole "$bytes") · trop petite (il faut $need Go)  $disk${R}"
    else
      n=$((n + 1))
      choices+=("$disk"$'\t'"$bytes"$'\t'"$name")
      say "${B}$n${R}  $name · $(go_whole "$bytes")  ${D}$disk${R}"
    fi
  done <<<"$list"
  say "${D}le disque de ce Mac n'est jamais proposé${R}"
  say ''
  if [ "$n" -eq 0 ]; then
    say "branchez une clé de $need Go au moins, puis ⏎ · ctrl-c pour quitter"
    read -r || exit 1
    continue
  fi
  pick=1
  if [ "$n" -gt 1 ]; then
    while true; do
      printf 'quelle clé ? [1-%d] ' "$n"
      read -r pick || exit 1
      [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "$n" ] && break
    done
  fi
  IFS=$'\t' read -r disk bytes name <<<"${choices[$((pick - 1))]}"
  label="$name · $(go_whole "$bytes")"

  # ⏎ ⏎: the first arms the erasing for 3 s, the second erases.
  say "${I}$label va être entièrement effacée${R}"
  say '⏎ effacer · ctrl-c annuler'
  read -r || exit 1
  printf "confirmer l'effacement ⏎ (3 s) "
  if read -r -t 3; then
    break
  fi
  say ''
  say "délai passé · rien n'est effacé"
  say ''
done

say "le Mac demande votre mot de passe pour écrire sur la clé"
sudo -v || exit 1
diskutil unmountDisk "$disk" >/dev/null || exit 1

# One line rewritten in place: 20 cells, the percentage, what is left.
bar() {
  local label=$1 done=$2 total=$3 started=$4
  local pct=$((done * 100 / total)) cells=$((done * 20 / total)) left='' now elapsed
  now=$(date +%s)
  elapsed=$((now - started))
  if [ "$done" -gt 0 ] && [ "$elapsed" -gt 2 ]; then
    local rest=$(((total - done) * elapsed / done))
    if [ "$rest" -ge 60 ]; then left=" · encore $((rest / 60 + 1)) min"; else left=" · encore $rest s"; fi
  fi
  local full empty
  full=$(printf '%*s' "$cells" '' | tr ' ' '█')
  empty=$(printf '%*s' $((20 - cells)) '' | tr ' ' '░')
  printf '%s%-13s%s%s %3d %%%s · %s sur %s%s%s' "$CLR" "$label" "$full" "$empty" "$pct" "$D" \
    "$(go "$done")" "$(go "$total")" "$left" "$R"
}

# Runs dd with its progress, drawn on the line; fails if the key goes away.
copy() {
  local label=$1 total=$2
  shift 2
  local log
  log=$(mktemp)
  "$@" 2>"$log" &
  local pid=$! started
  started=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    done=$(tr '\r' '\n' <"$log" | awk '/bytes/ {b=$1} END {print b+0}')
    bar "$label" "${done:-0}" "$total" "$started"
    sleep 0.5
  done
  wait "$pid"
  local status=$?
  rm -f "$log"
  [ "$status" -eq 0 ] || return 1
  bar "$label" "$total" "$total" "$started"
  printf '%s%s%s\n' "$CLR" "$label" 'fait'
}

removed() {
  say ''
  say "${I}la clé a été retirée pendant l'écriture${R}"
  say 'rebranchez-la et relancez : elle sera réécrite en entier'
  exit 1
}

raw=${disk/disk/rdisk}
blocks=$(((size + 1048575) / 1048576))
copy 'écriture' "$size" sudo dd if="$image" of="$raw" bs=1m status=progress || removed
sync
want=$(shasum -a 256 "$image" | cut -d' ' -f1)
sumfile=$(mktemp)
copy 'vérification' "$size" sh -c "sudo dd if='$raw' bs=1m count=$blocks status=progress | head -c $size | shasum -a 256 > '$sumfile'" ||
  removed
got=$(cut -d' ' -f1 <"$sumfile")
rm -f "$sumfile"
if [ "$got" != "$want" ]; then
  say "${I}la clé ne relit pas l'image à l'identique${R}"
  say 'relancez : elle sera réécrite en entier ; si cela revient, essayez une autre clé'
  exit 1
fi
diskutil eject "$disk" >/dev/null 2>&1

say ''
say "${B}la clé est prête${R} et éjectée : vous pouvez la retirer"
say ''
say 'sur le x250, éteint :'
say "  ${B}1${R} branchez la clé"
say "  ${B}2${R} allumez en tenant F12"
say "  ${B}3${R} choisissez « USB HDD : $name »"
say ''
say "${D}la clé n'apparaît pas ? au démarrage, F1 → Security → Secure Boot → Disabled${R}"
