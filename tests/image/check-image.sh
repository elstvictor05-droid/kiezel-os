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
check "catch-all for other registries is reject (Simple/Standard; ADR-0004)" \
    jq -e '.transports.docker[""][0].type == "reject"' "${policy}"
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

# --- First run (ADR-0007) --------------------------------------------------------
check "installer locale captured before Plasma Setup" systemctl is-enabled kiezel-locale-capture.service
check "installer region restored after Plasma Setup" systemctl is-enabled kiezel-locale-restore.path

# --- Phase 2 hardening (docs/hardening.md) ---------------------------------------
check "sysctl hardening file present" test -s /usr/lib/sysctl.d/60-kiezel-hardening.conf
check "no user-namespace restriction in sysctl (Flatpak/Firefox need userns)" \
    bash -c '! grep -rqE "user\.max_user_namespaces|unprivileged_userns_clone" /usr/lib/sysctl.d /etc/sysctl.d'
check "boot parameters valid TOML, without init_on_free" \
    python3 -c 'import tomllib,sys; k=tomllib.load(open("/usr/lib/bootc/kargs.d/10-kiezel-hardening.toml","rb"))["kargs"]; sys.exit(any(a.startswith("init_on_free") for a in k) or not k)'
check "unused risky kernel modules blocked (dccp, sctp, rds, tipc, firewire)" \
    bash -c 'for m in dccp sctp rds tipc firewire-core firewire-ohci firewire-sbp2; do grep -qx "install ${m} /bin/false" /usr/lib/modprobe.d/60-kiezel-blacklist.conf || exit 1; done'
check "firewalld default zone is kiezel" grep -qx 'DefaultZone=kiezel' /etc/firewalld/firewalld.conf
check "kiezel zone opens no ports, only dhcpv6-client" \
    bash -c '! grep -q "<port" /usr/lib/firewalld/zones/kiezel.xml && [ "$(grep -c "<service" /usr/lib/firewalld/zones/kiezel.xml)" = 1 ]'
check "firewalld enabled" systemctl is-enabled firewalld.service
dns=/usr/lib/systemd/resolved.conf.d/50-kiezel-dns-over-tls.conf
check "DNS: Quad9 primary with opportunistic DNS-over-TLS (ADR-0012)" \
    bash -c "grep -q '^DNS=9.9.9.9#dns.quad9.net' ${dns} && grep -qx 'DNSOverTLS=opportunistic' ${dns}"
check "DNS: fallback routing via NetworkManager dispatcher" test -x /usr/lib/NetworkManager/dispatcher.d/60-kiezel-dns-route
check "DNS: fallback re-check timer enabled" systemctl is-enabled kiezel-dns-route.timer
check "DNS: Quad9 outage watcher enabled (switches within ~10 s, not 5 min)" systemctl is-enabled kiezel-dns-watch.service
check "printers: mDNS only in the kiezel-home zone, never in the default zone" \
    bash -c 'grep -q "service name=\"mdns\"" /usr/lib/firewalld/zones/kiezel-home.xml && ! grep -q mdns /usr/lib/firewalld/zones/kiezel.xml'
check "fwupd metadata refresh enabled" systemctl is-enabled fwupd-refresh.timer
check "USBGuard installed but disabled" bash -c 'rpm -q usbguard && ! systemctl is-enabled usbguard.service'
fx=/usr/lib64/firefox/distribution/policies.json
check "Firefox: HTTPS-only forced" jq -e '.policies.HttpsOnlyMode == "force_enabled"' "${fx}"
check "Firefox: telemetry off" jq -e '.policies.DisableTelemetry == true' "${fx}"
check "Firefox: uBlock Origin force-installed" \
    jq -e '.policies.ExtensionSettings["uBlock0@raymondhill.net"].installation_mode == "force_installed"' "${fx}"
check "Firefox: primary password required to store passwords" jq -e '.policies.PrimaryPassword == true' "${fx}"
check "ujust shows the Kiezel recipes" \
    bash -c 'just --justfile /usr/share/ublue-os/justfile --list 2>/dev/null | grep -q kiezel-dns-strict'

# --- Baseline security ----------------------------------------------------------
check "SELinux configured enforcing" grep -qx 'SELINUX=enforcing' /etc/selinux/config
check "sshd not enabled" bash -c '! systemctl is-enabled sshd.service'

# --- Branding -------------------------------------------------------------------
check "os-release NAME is Kiezel" grep -qx 'NAME="Kiezel"' /usr/lib/os-release
check "os-release ID stays fedora" grep -qx 'ID=fedora' /usr/lib/os-release

echo
if [[ ${fails} -eq 0 ]]; then echo "All image checks passed."; else echo "${fails} image check(s) FAILED."; fi
exit $(( fails > 0 ))
