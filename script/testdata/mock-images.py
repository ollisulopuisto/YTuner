#!/usr/bin/env python3
"""Hostile image server, for script/fuzz-test.sh.

Serves the shapes a station logo URL can take when whoever controls it is not
friendly: truncated files, headers that declare far more pixels than the file
contains, bodies that are not images at all, and a redirect that never lands.
Every one of these reaches an in-process decoder in GetIcon, so every one of
them is a way to reach the memory manager from the internet.

    mock-images.py <port>

The catalogue is printed as "path type" lines on request of /_catalogue, so the
shell driver does not have to keep a duplicate list in step with this one.
"""
import struct
import sys
import zlib
from http.server import BaseHTTPRequestHandler, HTTPServer


def chunk(typ, data):
    return (struct.pack(">I", len(data)) + typ + data
            + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))


def png(width, height, rows=b"", bitdepth=8, colortype=0):
    ihdr = struct.pack(">IIBBBBB", width, height, bitdepth, colortype, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def grayscale_rows(width, height, value=0x80):
    return (b"\x00" + bytes([value]) * width) * height


VALID_PNG = png(16, 16, grayscale_rows(16, 16))

# 8000x8000 is 64 megapixels: 512 MB once TFPMemoryImage gives each pixel a
# TFPColor, from a file of a few hundred bytes. Nothing here is unusual - the
# declared size lives in IHDR and the pixel data does not have to match it. The
# same file at 64000x64000 asks for 32 GB and is no larger on the wire.
BOMB_PNG = png(8000, 8000, grayscale_rows(8000, 4))

# Under any per-pixel budget, over any sane per-edge one.
WIDE_PNG = png(65535, 1, grayscale_rows(64, 1))

# 3000x2 is a legal, small, unremarkable image - a banner. Scaled to fit a
# 200-pixel icon its height rounds to zero, and an image with no height is what
# the JPEG writer is then asked to encode.
THIN_PNG = png(3000, 2, grayscale_rows(3000, 2))

TRUNCATED_PNG = VALID_PNG[:len(VALID_PNG) // 2]
HEADER_ONLY_PNG = VALID_PNG[:33]

# Logical screen descriptor of 65535x65535 in a 30-byte file.
BOMB_GIF = (b"GIF89a" + struct.pack("<HH", 65535, 65535) + b"\xf0\x00\x00"
            + b"\x00\x00\x00\xff\xff\xff" + b",\x00\x00\x00\x00"
            + struct.pack("<HH", 65535, 65535) + b"\x00\x02\x02D\x01\x00;")

# SOF0 saying 30000x30000, and then nothing to decode.
BOMB_JPEG = (b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01"
             b"\x00\x00\xff\xc0\x00\x11\x08" + struct.pack(">HH", 30000, 30000)
             + b"\x03\x01\x11\x00\x02\x11\x01\x03\x11\x01")
TRUNCATED_JPEG = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01"

# A PNG signature and 16 MB of nothing in particular. The transfer itself is
# the attack: GetIcon read into memory with no ceiling.
FLOOD = b"\x89PNG\r\n\x1a\n" + bytes(1024) * 16384

PAYLOADS = {
    "/valid.png":      ("image/png", VALID_PNG),
    "/bomb.png":       ("image/png", BOMB_PNG),
    "/wide.png":       ("image/png", WIDE_PNG),
    "/thin.png":       ("image/png", THIN_PNG),
    "/truncated.png":  ("image/png", TRUNCATED_PNG),
    "/header.png":     ("image/png", HEADER_ONLY_PNG),
    "/empty.png":      ("image/png", b""),
    "/bomb.gif":       ("image/gif", BOMB_GIF),
    "/bomb.jpg":       ("image/jpeg", BOMB_JPEG),
    "/truncated.jpg":  ("image/jpeg", TRUNCATED_JPEG),
    "/html.png":       ("image/png", b"<html><body>not an image</body></html>"),
    "/nul.png":        ("image/png", bytes(4096)),
    "/flood.png":      ("image/png", FLOOD),
    # Content type says one thing, the bytes say another. The reader sniffs the
    # stream, so this must not become a way to pick the decoder.
    "/liar.png":       ("text/html", BOMB_PNG),
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/_catalogue":
            body = "".join(p + "\n" for p in PAYLOADS)
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body.encode())
            return
        if self.path == "/loop.png":
            self.send_response(302)
            self.send_header("Location", "/loop.png")
            self.end_headers()
            return
        if self.path not in PAYLOADS:
            self.send_response(404)
            self.end_headers()
            return
        ctype, body = PAYLOADS[self.path]
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            # Expected once the client enforces a byte ceiling and hangs up.
            pass

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
