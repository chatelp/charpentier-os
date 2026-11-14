#!/usr/bin/env python3
"""The install key, tried from end to end without anyone at the keyboard.

Starts scripts/try-installer.sh without a window, reads the screen through
QEMU's monitor (screendump, then OCR) and types on it (sendkey), as an author
would: the keyboard (azerty), the disk erased, the password twice, the copy,
the key pulled, the restart, then the disk's password screen (a wrong
password, refused, then the right one) and the app's first screen.

    nix run .#test-installer                 # the newest image in dist/installer
    nix run .#test-installer -- --timeout-copy 3600   # emulation, no KVM

The development key, in a machine of its own, left running (SSH on port 2222):

    CHARPENTIER_VM=dist/vm-dev CHARPENTIER_IMAGES=dist/installer-dev     CHARPENTIER_MONITOR=45455 OUT=dist/test-installer-dev nix run .#test-installer --       --keep -- -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22

Screenshots of every step land in dist/test-installer; the run fails on the
first screen that does not come, with its screenshot and what the OCR read.
"""

import argparse
import os
import re
import socket
import subprocess
import sys
import time

MONITOR = ("127.0.0.1", int(os.environ.get("CHARPENTIER_MONITOR", "45454")))
OUT = os.environ.get("OUT", "dist/test-installer")
PASSWORD = "charpente"  # in azerty: letters away from a/q, z/w and m
WRONG = "charpentf"

# The keys QEMU sends are US positions; the installer and the disk's prompt
# read them in azerty.
AZERTY = {"a": "q", "q": "a", "z": "w", "w": "z", "m": "semicolon"}


def monitor(command):
    """One command on QEMU's human monitor; returns its answer."""
    with socket.create_connection(MONITOR, timeout=30) as s:
        data = b""
        while not data.endswith(b"(qemu) "):
            data += s.recv(4096)
        s.sendall(command.encode() + b"\n")
        data = b""
        while not data.endswith(b"(qemu) "):
            chunk = s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data.decode(errors="replace")


def keys(*names):
    for name in names:
        monitor(f"sendkey {name}")
        time.sleep(0.15)


def type_azerty(text):
    keys(*(AZERTY.get(c, c) for c in text))


shots = 0


def screen(name):
    """A screenshot, kept, and the text the OCR reads on it."""
    global shots
    shots += 1
    base = os.path.abspath(f"{OUT}/{shots:02d}-{name}")
    monitor(f"screendump {base}.ppm")
    time.sleep(0.5)
    subprocess.run(["magick", f"{base}.ppm", f"{base}.png"], check=True)
    # Small light text on a dark ground: inverted and enlarged, read twice,
    # as scattered words (the installer's screens) and as a page (the inverted
    # line « mot de passe refusé », which scattered reading misses).
    text = ""
    for size, psm in (("200%", "11"), ("300%", "3")):
        subprocess.run(
            ["magick", f"{base}.ppm", "-colorspace", "gray", "-negate", "-resize", size, f"{base}-ocr.png"],
            check=True,
        )
        text += subprocess.run(
            ["tesseract", f"{base}-ocr.png", "-", "-l", "fra", "--psm", psm],
            capture_output=True,
            text=True,
        ).stdout
        os.remove(f"{base}-ocr.png")
    os.remove(f"{base}.ppm")
    return base, text


def wait_for(pattern, timeout, name):
    """Waits for a screen whose text matches pattern; fails with the last one."""
    deadline = time.monotonic() + timeout
    while True:
        base, text = screen(name)
        if re.search(pattern, text, re.IGNORECASE):
            print(f"✓ {name}  ({base}.png)", flush=True)
            return
        if time.monotonic() > deadline:
            sys.exit(f"✗ {name}: « {pattern} » not seen in {timeout} s; last screen {base}.png reads:\n{text}")
        os.remove(f"{base}.png")
        global shots
        shots -= 1
        time.sleep(3)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--timeout-boot", type=int, default=300)
    parser.add_argument("--timeout-copy", type=int, default=1200)
    parser.add_argument("--keep", action="store_true", help="leave the machine running at the end")
    parser.add_argument("qemu", nargs="*", help="QEMU options, after --")
    args = parser.parse_args()

    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))

    vm = subprocess.Popen(["scripts/try-installer.sh", "--", "-display", "none", *args.qemu])
    try:
        for _ in range(60):
            try:
                monitor("info status")
                break
            except OSError:
                time.sleep(1)

        # 0. Welcome, azerty by default.
        wait_for(r"installer\s+charpentier", args.timeout_boot, "accueil")
        keys("ret")
        # 1. The disk: erased after ⏎ ⏎ (the second within 3 s).
        wait_for(r"effacer\s+et\s+installer", 60, "disque")
        keys("ret", "ret")
        # 2. The password, twice.
        wait_for(r"encore\s+une\s+fois", 60, "mot-de-passe")
        type_azerty(PASSWORD)
        keys("ret")
        type_azerty(PASSWORD)
        wait_for(r"encore\s+une\s+fois", 30, "mot-de-passe-saisi")
        keys("ret")
        # 3. The copy, then 4. the key pulled.
        wait_for(r"copie\s+du\s+syst", 120, "copie")
        wait_for(r"est\s+install", args.timeout_copy, "installe")
        monitor("device_del /machine/peripheral-anon/device[0]")
        wait_for(r"cl.\s+retir", 60, "cle-retiree")
        keys("ret")
        # The installed system: the disk's password screen, a wrong password, the right one.
        wait_for(r"mot\s+de\s+passe\s+du\s+disque", args.timeout_boot, "disque-chiffre")
        type_azerty(WRONG)
        keys("ret")
        wait_for(r"refus", 120, "mot-de-passe-refuse")
        type_azerty(PASSWORD)
        keys("ret")
        # The app, at its first start.
        wait_for(r"Bienvenue", args.timeout_boot, "app")
        print("installation, disk password and app: all seen", flush=True)
        if args.keep:
            print(f"left running; its monitor: {MONITOR[0]}:{MONITOR[1]}", flush=True)
            vm.wait()
    finally:
        try:
            monitor("quit")
        except OSError:
            pass
        vm.wait(timeout=60)


if __name__ == "__main__":
    main()
