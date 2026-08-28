#!/usr/bin/env python3
"""Stands in for GitHub's release endpoints, for script/test-update.sh.

    mock-release.py <port> <version> <dir-with-assets> [digest-mode]

Serves the three things the updater asks for:

    /<owner>/<repo>/releases/latest                    -> 302 to the tag URL
    /<owner>/<repo>/releases/download/v<ver>/<asset>   -> the file
    /repos/<owner>/<repo>/releases/latest              -> JSON carrying a digest

digest-mode is "good" (the real sha256), "bad" (a wrong one, so the updater
must refuse) or "none" (no digest field at all, which must not stop it).
"""
import hashlib
import http.server
import json
import os
import sys

PORT = int(sys.argv[1])
VERSION = sys.argv[2]
ASSET_DIR = sys.argv[3]
DIGEST_MODE = sys.argv[4] if len(sys.argv) > 4 else "good"


def assets():
    out = []
    for name in sorted(os.listdir(ASSET_DIR)):
        if not name.endswith(".tar.gz"):
            continue
        entry = {"name": name, "browser_download_url": "/download/" + name}
        if DIGEST_MODE != "none":
            with open(os.path.join(ASSET_DIR, name), "rb") as f:
                real = hashlib.sha256(f.read()).hexdigest()
            entry["digest"] = "sha256:" + ("0" * 64 if DIGEST_MODE == "bad" else real)
        out.append(entry)
    return out


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="application/json"):
        body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path
        if path.endswith("/releases/latest") and path.startswith("/repos/"):
            self._send(200, json.dumps({"tag_name": "v" + VERSION, "assets": assets()}))
            return
        if path.endswith("/releases/latest"):
            # The updater reads the version out of where this lands, exactly as
            # it does against the real github.com.
            self.send_response(302)
            self.send_header("Location", path[: -len("latest")] + "tag/v" + VERSION)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        if "/releases/tag/" in path:
            self._send(200, "", "text/html")
            return
        if "/releases/download/" in path:
            name = path.rsplit("/", 1)[-1]
            full = os.path.join(ASSET_DIR, os.path.basename(name))
            if not os.path.isfile(full):
                self._send(404, "no such asset", "text/plain")
                return
            with open(full, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "application/gzip")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self._send(404, "not found", "text/plain")


http.server.HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
