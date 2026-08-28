#!/usr/bin/env python3
"""A stand-in for radio streams, for script/test-preset-strikes.sh.

    mock-stream.py <port> [dead-path ...]

Serves audio at any path, except the paths named on the command line, which
404. That inversion is deliberate: a test wants one station that plays and one
that does not, and which is which has to be decided per run so the same mock
can play a station back to life on a later pass.

Bodies are two kilobytes of silence rather than an empty 200, because
make-preset.py treats a 200 with no body as a failure -- a server that answers
and then sends nothing disappoints the receiver exactly as a 404 does.
"""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

DEAD = set(sys.argv[2:])


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in DEAD:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        body = b"\0" * 2048
        self.send_response(200)
        self.send_header("Content-Type", "audio/mpeg")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
