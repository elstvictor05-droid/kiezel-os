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
check "image records its build commit (/usr/share/kiezel/build-commit)" grep -qxE "[0-9a-f]{40}(-dirty)?" /usr/share/kiezel/build-commit
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
# Firefox is a Flatpak (ADR-0011); its policies reach the sandbox through the systemconfig extension.
fx=/usr/share/kiezel/firefox-systemconfig/policies/policies.json
check "Firefox RPM removed (Flatpak from Flathub instead)" bash -c '! rpm -q firefox'
check "Firefox policies linked into the systemconfig extension at boot" \
    grep -qx 'L+ /var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable - - - - /usr/share/kiezel/firefox-systemconfig' /usr/lib/tmpfiles.d/kiezel.conf
check "Firefox: HTTPS-only forced" jq -e '.policies.HttpsOnlyMode == "force_enabled"' "${fx}"
check "Firefox: telemetry off" jq -e '.policies.DisableTelemetry == true' "${fx}"
check "Firefox: uBlock Origin force-installed" \
    jq -e '.policies.ExtensionSettings["uBlock0@raymondhill.net"].installation_mode == "force_installed"' "${fx}"
check "Firefox: primary password required to store passwords" jq -e '.policies.PrimaryPassword == true' "${fx}"
# Curated apps (config.yaml, default profile) preinstalled from Flathub at first boot.
check "curated apps: preinstall list matches config.yaml (default profile)" bash -c '
    want=$(python3 -c "import yaml; c=yaml.safe_load(open(\"/config.yaml\")); o=[\"simple\",\"standard\",\"advanced\"]; p=c[\"profile\"][\"default\"]; print(\" \".join(a for q in o[:o.index(p)+1] for a in c[\"apps\"][q]))" 2>/dev/null)
    got=$(sed -n "s/^\[Flatpak Preinstall \(.*\)\]$/\1/p" /usr/share/flatpak/preinstall.d/kiezel.preinstall | xargs)
    [[ -n "${want}" && "${got}" == "${want}" ]]'
check "curated apps: preinstall service enabled" systemctl is-enabled kiezel-flatpak-preinstall.service
check "curated apps: Flathub is the only Flatpak remote" bash -c '[[ "$(ls /etc/flatpak/remotes.d)" == "flathub.flatpakrepo" ]]'
check "app install/remove prompt in clear Dutch (asks for the helper)" \
    bash -c '[[ $(grep -c "Vraag het aan de persoon die deze computer voor u heeft ingesteld" /usr/share/polkit-1/actions/org.freedesktop.Flatpak.policy) == 4 ]]'
check "ujust shows the Kiezel recipes" \
    bash -c 'just --justfile /usr/share/ublue-os/justfile --list 2>/dev/null | grep -q kiezel-dns-strict'

# --- First start: Kiezel "easy to read" page in Plasma Setup (ADR-0007, Phase 3) -------
check "Plasma Setup discovers the Kiezel accessibility page" \
    bash -c 'kpackagetool6 --type KDE/PlasmaSetup --list --global 2>/dev/null | grep -qx org.kiezel.plasmasetup.accessibility'
check "Kiezel page comes before every Plasma Setup page (lowest weight)" \
    bash -c 'k=$(jq ".\"X-KDE-Weight\"" /usr/share/plasma/packages/org.kiezel.plasmasetup.accessibility/metadata.json);
             for m in /usr/share/plasma/packages/org.kde.plasmasetup.*/metadata.json; do [[ $(jq ".\"X-KDE-Weight\" // 0" "$m") -gt $k ]] || exit 1; done'
check "the page can run commands (plasma5support executable engine present)" \
    test -d /usr/lib64/qt6/qml/org/kde/plasma/plasma5support
check "high-contrast colour scheme is installed" test -s /usr/share/color-schemes/KiezelHighContrast.colors
check "reading choices are applied at the first login" \
    bash -c 'test -x /usr/libexec/kiezel/a11y-apply && grep -q "a11y-apply first-login" /etc/xdg/autostart/kiezel-a11y-first-login.desktop'
check "a11y-apply writes text size and screen reader choice into kdeglobals" \
    bash -c 'h=$(mktemp -d); HOME=$h XDG_CONFIG_HOME=$h/.config /usr/libexec/kiezel/a11y-apply text xlarge >/dev/null 2>&1;
             HOME=$h XDG_CONFIG_HOME=$h/.config /usr/libexec/kiezel/a11y-apply reader on >/dev/null 2>&1;
             grep -q "^font=Noto Sans,16," $h/.config/kdeglobals && grep -q "^ScreenReader=true" $h/.config/kdeglobals && grep -q "^Enabled=true" $h/.config/kaccessrc'

# --- Administrator vs. daily account (ADR-0007, owner decision 1a) ----------------------
check "Plasma Setup makes the daily account without wheel (UserGroups set, no wheel)" \
    bash -c 'g=$(sed -n "s/^UserGroups=//p" /etc/xdg/plasmasetuprc); [[ -n "$g" && ",$g," != *",wheel,"* ]]'
check "Plasma Setup shows its account page although the installer made an administrator" \
    grep -qx 'PLASMA_SETUP_USER_CREATION_OVERRIDE=1' /usr/lib/environment.d/60-kiezel-plasma-setup.conf
check "account page no longer claims the daily user is an administrator" \
    bash -c 'q=/usr/share/plasma/packages/org.kde.plasmasetup.account/contents/ui/main.qml;
             grep -q "zonder beheerdersrechten" "$q" && ! grep -q "This user will be an administrator" "$q"'
check "login screen uses large text for everyone (greeter-only drop-in, no privileged code)" \
    bash -c 'grep -q "XDG_CONFIG_DIRS=/usr/share/kiezel/login-screen/xdg:/etc/xdg" /usr/lib/systemd/user/plasma-login.service.d/50-kiezel-large-text.conf &&
             grep -q "^font=Noto Sans,13," /usr/share/kiezel/login-screen/xdg/kdeglobals'

# --- Welcome Center pages: printer at home, DNS privacy (Phase 3) -------------------
check "Welcome Center: printer and DNS privacy pages installed" \
    test -s /usr/share/plasma/plasma-welcome/extra-pages/01-KiezelPrinter.qml -a -s /usr/share/plasma/plasma-welcome/extra-pages/02-KiezelDnsPrivacy.qml
check "polkit: Kiezel actions need an administrator (auth_admin_keep)" \
    bash -c 'f=/usr/share/polkit-1/actions/org.kiezel.settings.policy; xmllint --noout "$f" &&
             [[ $(grep -c "<allow_active>auth_admin_keep</allow_active>" "$f") -eq 2 ]] && ! grep -q "<allow_active>yes" "$f"'
check "Welcome page can read the DNS mode without root" \
    bash -c 'id nobody >/dev/null && setpriv --reuid=nobody --regid=nobody --clear-groups /usr/libexec/kiezel/dns-mode status 2>/dev/null | grep -qx "mode: quad9"'

# --- Baseline security ----------------------------------------------------------
check "SELinux configured enforcing" grep -qx 'SELINUX=enforcing' /etc/selinux/config
check "sshd not enabled" bash -c '! systemctl is-enabled sshd.service'

# --- Branding -------------------------------------------------------------------
check "os-release NAME is Kiezel" grep -qx 'NAME="Kiezel"' /usr/lib/os-release
check "os-release ID stays fedora" grep -qx 'ID=fedora' /usr/lib/os-release

echo
if [[ ${fails} -eq 0 ]]; then echo "All image checks passed."; else echo "${fails} image check(s) FAILED."; fi
exit $(( fails > 0 ))
