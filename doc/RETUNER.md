# Retuner

Retuner is a maintained fork of [YTuner](https://github.com/coffeegreg/YTuner) by Greg P., which replaces the vTuner internet radio service that AV receivers of a certain age depend on. Upstream is MIT licensed and that licence, with its copyright notice, is carried forward here unchanged.

## Why the fork exists

Upstream's last change to `src/` was in **April 2025**; every commit since has been a README edit. Meanwhile the code carried a set of bugs worth fixing:

- Every Radio-browser API request was issued twice, doubling the latency of every uncached browse and search.
- No outbound HTTP call had a timeout. `TFPHTTPClient` defaults `IOTimeout` to 0 — wait forever — so a slow favicon host or the long-dead `radio567.vtuner.com` could pin a request thread indefinitely. An AVR's vTuner browser waits on one request at a time, so that freezes the device UI.
- Shared state was reached from several request threads with no locking, which is the likely cause of the `double free or corruption` aborts reported after days of uptime.
- Icon responses contained the source image and the converted one concatenated, defeating `IconSize` and tripping stricter decoders.
- The maintenance shutdown endpoint authorised callers by the `Host` header, which the caller supplies.
- The project only compiled with FPC **trunk**, so it could not be built with the compiler Debian, Ubuntu or Raspberry Pi OS ship — and on FPC 3.2.2 a latent stack buffer overflow in `CalcFileCRC32` crashed it during startup.

No upstream pull requests have been opened yet; the fixes are meant to go back, and this note will say so once they have. The fork exists so they are available now, not so the project is divided.

## Why "Retuner"

The obvious names are all taken, and two of them are taken in ways that matter.

**vTuner** is a live registered trademark (US Reg. #4010696, in commerce since 1998) belonging to the company whose service this software replaces. It is still shipping on current hardware. A name like "vTuner Plus" or "vTuner Neo" sits in the same product category as the mark and implies an official successor, which is the one impression to avoid.

**zTuner** collides with the **Parasound Ztuner**, a real FM/AM tuner component sold into custom hi-fi installations — the same industry, and the thing you would be competing against in search results.

**Radio Bridge** is an IoT sensor company that owns `radiobridge.com`.

"Retuner" is clear of all three, and it says what the software is for: bringing a receiver back into use after its manufacturer stopped supporting it. The prefix does the work — this is about hardware getting a second life, not about replacing a competitor.

## Roadmap

Done:

- **Builds on stock FPC** — `script/build.sh` needs no Lazarus IDE, `script/smoke-test.sh` checks the binary actually serves, and both run in CI on every push.
- **The stall fixes** — single-fetch API calls, timeouts on every outbound request, correct icon encoding.
- **Thread safety** — the caches, the database connection, the station list and the per-AVR config are no longer reached unsynchronised from several request threads.
- **Playlist resolution** (`ResolvePlaylists`, off by default) — unwraps `.m3u`, `.pls`, `.asx` and `.xspf` links to the stream behind them, for firmware that cannot follow a playlist.
- **HTTPS relay** (`RelayHTTPS`, off by default) — a growing share of stations are HTTPS-only, and these receivers cannot do TLS. The `all-as-http` setting only rewrites the scheme and hopes the station still answers on port 80, which increasingly it does not; the relay fetches the stream and re-serves it over plain HTTP, passing on the real content type and the station's ICY metadata. Off by default deliberately: it puts Retuner in the audio path for the whole time a station is playing, which is fine on a spare machine and less welcome on a small Raspberry Pi.
- **A stations editor in the browser** (`WebGUI`, off by default) — edit the stations list without touching files over SSH. Answers only loopback unless widened, and refuses to start without a password.
- **A Home Assistant add-on** — `retuner/` packages all of this for the Home Assistant add-on store, with the options exposed in the UI and the station files in the add-on's configuration folder. See [retuner/DOCS.md](../retuner/DOCS.md).
- **Running from a VPS** — see [REMOTE-HOSTING.md](REMOTE-HOSTING.md). Setup on the listener's side is one DNS field on the amplifier, with no router configuration and nothing extra at home.
- **A "local stations" main menu entry** driven by the configured country.
- **Podcasts** (`Podcasts`, off by default) — feeds listed in `podcasts.ini` become folders and their episodes become stations, so the receiver browses and plays them exactly as it does radio. Episode lists are fetched when a feed is opened rather than when the folder list is drawn, and cached, because the receiver asks for a directory a screenful at a time.

Next:

- **Browse improvements** — "recently played", and alphabetical sub-grouping so a country with thousands of stations stays navigable with a jog dial.
- **The web editor extended** to bookmarks, podcast feeds and per-AVR filters.

Under consideration:

- **Spotify** — playing Spotify through a receiver that has no Spotify Connect of its own. This works today with parts Retuner does not supply, and [SPOTIFY.md](SPOTIFY.md) documents the recipe: a Connect client such as [go-librespot](https://github.com/devgianlu/go-librespot) republishes playback as an Icecast stream, and Retuner presents that stream as a station. Bundling a Spotify client would tie the project's fate to an unofficial reimplementation of someone else's protocol, so the likelier direction is to make the join less manual — detect a local bridge, generate the station entry, relay track titles to the display. Music Assistant's newer Spotify pairing approach is worth studying first. Expect caveats either way: Premium is required, latency means the receiver's transport buttons cannot usefully drive playback, and Spotify has restricted these clients before.

## Building

See the Build section of the [README](../README.md). In short:

```
sudo apt install fp-compiler fp-units-fcl fp-units-net fp-units-db fp-units-misc lazarus-src zip git
./script/build.sh
./script/smoke-test.sh
```
