# Retuner

Your AV receiver has an internet radio button that stopped working. Retuner
answers the service the receiver is still trying to reach, and the button works
again — the same menus, the same remote, no app.

This add-on runs Retuner on your Home Assistant machine.

## Installation

1. Settings → Add-ons → Add-on store → ⋮ → **Repositories**, and add
   `https://github.com/ollisulopuisto/YTuner`.
2. Install **Retuner** from the list. The first install compiles the source, so
   give it a few minutes — longer on a Raspberry Pi.
3. Start it, then point the receiver at it (below).

## Pointing the receiver at Retuner

The receiver has the old service's hostname built into its firmware, so the
whole job is making that name resolve to this machine. Pick whichever of these
you can actually do:

**On your router, Pi-hole or AdGuard Home** — add an override sending
`*.vtuner.com` to this machine's address. Nothing else changes, and the add-on's
own DNS service stays off. This is the tidiest option when you have a router you
can configure.

**With the add-on's DNS service** — turn on `dns_service`, then set the DNS
server on the receiver itself (Network settings, done with the remote) to this
machine's address. Only that one device is affected. Note that **port 53 is
often already taken** on a Home Assistant machine: if you run the AdGuard Home
or Pi-hole add-on, one of the two will fail to start, and the one that already
owns the port is the better place to do the redirect anyway.

Either way, the receiver then finds Retuner where it expected vTuner, and its
internet radio menu fills up.

## The options

**`act_as_host`** — the address the receiver is told to fetch stations and
artwork from. Leave it blank and Retuner uses this machine's own address, which
is right whenever the receiver is on the same network. Set it only when that
address is not the one the receiver should reach — for example, this machine is
behind NAT from the receiver's point of view.

**`web_port`** — 80 by default, because the receiver's firmware asks for port 80
and that is not negotiable from Retuner's side. If something else on this
machine already answers on port 80, the add-on will not start; changing the port
here only helps if you also have a proxy putting it back on 80.

**`local_country`** — put your country here (spelled as Radio Browser spells it,
e.g. `Finland`) and a **Local Stations** entry appears in the main menu going
straight to it. Otherwise reaching your own country means scrolling a few hundred
countries with a jog dial, every time. Blank hides the entry.

**`resolve_playlists`** — on by default here. Many station links are `.m3u` or
`.pls` files rather than the audio itself, and firmware of this era often cannot
follow one. With this on, Retuner opens the playlist and hands the receiver the
stream inside it. Costs one small fetch when a station is selected.

**`relay_https`** / **`relay_port`** — a growing share of stations are
HTTPS-only, and these receivers have no TLS at all. With the relay on, Retuner
fetches such a stream itself and re-serves it unencrypted on the local network.
The cost is real and worth knowing: a relayed station keeps a connection and a
thread open on this machine for as long as it plays. Fine on a spare PC, less
welcome on a Pi that is also running everything else in your house.

**`radiobrowser`** and **`cache_type`** — Radio Browser is the station
directory. `catMemStr` keeps the cache in memory and is a good default;
`catPermMemDB` is faster to browse but builds a full station database first,
which wants a few hundred MB and real CPU. On a Pi, stay with `catMemStr`.

**`my_stations`** — your own station list, kept in `stations.ini` in the add-on's
configuration folder. An example is written there on first start.

**`bookmarks`** — lets the receiver save favourites with its own remote, if it
supports that.

**`stations_editor`** — a small web page for editing the station list, on
`stations_editor_port`. **It will not start without a password**, because it
writes configuration files. Read the security note below before turning it on.

**`log_level`** — `normal` is right. `debug` logs every request, including
station names, and is for working out why something will not play.

**`advanced_ini`** — anything Retuner supports that the options above do not
cover. Include the `[Section]` header. It is merged into the generated
configuration rather than tacked on the end, so a setting here overrides the
same setting from the options above, and a section that already exists is added
to rather than duplicated:

```ini
[Configuration]
IconSize=75

[Radiobrowser]
RBAPIURL=http://de1.api.radio-browser.info
```

## Where your files live

The add-on's configuration folder (`/addon_configs/…_retuner/` on the host)
holds the things you curate:

- **`stations.ini`** — your own stations, grouped into categories:

  ```ini
  [Jazz]
  Radio Swiss Jazz=http://stream.srg-ssr.ch/m/rsj/mp3_128|http://example.com/logo.png
  ```

  The part after `|` is an optional logo and can be left off.

- **`avr.ini`** — per-receiver settings: which entries the main menu has,
  and filters for the Radio Browser directory. Written with sensible defaults
  on first start.

- **`<mac>.xml` / `bookmark.xml`** — bookmarks saved from the remote.

`ytuner.ini` is **generated from the options above every time the add-on
starts**, so editing it does nothing. Change the options instead, or use
`advanced_ini`.

Caches and the station database live in the add-on's private storage and can be
thrown away safely; they rebuild themselves.

## Security

The add-on shares the host's network, because the receiver has to reach it
directly and because the DNS service needs to see the address a query really
came from. That means every port it opens is open on your network. Specifically:

- **The radio service on `web_port`** is meant to be reachable — that is the
  whole point — and it has no authentication. Anyone on your network can browse
  it. It is not an open proxy: the play, icon and relay endpoints take a station
  id, never a URL, so they only ever fetch what is in the catalogue.
- **The stations editor** writes configuration files, so it is off by default
  and refuses to start without a password. It is reachable from anywhere on your
  network, protected by that password and nothing else. Choose a real one.
- **The DNS service** is off by default. Leave it off unless you are using it,
  and never expose port 53 to the internet from here.

## When it does not work

**The add-on will not start.** Check the log for `Binding of socket failed`.
Something else on this machine already owns port 80 (or 53 with `dns_service`
on). Stop the other service or do the DNS redirect at your router instead.

**The receiver still shows the old error.** It is still resolving the vTuner
hostname to the real thing. Confirm the redirect, then power-cycle the receiver
— they cache DNS answers, sometimes for a long time.

**Menus appear but nothing plays.** Turn on `resolve_playlists` if it is off.
If the station's address begins with `https`, turn on `relay_https`; these
receivers cannot do TLS at all.

**A whole category is empty.** Check the filters in `avr.ini`. The examples in
Retuner's own `cfg/avr.ini` include a demonstration tag filter that hides almost
everything — this add-on deliberately does not copy that file for exactly that
reason, but if you pasted from it, that is the likely cause.
