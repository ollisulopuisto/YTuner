#!/usr/bin/env python3
"""A stand-in for a Denon AVR's web interface, for script/test-remote.sh.

Serves the two endpoints the remote drives:

  GET  /goform/formNetAudio_StatusXml.xml   the browse list the AVR is showing
  POST /NetAudio/index.put.asp              cursor and search commands

The status document is the awkward part and the reason this mock exists rather
than a fixture file: szLine and chFlag are always ten entries whether or not the
receiver has ten lines to show, the trailing ones are empty, and one line is a
page counter rather than a list item. A remote that assumes the list is only the
non-empty entries gets the pagination row as a selectable station.

Every POST body is appended to RB_LOG-style DENON_LOG so a test can assert on
what was actually sent to the receiver -- an allowlist that silently forwards is
indistinguishable from one that works, unless you look at the wire.

    mock-denon.py <port>
"""
import os
import sys
from http.server import BaseHTTPRequestHandler

from localserver import serve

REQUEST_LOG = os.environ.get("DENON_LOG")

# Ten entries, as the receiver always sends. Line 0 is a heading, line 8 is the
# page counter, lines 9.. are empty padding.
LINES = [
    "Internet Radio",
    "*** Retuner ***",
    "Favourites",
    "My Stations",
    "Local Stations",
    "Radio Browser",
    "Recently Played",
    "Search by Keyword",
    "   [    1/7  ]",
    "",
]
FLAGS = ["0", "8", "0", "0", "0", "0", "0", "4", "0", "0"]


def status_xml():
    def block(tag, values):
        inner = "".join(f"<value>{v}</value>\n" for v in values)
        return f"<{tag}>\n{inner}</{tag}>\n"

    return (
        '<?xml version="1.0" encoding="utf-8" ?>\n<item>\n'
        + block("chFlag", FLAGS)
        + block("szLine", LINES)
        + "<InputFuncSelect><value>NETWORK</value></InputFuncSelect>\n"
        + "<NetFuncSelect><value>IRADIO</value></NetFuncSelect>\n"
        + "</item>\n"
    )


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, body, ctype="text/xml"):
        raw = body.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _record(self, text):
        if REQUEST_LOG:
            with open(REQUEST_LOG, "a") as fh:
                fh.write(text + "\n")

    def do_GET(self):
        self._record("GET " + self.path)
        if self.path.split("?")[0] == "/goform/formNetAudio_StatusXml.xml":
            self._send(status_xml())
        else:
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        self._record("POST " + self.path + " " + body)
        self._send("<?xml version=\"1.0\"?><rx></rx>\n")


serve(sys.argv[1], H)
