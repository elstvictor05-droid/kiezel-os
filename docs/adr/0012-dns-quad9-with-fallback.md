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
- `/usr/libexec/kiezel/dns-route`: probes the global servers (Quad9) **directly**: a DNS answer
  over UDP/53 or a TCP connection to the DoT port 853 within ~3 s. Only after the probe does it set
  the router link's `default-route`: **no** when Quad9 answers, **yes** (fallback) when it does
  not. The probe never changes the routing, so a link in fallback never briefly drops out.
- Runs are serialised: the **NetworkManager dispatcher** (connect, DHCP change, connectivity
  change) only restarts `kiezel-dns-route.service`, and the script holds a lock
  (`/run/kiezel-dns-route.lock`). The service also runs every **5 minutes**
  (`kiezel-dns-route.timer`). After a captive-portal login, Kiezel goes back to Quad9 by itself.
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
- **Race regression:** while in fallback, the dispatcher hook, the service and a manual run start
  at once; the link is sampled every 0.5 s for 10 s and must stay `yes` in all 20 samples.
- `router` mode: no global DNS, link default route on, lookups work.
- Limitation: a real captive portal (HTTP redirect page) is not simulated in CI. The DNS side of
  it, "outside DNS does not answer", is. A real hotel or train Wi-Fi test is on the v0.1
  hardware checklist.

## Incident: run #31 (2026-11-22)

The first version probed through systemd-resolved: it set the link to `default-route=no`, asked
Quad9, and set it back to `yes` on failure. Two flaws, made visible by an intermittent boot-test
failure (5 green runs, then `default-route=no query=Timer expired`):

1. During every probe (up to 6 s) a link in fallback dropped out, so lookups hung, every
   5 minutes and on every network event, on exactly the networks that need the fallback.
2. The dispatcher called the script directly, in parallel with the timer's service. With Quad9
   blocked, NetworkManager's connectivity check failed, the dispatcher started a second run, and
   its `no` window overlapped the test's read.

Fixed with the direct probe and serialisation above. The boot test now waits for runs to settle
before reading, checks the concurrent case explicitly, and saves the journal of dns-route,
NetworkManager and resolved when a DNS check fails.

### Follow-up found by the first PR #9 run: systemd's start limit

With the dispatcher restarting the service on every network event, a connect, which sends
several events within a second, exceeded systemd's default start limit (5 starts in 10 s). The
unit ended in `start-limit-hit`, the boot showed `degraded`, and the fallback could not run at all
until the interval passed. Reproduced deterministically in a VM with a burst of 8 dispatcher
events (`Result=start-limit-hit`).

Fix:

- `StartLimitIntervalSec=0`: each run is a short oneshot and a restart replaces the previous one.
- `SuccessExitStatus=SIGTERM 143`: a probe interrupted by a restart is intended, not a failure.
  Without it every burst logged "Failed with result 'signal'".

After the fix, the same burst gives `Result=success`, `running`, and no failure lines. The boot
test now checks the burst, and when the system is degraded it records each failed unit's
`Result` and journal in the report.
