#!/usr/bin/bash
# Kiezel required health checks (ADR-0008).
# greenboot runs every script in required.d after boot; if any exits non-zero on three
# consecutive boots of a NEW deployment, greenboot rolls back to the previous deployment.
# Keep these checks about things that make the computer unusable, never about cosmetics.
set -uo pipefail

say() {
    # stderr ends up in the journal; /dev/kmsg also shows on the console, which helps diagnosis.
    echo "kiezel-healthcheck: $*" >&2
    echo "kiezel-healthcheck: $*" > /dev/kmsg 2>/dev/null || true
}

wait_active() {
    # Units may still be starting when greenboot runs: wait up to 120 s.
    local unit="$1"
    for _ in $(seq 1 120); do
        systemctl is-active --quiet "${unit}" && return 0
        sleep 1
    done
    say "${unit} is not active"
    return 1
}

rc=0

# The login screen must come up, otherwise the user is locked out. Use the generic alias:
# Fedora 45 KDE ships Plasma Login Manager (plasmalogin.service), not SDDM. On first boot it
# runs the Plasma Setup wizard through the same display manager.
wait_active display-manager.service || rc=1

# Networking is required to receive the fix for a broken update.
wait_active NetworkManager.service || rc=1

# Security baseline must not have been silently lost by an update.
if [[ "$(getenforce)" != "Enforcing" ]]; then
    say "SELinux is not enforcing"
    rc=1
fi

if ! grep -q '"ghcr.io/elstvictor05-droid/kiezel"' /etc/containers/policy.json; then
    say "Kiezel trust policy missing"
    rc=1
fi

[[ ${rc} -eq 0 ]] && say "all required checks passed"
exit "${rc}"
