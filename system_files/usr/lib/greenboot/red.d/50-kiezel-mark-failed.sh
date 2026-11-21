#!/usr/bin/bash
# greenboot "red" hook: runs on every boot whose required health checks failed (ADR-0008).
# Remember the failing image digest, so the update timer never stages it again after greenboot
# rolled back (no rollback loop), and leave a plain-language notice for the user.
set -uo pipefail

state=/var/lib/kiezel
mkdir -p "${state}/notices"

digest="$(bootc status --format json 2>/dev/null | jq -r '.status.booted.image.imageDigest // empty')"
if [[ -n "${digest}" ]]; then
    touch "${state}/failed-digests"
    grep -qxF "${digest}" "${state}/failed-digests" || echo "${digest}" >> "${state}/failed-digests"
    echo "kiezel: marked failed image ${digest}; it will not be installed again" > /dev/kmsg 2>/dev/null || true
fi

# One notice file; its timestamp tells the desktop notifier whether it is new.
echo "update-failed" > "${state}/notices/update-failed"
chmod 0644 "${state}/notices/update-failed"
exit 0
