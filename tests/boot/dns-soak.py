#!/usr/bin/python3 -I
"""DNS soak test, runs INSIDE the VM as root (copied there by boot-test.sh).

Owner requirement (after run 45015996234, "lookup ghcr.io: no such host" while DNS had worked a
minute earlier): one lookup per second for 5 minutes, also during network events and during the
Quad9 fallback, with ZERO failed lookups. A failure is an image bug until proven otherwise, so
every failure is recorded with its time, phase, error text and the DNS routing at that moment.

Each second starts two lookups of the next name in a fixed list, in their own threads (a slow
lookup never delays the schedule):
  nss       getent ahosts NAME: the glibc/NSS path (nss-resolve -> systemd-resolved), which is
            the path bootc/podman (Go, cgo resolver) took when they reported "no such host"
  upstream  resolvectl query --cache=no NAME: bypasses resolved's cache, so every lookup really
            reaches the current upstream server (Quad9, or the router during the fallback)

Timeline (seconds from start). Events are what NetworkManager or the network do in real life:
   30  nmcli device reapply LINK                       real NetworkManager event
   60  burst of 8 dispatcher events                    like a flapping Wi-Fi
   90  JOIN a network that blocks Quad9: Quad9 blocked, then a real reconnect
       (nmcli connection up)                            captive portal / DNS-filtering network
  150  burst of 8 dispatcher events                    during the fallback
  180  Quad9 answers again, NO trigger                 the watcher must switch back by itself
  210  nmcli device reapply LINK
  240  Quad9 OUTAGE mid-session, NO trigger            the watcher must switch to the fallback
  275  Quad9 answers again, NO trigger
  300  end

Classification of a failed lookup:
  no-link    started while the link was down during the reconnect at 90 s (there is no network
             at all; reported, not a DNS failure)
  detect     started during the mid-session outage BEFORE the routing switched to the fallback
             (only the router could answer it, and by design it does not take part while Quad9
             is primary; reported separately, see ADR-0012)
  failure    everything else: must be ZERO

Usage: dns-soak.py LINK [DURATION]   (writes JSON lines to stdout; last line is the summary)
"""
import json
import subprocess
import sys
import threading
import time

LINK = sys.argv[1]
DURATION = int(sys.argv[2]) if len(sys.argv) > 2 else 300
NAMES = ["ghcr.io", "example.com", "fedoraproject.org", "flathub.org", "github.com",
         "mozilla.org", "kde.org", "quad9.net"]
DISPATCHER = "/usr/lib/NetworkManager/dispatcher.d/60-kiezel-dns-route"
NFT_BLOCK = ('add table inet kiezelsoak; '
             'add chain inet kiezelsoak out { type filter hook output priority 0; }; '
             'add rule inet kiezelsoak out ip daddr { 9.9.9.9, 149.112.112.112 } drop; '
             'add rule inet kiezelsoak out ip6 daddr { 2620:fe::fe, 2620:fe::9 } drop')

lock = threading.Lock()
results = []          # (t, method, name, ok, seconds, detail)
events = []
start = time.monotonic()


def now():
    return round(time.monotonic() - start, 1)


def emit(obj):
    with lock:
        print(json.dumps(obj), flush=True)


def sh(cmd, timeout=30):
    try:
        p = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return p.returncode, (p.stdout + p.stderr).strip()
    except subprocess.TimeoutExpired:
        return 124, "timeout"


def route():
    rc, out = sh(f"resolvectl default-route {LINK}", 5)
    return out.split()[-1] if rc == 0 and out else "?"


window = {}          # name -> [t_start, t_end]


def phase(t):
    for name, (a, b) in window.items():
        if a <= t <= (b if b is not None else 1e9):
            return name
    return "normal"


def lookup(method, name):
    t = now()
    t0 = time.monotonic()
    if method == "nss":
        rc, out = sh(f"getent ahosts {name}", 15)
        ok = rc == 0 and bool(out)
        detail = "" if ok else f"getent rc={rc} {out[:200]}"
    else:
        rc, out = sh(f"resolvectl query --cache=no --legend=no {name}", 20)
        ok = rc == 0
        detail = "" if ok else f"resolvectl rc={rc} {out[:200]}"
    dt = round(time.monotonic() - t0, 2)
    rec = {"t": t, "method": method, "name": name, "ok": ok, "secs": dt, "phase": phase(t)}
    rec["class"] = "ok" if ok else (rec["phase"] if rec["phase"] in ("no-link", "detect") else "failure")
    if not ok:
        rec["route"] = route()
        rec["error"] = detail
        rc2, glob = sh("resolvectl dns | sed -n 's/^Global: *//p'; resolvectl status | "
                       "grep -E 'Current DNS Server|DNS Servers' | head -4", 5)
        rec["dns"] = glob.replace("\n", " | ")
        emit({"failure": rec})
    with lock:
        results.append(rec)


def event(label, cmd):
    rc, out = sh(cmd, 90)
    rec = {"t": now(), "event": label, "rc": rc, "route_after": route()}
    events.append(rec)
    emit(rec)


def wait_route(want, limit):
    """Seconds until the link's default-route is `want` (None when it never got there)."""
    t0 = time.monotonic()
    while time.monotonic() - t0 < limit:
        if route() == want:
            return round(time.monotonic() - t0, 1)
        time.sleep(0.5)
    return None


def link_ready():
    rc, out = sh(f"resolvectl dns {LINK}", 5)
    return rc == 0 and any(ch.isdigit() for ch in out.split(":", 1)[-1])


def join_blocking_network():
    window["no-link"] = [now(), None]
    sh(f"nft '{NFT_BLOCK}'")
    rc, out = sh(f"nmcli connection up \"$(nmcli -g GENERAL.CONNECTION device show {LINK})\"", 90)
    while not link_ready():
        time.sleep(0.2)
    window["no-link"][1] = now()
    rec = {"t": now(), "event": "joined a network that blocks Quad9 (reconnect)", "rc": rc,
           "no_link_secs": round(window["no-link"][1] - window["no-link"][0], 1),
           "fallback_after_secs": wait_route("yes", 30)}
    events.append(rec)
    emit(rec)


def quad9_back():
    sh("nft delete table inet kiezelsoak")
    rec = {"t": now(), "event": "Quad9 answers again (no trigger)",
           "back_to_quad9_after_secs": wait_route("no", 30)}
    rec["ok"] = rec["back_to_quad9_after_secs"] is not None
    events.append(rec)
    emit(rec)


def outage():
    window["detect"] = [now(), None]
    sh(f"nft '{NFT_BLOCK}'")
    secs = wait_route("yes", 30)
    window["detect"][1] = now()
    rec = {"t": now(), "event": "Quad9 outage mid-session (no trigger)",
           "fallback_after_secs": secs, "ok": secs is not None}
    events.append(rec)
    emit(rec)


burst = " ; ".join(f"{DISPATCHER} {LINK} {e}" for e in
                   ["up", "dhcp4-change", "connectivity-change", "dhcp6-change",
                    "up", "connectivity-change", "dhcp4-change", "up"])
SCHEDULE = {
    30: lambda: event("nmcli device reapply", f"nmcli device reapply {LINK}"),
    60: lambda: event("dispatcher burst x8", burst),
    90: join_blocking_network,
    150: lambda: event("dispatcher burst x8 (in fallback)", burst),
    180: quad9_back,
    210: lambda: event("nmcli device reapply", f"nmcli device reapply {LINK}"),
    240: outage,
    275: quad9_back,
}

emit({"start": True, "link": LINK, "duration": DURATION, "route": route()})
threads = []
for i in range(DURATION):
    target = start + i
    delay = target - time.monotonic()
    if delay > 0:
        time.sleep(delay)
    if i in SCHEDULE:
        th = threading.Thread(target=SCHEDULE[i])
        th.start()
        threads.append(th)
    name = NAMES[i % len(NAMES)]
    for m in ("nss", "upstream"):
        th = threading.Thread(target=lookup, args=(m, name))
        th.start()
        threads.append(th)
for th in threads:
    th.join()
sh("nft delete table inet kiezelsoak 2>/dev/null")   # never leave the block behind

def count(cls, method=None):
    return sum(1 for r in results if r["class"] == cls and (method is None or r["method"] == method))


summary = {"summary": True, "seconds": DURATION, "lookups": len(results),
           "failed": count("failure"),
           "failed_by_method": {m: count("failure", m) for m in ("nss", "upstream")},
           "no_link": count("no-link"), "detect_window": count("detect"),
           "slowest_ok_secs": max((r["secs"] for r in results if r["ok"]), default=0),
           "events": events, "route_end": route()}
emit(summary)
