#!/usr/bin/bash
# Guard for ADR-0005 owner condition 1: the installer must verify the image signature.
# Usage: tests/iso/check-kickstart.sh <kickstart>...
set -euo pipefail

rc=0
for ks in "$@"; do
    # Comment lines may mention the flag (as a warning); only real kickstart lines count.
    if grep -nvE '^[[:space:]]*#' "${ks}" | grep -E -- '--no-signature-verification|ostree-unverified'; then
        echo "FAIL  ${ks}: signature verification is disabled" >&2
        rc=1
    fi
    if ! grep -qE '^ostreecontainer ' "${ks}"; then
        echo "FAIL  ${ks}: no ostreecontainer line" >&2
        rc=1
    fi
    if ! grep -q '"type": "sigstoreSigned"' "${ks}"; then
        echo "FAIL  ${ks}: %pre does not install a sigstoreSigned policy" >&2
        rc=1
    fi
    # Administrator (ADR-0007, owner decision a): in a production kickstart the helper creates the
    # admin in the installer. Any rootpw line (even --lock) makes Anaconda skip that step, and a
    # user line would bake an account (and maybe a password) into a public ISO.
    if ! grep -q '^# !!! CI TEST KICKSTART' "${ks}"; then
        if grep -nE '^[[:space:]]*(rootpw|user)[[:space:]]' "${ks}"; then
            echo "FAIL  ${ks}: production kickstart must not contain rootpw/user (the installer must ask for the administrator)" >&2
            rc=1
        fi
    fi
    if ! grep -qE '^[[:space:]]*passwd -l root' "${ks}"; then
        echo "FAIL  ${ks}: %post does not lock root when an administrator exists" >&2
        rc=1
    fi
    [[ ${rc} -eq 0 ]] && echo "PASS  ${ks}: signature verification enforced; administrator asked in the installer"
done
exit "${rc}"
