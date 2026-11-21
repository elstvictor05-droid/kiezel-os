#!/usr/bin/bash
# greenboot "red" hook: runs on every boot whose required health checks failed (ADR-0008).
# Remember the failing image digest, so the update timer never stages it again after greenboot
# rolled back (no rollback loop), and leave a plain-language notice for the user.
set -uo pipefail

state=/var/lib/kiezel
mkdir -p "${state}/notices"

status_json="$(bootc status --format json 2>/dev/null)"

# Only an UPDATE can be rolled back. On a fresh install (no previous deployment) there is nothing
# to go back to: do not mark the installed image as failed and do not tell the user that "an
# update did not work". The failing health check itself is still logged by greenboot.
if [[ "$(jq -r '.status.rollback // empty | length' <<<"${status_json}")" == "" ]]; then
    echo "kiezel: health check failed on a deployment without a rollback target (fresh install?)" > /dev/kmsg 2>/dev/null || true
    exit 0
fi

digest="$(jq -r '.status.booted.image.imageDigest // empty' <<<"${status_json}")"
if [[ -n "${digest}" ]]; then
    touch "${state}/failed-digests"
    grep -qxF "${digest}" "${state}/failed-digests" || echo "${digest}" >> "${state}/failed-digests"
    echo "kiezel: marked failed image ${digest}; it will not be installed again" > /dev/kmsg 2>/dev/null || true
fi

# One notice file; its timestamp tells the desktop notifier whether it is new.
echo "update-failed" > "${state}/notices/update-failed"
chmod 0644 "${state}/notices/update-failed"
exit 0
