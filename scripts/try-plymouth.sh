#!/usr/bin/env bash
# Tries the disk's password screen (hosts/x250/plymouth) in a window, on the
# x86_64 Linux that builds it (the ThinkPad, under WSL2 with WSLg): plymouthd
# with its X11 renderer, the theme and font of the X250's initrd, no root (a
# user namespace with its own /run and /etc). The keyboard is the window's,
# not the console's: the layout is checked in the virtual machine only.
#
#   scripts/try-plymouth.sh start           # the daemon and its window
#   scripts/try-plymouth.sh ask             # what systemd-cryptsetup asks; again after ⏎ = a wrong password
#   scripts/try-plymouth.sh shot <file.png> # a screenshot of the window
#   scripts/try-plymouth.sh stop
set -euo pipefail
cd "$(dirname "$0")/.."
state=dist/plymouth
mkdir -p "$state"
nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }
build() { nix build --no-link --print-out-paths "$@"; }
initrd='.#nixosConfigurations.x250.config.boot.initrd.systemd.contents'
plymouth=$(build --inputs-from . nixpkgs#plymouth)
window() { nix shell --inputs-from . nixpkgs#xwininfo -c xwininfo -root -tree | awk '/"plymouthd"/ && /[0-9]+x[0-9]+\+0\+0/ { print $1; exit }'; }

case ${1:-} in
start)
  themes=$(build "$initrd.\"/etc/plymouth/themes\".source")
  fonts=$(build "$initrd.\"/etc/plymouth/fonts\".source")
  printf '<?xml version="1.0"?><fontconfig><dir>%s</dir><cachedir>/tmp/plymouth-fc</cachedir></fontconfig>\n' "$fonts" >"$state/fonts.conf"
  # plymouthd needs a controlling terminal (the pty), its plugins and themes
  # under /run/plymouth, and no serial console (WSL has hvc0).
  FONTCONFIG_FILE=$PWD/$state/fonts.conf setsid python3 -c 'import pty, sys; pty.spawn(sys.argv[1:])' \
    unshare -rm bash -c "
      mount -t tmpfs none /run && mkdir -p /run/plymouth/themes &&
      ln -s $plymouth/lib/plymouth /run/plymouth/plugins &&
      ln -s $themes/charpentier /run/plymouth/themes/charpentier &&
      exec $plymouth/sbin/plymouthd --no-daemon --debug --debug-file=$PWD/$state/debug.log \
        --kernel-command-line='splash plymouth.splash=charpentier plymouth.ignore-serial-consoles'
    " </dev/null >"$state/daemon.log" 2>&1 &
  sleep 3
  "$plymouth/bin/plymouth" show-splash
  ;;
ask) setsid "$plymouth/bin/plymouth" ask-for-password --prompt='Please enter passphrase for disk charpentier (racine)' >"$state/answer" 2>&1 & ;;
shot) nix shell --inputs-from . nixpkgs#imagemagick -c import -window "$(window)" "$2" ;;
stop) "$plymouth/bin/plymouth" quit || pkill -f "$plymouth/sbin/plymouthd" ;;
*) sed -n '2,13p' "$0" >&2; exit 1 ;;
esac
