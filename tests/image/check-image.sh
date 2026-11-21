#!/usr/bin/bash
# Static checks on a built Kiezel image. Runs INSIDE the image:
#   podman run --rm -v ./tests/image:/t:ro,z <image> /t/check-image.sh
# Every check prints PASS/FAIL; the script exits non-zero if any check fails.
set -uo pipefail

fails=0
pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
check() { local desc="$1"; shift; if "$@" >/dev/null 2>&1; then pass "${desc}"; else fail "${desc}"; fi; }

policy=/etc/containers/policy.json
scope='ghcr.io/elstvictor05-droid/kiezel'

# --- Trust policy (ADR-0004) ---------------------------------------------------
check "policy.json is valid JSON" jq -e . "${policy}"
check "default policy is reject" jq -e '.default[0].type == "reject"' "${policy}"
check "Kiezel scope requires sigstore signature" \
    jq -e --arg s "${scope}" '.transports.docker[$s][0].type == "sigstoreSigned"' "${policy}"
check "Kiezel scope pins repository identity" \
    jq -e --arg s "${scope}" '.transports.docker[$s][0].signedIdentity.type == "matchRepository"' "${policy}"
check "no ublue-os scope is trusted" \
    jq -e '[.transports.docker | keys[] | select(test("ublue-os"))] | length == 0' "${policy}"

missing=0
while read -r key; do
    [[ -s "${key}" ]] || { echo "      missing key file: ${key}"; missing=1; }
done < <(jq -r --arg s "${scope}" '.transports.docker[$s][0].keyPaths[]' "${policy}")
if [[ ${missing} -eq 0 ]]; then pass "all trusted key files exist"; else fail "all trusted key files exist"; fi

check "sigstore attachments enabled for Kiezel" \
    grep -q 'use-sigstore-attachments: true' /etc/containers/registries.d/kiezel.yaml

# --- Updates (ADR-0004) -------------------------------------------------------
check "rpm-ostreed-automatic.timer enabled" systemctl is-enabled rpm-ostreed-automatic.timer
check "rpm-ostreed policy is stage" grep -qx 'AutomaticUpdatePolicy=stage' /etc/rpm-ostreed.conf
if [[ "$(systemctl is-enabled bootc-fetch-apply-updates.timer 2>/dev/null)" == "masked" ]]; then
    pass "bootc-fetch-apply-updates.timer masked (no surprise reboots)"
else
    fail "bootc-fetch-apply-updates.timer masked (no surprise reboots)"
fi

# --- Rollback (ADR-0008) --------------------------------------------------------
check "greenboot installed" rpm -q greenboot
check "greenboot-healthcheck enabled" systemctl is-enabled greenboot-healthcheck.service
check "Kiezel health checks present" test -x /usr/lib/greenboot/check/required.d/50-kiezel-core.sh

check "greenboot red hook marks failed images" test -x /usr/lib/greenboot/red.d/50-kiezel-mark-failed.sh
check "update gate wired into rpm-ostreed-automatic" \
    grep -q '^ExecCondition=/usr/libexec/kiezel/update-gate' /usr/lib/systemd/system/rpm-ostreed-automatic.service.d/50-kiezel-update-gate.conf
check "update gate is executable" test -x /usr/libexec/kiezel/update-gate
check "user notices enabled for all users" test -L /etc/systemd/user/graphical-session.target.wants/kiezel-notices.service
check "notice text exists in English and Dutch" \
    bash -c 'grep -q "^en.body=" /usr/share/kiezel/notices/update-failed && grep -q "^nl.body=" /usr/share/kiezel/notices/update-failed'

# --- Baseline security ----------------------------------------------------------
check "SELinux configured enforcing" grep -qx 'SELINUX=enforcing' /etc/selinux/config
check "sshd not enabled" bash -c '! systemctl is-enabled sshd.service'

# --- Branding -------------------------------------------------------------------
check "os-release NAME is Kiezel" grep -qx 'NAME="Kiezel"' /usr/lib/os-release
check "os-release ID stays fedora" grep -qx 'ID=fedora' /usr/lib/os-release

echo
if [[ ${fails} -eq 0 ]]; then echo "All image checks passed."; else echo "${fails} image check(s) FAILED."; fi
exit $(( fails > 0 ))
