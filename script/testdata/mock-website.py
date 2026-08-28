#!/usr/bin/env python3
"""A station directory and the homepages it points at, for
script/test-preset-icons.sh.

    mock-website.py <port> [nofavicon]

One mock rather than two wired together: make-preset.py asks a directory for
candidates and then goes to each station's own site for a logo, and both halves
have to agree about which station is which. Serving them from one port keeps
the fixture honest and the test short.

The homepages are the shapes a logo scraper meets, and the ways they lie:

  /plain/      <link rel="icon"> with a root-relative href
  /absolute/   <link rel="shortcut icon"> with a full URL
  /apple/      only an apple-touch-icon, href relative to the page
  /bare/       no link at all -- the scraper should try /favicon.ico
  /notimage/   a link to something that answers text/html
  /huge/       a link to four megabytes of not-really-an-image
  /empty/      a link to a 200 with no body

A scraper that believes the markup ships a station logo that is really a login
page; one that believes the Content-Type without a size bound downloads
whatever the page points it at. Both are here.

With "nofavicon" the site has no /favicon.ico. Two instances on two ports is
the only way to cover both halves of that fallback: a site either has one or it
does not, and <origin>/favicon.ico is the same guess either way.
"""
import json
import sys

from http.server import BaseHTTPRequestHandler

from localserver import serve

# A one-pixel PNG. Small enough to inline, real enough to have a signature.
PNG = bytes([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
])

PAGES = {
    "/plain/": '<html><head><link rel="icon" href="/plain/icon.png">'
               "<title>Plain</title></head><body>radio</body></html>",
    "/absolute/": '<html><head><link rel="shortcut icon"'
                  ' href="%(base)s/absolute/logo.png"></head></html>',
    "/apple/": '<html><head><link rel="apple-touch-icon" href="apple.png">'
               "</head></html>",
    "/bare/": "<html><head><title>No link here</title></head></html>",
    "/notimage/": '<html><head><link rel="icon" href="/notimage/page.html">'
                  "</head></html>",
    "/huge/": '<html><head><link rel="icon" href="/huge/enormous.png">'
              "</head></html>",
    "/empty/": '<html><head><link rel="icon" href="/empty/nothing.png">'
               "</head></html>",
}

IMAGES = {"/plain/icon.png", "/absolute/logo.png", "/apple/apple.png"}
if len(sys.argv) < 3 or sys.argv[2] != "nofavicon":
    IMAGES.add("/favicon.ico")

# name, homepage path, favicon the directory already knows about
STATIONS = [
    ("Plain FM", "/plain/", ""),
    ("Absolute FM", "/absolute/", ""),
    ("Apple FM", "/apple/", ""),
    ("Bare FM", "/bare/", ""),
    ("Notimage FM", "/notimage/", ""),
    ("Huge FM", "/huge/", ""),
    ("Empty FM", "/empty/", ""),
    # Already has a logo: nothing should go looking for another one.
    ("Known FM", "/plain/", "/absolute/logo.png"),
]


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def base(self):
        return "http://127.0.0.1:%d" % self.server.server_address[1]

    def _send(self, body, ctype):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def directory(self):
        base = self.base()
        rows = []
        for name, home, favicon in STATIONS:
            rows.append({
                "name": name,
                "url": base + "/stream.mp3",
                "url_resolved": base + "/stream.mp3",
                "homepage": base + home,
                "favicon": (base + favicon) if favicon else "",
                "tags": "pop",
                "bitrate": 128,
                "codec": "MP3",
            })
        self._send(json.dumps(rows).encode(), "application/json")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path.startswith("/json/stations/"):
            self.directory()
            return
        if path == "/stream.mp3":
            self._send(b"\0" * 4096, "audio/mpeg")
            return
        page = PAGES.get(path)
        if page is not None:
            self._send((page % {"base": self.base()}).encode(),
                       "text/html; charset=utf-8")
            return
        if path in IMAGES:
            self._send(PNG, "image/png")
            return
        if path == "/notimage/page.html":
            self._send(b"<html>not an icon</html>", "text/html")
            return
        if path == "/huge/enormous.png":
            self._send(b"\0" * (4 * 1024 * 1024), "image/png")
            return
        if path == "/empty/nothing.png":
            self._send(b"", "image/png")
            return
        self.send_response(404)
        self.send_header("Content-Length", "0")
        self.end_headers()


if __name__ == "__main__":
    serve(sys.argv[1], H)
