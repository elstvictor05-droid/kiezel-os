#!/usr/bin/bash
# The daily account (made by Plasma Setup) cannot get administrator rights (owner decision 1a).
# Usage: tests/security/daily-account.sh <image>
#   1. groups: Plasma Setup's UserGroups is set, and contains no admin group (wheel, empower, ...)
#   2. sudo: no sudoers rule applies to the daily account or its groups
#   3. polkit: every rule and action of the image, evaluated for the daily account in an active
#      local session (tests/security/polkit-daily-account.js)
set -uo pipefail
IMAGE="${1:?usage: daily-account.sh <image>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"; trap 'rm -rf "${work}"' EXIT
fails=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

groups="$(podman run --rm "${IMAGE}" sh -c "sed -n 's/^UserGroups=//p' /etc/xdg/plasmasetuprc" | tr -d '[:space:]')"
if [[ -z "${groups}" ]]; then
    fail "Plasma Setup UserGroups is empty (Plasma Setup would fall back to wheel)"
elif tr ',' '\n' <<<"${groups}" | grep -qxE 'wheel|empower|adm|sudo|root|systemd-journal|libvirt|docker|kvm'; then
    fail "Plasma Setup UserGroups contains an admin or privileged group: ${groups}"
else
    pass "daily account groups: ${groups} (no wheel or other admin group)"
fi

sudo_hits="$(podman run --rm "${IMAGE}" sh -c 'cat /etc/sudoers /etc/sudoers.d/* 2>/dev/null' \
    | grep -vE '^[[:space:]]*(#|Defaults|$)' | grep -vE '^[[:space:]]*(root|%wheel)[[:space:]]' || true)"
for g in $(tr ',' ' ' <<<"${groups}"); do
    grep -qE "(^|[[:space:],])%${g}([[:space:],]|$)" <<<"${sudo_hits}" && fail "sudoers grants something to group ${g}"
done
if grep -qE '^[[:space:]]*ALL[[:space:]]' <<<"${sudo_hits}"; then fail "sudoers has a rule for ALL users"; fi
[[ -z "${sudo_hits}" ]] && pass "sudoers: only root and %wheel have rules"
[[ -n "${sudo_hits}" ]] && echo "INFO  other sudoers lines (reviewed above): ${sudo_hits//$'\n'/ | }"

podman run --rm "${IMAGE}" tar -C / -cf - usr/share/polkit-1 etc/polkit-1 2>/dev/null | tar -C "${work}" -xf -
node "${HERE}/polkit-daily-account.js" "${work}" "${groups}" || fails=$((fails + 1))

echo
[[ ${fails} -eq 0 ]] && echo "All daily-account checks passed." || echo "${fails} daily-account check(s) FAILED."
exit $(( fails > 0 ))
