#!/usr/bin/env bash
# The X250's installer (docs/PLAN.md phase 5.9 bis, docs/DESIGN.md §4.12
# « Installation », renders x250/13 to 17). It runs on the first console, in
# kmscon (or the kernel's console if kmscon fails), from a system loaded in
# memory: the key may be pulled at the end. It erases the internal disk,
# encrypts it with the author's password and copies the system already built
# on the key. Nothing is downloaded.
#
# Written ahead of this script by the image (installer/default.nix), since
# kmscon gives its program an empty environment: CHARPENTIER_VERSION,
# CHARPENTIER_SYSTEMS (layout=/nix/store/…-toplevel,…), CHARPENTIER_KEY_LABEL
# (the key's label). From the service: CHARPENTIER_PLAIN (1 on the kernel's console).
# kmscon's keyboard is set when it starts, and kmscon starts this script again
# when it ends: a new layout, written in /run/charpentier/layout, restarts the
# whole service.
set -uo pipefail

version=${CHARPENTIER_VERSION:-0.0.0}
plain=${CHARPENTIER_PLAIN:-0}
key_label=${CHARPENTIER_KEY_LABEL:-CHARPENTIER}
state=/run/charpentier
log=$state/install.log
mkdir -p "$state"
layout=$(cat "$state/layout" 2>/dev/null || echo azerty)
enter='⏎'
[ "$plain" = 1 ] && enter='entrée'

# ─── Drawing: one block, left-aligned, always at the same place ───
INK=$'\e[0;97m' INK2=$'\e[0;37m' FAINT=$'\e[0;90m' INV=$'\e[0;7m' OFF=$'\e[0m'
cols() { tput cols 2>/dev/null || echo 120; }
left=$((($(cols) - 84) / 2))
[ "$left" -lt 1 ] && left=1
top=8
row=0
clear_screen() {
  printf '\e[?25l\e[2J'
  row=$top
}
line() { # line [style] text…
  printf '\e[%d;%dH\e[K%s%s%s' "$row" "$left" "$1" "$2" "$OFF"
  row=$((row + 1))
}
gap() { row=$((row + 1)); }
# repeat <character> <count>: tr would cut a character of several bytes.
repeat() {
  local s
  printf -v s '%*s' "$2" ''
  printf '%s' "${s// /$1}"
}
head_lines() { # the head and the steps, the current one in ink
  local current=$1 i s out=''
  line "$FAINT" 'charpentier · x250 · installation'
  gap
  local steps=('1 disque' '2 mot de passe' '3 copie' '4 redémarrage')
  for i in 0 1 2 3; do
    s=${steps[$i]}
    if [ "$current" -eq 0 ]; then out+="$FAINT$s   "
    elif [ $((i + 1)) -lt "$current" ]; then out+="$INK2$s   "
    elif [ $((i + 1)) -eq "$current" ]; then out+="$INK$s   "
    else out+="$FAINT$s   "; fi
  done
  line '' "$out"
  gap
}

# A key: enter, escape, tab, left, right, up, down, backspace, or a character.
read_key() {
  local k rest
  IFS= read -rsn1 k || { echo eof; return; }
  case "$k" in
    '') echo enter ;;
    $'\t') echo tab ;;
    $'\x7f' | $'\b') echo backspace ;;
    $'\e')
      IFS= read -rsn2 -t 0.05 rest || true
      case "$rest" in
        '[C') echo right ;; '[D') echo left ;; '[A') echo up ;; '[B') echo down ;;
        *) echo escape ;;
      esac
      ;;
    *) printf 'char:%s\n' "$k" ;;
  esac
}

power_off() {
  printf '\e[2J\e[?25h'
  systemctl poweroff
  exit 0
}

# ─── The machine ───
on_mains() {
  local s
  for s in /sys/class/power_supply/*; do
    [ "$(cat "$s/type" 2>/dev/null)" = Mains ] && [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && return 0
  done
  return 1
}
battery() {
  local s n=0 t=0
  for s in /sys/class/power_supply/BAT*; do
    [ -r "$s/capacity" ] || continue
    t=$((t + $(cat "$s/capacity")))
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] && echo $((t / n)) || echo 100
}
# The internal disks: not removable, not on USB (the key is never offered).
internal_disks() {
  lsblk -dnpo NAME,TYPE,RM,TRAN | awk '$2 == "disk" && $3 == "0" && $4 != "usb" { print $1 }' |
    grep -v -E '/dev/(loop|zram|sr)'
}
disk_label() {
  local model size
  model=$(lsblk -dno MODEL "$1" | tr '[:upper:]' '[:lower:]' | sed 's/ *$//')
  size=$(lsblk -dbno SIZE "$1" | awk '{ printf "%d go", $1 / 1e9 + 0.5 }')
  echo "${model:-disque} · $size"
}
disk_contents() {
  local types labels
  types=$(lsblk -nro FSTYPE "$1" | sort -u | tr '\n' ' ')
  labels=$(lsblk -nro PARTLABEL "$1" | tr '\n' ' ')
  if [[ "$labels" == *charpentier* ]]; then echo 'charpentier · ce qui n’a pas été synchronisé sera perdu'
  elif [[ "$types" == *ntfs* ]]; then echo 'windows'
  elif [[ "$types" == *crypto_LUKS* || "$types" == *ext4* || "$types" == *btrfs* || "$types" == *xfs* ]]; then echo 'linux'
  elif [ -n "${types// /}" ]; then echo 'des données'
  else echo 'rien'; fi
}
key_present() { [ -e "/dev/disk/by-label/$key_label" ]; }

# ─── 0. Welcome: the keyboard, tried ───
welcome() {
  local layouts=(azerty bepo qwerty) names=(azerty bépo qwerty) trial='' k i
  while true; do
    clear_screen
    head_lines 0
    line "$INK" "installer charpentier $version sur cet ordinateur"
    line "$INK2" 'tout est sur la clé : rien à télécharger, pas besoin de réseau'
    line "$FAINT" 'environ 5 minutes'
    gap
    local keys=''
    for i in 0 1 2; do
      if [ "${layouts[$i]}" = "$layout" ]; then keys+="$INV ${names[$i]} $OFF  "
      else keys+="$INK2 ${names[$i]} $OFF  "; fi
    done
    line "$INK2" "clavier    $keys$FAINT← → changer"
    line "$INK2" "essai      $INK$trial$INK2▏"
    line "$FAINT" '           tapez quelques lettres : ce clavier servira au mot de passe'
    gap
    local level ready=1
    level=$(battery)
    if on_mains; then
      line "$INK2" 'secteur    branché'
    elif [ "$level" -lt 30 ]; then
      line "$INV" " sur batterie · $level % "
      line "$INK2" 'branchez le chargeur pour commencer'
      ready=0
    else
      line "$INK2" "secteur    sur batterie · $level %"
    fi
    gap
    if [ "$ready" = 1 ]; then line "$INK" "$enter commencer"; else line "$FAINT" "$enter commencer"; fi
    line "$FAINT" 'échap éteindre sans rien changer'
    k=$(read_key)
    case "$k" in
      left | right)
        for i in 0 1 2; do [ "${layouts[$i]}" = "$layout" ] && break; done
        if [ "$k" = right ]; then i=$(((i + 1) % 3)); else i=$(((i + 2) % 3)); fi
        echo "${layouts[$i]}" >"$state/layout"
        [ "$plain" = 1 ] && loadkeys "$(console_map "${layouts[$i]}")" >/dev/null 2>&1 && layout=${layouts[$i]} && continue
        # kmscon takes its keyboard when it starts: start it again with this one.
        systemctl restart --no-block charpentier-installer.service
        sleep 10
        exit 0
        ;;
      enter) [ "$ready" = 1 ] && return 0 ;;
      escape) power_off ;;
      backspace) trial=${trial%?} ;;
      char:*) [ "${#trial}" -lt 40 ] && trial+=${k#char:} ;;
    esac
  done
}
console_map() { case $1 in bepo) echo fr-bepo ;; qwerty) echo us ;; *) echo fr ;; esac; }

# ─── 1. The disk, erased after ⏎ ⏎ ───
disk=''
choose_disk() {
  local disks k i=0 armed=0
  mapfile -t disks < <(internal_disks)
  while true; do
    clear_screen
    head_lines 1
    if [ "${#disks[@]}" -eq 0 ]; then
      line "$INV" ' aucun disque interne trouvé '
      line "$INK2" 'vérifiez que le disque est bien en place, puis rallumez'
      gap
      line "$INK" 'échap éteindre'
      [ "$(read_key)" = escape ] && power_off
      continue
    fi
    if [ "${#disks[@]}" -gt 1 ]; then
      line "$INK" 'deux disques internes : lequel recevra charpentier ?'
      local j
      for j in "${!disks[@]}"; do
        if [ "$j" = "$i" ]; then line "$INK" "› $(disk_label "${disks[$j]}")"
        else line "$INK2" "  $(disk_label "${disks[$j]}")"; fi
      done
      line "$FAINT" '↑ ↓ choisir · l’autre disque n’est pas touché'
    else
      line "$INK2" 'disque interne'
      line "$INK" "$(disk_label "${disks[0]}")"
    fi
    gap
    line "$INK2" "il contient : $(disk_contents "${disks[$i]}")"
    gap
    line "$INV" ' tout ce disque va être effacé '
    line "$INK2" 'ce qu’il contient sera perdu pour de bon'
    line "$INK2" 'vos textes restent sur le serveur de synchronisation, s’ils y ont été envoyés'
    gap
    if [ "$armed" = 1 ]; then
      line "$INK" "confirmer l'effacement $enter  $FAINT 3 s"
    else
      line "$INK" "$enter effacer et installer"
    fi
    line "$FAINT" 'échap éteindre sans rien changer'
    if [ "$armed" = 1 ]; then
      if k=$(read_key_timeout 3); then
        [ "$k" = enter ] && { disk=${disks[$i]}; return 0; }
      fi
      armed=0
      continue
    fi
    k=$(read_key)
    case "$k" in
      up) i=$(((i + ${#disks[@]} - 1) % ${#disks[@]})) ;;
      down) i=$(((i + 1) % ${#disks[@]})) ;;
      enter) armed=1 ;;
      escape) power_off ;;
    esac
  done
}
read_key_timeout() {
  local k
  IFS= read -rsn1 -t "$1" k || return 1
  [ -z "$k" ] && echo enter || echo other
}

# ─── 2. The disk's password, twice ───
password=''
ask_password() {
  local first='' second='' field=1 shown=0 help="8 caractères au moins · clavier ${layout/bepo/bépo}" warn=0 k
  while true; do
    clear_screen
    head_lines 2
    line "$INK" 'mot de passe du disque'
    line "$INK2" 'demandé à chaque allumage, avant tout le reste'
    line "$INK2" 'oublié, il ne se retrouve pas : le disque est perdu'
    line "$INK2" 'écrivez-le sur papier, rangé loin de l’ordinateur'
    gap
    local a b
    if [ "$shown" = 1 ]; then a=$first b=$second; else
      a=$(repeat '•' "${#first}")
      b=$(repeat '•' "${#second}")
    fi
    line "$INK2" "mot de passe      $INK$a$([ "$field" = 1 ] && printf '▏')"
    line "$INK2" "encore une fois   $INK$b$([ "$field" = 2 ] && printf '▏')"
    if [ "$warn" = 1 ]; then line "$INK" "                  $help"; else line "$FAINT" "                  $help"; fi
    gap
    line "$INK" "$enter continuer"
    line "$FAINT" "⇥ $([ "$shown" = 1 ] && echo masquer || echo afficher) · échap revenir"
    k=$(read_key)
    case "$k" in
      tab) shown=$((1 - shown)) ;;
      escape) return 1 ;;
      backspace) if [ "$field" = 1 ]; then first=${first%?}; else second=${second%?}; fi ;;
      char:*) if [ "$field" = 1 ]; then first+=${k#char:}; else second+=${k#char:}; fi ;;
      enter)
        if [ "${#first}" -lt 8 ]; then
          help='8 caractères au moins'
          warn=1
          field=1
        elif [ "$field" = 1 ]; then
          field=2
        elif [ "$first" != "$second" ]; then
          help='les deux sont différents · recommencez le second'
          warn=1
          second=''
        else
          password=$first
          return 0
        fi
        ;;
    esac
  done
}

# ─── 3. The copy: one line per task ───
tasks=('effacement du disque' 'partitions' 'chiffrement' 'copie du système' 'démarrage')
draw_copy() { # draw_copy <current index> <percent> <minutes left>
  local i
  clear_screen
  head_lines 3
  for i in "${!tasks[@]}"; do
    if [ "$i" -lt "$1" ]; then
      line "$INK2" "$(printf '%-24s' "${tasks[$i]}")$FAINT fait"
    elif [ "$i" -eq "$1" ]; then
      local cells=$(($2 * 20 / 100))
      line "$INK" "$(printf '%-24s' "${tasks[$i]}")$(repeat '█' "$cells")$FAINT$(repeat '░' $((20 - cells)))$INK $(printf '%3d' "$2") %"
    else
      line "$FAINT" "${tasks[$i]}"
    fi
  done
  gap
  line "$INK2" "ne pas éteindre, ne pas retirer la clé$FAINT · encore $3"
}
failed_step=''
fail() {
  failed_step=$1
  return 1
}
run() { "$@" >>"$log" 2>&1; }

install_system() {
  local system part_boot part_root
  system=$(tr ',' '\n' <<<"${CHARPENTIER_SYSTEMS:-}" | awk -F= -v l="$layout" '$1 == l { print $2 }')
  [ -n "$system" ] || { echo "no system for $layout" >>"$log"; fail 'copie du système : système absent de la clé'; return 1; }
  : >"$log"

  draw_copy 0 0 '5 min'
  umount -R /mnt >/dev/null 2>&1
  cryptsetup close racine >/dev/null 2>&1
  run wipefs -af "$disk" || { fail 'effacement du disque : le disque refuse l’écriture'; return 1; }
  run sgdisk --zap-all "$disk"
  run blkdiscard -f "$disk" || true

  draw_copy 1 0 '5 min'
  run sgdisk -n1:0:+1G -t1:ef00 -c1:demarrage -n2:0:0 -t2:8309 -c2:charpentier "$disk" ||
    { fail 'partitions : le disque refuse la table de partitions'; return 1; }
  run partprobe "$disk"
  run udevadm settle
  part_boot=/dev/disk/by-partlabel/demarrage
  part_root=/dev/disk/by-partlabel/charpentier
  run mkfs.vfat -F 32 -n DEMARRAGE "$part_boot" || { fail 'partitions : formatage impossible'; return 1; }

  draw_copy 2 0 '4 min'
  printf '%s' "$password" | run cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$part_root" ||
    { fail 'chiffrement : le disque n’a pas pu être chiffré'; return 1; }
  printf '%s' "$password" | run cryptsetup open --allow-discards --key-file - "$part_root" racine ||
    { fail 'chiffrement : le disque chiffré ne s’ouvre pas'; return 1; }
  run mkfs.ext4 -q -L racine /dev/mapper/racine || { fail 'chiffrement : formatage impossible'; return 1; }
  if ! { run mount /dev/mapper/racine /mnt && mkdir -p /mnt/boot && run mount -o umask=0077 "$part_boot" /mnt/boot; }; then
    fail 'chiffrement : le disque ne se monte pas'
    return 1
  fi

  # The copy: progress by the store paths already there.
  # Not `left`: that one is the block's column, for every line drawn.
  local total done=0 pid started now remaining
  total=$(nix-store -qR "$system" | wc -l)
  started=$(date +%s)
  nix --extra-experimental-features nix-command copy --no-check-sigs --to /mnt "$system" >>"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    done=$(find /mnt/nix/store -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
    [ "$done" -gt "$total" ] && done=$total
    now=$(date +%s)
    remaining='3 min'
    if [ "$done" -gt 10 ]; then
      local rest=$(((total - done) * (now - started) / done))
      remaining="$((rest / 60 + 1)) min"
    fi
    draw_copy 3 $((done * 100 / total)) "$remaining"
    sleep 1
  done
  wait "$pid" || { fail 'copie du système : erreur d’écriture sur le disque'; return 1; }

  draw_copy 4 0 '1 min'
  run nixos-install --system "$system" --no-root-passwd --no-channel-copy ||
    { fail 'démarrage : le démarrage n’a pas pu être installé'; return 1; }
  run umount -R /mnt
  run cryptsetup close racine
  draw_copy 5 100 '0 min'
  return 0
}

failure() {
  local k
  while true; do
    clear_screen
    head_lines 3
    line "$INV" ' l’installation s’est arrêtée '
    line "$INK" "$failed_step"
    line "$INK2" 'le disque n’est pas utilisable en l’état, la clé n’a pas bougé'
    gap
    line "$INK" "$enter recommencer depuis le début"
    line "$FAINT" 'd détail · échap éteindre'
    k=$(read_key)
    case "$k" in
      enter) return 0 ;;
      escape) power_off ;;
      char:d)
        printf '\e[2J\e[H%s' "$INK2"
        tail -n "$(($(tput lines 2>/dev/null || echo 40) - 2))" "$log"
        printf '%s\n%séchap revenir%s' "$OFF" "$FAINT" "$OFF"
        until [ "$(read_key)" = escape ]; do :; done
        ;;
    esac
  done
}

# ─── 4. The end: the key out first, never a restart on its own ───
the_end() {
  local k out=0
  while true; do
    key_present || out=1
    clear_screen
    head_lines 4
    line "$INK" 'charpentier est installé'
    gap
    line "$INK2" 'au redémarrage :'
    line "$INK2" '  1 le mot de passe du disque'
    line "$INK2" '  2 charpentier, et ses quatre réglages : wifi, code, synchronisation, compagnon'
    gap
    if [ "$out" = 1 ]; then
      line "$INK2" 'clé retirée'
      line "$INK" "$enter redémarrer"
    else
      line "$INK" 'retirez la clé pour continuer'
      line "$FAINT" "$enter redémarrer"
    fi
    if IFS= read -rsn1 -t 1 k; then
      [ -z "$k" ] && [ "$out" = 1 ] && { printf '\e[2J'; systemctl reboot; exit 0; }
    fi
  done
}

welcome
# « Recommencer depuis le début »: back to the disk, with its confirmation.
while true; do
  while true; do
    choose_disk
    ask_password && break
  done
  install_system && the_end
  failure
done
