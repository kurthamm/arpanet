#!/usr/bin/env python3
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from pathlib import Path
from urllib.parse import unquote, urlparse
import os

ROOT = Path(__file__).resolve().parents[2]
HOST = "127.0.0.1"
PORT = int(os.environ.get("ARPANET_STATIC_PORT", "8888"))
BLOCKED_PREFIXES = (
    "/.git",
    "/PIDP Computer Lab.zip",
    "/PiDP Lab",
)

class ArpanetHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/arpanet_home.html")
            self.end_headers()
            return
        if path.startswith(BLOCKED_PREFIXES) or "/." in path:
            self.send_error(404)
            return
        return super().do_GET()

    def do_HEAD(self):
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/":
            self.send_response(302)
            self.send_header("Location", "/arpanet_home.html")
            self.end_headers()
            return
        if path.startswith(BLOCKED_PREFIXES) or "/." in path:
            self.send_error(404)
            return
        return super().do_HEAD()

    def list_directory(self, path):
        self.send_error(404)
        return None

if __name__ == "__main__":
    os.chdir(ROOT)
    server = ThreadingHTTPServer((HOST, PORT), ArpanetHandler)
    print(f"Serving ARPANET public files from {ROOT} on http://{HOST}:{PORT}", flush=True)
    server.serve_forever()
