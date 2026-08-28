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

    mock-denon.py <port> [screen]

screens: menu (default) | search | playing

The flags are the ones a real Denon sends, not a guess. On a search-results
screen it reports 0 for the heading, 1 for every selectable station and 9 --
1 or 8 -- for the line the cursor is on; on Now Playing it reports 0 for
everything, cursor included, because there is nothing to select. A remote that
tests chFlag = 8 highlights nothing on any list whose items are selectable,
which is every list worth browsing.

The cursor moves. CurUp and CurDown shift which line carries bit 8, so a test
can click a name and then look at where the cursor ended up, rather than
counting button presses and hoping they meant something.
"""
import os
import sys
from http.server import BaseHTTPRequestHandler

from localserver import serve

REQUEST_LOG = os.environ.get("DENON_LOG")

SCREEN = sys.argv[2] if len(sys.argv) > 2 else "menu"

# Ten entries, as the receiver always sends. Line 0 is a heading, line 8 is the
# page counter, lines 9.. are empty padding.
MENU = [
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
MENU_FLAGS = [0, 8, 0, 0, 0, 0, 0, 4, 0, 0]

# Captured from a Denon showing search results: the heading is 0, every station
# is 1, and the one under the cursor is 9.
SEARCH = [
    "Search by Keyword",
    "Radio Dei Helsinki",
    "Radio Helsinki",
    "Radio Helsinki 92,6 MHz (128 kbps)",
    "Radio Helsinki 92,6 MHz (160 kbps)",
    "Radio Helsinki 92.6 FM",
    "Radio Helsinki 98,5 Mhz",
    "Yle Radio Suomi Helsinki",
    "   [    1/9  ]",
    "",
]
SEARCH_FLAGS = [0, 9, 1, 1, 1, 1, 1, 1, 0, 0]

# Now Playing: three lines, nothing selectable, no cursor anywhere.
PLAYING = ["Now Playing", "Radio Helsinki 92,6 MHz (160 kbps)", "Yle Radio Suomi"]
PLAYING_FLAGS = [0, 0, 0]

SCREENS = {
    "menu": (MENU, MENU_FLAGS),
    "search": (SEARCH, SEARCH_FLAGS),
    "playing": (PLAYING, PLAYING_FLAGS),
}
LINES, FLAGS = SCREENS[SCREEN]
FLAGS = list(FLAGS)

CURSOR_BIT = 8


def move_cursor(step):
    """CurUp and CurDown move the bit, within the lines that carry text.

    A receiver does not let the cursor leave the list, and a test that could
    push it past the end would be testing something no device does.
    """
    here = next((i for i, f in enumerate(FLAGS) if f & CURSOR_BIT), None)
    if here is None:
        return
    last = max(i for i, text in enumerate(LINES) if text.strip())
    there = min(max(here + step, 0), last)
    FLAGS[here] &= ~CURSOR_BIT
    FLAGS[there] |= CURSOR_BIT


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
        # A cursor command moves the cursor, so a test can ask where it ended
        # up rather than counting the presses that were meant to put it there.
        if "PutNetAudioCommand%2FCurDown" in body:
            move_cursor(1)
        elif "PutNetAudioCommand%2FCurUp" in body:
            move_cursor(-1)
        self._send("<?xml version=\"1.0\"?><rx></rx>\n")


serve(sys.argv[1], H)
