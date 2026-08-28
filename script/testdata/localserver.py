#!/usr/bin/env python3
"""A loopback HTTP server that binds without a reverse DNS lookup.

Imported by the mocks beside it, and runnable on its own to serve a directory:

    python3 localserver.py <port>        serves the working directory

http.server.HTTPServer.server_bind() calls socket.getfqdn(host) to fill in
server_name, which nothing in these tests reads. On a GitHub macOS runner
127.0.0.1 has no reverse record and that one call waits out the resolver:
35 seconds per bind, once per test phase. It was five minutes of each of two
suites, and the reason the macOS jobs took twelve minutes to do two minutes of
work. On Linux the same lookup costs four milliseconds, which is why nobody
noticed.
"""
import socketserver
from http.server import HTTPServer, SimpleHTTPRequestHandler


class LocalHTTPServer(HTTPServer):
    # A phase that has just killed its mock must be able to rebind the port at
    # once rather than wait out TIME_WAIT. http.server sets this too; it is
    # spelled out because two of the mocks used to set it for themselves, and
    # losing it here would cost them a flaky start with nothing to point at.
    allow_reuse_address = True

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name, self.server_port = self.server_address[:2]


def serve(port, handler):
    LocalHTTPServer(("127.0.0.1", int(port)), handler).serve_forever()


if __name__ == "__main__":
    import sys

    class Quiet(SimpleHTTPRequestHandler):
        def log_message(self, *a):
            pass

    serve(sys.argv[1], Quiet)
