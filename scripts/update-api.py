#!/usr/bin/env python3
"""A fake of the sync server's updates, for tests/update-channels.nix:
  GET  /api/updates/<channel>   <root>/api/<channel>.json (404: nothing published)
  GET, HEAD /nix-cache/<file>   <root>/cache/<file>, a binary cache
Every request asks for a token (Bearer or Basic, any value: the test is about
the channels, not the tokens), and is written to <root>/requests.log.
argv: root port"""
import http.server, os, sys

root, port = sys.argv[1], int(sys.argv[2])


class H(http.server.BaseHTTPRequestHandler):
    def reply(self, code, body=b"", head=False):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head:
            self.wfile.write(body)

    def serve(self, head):
        with open(os.path.join(root, "requests.log"), "a") as log:
            log.write(f"{self.client_address[0]} {self.command} {self.path}\n")
        if not self.headers.get("Authorization", "").startswith(("Bearer ", "Basic ")):
            self.send_response(401)
            self.send_header("WWW-Authenticate", "Basic")
            self.send_header("Content-Length", "0")
            return self.end_headers()
        if self.path.startswith("/api/updates/"):
            name = self.path[len("/api/updates/"):]
            file = os.path.join(root, "api", f"{name}.json") if name in ("latest", "dev") else ""
        elif self.path.startswith("/nix-cache/") and ".." not in self.path:
            file = os.path.join(root, "cache", self.path[len("/nix-cache/"):])
        else:
            file = ""
        if not file or not os.path.isfile(file):
            return self.reply(404, head=head)
        with open(file, "rb") as f:
            self.reply(200, f.read(), head)

    def do_GET(self):
        self.serve(False)

    def do_HEAD(self):
        self.serve(True)

    def log_message(self, *_):
        pass


http.server.ThreadingHTTPServer(("", port), H).serve_forever()
