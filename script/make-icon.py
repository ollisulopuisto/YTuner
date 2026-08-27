#!/usr/bin/env python3
"""Renders the Retuner mark to PNG without any imaging library.

Shapes are signed distance fields, so edges get analytic anti-aliasing and
there is no supersampling to pay for. A tuning dial: teal scale, amber needle.
"""
import math, struct, zlib

BG     = (0x16, 0x20, 0x2b)   # deep slate, same family as the editor's dark theme
SCALE  = (0x3f, 0xc1, 0xcb)   # editor accent teal
NEEDLE = (0xff, 0xb4, 0x54)   # dial-lamp amber
HUB    = (0xe6, 0xeb, 0xef)

def sd_round_box(px, py, cx, cy, hw, hh, r):
    dx, dy = abs(px - cx) - (hw - r), abs(py - cy) - (hh - r)
    outside = math.hypot(max(dx, 0.0), max(dy, 0.0))
    return outside + min(max(dx, dy), 0.0) - r

def sd_ring(px, py, cx, cy, rad, half):
    return abs(math.hypot(px - cx, py - cy) - rad) - half

def sd_capsule(px, py, ax, ay, bx, by, r):
    vx, vy, wx, wy = bx - ax, by - ay, px - ax, py - ay
    L = vx * vx + vy * vy
    t = 0.0 if L == 0 else max(0.0, min(1.0, (wx * vx + wy * vy) / L))
    return math.hypot(wx - vx * t, wy - vy * t) - r

def sd_disc(px, py, cx, cy, r):
    return math.hypot(px - cx, py - cy) - r

def polar(cx, cy, ang, rad):
    a = math.radians(ang)
    return cx + rad * math.cos(a), cy - rad * math.sin(a)

def build(w, h):
    cx, cy = 0.5, 0.54          # dial centre, in unit coords of the shorter side
    px_unit = 1.0 / min(w, h)   # one pixel, in unit coords
    # tick marks across the upper arc, longer at both ends and at centre
    ticks = []
    for i in range(7):
        ang = 160.0 - i * 20.0
        long_one = i in (0, 3, 6)
        # inside the ring, not across it -- crossing it reads as gear teeth
        r_out = 0.272
        r_in = 0.196 if long_one else 0.232
        ax, ay = polar(cx, cy, ang, r_in)
        bx, by = polar(cx, cy, ang, r_out)
        ticks.append((ax, ay, bx, by, 0.024 if long_one else 0.015))
    nx, ny = polar(cx, cy, 62.0, 0.232)

    rows = []
    for y in range(h):
        row = bytearray()
        uy = (y + 0.5) / min(w, h) + (0 if h <= w else 0)
        ux_off = (w - min(w, h)) / (2.0 * min(w, h))
        for x in range(w):
            ux = (x + 0.5) / min(w, h) - ux_off
            # background plate: full bleed on a square, a rounded card on a banner
            if w == h:
                d = sd_round_box(ux, uy, 0.5, 0.5, 0.5, 0.5, 0.225)
            else:
                d = sd_round_box(ux, uy, 0.5, 0.5, (w / min(w, h)) * 0.5, 0.5, 0.225)
            a_bg = max(0.0, min(1.0, 0.5 - d / px_unit))
            r, g, b = BG
            a = a_bg

            def over(sd, col, alpha_scale=1.0):
                nonlocal r, g, b, a
                cov = max(0.0, min(1.0, 0.5 - sd / px_unit)) * alpha_scale
                if cov <= 0.0:
                    return
                cr, cg, cb = col
                r = cr * cov + r * (1 - cov)
                g = cg * cov + g * (1 - cov)
                b = cb * cov + b * (1 - cov)
                a = cov + a * (1 - cov)

            over(sd_ring(ux, uy, cx, cy, 0.325, 0.019), SCALE)
            for (ax, ay, bx, by, tw) in ticks:
                over(sd_capsule(ux, uy, ax, ay, bx, by, tw), SCALE)
            over(sd_capsule(ux, uy, cx, cy, nx, ny, 0.020), NEEDLE)
            over(sd_disc(ux, uy, cx, cy, 0.052), HUB)

            row += bytes((int(r + 0.5), int(g + 0.5), int(b + 0.5), int(a * 255 + 0.5)))
        rows.append(bytes(row))
    return rows

def write_png(path, w, h, rows):
    raw = b"".join(b"\x00" + r for r in rows)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))
    open(path, "wb").write(png)
    return len(png)

for path, w, h in (("retuner/icon.png", 512, 512), ("retuner/logo.png", 640, 320)):
    n = write_png(path, w, h, build(w, h))
    print(f"{path}  {w}x{h}  {n/1024:.1f} KB")
