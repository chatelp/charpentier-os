#!/usr/bin/env bash
# Tries the install key in a virtual machine shaped like the X250 (UEFI, a
# blank SATA disk, the image plugged as a USB key, 4 Go of memory), on the
# x86_64 Linux that builds it (the Yoga L13, under WSL2): KVM when /dev/kvm is
# there, emulation otherwise (slow: half an hour for the copy).
#
#   scripts/try-installer.sh            # a blank disk, the newest image in dist/installer
#   scripts/try-installer.sh --disk     # start again on the installed disk, key out
#   scripts/try-installer.sh -- -display none   # QEMU options after --, here no window
#
# The machine's monitor listens on 127.0.0.1:45454 (QEMU's human monitor), to
# type on it or take screenshots from a script:
#   echo 'sendkey ret' | nc -q1 127.0.0.1 45454
#   echo 'screendump shot.png -f png' | nc -q1 127.0.0.1 45454
#   echo 'device_del /machine/peripheral-anon/device[0]' | nc -q1 127.0.0.1 45454   # pull the key
# Everything lives in dist/vm: remove it to give the disk back.
set -euo pipefail
cd "$(dirname "$0")/.."
vm=dist/vm
mkdir -p "$vm"

# QEMU and the UEFI firmware from the same nixpkgs as the system.
qemu=$(nix --extra-experimental-features 'nix-command flakes' build --inputs-from . --no-link --print-out-paths nixpkgs#qemu)
ovmf=$(nix --extra-experimental-features 'nix-command flakes' build --inputs-from . --no-link --print-out-paths nixpkgs#OVMF.fd)

disk_only=0
if [ "${1:-}" = '--disk' ]; then
  disk_only=1
  shift
fi
[ "${1:-}" = '--' ] && shift

key=()
if [ "$disk_only" = 0 ]; then
  image=$(ls -t dist/installer/iso/*.iso 2>/dev/null | head -1)
  [ -n "$image" ] || { echo "pas d'image : scripts/nix.sh --out dist/installer build .#installer" >&2; exit 1; }
  rm -f "$vm/disk.qcow2"
  install -m 644 "$ovmf/FV/OVMF_VARS.fd" "$vm/vars.fd"
  key=(-drive "if=none,id=key,format=raw,readonly=on,file=$image"
    -device usb-storage,bus=xhci.0,drive=key,removable=on)
fi
[ -f "$vm/disk.qcow2" ] || "$qemu/bin/qemu-img" create -f qcow2 "$vm/disk.qcow2" 20G >/dev/null

accel=tcg,thread=multi
cpu=max
if [ -w /dev/kvm ]; then
  accel=kvm
  cpu=host
fi

exec "$qemu/bin/qemu-system-x86_64" -machine q35 -accel "$accel" -cpu "$cpu" -smp 4 -m 4096 \
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf/FV/OVMF_CODE.fd" \
  -drive "if=pflash,format=raw,file=$vm/vars.fd" \
  -device qemu-xhci,id=xhci \
  ${key[@]+"${key[@]}"} \
  -drive "if=none,id=disk,format=qcow2,file=$vm/disk.qcow2" -device ide-hd,drive=disk,bus=ide.0 \
  -device virtio-vga -nic none \
  -monitor tcp:127.0.0.1:45454,server,nowait \
  "$@"
