#!/usr/bin/env python3
"""A fake of the sync server's network boot (the app's apps/server/src/netboot.ts),
for scripts/try-netboot.sh: Pixiecore's API answered for one MAC only.
  GET /netboot/<secret>/v1/boot/<mac>        {kernel, initrd, cmdline}, the declared MAC only
  GET /netboot/<secret>/files/<f>            bzImage or initrd
argv: address port secret mac netboot-folder"""
import http.server, json, os, shutil, sys

addr, port, secret, mac, folder = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4].lower(), sys.argv[5]
base = f"/netboot/{secret}/"


class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if not self.path.startswith(base):
            return self.reply(404)
        rest = self.path[len(base):]
        if rest.startswith("v1/boot/"):
            asked = rest[len("v1/boot/"):].lower()
            sys.stderr.write(f"boot? {asked} -> {'installateur' if asked == mac else 'rien'}\n")
            if asked != mac:
                return self.reply(404, b'{"error":"unknown-machine"}')
            cmdline = open(os.path.join(folder, "cmdline")).read().strip()
            return self.reply(200, json.dumps({
                "kernel": f"http://{addr}:{port}{base}files/bzImage",
                "initrd": [f"http://{addr}:{port}{base}files/initrd"],
                "cmdline": cmdline,
            }).encode())
        if rest in ("files/bzImage", "files/initrd"):
            path = os.path.join(folder, rest.split("/")[1])
            size = os.path.getsize(path)
            sys.stderr.write(f"GET {rest} ({size >> 20} Mio)\n")
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(size))
            self.end_headers()
            with open(path, "rb") as f:
                shutil.copyfileobj(f, self.wfile, 1 << 20)
            return
        self.reply(404)

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer((addr, port), H).serve_forever()
