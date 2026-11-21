#!/usr/bin/bash
# Kiezel required health checks (ADR-0008).
# greenboot runs every script in required.d after boot; if any exits non-zero on three
# consecutive boots of a NEW deployment, greenboot rolls back to the previous deployment.
# Keep these checks about things that make the computer unusable, never about cosmetics.
set -uo pipefail

wait_active() {
    # Units may still be starting when greenboot runs: wait up to 120 s.
    local unit="$1"
    for _ in $(seq 1 120); do
        systemctl is-active --quiet "${unit}" && return 0
        sleep 1
    done
    echo "kiezel-healthcheck: ${unit} is not active" >&2
    return 1
}

rc=0

# The login screen must come up, otherwise the user is locked out.
wait_active sddm.service || rc=1

# Networking is required to receive the fix for a broken update.
wait_active NetworkManager.service || rc=1

# Security baseline must not have been silently lost by an update.
if [[ "$(getenforce)" != "Enforcing" ]]; then
    echo "kiezel-healthcheck: SELinux is not enforcing" >&2
    rc=1
fi

if ! grep -q '"ghcr.io/elstvictor05-droid/kiezel"' /etc/containers/policy.json; then
    echo "kiezel-healthcheck: Kiezel trust policy missing" >&2
    rc=1
fi

exit "${rc}"
