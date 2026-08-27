# Devices: what is known, and what needs testing

The list in the README is a list of devices *people happened to own*. It is not
a survey, and its shape says more about who has filed a report than about which
hardware can work. This page is the other half: what can be established without
a device in hand, and what still needs someone to try it.

## What actually decides whether a device works

Two things, and only two.

1. **The hostname its firmware asks for** has to be one Retuner can be pointed
   at. That is `InterceptDNs`, or an equivalent override on your own resolver.
2. **The request path shape** has to be one Retuner serves. There are two, and
   both are covered:

   ```
   AVRs               /setupapp/<vendor>/loginxml.asp
   Frontier Silicon   /setupapp/<vendor>/asp/BrowseXML/loginXML.asp
   ```

Everything else — brand, model year, whether the vendor's own portal is dead or
merely paywalled — follows from those two.

## What DNS says about which brands vTuner provisioned

`vtuner.com` has a **wildcard record**. `nad.vtuner.com`, `rotel.vtuner.com` and
`zzzz-no-such-oem.vtuner.com` all resolve to the same address, so a brand
resolving under vtuner.com proves nothing at all. What does mean something is a
name with its **own** A record, pointing where another known vTuner host points.

By that test, these have their own records — vTuner provisioned something for
them:

| address | names with their own record |
|---|---|
| 8.38.76.252 | `denon.vtuner.com`, `marantz.vtuner.com`, `radiomarantz.com`, `radiodenon.com` |
| 23.238.115.210 | `yamaha.vtuner.com`, `yradio.vtuner.com` |
| 192.227.77.203 | `onkyo.vtuner.com`, `radiosetup.com` |
| 75.126.113.179 | `pioneer.vtuner.com`, `technics.vtuner.com`, `arcam.vtuner.com`, `samsung.vtuner.com`, `teac.vtuner.com`, `harmankardon.vtuner.com` |
| 192.227.85.83 | `revox.vtuner.com`, `radioharmankardon.com` |

Two of those are why `radiodenon.com` and `radioharmankardon.com` are now in the
default `InterceptDNs`: each is a separate portal name sharing an address with a
host already known to be vTuner's. **That is infrastructure evidence, not a
device report.** Nobody has yet confirmed a receiver asking for either name.

`radiotechnics.com` resolves, but to an address that matches nothing else here,
so it is not in the list. `radiopioneer.com` and `radiolg.com` resolve to what
look like parking or CDN addresses. Those need a device, not more guessing.

What could not be checked from here: whether any of these hosts still *answer*.
The development environment cannot make outbound HTTP to them, so every claim
above is about DNS only.

## Wanted: these devices, tested

**Brands with their own vTuner record that nobody has reported.** These are the
best candidates — the infrastructure existed, and `*.vtuner.com` already covers
them, so they may work today with no change at all:

- **Technics** — `technics.vtuner.com` has its own record, and Panasonic
  [announced the end of the Technics vTuner feature on 30 November 2022](https://help.na.panasonic.com/answers/notice-discontinuation-of-technics-vtuner-feature/),
  after the service had already stopped in mid-August. Named models: **SU-G30,
  ST-C700D, SC-C500, SU-C550, SC-C70, ST-G30**, and the OTTAVA range.
- **Arcam** — `arcam.vtuner.com`. Arcam is among the brands that
  [moved to Airable](https://hifinews.com/content/internet-radio), which is what
  a vendor does when the old directory stops.
- **Samsung** — `samsung.vtuner.com`. Which product line is unknown; likely the
  networked audio and Blu-ray range rather than televisions.

**Brands documented as vTuner users, with no DNS evidence either way.** The
wildcard means their `<brand>.vtuner.com` tells us nothing, so their firmware
may ask for something else entirely:

- **Cambridge Audio**, **Rotel**, **NAD**, **Naim** — reported alongside Arcam
  as having moved to Airable.
- **LG** — [discontinued vTuner on 28 October 2015](https://www.lg.com/us/support/help-library/vtuner-service-discontinuation--20154860341006),
  the earliest cut-off found.
- **Philips**, **Loewe**, **Grundig**, **Magnat**, **Block**, **Sonoro** —
  European hi-fi and table-radio brands of the right era. Unverified.

**Already covered, unconfirmed on hardware.** The Frontier Silicon radios — Hama,
Medion, Technisat, Teufel, Roberts, Pure, Sangean, Auna, Karcher, Silvercrest.
The deeper path is served and asserted by `script/smoke-test.sh`, and
`*.wifiradiofrontier.com` is intercepted, but no one has reported a full browse
on a real radio.

**Out of scope: Reciva.** Grace Digital, Ocean Digital, Como Audio, Crane and
some Sangean radios used **Reciva**, not vTuner. Reciva shut down in January
2021 and its devices are just as dead, but the protocol is a different one and
Retuner does not speak it. Worth knowing before you buy something second-hand
hoping this will revive it.

## How to test a device, and what to report

The useful part of a report is **the hostname the device asks for**. You do not
have to capture packets to find it — Retuner will tell you.

1. Run Retuner with `[DNSServer] Enable=1` and `MessageInfoLevel=4`.
2. Point the device's DNS at the Retuner machine. On an AVR that usually means
   turning DHCP off in its network menu and entering the address by hand.
3. Press the internet-radio button and watch the log.

```
DNS Query intercept : radioyamaha.vtuner.com     <- a name already handled
DNS query not intercepted: something.example.com <- a name nobody has reported
```

The second line is the one worth sending. Anything a receiver asks for that is
not on the list is either ordinary traffic or a directory this project has never
heard of, and from inside the server those look identical — a human has to look.

Then, whatever happened:

- the exact model, and the hostname from the log;
- whether the menu appeared, and whether a station played;
- if the menu appeared but was empty, the log lines at `MessageInfoLevel=4` for
  the request that came back empty.

A report that says "it did not work" and names the model is still worth sending.
Half the entries in the README started that way.
