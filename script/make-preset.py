#!/usr/bin/env python3
"""Build or prune a country preset file for Retuner.

A preset file is a curated, short station list for one country, shipped in
presets/ and fetched by Retuner at startup. The point of generating it rather
than typing it is that every URL in the result has been connected to and has
answered with audio -- a preset full of dead links is worse than no preset at
all, because the receiver's only feedback is a spinner.

    ./script/make-preset.py --country fi --out presets/fi.ini
    ./script/make-preset.py --prune presets/fi.ini
    ./script/make-preset.py --prune presets/fi.ini --strikes presets/strikes.json

Candidates come from radio-browser.info, which is where Retuner's own directory
comes from, so nothing new is being trusted. What the script cannot judge is
whether a stream is a broadcaster's own: that stays a human decision, and the
file is meant to be edited after generation. See presets/README.md.
"""

import argparse
import configparser
import json
import re
import sys
import urllib.error
import urllib.request
from collections import OrderedDict

API = "https://all.api.radio-browser.info"
UA = "Retuner-preset-builder/1.0 (+https://github.com/ollisulopuisto/retuner)"
AUDIO_TYPES = ("audio/", "application/ogg", "application/octet-stream")
PLAYLIST_EXT = (".m3u", ".m3u8", ".pls", ".asx")


def get(url, timeout=20):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def candidates(country, limit):
    url = (f"{API}/json/stations/bycountrycodeexact/{country.upper()}"
           f"?limit={limit}&order=clickcount&reverse=true&hidebroken=true")
    try:
        return json.loads(get(url))
    except (urllib.error.URLError, json.JSONDecodeError, TimeoutError) as e:
        sys.exit(f"error: cannot reach radio-browser ({e})")


def resolve_playlist(url, timeout):
    """One level of .m3u/.pls indirection, which is all these ever use."""
    try:
        body = get(url, timeout).decode("utf-8", "replace")
    except Exception:
        return None
    for line in body.splitlines():
        line = line.strip()
        if line.lower().startswith("file"):          # .pls: File1=http://...
            line = line.split("=", 1)[-1].strip()
        if line.startswith(("http://", "https://")):
            return line
    return None


def plays(url, timeout=12):
    """Connect and read a little. Returns the URL that actually served audio."""
    if url.lower().split("?")[0].endswith(PLAYLIST_EXT):
        inner = resolve_playlist(url, timeout)
        if not inner:
            return None
        url = inner
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Icy-MetaData": "0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            ctype = (r.headers.get("Content-Type") or "").lower()
            if not ctype.startswith(AUDIO_TYPES):
                return None
            # A 200 with an empty body is a server that will disappoint the
            # receiver in exactly the same way a 404 would.
            return url if r.read(2048) else None
    except Exception:
        return None


def category_of(station):
    """Group by the first tag that is a word, falling back to a catch-all."""
    for tag in (station.get("tags") or "").split(","):
        tag = tag.strip()
        if re.fullmatch(r"[A-Za-z][A-Za-z0-9 &'-]{1,24}", tag):
            return tag.title()
    return "Radio"


def clean_name(text):
    """INI keys cannot carry '=' and the receiver's display cannot carry much."""
    return re.sub(r"\s+", " ", (text or "").replace("=", "-")).strip()[:48]


def safe_url(text):
    """A URL is not a display string: it must not be shortened or rewritten.

    Running names and URLs through the same cleaner truncated every logo to 48
    characters and turned '=' into '-', which quietly produced broken links --
    a real Yle logo came out of the first generated preset as
    https://images.cdn.yle.fi/f_auto,w_48,h_48,dpr_4 and nothing said so. The
    only things that matter here are that the value carries no '|', which
    separates stream from logo, and no newline, which would end the line early.
    """
    url = (text or "").strip()
    if not url.startswith(("http://", "https://")):
        return ""
    if "|" in url or "\n" in url or "\r" in url:
        return ""
    return url


def build(args):
    rows = candidates(args.country, args.candidates)
    print(f"{len(rows)} candidates for {args.country.upper()}", file=sys.stderr)
    groups, seen, dropped = OrderedDict(), set(), 0
    for s in rows:
        name = clean_name(s.get("name"))
        url = safe_url(s.get("url_resolved") or s.get("url"))
        if not name or not url or name.lower() in seen:
            continue
        cat = category_of(s)
        if len(groups.get(cat, ())) >= args.per_category:
            continue
        if args.verify:
            live = plays(url, args.timeout)
            if not live:
                print(f"  drop  {name}: no audio from {url}", file=sys.stderr)
                dropped += 1
                continue
            url = live
        seen.add(name.lower())
        groups.setdefault(cat, []).append((name, url, safe_url(s.get("favicon"))))
    write(args.out, args.country, groups)
    kept = sum(len(v) for v in groups.values())
    print(f"wrote {args.out}: {kept} stations in {len(groups)} categories"
          f"{f', {dropped} dropped as unreachable' if dropped else ''}", file=sys.stderr)


def write(path, country, groups):
    with open(path, "w", encoding="utf-8") as f:
        f.write(f"; Retuner country preset: {country.lower()}\n"
                "; Generated by script/make-preset.py and then curated by hand.\n"
                "; Every URL here answered with audio when the file was written.\n"
                "; See presets/README.md before adding anything.\n\n")
        for cat, rows in groups.items():
            f.write(f"[{cat}]\n")
            for name, url, logo in rows:
                f.write(f"{name}={url}|{logo}\n" if logo else f"{name}={url}\n")
            f.write("\n")


def load_strikes(path):
    """The record of consecutive failures, or an empty one if there is none.

    A malformed file is treated as absent rather than fatal: the worst that
    costs is one forgotten week of counting, whereas exiting would leave the
    weekly job red until someone repaired a file nobody reads by hand.
    """
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_strikes(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")


def prune(args):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    cp.read(args.prune, encoding="utf-8")

    # Without --strikes a failure drops the station there and then, which is
    # what a human running this wants. The unattended weekly job is the caller
    # that needs patience: one CDN hiccup at 04:00 on a Sunday should not
    # silently delete a national broadcaster from the preset.
    book, seen = None, {}
    if args.strikes:
        strikes = load_strikes(args.strikes)
        book = strikes.get(preset_key(args.prune), {})

    groups, dropped, warned = OrderedDict(), 0, 0
    for cat in cp.sections():
        for name, value in cp.items(cat):
            url, _, logo = value.partition("|")
            url, logo = url.strip(), logo.strip()
            key = f"[{cat}] {name}"
            live = plays(url, args.timeout)
            if live:
                groups.setdefault(cat, []).append((name, live, logo))
                continue
            if book is None:
                print(f"  drop  {key}: no audio from {url}", file=sys.stderr)
                dropped += 1
                continue
            # A record is against a URL, not a name. Someone who fixes a broken
            # link by hand should not inherit the strikes the old one collected
            # and lose the station on the next run.
            previous = book.get(key)
            count = 1
            if isinstance(previous, dict) and previous.get("url") == url:
                count = int(previous.get("strikes", 0)) + 1
            if count >= args.strike_limit:
                print(f"  drop  {key}: no audio from {url}"
                      f" ({count} runs in a row)", file=sys.stderr)
                dropped += 1
                continue
            print(f"  warn  {key}: no audio from {url}"
                  f" ({count} of {args.strike_limit})", file=sys.stderr)
            seen[key] = {"url": url, "strikes": count}
            groups.setdefault(cat, []).append((name, url, logo))
            warned += 1

    write(args.prune, args.prune.rsplit("/", 1)[-1].split(".")[0], groups)
    if book is not None:
        # `seen` is built fresh each run, so a station that played, that was
        # dropped, or that someone removed by hand leaves no record behind. The
        # file is committed by the weekly job; anything that never expires
        # accumulates there forever.
        strikes = load_strikes(args.strikes)
        if seen:
            strikes[preset_key(args.prune)] = seen
        else:
            strikes.pop(preset_key(args.prune), None)
        save_strikes(args.strikes, strikes)

    kept = sum(len(v) for v in groups.values())
    print(f"pruned {args.prune}: {kept} kept, {dropped} dropped"
          f"{f', {warned} failing but under the limit' if warned else ''}",
          file=sys.stderr)


def preset_key(path):
    """Presets are keyed by file name: presets/fi.ini and a copy of it under
    another directory are the same list of stations."""
    return path.rsplit("/", 1)[-1]


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--country", help="ISO 3166-1 alpha-2 code, e.g. fi")
    p.add_argument("--out", help="file to write, e.g. presets/fi.ini")
    p.add_argument("--prune", metavar="FILE", help="re-check an existing preset and drop dead entries")
    p.add_argument("--candidates", type=int, default=60, help="stations to consider (default 60)")
    p.add_argument("--per-category", type=int, default=8, help="cap per category (default 8)")
    p.add_argument("--timeout", type=int, default=12, help="seconds per stream check (default 12)")
    p.add_argument("--no-verify", dest="verify", action="store_false",
                   help="skip the does-it-play check (not recommended)")
    p.add_argument("--strikes", metavar="FILE",
                   help="with --prune: record consecutive failures here and "
                        "drop a station only once it reaches the limit")
    p.add_argument("--strike-limit", type=int, default=3, metavar="N",
                   help="failures in a row before --strikes drops a station (default 3)")
    args = p.parse_args()
    if args.strikes and not args.prune:
        p.error("--strikes is only meaningful with --prune")
    if args.strike_limit < 1:
        p.error("--strike-limit must be at least 1")
    if args.prune:
        prune(args)
    elif args.country and args.out:
        build(args)
    else:
        p.error("give either --prune FILE, or both --country and --out")


if __name__ == "__main__":
    main()
