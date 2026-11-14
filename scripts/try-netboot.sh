#!/usr/bin/env bash
# Tries the installer from the network (phase 5.9 ter, D-32) on the build
# machine, without root and without touching its network: in a network
# namespace of its own (unshare -rn), a bridge with
#   dnsmasq    the home box's DHCP, addresses only (Pixiecore never replaces it),
#   Pixiecore  in API mode, proxyDHCP, as on the prodesk2021,
#   a fake of the sync server's answer (scripts/netboot-api.py, the contract
#              of the app's apps/server/src/netboot.ts): the installer for one MAC,
#   QEMU       an X250-shaped machine (UEFI, a blank disk) that starts on the network.
#
#   scripts/try-netboot.sh                      # the declared MAC: the installer starts
#   scripts/try-netboot.sh --other              # another MAC: nothing is served
#   scripts/try-netboot.sh -- -display none     # QEMU options after --
#
# The image: scripts/nix.sh --out dist/netboot build .#netboot. Everything in
# dist/netboot-try: the logs, and the machine's monitor, a Unix socket
# (`echo 'screendump s.ppm' | nc -U -q1 dist/netboot-try/monitor.sock`).
set -euo pipefail
cd "$(dirname "$0")/.."
boot_mac=52:54:00:25:00:01 # the « X250 »
declared=$boot_mac
if [ "${1:-}" = --other ]; then
  boot_mac=52:54:00:99:99:99
  shift
fi
[ "${1:-}" = -- ] && shift
folder=$(readlink -f dist/netboot)
[ -e "$folder/initrd" ] || { echo "pas d'image : scripts/nix.sh --out dist/netboot build .#netboot" >&2; exit 1; }
out=$PWD/dist/netboot-try
mkdir -p "$out"
rm -f "$out"/*.log "$out/monitor.sock"
nix() { command nix --extra-experimental-features 'nix-command flakes' "$@"; }
tool() { nix build --inputs-from . --no-link --print-out-paths "nixpkgs#$1" | head -1; }
export QEMU OVMF PIXIECORE DNSMASQ IPROUTE ACCEL=tcg,thread=multi CPU=max
QEMU=$(tool qemu)
OVMF=$(tool OVMF.fd)
PIXIECORE=$(tool pixiecore)
DNSMASQ=$(tool dnsmasq)
IPROUTE=$(tool iproute2)
if [ -w /dev/kvm ]; then
  ACCEL=kvm
  CPU=host
fi
install -m 644 "$OVMF/FV/OVMF_VARS.fd" "$out/vars.fd"
rm -f "$out/disk.qcow2"
"$QEMU/bin/qemu-img" create -f qcow2 "$out/disk.qcow2" 20G >/dev/null
export OUT=$out FOLDER=$folder DECLARED=$declared BOOT_MAC=$boot_mac SECRET=essai-$RANDOM$RANDOM

# shellcheck disable=SC2016 # expanded inside the namespace
exec unshare -rn bash -euo pipefail -c '
  ip=$IPROUTE/bin/ip
  $ip link set lo up
  $ip link add br0 type bridge
  $ip addr add 10.77.0.1/24 dev br0
  $ip link set br0 up
  $ip tuntap add tap0 mode tap
  $ip link set tap0 master br0
  $ip link set tap0 up
  # The home box, in a namespace of its own on the same bridge (Pixiecore
  # needs port 67 too, as on two machines at home): addresses only, no boot
  # file. --no-daemon: it changes neither user nor group (a namespace
  # without setgroups refuses it).
  unshare -n sleep infinity &
  box=$!
  sleep 0.5
  $ip link add vbr type veth peer name vbox
  $ip link set vbr master br0
  $ip link set vbr up
  $ip link set vbox netns $box
  nsenter --net=/proc/$box/ns/net bash -c "
    $ip link set lo up && $ip link set vbox up && $ip addr add 10.77.0.2/24 dev vbox &&
    exec $DNSMASQ/bin/dnsmasq --no-daemon --interface=vbox --bind-interfaces --port=0 \
      --dhcp-range=10.77.0.50,10.77.0.99,1h --no-resolv --pid-file=$OUT/dnsmasq.pid \
      --dhcp-leasefile=$OUT/dnsmasq.leases --log-dhcp --log-facility=$OUT/dnsmasq.log
  " &
  python3 scripts/netboot-api.py 10.77.0.1 8081 "$SECRET" "$DECLARED" "$FOLDER" 2>"$OUT/api.log" &
  sleep 1
  $PIXIECORE/bin/pixiecore api "http://10.77.0.1:8081/netboot/$SECRET" \
    --port=8082 --listen-addr=10.77.0.1 --debug >"$OUT/pixiecore.log" 2>&1 &
  sleep 1
  exec $QEMU/bin/qemu-system-x86_64 -machine q35 -accel "$ACCEL" -cpu "$CPU" -smp 4 -m 6144 \
    -drive "if=pflash,format=raw,readonly=on,file=$OVMF/FV/OVMF_CODE.fd" \
    -drive "if=pflash,format=raw,file=$OUT/vars.fd" \
    -drive "if=none,id=disk,format=qcow2,file=$OUT/disk.qcow2" -device ide-hd,drive=disk,bus=ide.0 \
    -device virtio-vga \
    -netdev tap,id=n0,ifname=tap0,script=no,downscript=no \
    -device virtio-net-pci,netdev=n0,mac="$BOOT_MAC",bootindex=1 \
    -monitor "unix:$OUT/monitor.sock,server,nowait" \
    "$@"
' try-netboot "$@"
