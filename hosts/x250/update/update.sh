#!/usr/bin/env bash
# The X250's updates (docs/PLAN.md phase 5.12), under root. The contract with
# the app is in the README (« Mises à jour »); its reference is the app's
# docs/x250-update-contract.md.
#   update.sh state       at every start: the generation that started, its file
#   update.sh check       the hourly check (and « Vérifier maintenant »)
#   update.sh boot <gen>  the next start on <gen>: previous, or set aside
#   update.sh watch       at every start: a first start whose app never comes up
#   update.sh clean       every day: the generations no one needs, and the store
# It never restarts the X250 (but for a first start whose screen stays
# black), and never speaks to the author: it writes
# /run/charpentier/update.json, which the app reads.
# Two channels (D-42, phase 5.12 bis), one per variant, never crossed: the
# writing system reads /api/updates/latest (X.Y.Z, X.Y.Z-N) and takes writing
# systems only; the development variant reads /api/updates/dev (X.Y.Z-dev.N)
# and takes development systems only.
# shellcheck disable=SC2016 # jq's programs, in single quotes on purpose
set -euo pipefail
umask 022

run=/run/charpentier
state_file=$run/update.json
lib=/var/lib/charpentier/update
db=$lib/generations.json # generation → {version, notes, publishedAt, receivedAt, installedAt}
saved=$lib/state.json    # {ready, setAside, lastCheck, failure}, kept across starts
profiles=/nix/var/nix/profiles
access=${CHARPENTIER_UPDATE_ACCESS:-/home/auteur/.config/charpentier/update-access.json}
key_file=${CHARPENTIER_UPDATE_KEY:?the cache\'s public key}

# The channel of the system that runs: its pointer, its version numbers, the
# variant of the systems it takes (none: a writing system).
if [ "$(cat /etc/charpentier/variant 2>/dev/null)" = developpement ]; then
  channel=dev
  versions='^[0-9]+\.[0-9]+\.[0-9]+-dev\.[0-9]+$'
  variant=developpement
else
  channel=latest
  versions='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$'
  variant=
fi

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "$*" >&2; }

init() {
  mkdir -p "$run" "$lib"
  chmod 0755 "$run"
  chmod 0700 "$lib"
  [ -s "$db" ] || echo '{}' >"$db"
  [ -s "$saved" ] || echo '{"ready":null,"setAside":null,"lastCheck":null,"failure":null}' >"$saved"
}

# A JSON file changed by jq, written beside then renamed.
jq_in() {
  local file=$1
  shift
  jq "$@" "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

# ─── Generations ───
gens() {
  local l
  for l in "$profiles"/system-*-link; do
    [ -e "$l" ] || continue
    l=${l##*/system-}
    echo "${l%-link}"
  done | sort -n
}
path_of() { readlink -f "$profiles/system-$1-link"; }
gen_of() {
  local g
  for g in $(gens); do
    [ "$(path_of "$g")" = "$1" ] && { echo "$g"; return; }
  done
  return 0
}
installed_gen() { gen_of "$(readlink -f /run/booted-system)"; }
default_gen() {
  local l
  l=$(readlink "$profiles/system")
  l=${l#system-}
  echo "${l%-link}"
}
exists() { [ -n "$1" ] && [ -e "$profiles/system-$1-link" ]; }
# The highest generation below the one that runs: the boot menu's previous one.
previous_gen() {
  local inst=$1 g prev=
  for g in $(gens); do
    [ "$g" -lt "$inst" ] && prev=$g
  done
  echo "$prev"
}
# The app's package in a generation, from its command.
app_of() {
  local bin
  bin=$(readlink -f "$(path_of "$1")/sw/bin/charpentier" 2>/dev/null || true)
  echo "${bin%/bin/*}"
}
data_format() {
  local n
  n=$(tr -dc 0-9 <"$(app_of "$1")/share/charpentier/data-format" 2>/dev/null || true)
  echo "${n:-1}"
}
# The version of a generation: the registry, or else (the first installation,
# by the key) the version of its app's package.
version_of() {
  local v
  v=$(jq -r --arg g "$1" '.[$g].version // empty' "$db")
  [ -n "$v" ] || v=$(jq -r '.version // empty' "$(app_of "$1")/share/charpentier/package.json" 2>/dev/null || true)
  echo "${v:-0.0.0}"
}
saved_gen() {
  local g
  g=$(jq -r ".$1 // empty" "$saved")
  exists "$g" && echo "$g"
  return 0
}

# ─── The file the app reads ───
write_state() {
  local checking=${1:-false} inst prev ready aside development=false
  [ "$channel" = dev ] && development=true
  inst=$(installed_gen)
  ready=$(saved_gen ready)
  aside=$(saved_gen setAside)
  [ "$ready" = "$inst" ] && ready=
  [ "$ready" = "$(default_gen)" ] || ready=
  [ "$aside" = "$inst" ] && aside=
  prev=$(previous_gen "${inst:-0}")
  [ "$prev" = "$aside" ] && prev=

  short() { # gen → {version, generation, dataFormat} or null
    if [ -n "$1" ]; then
      jq -n --arg v "$(version_of "$1")" --argjson g "$1" --argjson d "$(data_format "$1")" \
        '{version: $v, generation: $g, dataFormat: $d}'
    else echo null; fi
  }
  local installed=null ready_json=null
  if [ -n "$inst" ]; then
    installed=$(jq -n --slurpfile db "$db" --arg g "$inst" --arg v "$(version_of "$inst")" \
      --argjson d "$(data_format "$inst")" \
      '{version: $v, generation: ($g | tonumber), installedAt: ($db[0][$g].installedAt // null),
        notes: ($db[0][$g].notes // []), dataFormat: $d}')
  fi
  if [ -n "$ready" ]; then
    ready_json=$(jq -n --slurpfile db "$db" --arg g "$ready" --arg v "$(version_of "$ready")" \
      '{version: $v, generation: ($g | tonumber), publishedAt: ($db[0][$g].publishedAt // null),
        receivedAt: ($db[0][$g].receivedAt // null), notes: ($db[0][$g].notes // [])}')
  fi
  jq -n --argjson installed "$installed" --argjson ready "$ready_json" \
    --argjson previous "$(short "$prev")" --argjson setAside "$(short "$aside")" \
    --slurpfile saved "$saved" --argjson checking "$checking" --argjson development "$development" \
    '{contract: 1, installed: $installed, ready: $ready, previous: $previous, setAside: $setAside,
      lastCheck: $saved[0].lastCheck, checking: $checking, failure: $saved[0].failure,
      development: $development}' >"$state_file.tmp"
  chmod 0644 "$state_file.tmp"
  mv "$state_file.tmp" "$state_file"
}

# ─── At every start ───
# The generation that started is installed: its date, the first time; its
# entry loses the « mise à jour » line of the disk's screen; it is neither
# ready nor set aside any more.
cmd_state() {
  local inst
  inst=$(installed_gen)
  if [ -n "$inst" ]; then
    # Its first start: watched until the app comes up (cmd_watch).
    jq_in "$db" --arg g "$inst" --arg t "$(now)" --arg v "$(version_of "$inst")" \
      '.[$g] = ({version: $v, notes: []} + (.[$g] // {}))
       | if .[$g].installedAt == null then .[$g].installedAt = $t | .[$g].watch = true else . end'
    sed -i 's/ charpentier\.maj=[^ ]*//' "/boot/loader/entries/nixos-generation-$inst.conf" 2>/dev/null || true
    [ "$(saved_gen ready)" = "$inst" ] && jq_in "$saved" '.ready = null'
    [ "$(saved_gen setAside)" = "$inst" ] && jq_in "$saved" '.setAside = null'
  fi
  write_state
}

# ─── The check ───
finish() {
  jq_in "$saved" --arg t "$(now)" '.lastCheck = $t'
  write_state
}
fail() { # reason version
  log "mise à jour $2 écartée : $1"
  jq_in "$saved" --arg r "$1" --arg v "$2" --arg t "$(now)" '.failure = {version: $v, at: $t, reason: $r}'
  finish
}

cmd_check() {
  if [ ! -r "$access" ]; then
    log "pas de compte (pas de $access) : rien n'est vérifié"
    write_state
    return
  fi
  local server token
  server=$(jq -r '.server // empty' "$access")
  token=$(jq -r '.token // empty' "$access")
  if ! [[ $server =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] || [ -z "$token" ]; then
    log "compte illisible dans $access"
    write_state
    return
  fi
  write_state true

  # The token never reaches a command line: a header file and a netrc, in a
  # folder of root's own, removed at the end.
  local tmp
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  printf 'Authorization: Bearer %s\n' "$token" >"$tmp/header"
  printf 'machine %s login appareil password %s\n' "$(sed -E 's|^https?://([^:/]+).*|\1|' <<<"$server")" "$token" >"$tmp/netrc"

  local code
  code=$(curl -sS --max-time 60 -o "$tmp/pointer.json" -w '%{http_code}' -H @"$tmp/header" \
    "$server/api/updates/$channel" 2>"$tmp/curl.err") || code=000
  case $code in
    200) ;;
    404) log "aucune version publiée" && finish && return ;;
    *) log "pointeur injoignable ($code) : $(cat "$tmp/curl.err")" && finish && return ;;
  esac

  local keyboard version path published notes
  keyboard=$(cat /etc/charpentier/keyboard)
  version=$(jq -r '.version // empty' "$tmp/pointer.json" 2>/dev/null || true)
  path=$(jq -r --arg k "$keyboard" '.systems[$k] // empty' "$tmp/pointer.json" 2>/dev/null || true)
  published=$(jq -r '.publishedAt // empty' "$tmp/pointer.json")
  notes=$(jq -c '(.notes // "") | tostring | split("\n") | map(sub("^\\s*-\\s*"; "") | sub("\\s+$"; "")) | map(select(length > 0))' "$tmp/pointer.json")
  if ! [[ $version =~ $versions ]] || ! [[ $path =~ ^/nix/store/[a-z0-9]{32}-nixos-system-[^/]+$ ]]; then
    fail unreadable "${version:-?}"
    return
  fi

  # Already here: what runs, what is ready, what was set aside.
  local inst existing
  inst=$(installed_gen)
  existing=$(gen_of "$path")
  if [ -n "$existing" ]; then
    if [ "$existing" = "$inst" ] || [ "$existing" = "$(saved_gen setAside)" ] || [ "$existing" = "$(saved_gen ready)" ]; then
      finish
      return
    fi
    # A newer generation already here (a version ready, then left by a
    # return): ready again, without downloading anything.
    if [ "$existing" -gt "${inst:-0}" ]; then
      install_gen "$existing" "$version" "$notes" "$published"
      finish
    else
      finish
    fi
    return
  fi

  # The development variant (D-42): the latest wins. A version published
  # before the newest system here is older than it, and is not taken; one
  # published after it is. That system's date: its publication's, when it
  # came from the pointer (a version published while the previous one was
  # downloading stays newer than it); else its own making's (an update by
  # update-x250.sh, say, even before the restart).
  if [ "$channel" = dev ]; then
    local newest made at=0 from
    newest=$(gens | tail -1)
    if [ -n "$newest" ]; then
      from=$(jq -r --arg g "$newest" '.[$g].publishedAt // empty' "$db")
      if [ -n "$from" ] && made=$(date -d "$from" +%s 2>/dev/null); then :; else
        made=$(stat -c %Y "$profiles/system-$newest-link")
      fi
      [ -n "$published" ] && at=$(date -d "$published" +%s 2>/dev/null || echo 0)
      if [ "$at" -le "$made" ]; then
        log "mise à jour $version publiée avant la génération $newest : rien n'est pris"
        finish
        return
      fi
    fi
  fi

  # Download what changed, from the server's cache only, every path signed by
  # the key laid at installation.
  log "mise à jour $version : téléchargement de $path"
  if ! nix-store --realise "$path" \
    --option substituters "$server/nix-cache" \
    --option trusted-public-keys "$(cat "$key_file")" \
    --option require-sigs true \
    --option netrc-file "$tmp/netrc" \
    --option fallback false >/dev/null 2>"$tmp/nix.err"; then
    log "$(tail -5 "$tmp/nix.err")"
    if grep -qiE 'signature|not signed|lacks a valid' "$tmp/nix.err"; then
      fail signature "$version"
    elif grep -qiE 'no space left|disk full' "$tmp/nix.err"; then
      fail disk-full "$version"
    elif grep -qiE "does not exist|is not valid|cannot build|don't know how to build" "$tmp/nix.err"; then
      fail unreadable "$version"
    else
      fail interrupted "$version"
    fi
    return
  fi
  # A system of this channel, for this keyboard: a writing system never takes
  # the development variant, nor the development variant a writing system.
  if ! [ -x "$path/bin/switch-to-configuration" ] ||
    [ "$(cat "$path/etc/charpentier/keyboard" 2>/dev/null)" != "$keyboard" ] ||
    [ "$(cat "$path/etc/charpentier/variant" 2>/dev/null || true)" != "$variant" ]; then
    fail unreadable "$version"
    return
  fi

  nix-env -p "$profiles/system" --set "$path"
  install_gen "$(default_gen)" "$version" "$notes" "$published"
  finish
}

# The disk's screen says « mise à jour X.Y.Z » on a generation's first start
# only: a line its start menu's entry carries until then (every
# switch-to-configuration writes the entries again, without it).
mark_maj() { # gen version
  local entry=/boot/loader/entries/nixos-generation-$1.conf
  if [ -f "$entry" ] && ! grep -q 'charpentier\.maj=' "$entry"; then
    sed -i "s/^options .*/& charpentier.maj=$2/" "$entry"
  fi
}

# <gen> becomes the next start's, announced as ready.
install_gen() { # gen version notes publishedAt
  local gen=$1
  nix-env -p "$profiles/system" --switch-generation "$gen" >/dev/null 2>&1 || true
  "$(path_of "$gen")/bin/switch-to-configuration" boot
  jq_in "$db" --arg g "$gen" --arg v "$2" --argjson n "$3" --arg p "$4" --arg t "$(now)" \
    '.[$g] = ((.[$g] // {}) + {version: $v, notes: $n, publishedAt: (if $p == "" then null else $p end), receivedAt: $t})'
  mark_maj "$gen" "$2"
  # A newer version than the one set aside: that one is not offered any more.
  jq_in "$saved" --argjson g "$gen" '.ready = $g | .failure = null | .setAside = null'
  log "mise à jour $2 prête : génération $gen au prochain démarrage"
}

# ─── Back to the previous version, or on to the one set aside ───
cmd_boot() {
  local gen=${1:-} inst prev aside
  [[ $gen =~ ^[0-9]+$ ]] || { log "génération attendue"; return 2; }
  inst=$(installed_gen)
  aside=$(saved_gen setAside)
  prev=$(previous_gen "${inst:-0}")
  [ "$prev" = "$aside" ] && prev=
  if [ -n "$prev" ] && [ "$gen" = "$prev" ]; then
    nix-env -p "$profiles/system" --switch-generation "$gen"
    "$(path_of "$gen")/bin/switch-to-configuration" boot
    jq_in "$saved" --argjson i "$inst" '.setAside = $i | .ready = null'
  elif [ -n "$aside" ] && [ "$gen" = "$aside" ]; then
    nix-env -p "$profiles/system" --switch-generation "$gen"
    "$(path_of "$gen")/bin/switch-to-configuration" boot
    jq_in "$saved" '.setAside = null | .ready = null'
  else
    log "génération $gen : ni la précédente ni celle mise de côté"
    return 1
  fi
  write_state
  log "prochain démarrage : génération $gen"
}

# ─── A first start whose screen stays black (the outside review of 18 November 2026) ───
# A generation's first start is watched: the app must come up, and stay up,
# within a few minutes. If it never does (Sway does not start, the app dies
# again and again), the X250 goes back to the previous generation by the
# app's own gesture (cmd_boot: the new one set aside, offered again, never
# taken again by itself) and starts again, the failure said in the file:
# the one time the service restarts the X250, a black screen having nothing
# to lose. Watched once only: a generation that came up, or was sent back,
# never is again; one stopped before the verdict (the author holding the
# power key) is, at its next start. The time counts in rounds, which a sleep
# does not move.
watch_wait=${CHARPENTIER_WATCH_WAIT:-300}    # seconds, at most, for the app to be up
watch_steady=${CHARPENTIER_WATCH_STEADY:-30} # seconds it must have run: not a loop of restarts
app_up() {
  local pid age
  pid=$(pgrep -u auteur -o -f -- ' --appliance' || true)
  [ -n "$pid" ] || return 1
  age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ' || true)
  [ "${age:-0}" -ge "$watch_steady" ]
}

cmd_watch() {
  local inst prev aside i
  inst=$(installed_gen)
  [ -n "$inst" ] || return 0
  [ "$(jq -r --arg g "$inst" '.[$g].watch // false' "$db")" = true ] || return 0
  # The wait, without the lock: the hourly check is not held back by it.
  flock -u 9
  for ((i = 0; i < watch_wait; i += 5)); do
    app_up && break
    sleep 5
  done
  flock 9
  jq_in "$db" --arg g "$inst" 'del(.[$g].watch)'
  if app_up; then
    log "génération $inst : l'app a démarré"
    return
  fi
  aside=$(saved_gen setAside)
  prev=$(previous_gen "$inst")
  [ "$prev" = "$aside" ] && prev=
  if [ -z "$prev" ]; then
    log "génération $inst : l'app n'a pas démarré, et aucune génération avant elle"
    return
  fi
  log "génération $inst : l'app n'a pas démarré en $watch_wait s ; retour à la génération $prev"
  jq_in "$saved" --arg v "$(version_of "$inst")" --arg t "$(now)" '.failure = {version: $v, at: $t, reason: "start"}'
  cmd_boot "$prev"
  # shellcheck disable=SC2086 # the command and its words
  ${CHARPENTIER_REBOOT:-systemctl reboot}
}

# The start menu written again, the next start's generation unchanged. A
# switch under way (update-x250.sh, an update's activation) holds its lock:
# tried again every 10 s, 10 minutes at most; on a failure, the script stops
# there, before the store is touched (set -e).
write_menu() {
  local i
  for ((i = 0; i < 60; i++)); do
    "$(path_of "$(default_gen)")/bin/switch-to-configuration" boot 2>"$run/menu.err" && return 0
    if ! grep -q 'Could not acquire lock' "$run/menu.err"; then
      cat "$run/menu.err" >&2
      return 1
    fi
    sleep 10
  done
  log "menu de démarrage : une mise à jour en cours depuis 10 minutes, rien n'est nettoyé"
  return 1
}

# ─── The store, cleaned (the outside review of 18 November 2026) ───
# Every update leaves a generation behind, and the store never shrank. Kept:
# the generation that started and the one that runs (not the same after an
# update by update-x250.sh), the previous one (the way back), the one ready
# and the one set aside (the app offers them), the next start's, and the
# newest (the development variant dates the latest by it). The others go,
# from the profile and the registry; the start menu is written again (every
# time: the store never loses what an entry still names), then the store
# loses what no generation needs any more.
cmd_clean() {
  local inst ready keep g gone=()
  inst=$(installed_gen)
  ready=$(saved_gen ready)
  keep=" $inst $(gen_of "$(readlink -f /run/current-system)") $(previous_gen "${inst:-0}") $ready"
  keep+=" $(saved_gen setAside) $(default_gen) $(gens | tail -1) "
  for g in $(gens); do
    [[ $keep == *" $g "* ]] || gone+=("$g")
  done
  if [ ${#gone[@]} -gt 0 ]; then
    nix-env -p "$profiles/system" --delete-generations "${gone[@]}"
    for g in "${gone[@]}"; do
      jq_in "$db" --arg g "$g" 'del(.[$g])'
    done
    log "générations retirées : ${gone[*]}"
  fi
  write_menu
  [ -n "$ready" ] && mark_maj "$ready" "$(version_of "$ready")"
  nix-store --gc 2>&1 | tail -1 >&2
  write_state
}

init
exec 9>"$run/update.lock"
flock 9
case "${1:-}" in
  state) cmd_state ;;
  check) cmd_check ;;
  boot) cmd_boot "${2:-}" ;;
  watch) cmd_watch ;;
  clean) cmd_clean ;;
  *) sed -n '2,12p' "$0" >&2 && exit 2 ;;
esac
