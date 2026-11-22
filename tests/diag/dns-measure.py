# In-VM DNS measurement for the run #45 investigation (diagnostic only, not a product test).
# Usage: dns-measure.py VARIANT STEADY CYCLES BLOCK_SECS AFTER
#   STEADY lookups at 1/s, then CYCLES x [Quad9 (IPv4+IPv6) dropped for BLOCK_SECS with a lookup
#   every second (as the boot test's earlier DNS checks do) -> unblock -> wait until the link is
#   back to default-route=no (Quad9 in use) -> AFTER lookups at 1/s].
# A lookup fails when "resolvectl query --cache=no" OR "getent ahosts" fails.
import json, subprocess, sys, threading, time

variant, steady, cycles, block, after = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), int(sys.argv[5])
LINK = "enp0s2"
NAMES = ["kde.org", "github.com", "example.org", "fedoraproject.org", "flathub.org", "mozilla.org", "quad9.net", "wikipedia.org"]
t0 = time.monotonic()


def sh(cmd, timeout=40):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None


def current():
    p = sh("resolvectl status | grep -m1 'Current DNS Server' | awk '{print $4}'", 5)
    return p.stdout.strip() if p else "?"


def route():
    p = sh(f"resolvectl default-route {LINK}", 5)
    return p.stdout.split()[-1] if p and p.stdout.split() else "?"


def emit(o):
    o["variant"] = variant
    o["t"] = round(time.monotonic() - t0, 1)
    print(json.dumps(o), flush=True)


stats = {"steady": [0, 0], "after_block": [0, 0]}
servers_at_fail = {}


def lookup(i, phase):
    name = NAMES[i % len(NAMES)]
    srv, rt = current(), route()
    a = sh(f"resolvectl query --cache=no --legend=no {name}", 25)
    g = sh(f"getent ahosts {name}", 25)
    bad = a is None or a.returncode != 0 or g is None or g.returncode != 0
    stats[phase][0] += 1
    if bad:
        stats[phase][1] += 1
        servers_at_fail[srv] = servers_at_fail.get(srv, 0) + 1
        emit({"fail": True, "phase": phase, "name": name, "server_before": srv, "route": rt,
              "rq": (a.stdout + a.stderr).strip()[:160] if a else "timeout",
              "getent_rc": g.returncode if g else "timeout",
              "secs": None})


emit({"start": True, "servers": " ".join(sh("resolvectl dns", 5).stdout.split()),
      "ipv6_default": sh("ip -6 route show default", 5).stdout.strip()})
for i in range(steady):
    lookup(i, "steady")
    time.sleep(1)

for c in range(cycles):
    sh("nft add table inet diagblk; nft add chain inet diagblk out '{ type filter hook output priority 0; }'; "
       "nft add rule inet diagblk out ip daddr '{ 9.9.9.9, 149.112.112.112 }' drop; "
       "nft add rule inet diagblk out ip6 daddr '{ 2620:fe::fe, 2620:fe::9 }' drop")
    s = time.monotonic(); j = 0
    while time.monotonic() - s < block:
        threading.Thread(target=sh, args=(f"resolvectl query --cache=no blk-{c}-{j}.example.net", 25), daemon=True).start()
        j += 1
        time.sleep(1)
    sh("nft delete table inet diagblk")
    s = time.monotonic()
    while route() != "no" and time.monotonic() - s < 90:
        time.sleep(1)
    emit({"cycle": c, "server_after_block": current(), "route_back_after_secs": round(time.monotonic() - s, 1)})
    for k in range(after):
        lookup(c * after + k, "after_block")
        time.sleep(1)

emit({"summary": True, "steady": stats["steady"], "after_block": stats["after_block"],
      "failed": stats["steady"][1] + stats["after_block"][1],
      "lookups": stats["steady"][0] + stats["after_block"][0], "servers_at_fail": servers_at_fail})
