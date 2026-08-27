# Running on a remote host (VPS)

Short answer: **yes, this works from a VPS** — an Oracle Free Tier instance, a small cloud VM, anything with a public address. Your AVR does not need YTuner on the same LAN. But three things behave differently off-LAN, and one of them is a hard limitation rather than a setting.

## 1. The built-in DNS server will not work from a NAT'd VPS

This is the part that surprises people, so it comes first.

YTuner's DNS service answers `*.vtuner.com` lookups with **the address of the interface the query arrived on** (`ABinding.IP` in `dnsserver.pas`). On a machine whose public address is NAT'd onto a private interface — which is exactly how Oracle Cloud, AWS, GCP and most VPS providers work — that is the *private* address, something like `10.0.0.x`. Your AVR would be told to connect there, and it would fail.

Setting `DNSServerIPAddress` to the public address does not help either: that value is passed through `GetLocalIP`, which only accepts an address that actually exists on a local interface and otherwise falls back to the first one it finds.

**So: turn the DNS server off and redirect the hostname on your own network instead.**

```ini
[DNSServer]
Enable=0
```

Then point `*.vtuner.com` at your VPS's public address using whatever already does DNS on your LAN — your router, Pi-hole, AdGuard Home, dnsmasq, OPNsense. That is the same override the built-in server exists to save you from configuring, and it is the only part of YTuner that genuinely needs to be near the AVR.

If your AVR lets you set a DNS server directly, pointing it at the VPS also works, provided you open UDP/53 — but think carefully before exposing a DNS resolver to the internet.

## 2. Set `ActAsHost`, or every link points somewhere unreachable

YTuner builds the URLs it hands the AVR — station links, icons, bookmarks — from `URLHost`. Left at `default` that resolves through `GetLocalIP` to the machine's own interface address, which on a VPS is the private one again.

```ini
[Configuration]
ActAsHost=203.0.113.10        ; your public IP, or a hostname
```

A hostname works, and so does an explicit port if you ever need one (`ActAsHost=radio.example.com:8080`), since the value is used verbatim.

## 3. Port 80 has to be reachable

The AVR's firmware contacts the vTuner hostname on port 80 and that is not configurable from YTuner's side, so the entry point must be there.

```ini
[WebServer]
WebServerIPAddress=default
WebServerPort=80
```

On **Oracle Cloud** specifically, two firewalls must both allow it and only one is obvious:

1. An ingress rule for TCP/80 in the VCN security list (or network security group).
2. The instance's own firewall. Oracle's images ship with restrictive `iptables`/`firewalld` rules, and forgetting this is the usual reason a correctly-configured security list still appears dead.

Binding port 80 needs privileges: run as root, grant the capability once with `setcap 'cap_net_bind_service=+ep' ./ytuner`, or put a reverse proxy in front.

## Restrict it to yourself

On a VPS your YTuner is world-reachable, so add a source restriction to that TCP/80 rule — your home IP, or a VPN. This matters more than it might seem, though less than you might fear:

- The icon, play and relay endpoints all take a **station id**, never a URL, so nobody can hand YTuner an arbitrary address and use it as an open proxy. It will only fetch things in its own station catalogue.
- The maintenance shutdown service is off by default, and when enabled it authorises on the peer address.
- But the bookmark endpoints write files keyed by the MAC in the query string, so a stranger could create or pollute bookmark files, and anyone who finds the port can browse and stream through your instance on your bandwidth.

`MyToken` is not authentication — the login endpoint hands it out to anyone who asks. Do not treat it as a lock.

## What actually crosses the VPS

Only menus, by default. Once the AVR has a station's URL it connects to the station **directly**, so audio never touches your VPS and its location does not affect playback at all — only how quickly menus paint.

That changes if you enable `RelayHTTPS`. A relayed station is fetched by YTuner and re-served, so its audio flows in and out of the VPS for as long as you listen, doubling that traffic against your egress allowance and adding a hop. Oracle's Free Tier allowance is generous enough that ordinary listening is not a concern, but it is worth knowing which switch moves audio onto the machine.

## Minimal VPS configuration

```ini
[Configuration]
ActAsHost=203.0.113.10        ; public IP or hostname -- not "default"

[WebServer]
WebServerIPAddress=default
WebServerPort=80

[DNSServer]
Enable=0                      ; redirect *.vtuner.com on your own network instead
```

Plus, on your LAN: `*.vtuner.com` → `203.0.113.10`.
