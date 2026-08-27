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

The fixes are offered upstream as well. This fork exists so they are available now, not so the project is divided.

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

Next:

- **HTTPS relay** (off by default) — a growing share of stations are HTTPS-only, and these receivers cannot do TLS. Today the `all-as-http` setting just rewrites the scheme and hopes the station still answers on port 80, which increasingly it does not. An opt-in relay would let Retuner fetch the stream and re-serve it over plain HTTP. It is off by default deliberately: it puts Retuner in the audio path for the whole time a station is playing, which is fine on a spare machine and less welcome on a small Raspberry Pi.
- **Browse improvements** — a "local stations" entry driven by the configured country, "recently played", and alphabetical sub-grouping so a country with thousands of stations stays navigable with a jog dial.

Under consideration:

- **Spotify** — playing Spotify through a receiver that has no Spotify Connect of its own. The bridge already exists in projects such as [Spotycast](https://github.com/chourmovs/spotycast) and [librespot](https://github.com/librespot-org/librespot): Spotify playback is republished as an Icecast/HTTP stream, and Retuner's role is only to present that stream as a station the AVR can select. Music Assistant's newer Spotify pairing approach is worth evaluating before committing to an implementation. Expect caveats: Spotify Premium is required, latency means the receiver's transport buttons cannot usefully drive playback, and the underlying clients are unofficial — so this would be documented as an optional companion rather than bundled.
- **Podcasts** via RSS, which map cleanly onto the vTuner directory and station model.
- **A small web UI** for stations, bookmarks and per-AVR filters, instead of editing files by hand.

## Building

See the Build section of the [README](../README.md). In short:

```
sudo apt install fp-compiler fp-units-fcl fp-units-net fp-units-db fp-units-misc lazarus-src zip git
./script/build.sh
./script/smoke-test.sh
```
