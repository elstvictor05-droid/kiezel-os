# ADR-0012: DNS — Quad9 over TLS, with automatic fallback to the network's DNS

- **Status:** Accepted (owner decision 2026-11-21)
- **Date:** 2026-11-21
- **Phase:** 2

## Context

The owner chose: opportunistic DNS-over-TLS **with Quad9**, an automatic fallback to the
router's DNS, working local names (router, NAS) and captive portals, a visible privacy
trade-off in the welcome wizard, and a `ujust` way to turn it off.

A naive configuration (Quad9 as global DNS, router DNS on the link) does **not** give that.
systemd-resolved sends a lookup without a matching routing domain to the global servers **and**
to every link with `DefaultRoute=yes`, in parallel. The router would still see every lookup.

## Decision

| Lookup | Goes to |
|---|---|
| Normal names (example.com) | **Quad9 only**, DNS-over-TLS when port 853 works, otherwise plain DNS to Quad9 (opportunistic) |
| Local names: the DHCP domain (e.g. `fritz.box`, `home.arpa`) and single-label names through the search domain (`nas`, `router`) | The **router**, through the routing domain resolved derives from DHCP |
| Anything, while Quad9 does not answer (captive portal, a network that blocks outside DNS) | The **router** (automatic fallback) |

Mechanism:

- `/usr/lib/systemd/resolved.conf.d/50-kiezel-dns-over-tls.conf`: `DNS=` Quad9 (IPv4+IPv6, with
  TLS server name), `DNSOverTLS=opportunistic`.
- `/usr/libexec/kiezel/dns-route`: sets the router link's `default-route` to **no**, then
  checks whether Quad9 resolves `dns.quad9.net` within 6 s. If not, it sets the link back to
  **yes** (fallback).
- It runs from the **NetworkManager dispatcher** (connect, DHCP change, connectivity change) and
  every **5 minutes** (`kiezel-dns-route.timer`). After a captive-portal login, Kiezel goes back
  to Quad9 by itself.
- Modes (`/usr/libexec/kiezel/dns-mode`, `ujust`):
  - `quad9` (default);
  - `router`: the privacy choice "off", network DNS only;
  - `strict quad9|cloudflare`: Advanced, encrypted only, **no fallback**.

## Privacy trade-off (shown in the welcome wizard, Phase 3)

- **Quad9 sees the names you look up** instead of your internet provider. Quad9 is a
  non-profit in Switzerland that says it does not log IP addresses. That is a trust decision,
  not a technical guarantee.
- On networks that block port 853, the lookups go to Quad9 **unencrypted**. On networks where
  Quad9 is unreachable, they go to the router (fallback). Kiezel never stops resolving names in
  the default mode.
- Turning it off: `ujust kiezel-dns-router`, and a switch on the welcome page.

## Tests (boot test, every PR)

- Quad9 is the global DNS, the router link has `default-route=no`, and lookups work.
- DNS-over-TLS connections to port 853 are visible when the CI network allows them (otherwise
  reported as INFO; opportunistic by design).
- **Local names** `nas.home.arpa` and the short name `nas` resolve through the router (the QEMU
  DHCP domain `home.arpa`; the host maps the name).
- **Fallback:** Quad9 blocked with nftables inside the VM → the link switches to
  `default-route=yes` and lookups still work → block removed → back to `no`.
- `router` mode: no global DNS, link default route on, lookups work.
- Limitation: a real captive portal (HTTP redirect page) is not simulated in CI. The DNS side of
  it, "outside DNS does not answer", is. A real hotel or train Wi-Fi test is on the v0.1
  hardware checklist.
