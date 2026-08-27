#!/usr/bin/env python3
"""Hostile DNS packets, for script/fuzz-test.sh.

The query name is pulled out of the datagram by hand in
TIdDNSServerProxy.IdDNS_UDPServerDoAfterQuery: a loop that reads a length byte,
copies that many bytes, and moves on until it meets a zero. Nothing in it is
bounded by the length of the packet.

The packets come in two groups, because they do not all get the same distance.
Indy parses the datagram before that handler is called, and drops anything it
cannot make sense of, so a truncated or nonsense packet never reaches the loop -
the MALFORMED group establishes that, and that nothing falls over on the way.
What does reach the loop is a well-formed query carrying an awkward name, and
that is the REACHING group: maximum labels, maximum length, bytes that are not
ASCII, an empty label in the middle, a name that is nothing but a dot. Those are
the ones that actually exercise the hand-written walk.

    fuzz-dns.py <port> [rounds]

Sends each packet, then a well-formed query for an intercepted name, and reports
the first packet after which that query stops being answered.
"""
import random
import socket
import struct
import sys

PORT = int(sys.argv[1])
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 200
ADDR = ("127.0.0.1", PORT)

HEADER = struct.pack(">HHHHHH", 0x1234, 0x0100, 1, 0, 0, 0)


def name(labels):
    return b"".join(bytes([len(l)]) + l for l in labels) + b"\x00"


def query(labels, qtype=1, qclass=1, header=HEADER):
    return header + name(labels) + struct.pack(">HH", qtype, qclass)


LIVE = query([b"radio", b"vtuner", b"com"])

VTUNER = [b"vtuner", b"com"]

# Well formed in every way Indy checks, and awkward in every way the name walk
# has to survive. Each of these reaches IdDNS_UDPServerDoAfterQuery; the ones
# under vtuner.com are intercepted, which is what makes their arrival visible in
# the log and lets the driver prove this group is not being dropped.
REACHING = [
    ("root name, just a dot", query([])),
    ("empty label in the middle", HEADER + b"\x03www\x00" + name(VTUNER) + struct.pack(">HH", 1, 1)),
    ("a 63 byte label", query([b"a" * 63] + VTUNER)),
    ("100 one-byte labels", query([b"a"] * 100 + VTUNER)),
    ("a name at the 255 byte limit", query([b"a" * 63, b"b" * 63, b"c" * 63] + VTUNER)),
    ("bytes that are not ASCII", query([bytes(range(200, 240))] + VTUNER)),
    ("a dot inside a label", query([b"a.b"] + VTUNER)),
    # 0x20 encoding: resolvers randomise the case of the name they forward, and
    # a case-sensitive comparison here fails intermittently and for no reason a
    # user could ever see.
    ("mixed case", query([b"RaDiO", b"VtUnEr", b"CoM"])),
    ("the apex on its own", query(VTUNER)),
    ("a very deep name under it", query([b"x"] * 8 + [b"radio"] + VTUNER)),
]

MALFORMED = [
    ("empty datagram", b""),
    ("one byte", b"\x01"),
    ("header cut in half", HEADER[:6]),
    ("header only, no question", HEADER),
    ("header plus a lone length byte", HEADER + b"\x05"),
    # The length byte says five, the packet ends after two. The copy is
    # clamped by Substring, but the cursor still steps past the end.
    ("length byte overruns the packet", HEADER + b"\x05vt"),
    ("no terminating zero", HEADER + b"\x06vtuner\x03com"),
    ("label length 63 to the edge", HEADER + b"\x3f" + b"a" * 10),
    ("label length 255", HEADER + b"\xff" + b"a" * 10),
    # 0xC0 is a compression pointer, not a length. Read as a length it asks for
    # 192 bytes that are not there, and the loop keeps going.
    ("compression pointer as first label", HEADER + b"\xc0\x0c"),
    ("pointer to itself", HEADER + b"\xc0\x0c" + struct.pack(">HH", 1, 1)),
    ("intercepted name, truncated type", query([b"radio", b"vtuner", b"com"])[:-3]),
    ("intercepted name, no type or class", HEADER + name([b"radio", b"vtuner", b"com"])),
    ("intercepted name, trailing junk", LIVE + b"\x00" * 64),
    ("255 labels of one byte", HEADER + name([b"a"] * 255) + struct.pack(">HH", 1, 1)),
    ("one label of 200 bytes", query([b"a" * 200])),
    ("nul bytes inside a label", query([b"vt\x00un\x00er", b"com"])),
    ("high bytes inside a label", query([bytes(range(200, 240)), b"com"])),
    ("qdcount says zero", query([b"radio", b"vtuner", b"com"],
                                header=struct.pack(">HHHHHH", 1, 0x0100, 0, 0, 0, 0))),
    ("qdcount says 65535", query([b"radio", b"vtuner", b"com"],
                                 header=struct.pack(">HHHHHH", 1, 0x0100, 0xFFFF, 0, 0, 0))),
    ("response bit set on a query", query([b"radio", b"vtuner", b"com"],
                                          header=struct.pack(">HHHHHH", 1, 0x8180, 1, 0, 0, 0))),
    ("type AAAA on an intercepted name", query([b"radio", b"vtuner", b"com"], qtype=28)),
    ("class CHAOS on an intercepted name", query([b"radio", b"vtuner", b"com"], qclass=3)),
    ("4 KB of zeros", HEADER + bytes(4096)),
    ("maximum size datagram", HEADER + bytes([63]) + b"z" * 65000),
]

CASES = REACHING + MALFORMED


def send(payload, timeout=0.4):
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.settimeout(timeout)
        s.sendto(payload, ADDR)
        try:
            return s.recvfrom(4096)[0]
        except (socket.timeout, ConnectionError):
            return None


def alive():
    # Three chances: a dropped datagram is not a dead server.
    for _ in range(3):
        if send(LIVE, timeout=1.0):
            return True
    return False


def main():
    if not alive():
        print("error: the server did not answer before any fuzzing", file=sys.stderr)
        return 2

    for label, payload in CASES:
        send(payload)
        if not alive():
            print("CRASHED after: " + label)
            print("packet: " + payload.hex())
            return 1

    rng = random.Random(20260827)
    for i in range(ROUNDS):
        kind = i % 3
        if kind == 0:
            payload = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 64)))
        elif kind == 1:
            # A real query with one byte corrupted: the shape survives, the
            # lengths stop agreeing with each other.
            payload = bytearray(LIVE)
            payload[rng.randrange(len(payload))] = rng.randrange(256)
            payload = bytes(payload)
        else:
            labels = [bytes(rng.randrange(97, 123) for _ in range(rng.randrange(1, 70)))
                      for _ in range(rng.randrange(1, 8))]
            payload = HEADER + name(labels)[:rng.randrange(1, 40)]
        send(payload)
        if not alive():
            print("CRASHED after random packet %d" % i)
            print("packet: " + payload.hex())
            return 1

    print("survived %d packets that reach the name walk, %d malformed, %d random"
          % (len(REACHING), len(MALFORMED), ROUNDS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
