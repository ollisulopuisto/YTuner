#!/usr/bin/env python3
"""Checks that every name the shipped configuration claims to intercept is
actually answered locally, for script/fuzz-test.sh.

The list in src/dnsserver.pas and the one in cfg/retuner.ini have to say the
same thing, and both have to survive a change to InterceptMatches - which has
already been wrong once, when '*.example.com' did not cover the apex and a
device asking for the bare name went silently to the real resolver.

    dns-intercepts.py <port> <expected-ip> <pattern,pattern,...>

Each pattern is checked twice, as a subdomain and as the apex, because a
receiver asks for whichever its firmware was built with. A control name that
nobody intercepts must NOT be answered: the test runs offline, so forwarding
cannot succeed, and an answer for it would mean the matching is too eager.
"""
import socket
import struct
import sys

PORT = int(sys.argv[1])
EXPECTED = sys.argv[2]
PATTERNS = [p.strip() for p in sys.argv[3].split(",") if p.strip()]

HEADER = struct.pack(">HHHHHH", 0x2A2A, 0x0100, 1, 0, 0, 0)


def query(host, timeout=1.5):
    name = b"".join(bytes([len(l)]) + l for l in host.encode().split(b".")) + b"\x00"
    packet = HEADER + name + struct.pack(">HH", 1, 1)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(timeout)
        s.sendto(packet, ("127.0.0.1", PORT))
        try:
            return s.recvfrom(4096)[0]
        except (socket.timeout, ConnectionError):
            return None


def answered_with(reply, ip):
    # The answer this server builds is the query echoed back with one A record
    # appended, so the address is the last four bytes.
    if not reply or len(reply) < 4:
        return False
    return ".".join(str(b) for b in reply[-4:]) == ip


def main():
    failures = 0
    for pattern in PATTERNS:
        apex = pattern[2:] if pattern.startswith("*.") else pattern
        for host in ("radio." + apex, apex):
            reply = query(host)
            if answered_with(reply, EXPECTED):
                print("  ok   %s answered with %s" % (host, EXPECTED))
            else:
                got = "no reply" if reply is None else ".".join(str(b) for b in reply[-4:])
                print("  FAIL %s -> %s, wanted %s" % (host, got, EXPECTED))
                failures += 1

    # Nothing intercepts this one. It may still get an answer - the upstream
    # resolver is reachable from some test environments and not others - so what
    # is checked is that the answer is not OURS. Testing for silence instead
    # passes for the wrong reason wherever forwarding happens to be broken.
    control = "example.org"
    reply = query(control)
    if not answered_with(reply, EXPECTED):
        print("  ok   %s is not answered with %s" % (control, EXPECTED))
    else:
        print("  FAIL %s was answered with %s, so the matching is too eager"
              % (control, EXPECTED))
        failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
