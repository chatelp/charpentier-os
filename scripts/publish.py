#!/usr/bin/env python3
"""Sends what the X250 receives to the sync server, through Cloudflare.

Cloudflare refuses a request body above 100 Mo: a file of 95 MiB or less goes
in one PUT; a larger one goes in parts of 95 MiB on the same path, with
`X-Part: <n>/<total>` and `X-Checksum-SHA256: <the whole file's hex>`; the
server answers 202 until the last part, then 201 once it has assembled and
checked the file (409: wrong sum, everything to send again).

    publish.py cache <store path>...   # their closures, into the binary cache
    publish.py file <url path> <file>  # one file (the install key's image)

The token is CHARPENTIER_CACHE_TOKEN (the CI's), sent as Bearer. For `cache`,
NIX_SIGNING_KEY_FILE names the secret key that signs the paths.

`cache` sends only the paths the server lacks (asked by their .narinfo):
copied, signed, into a local file cache, then sent, the NARs before their
.narinfo, so that a device never sees a .narinfo whose NAR is missing.
"""

import concurrent.futures
import hashlib
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

SERVER = os.environ.get("CHARPENTIER_SERVER", "https://charpentier.chatel.pm")
CACHE = f"{SERVER}/nix-cache"
PART = int(os.environ.get("CHARPENTIER_PART_BYTES", 95 * 1024 * 1024))  # smaller only to test
TOKEN = os.environ.get("CHARPENTIER_CACHE_TOKEN", "")


def request(method, url, body=None, headers=None):
    """One HTTP request; returns (status, body). Retries the network's failures."""
    headers = {"Authorization": f"Bearer {TOKEN}", **(headers or {})}
    for attempt in range(5):
        req = urllib.request.Request(url, data=body, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return r.status, r.read()
        except urllib.error.HTTPError as e:
            if e.code < 500 and e.code != 429:
                return e.code, e.read()
            error = f"{e.code} {e.read()[:200]!r}"
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            error = str(e)
        time.sleep(2**attempt)
        print(f"  again ({error}): {method} {url}", flush=True)
    sys.exit(f"✗ {method} {url}: {error}")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def put_file(url, path, checksum=None):
    """A file, in one PUT or in parts; fails on anything but 200/201/204."""
    size = os.path.getsize(path)
    if size <= PART:
        headers = {"Content-Type": "application/octet-stream"}
        if checksum:
            headers["X-Checksum-SHA256"] = checksum
        with open(path, "rb") as f:
            status, body = request("PUT", url, f.read(), headers)
        if status not in (200, 201, 204):
            sys.exit(f"✗ PUT {url}: {status} {body[:300]!r}")
        return
    checksum = checksum or sha256(path)
    total = (size + PART - 1) // PART
    with open(path, "rb") as f:
        for n in range(1, total + 1):
            part = f.read(PART)
            status, body = request(
                "PUT",
                url,
                part,
                {
                    "Content-Type": "application/octet-stream",
                    "X-Part": f"{n}/{total}",
                    "X-Checksum-SHA256": checksum,
                },
            )
            expected = 201 if n == total else 202
            if status != expected and not (n == total and status in (200, 204)):
                sys.exit(f"✗ PUT {url} part {n}/{total}: {status} {body[:300]!r}")
    print(f"  {os.path.basename(path)}: {total} parts", flush=True)


def missing(paths):
    """The store paths whose .narinfo the server does not have."""

    def absent(path):
        digest = os.path.basename(path).split("-", 1)[0]
        status, _ = request("HEAD", f"{CACHE}/{digest}.narinfo")
        if status in (401, 403):
            sys.exit(f"✗ the cache refuses the token ({status})")
        return status == 404

    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        return [p for p, a in zip(paths, pool.map(absent, paths)) if a]


def cache(roots):
    key = os.environ.get("NIX_SIGNING_KEY_FILE")
    if not key:
        sys.exit("✗ NIX_SIGNING_KEY_FILE: the secret key that signs the paths")
    closure = subprocess.run(
        ["nix", "path-info", "--recursive", *roots], check=True, capture_output=True, text=True
    ).stdout.split()
    todo = missing(closure)
    print(f"{len(closure)} paths, {len(todo)} to send", flush=True)
    if not todo:
        return
    with tempfile.TemporaryDirectory(dir=os.environ.get("RUNNER_TEMP")) as local:
        subprocess.run(
            ["nix", "copy", "--no-recursive", "--to", f"file://{local}?compression=zstd&secret-key={key}", *todo],
            check=True,
        )
        files = []
        for top, _, names in os.walk(local):
            for name in names:
                rel = os.path.relpath(os.path.join(top, name), local)
                if rel != "nix-cache-info":
                    files.append(rel)
        # The NARs (and logs) first, the .narinfo last.
        files.sort(key=lambda rel: (rel.endswith(".narinfo"), rel))
        for i, rel in enumerate(files, 1):
            print(f"[{i}/{len(files)}] {rel} ({os.path.getsize(os.path.join(local, rel)) >> 20} MiB)", flush=True)
            put_file(f"{CACHE}/{rel}", os.path.join(local, rel))


def main():
    if not TOKEN:
        sys.exit("✗ CHARPENTIER_CACHE_TOKEN: the CI's token on the sync server")
    if len(sys.argv) >= 3 and sys.argv[1] == "cache":
        cache(sys.argv[2:])
    elif len(sys.argv) == 4 and sys.argv[1] == "file":
        path = sys.argv[3]
        print(f"{path}: sha256…", flush=True)
        put_file(f"{SERVER}/{sys.argv[2].lstrip('/')}", path, sha256(path))
    else:
        sys.exit(__doc__)
    print("✓ sent", flush=True)


if __name__ == "__main__":
    main()
