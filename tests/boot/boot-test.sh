#!/usr/bin/bash
# Kiezel boot test: boots a disk image under QEMU with UEFI Secure Boot (Microsoft-enrolled OVMF
# vars, so Fedora's shim must be accepted) and an emulated TPM2, then checks the running system
# over SSH. Optionally runs the update/rollback scenarios.
#
# Usage:
#   tests/boot/boot-test.sh --disk disk.qcow2 --key id_ed25519 [--registry HOST:PORT]
#                           [--sigtest DIR] [--allow-skip] [--workdir DIR]
#   --sigtest DIR  fixtures from tests/sign/sigtest-setup.sh (signature path; required unless
#                  --allow-skip, which the workflow passes only for fork PRs)
#
# The disk must contain the test user "root" with the given SSH key (make-test-disk.sh). SSH runs
# over virtio-vsock (systemd-ssh-generator binds sshd to vsock inside VMs); sshd.service stays
# OFF and the Kiezel firewall stays ON, exactly as in production.
#
# Update scenarios (--registry): a plain HTTP registry on the host (e.g. 127.0.0.1:5000, seen by
# the VM as 10.0.2.2:5000) holding kiezel:good, kiezel:good2 (same OS, different digest) and
# kiezel:broken (health check fails). The test moves the tag kiezel:channel between them through
# the registry API and lets the REAL update timer service (rpm-ostreed-automatic) do the work:
#   1. update + power-off with a staged update  -> no false rollback (greenboot-rs #219)
#   2. broken update                             -> automatic rollback + user notice
#   3. two timer runs after the rollback         -> the failed digest is NOT staged again
set -uo pipefail

DISK="" KEY="" REGISTRY="" SIGTEST="" ALLOW_SKIP=0 LYNIS_TARBALL="" WORKDIR="${PWD}/tests/out/boot"
VSOCK_CID="${VSOCK_CID:-3}"        # SSH goes over virtio-vsock: the Kiezel firewall stays fully on
PROBE_PORT="${PROBE_PORT:-18080}"   # host port forwarded to guest TCP 8080 for the firewall probe
HERE="$(cd "$(dirname "$0")" && pwd)"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.ms.fd}"
MEM_MB="${MEM_MB:-4096}"
VCPUS="${VCPUS:-2}"
KIEZEL_REF="ghcr.io/elstvictor05-droid/kiezel"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        --registry) REGISTRY="$2"; shift 2 ;;
        --sigtest) SIGTEST="$2"; shift 2 ;;
        --allow-skip) ALLOW_SKIP=1; shift ;;
        --lynis) LYNIS_TARBALL="$2"; shift 2 ;;   # fork PRs only: missing signature fixtures may SKIP
        --workdir) WORKDIR="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${DISK}" && -f "${KEY}" ]] || { echo "need --disk and --key" >&2; exit 2; }

mkdir -p "${WORKDIR}/tpm"
REPORT="${WORKDIR}/report.txt"
SERIAL="${WORKDIR}/serial.log"
: > "${REPORT}"

fails=0
log()  { printf '%s\n' "$*" | tee -a "${REPORT}"; }
pass() { log "PASS  $1"; }
fail() { log "FAIL  $1${2:+  ($2)}"; fails=$((fails + 1)); }
skip() { log "SKIP  $1${2:+  ($2)}"; }

SSH_OPTS=(-i "${KEY}" -o "ProxyCommand=python3 -I ${HERE}/vsock-proxy.py ${VSOCK_CID} 22"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes)
ssh_vm() { ssh "${SSH_OPTS[@]}" root@vsock "$@"; }
scp_vm() { scp -q "${SSH_OPTS[@]}" "$@"; }

wait_ssh() {
    local timeout="$1" start=${SECONDS}
    while (( SECONDS - start < timeout )); do
        ssh_vm true 2>/dev/null && return 0
        sleep 5
    done
    return 1
}

cleanup() {
    [[ -f "${WORKDIR}/qemu.pid" ]] && kill "$(cat "${WORKDIR}/qemu.pid")" 2>/dev/null
    [[ -f "${WORKDIR}/swtpm.pid" ]] && kill "$(cat "${WORKDIR}/swtpm.pid")" 2>/dev/null
}
trap cleanup EXIT

# --- VM lifecycle -----------------------------------------------------------------------------
cp "${OVMF_VARS}" "${WORKDIR}/OVMF_VARS.fd"
BOOT=0
start_vm() {
    BOOT=$((BOOT + 1))
    SERIAL="${WORKDIR}/serial-${BOOT}.log"
    # QEMU shuts swtpm down when it exits, so (re)start it for every power-on. TPM state persists.
    swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm.pid" \
        --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm.sock"
    qemu-system-x86_64 \
        -name kiezel-boot-test \
        -machine q35,smm=on,accel=kvm -cpu host -m "${MEM_MB}" -smp "${VCPUS}" \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
        -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
        -drive "file=${DISK},if=virtio,format=qcow2" \
        -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm.sock" \
        -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
        -netdev "user,id=n0,domainname=home.arpa,hostfwd=tcp:127.0.0.1:${PROBE_PORT}-:8080" -device virtio-net-pci,netdev=n0 \
        -device "vhost-vsock-pci,guest-cid=${VSOCK_CID}" \
        -serial "file:${SERIAL}" -display none \
        -daemonize -pidfile "${WORKDIR}/qemu.pid" || { echo "QEMU failed to start" >&2; exit 1; }
}

wait_poweroff() {
    local timeout="$1" start=${SECONDS} pid
    pid="$(cat "${WORKDIR}/qemu.pid")"
    while (( SECONDS - start < timeout )); do
        kill -0 "${pid}" 2>/dev/null || return 0
        sleep 3
    done
    return 1
}

start_vm
log "== Kiezel boot test  $(date -u +%FT%TZ)"
log "   disk=${DISK} mem=${MEM_MB}MB vcpus=${VCPUS} secureboot=on tpm2=swtpm"

if ! wait_ssh 900; then
    fail "VM reachable over SSH within 15 min" "see serial-${BOOT}.log"
    tail -50 "${SERIAL}" >&2
    exit 1
fi
pass "VM booted and reachable"

# Never test a stale image (owner requirement): the system that booted must be built from the
# commit under test. The image writes its KIEZEL_COMMIT there (build/build.sh, ci/build-commit.sh).
want_commit="$(git -C "${HERE}" rev-parse HEAD)"
got_commit="$(ssh_vm 'cat /usr/share/kiezel/build-commit' 2>&1)"
if [[ "${got_commit}" == "${want_commit}" ]]; then
    pass "booted image was built from HEAD ${want_commit}"
else
    fail "booted image was built from HEAD ${want_commit}" "image says '${got_commit}'; rebuild the image and the disk from a clean work tree"
    log "RESULT: stale image; the remaining checks would not test this commit"
    exit 1
fi

# --- Checks on the running system --------------------------------------------------
state="$(ssh_vm 'systemctl is-system-running --wait' 2>/dev/null)"
if [[ "${state}" == "running" ]]; then pass "system state: running"
else fail "system state: running" "got '${state}'; failed: $(ssh_vm 'systemctl --failed --no-legend --plain | cut -d" " -f1 | xargs')"
    # Keep the reason, not just the unit name (PR #9: the cause was only found by reproducing it).
    ssh_vm 'for u in $(systemctl --failed --no-legend --plain | cut -d" " -f1); do
                echo "--- ${u}: $(systemctl show "${u}" -p Result --value)"; journalctl -b --no-pager -o cat -u "${u}" | tail -15
            done' >> "${REPORT}" 2>&1; fi

sb="$(ssh_vm 'mokutil --sb-state' 2>&1)"
if grep -q 'SecureBoot enabled' <<<"${sb}"; then pass "Secure Boot enabled (Fedora shim accepted)"
else fail "Secure Boot enabled" "${sb}"; fi

se="$(ssh_vm getenforce 2>&1)"
[[ "${se}" == "Enforcing" ]] && pass "SELinux enforcing" || fail "SELinux enforcing" "${se}"

# AVC denials (ADR-0010): a denial is KNOWN only if its full (scontext, tcontext, tclass,
# permission) tuple is in tests/boot/avc-allowlist.txt; anything else fails the test.
ssh_vm "journalctl -b --no-pager -o cat | grep 'avc:  denied'" > "${WORKDIR}/avc.txt" 2>/dev/null || true
python3 -I "$(dirname "$0")/avc-check.py" "$(dirname "$0")/avc-allowlist.txt" "${WORKDIR}/avc.txt" > "${WORKDIR}/avc-result.txt"
avc_rc=$?
summary="$(grep '^SUMMARY' "${WORKDIR}/avc-result.txt")"
if [[ ${avc_rc} -eq 0 ]]; then
    pass "0 unexpected SELinux AVC denials since boot (${summary#SUMMARY })"
else
    fail "0 unexpected SELinux AVC denials since boot" "${summary#SUMMARY }"
    grep '^UNKNOWN' "${WORKDIR}/avc-result.txt" | head -20 >> "${REPORT}"
    {
        echo "--- AVC context (ausearch -i) ---"
        ssh_vm "ausearch -m AVC -ts boot -i 2>/dev/null | grep -E 'type=(SYSCALL|PROCTITLE)' | head -20"
    } >> "${REPORT}" 2>&1
fi
while read -r _ entry; do
    log "WARN  stale AVC allowlist entry (matched nothing; upstream fixed?): ${entry}"
done < <(grep '^STALE' "${WORKDIR}/avc-result.txt")

gb="$(ssh_vm 'systemctl show -p Result --value greenboot-healthcheck.service; systemctl is-active boot-complete.target' 2>&1 | xargs)"
if [[ "${gb}" == "success active" ]]; then pass "greenboot healthy (boot-complete reached)"
else
    fail "greenboot healthy" "${gb}"
    ssh_vm "journalctl -b --no-pager -o cat -u greenboot-healthcheck | tail -30" >> "${REPORT}" 2>&1
fi

tpm="$(ssh_vm 'test -c /dev/tpmrm0 && echo yes' 2>&1)"
[[ "${tpm}" == "yes" ]] && pass "TPM2 device present" || fail "TPM2 device present"

booted="$(ssh_vm "bootc status --json | jq -r '.status.booted.image.image.image'" 2>&1)"
[[ "${booted}" == "${KIEZEL_REF}:"* ]] && pass "booted image reference is ${booted}" \
    || fail "booted image reference is ${KIEZEL_REF}:*" "${booted}"

# --- Phase 2 hardening (docs/hardening.md): every measure is checked on the running system --------
# sysctl: every key in the shipped file must have its value at runtime.
bad=""
while IFS='=' read -r key val; do
    key="$(xargs <<<"${key}")"; val="$(xargs <<<"${val}")"
    [[ -z "${key}" || "${key}" == \#* ]] && continue
    got="$(ssh_vm "sysctl -n ${key}" 2>&1 | xargs)"
    [[ "${got}" == "${val}" ]] || bad+=" ${key}=${got}(want ${val})"
done < <(grep -vE '^\s*(#|$)' "${HERE}/../../system_files/usr/lib/sysctl.d/60-kiezel-hardening.conf")
[[ -z "${bad}" ]] && pass "all kernel hardening sysctls active" || fail "kernel hardening sysctls active" "${bad}"

# Boot parameters from bootc kargs.d.
cmdline="$(ssh_vm 'cat /proc/cmdline' 2>&1)"
missing=""
for karg in $(python3 -c 'import tomllib,sys; print(" ".join(tomllib.load(open(sys.argv[1],"rb"))["kargs"]))' \
        "${HERE}/../../system_files/usr/lib/bootc/kargs.d/10-kiezel-hardening.toml"); do
    grep -qw -- "${karg}" <<<"${cmdline}" || missing+=" ${karg}"
done
[[ -z "${missing}" ]] && pass "hardening boot parameters active" || fail "hardening boot parameters active" "missing:${missing}"

# Blocked kernel modules cannot be loaded (and none of them is loaded).
mods="$(ssh_vm 'for m in dccp sctp rds tipc firewire_ohci; do modprobe $m 2>/dev/null && echo LOADED:$m; done; lsmod | grep -E "^(dccp|sctp|rds|tipc|firewire)" | cut -d" " -f1' 2>&1 | xargs)"
[[ -z "${mods}" ]] && pass "unused risky kernel modules cannot be loaded" || fail "risky kernel modules blocked" "${mods}"

# Firewall: Kiezel zone active, and a real listener inside the VM is NOT reachable from outside.
# --get-active-zones prints e.g. "kiezel (default)" followed by "  interfaces: ...": take the name only.
zone="$(ssh_vm "firewall-cmd --get-default-zone; firewall-cmd --get-active-zones | head -1 | awk '{print \$1}'" 2>&1 | xargs)"
[[ "${zone}" == "kiezel kiezel" ]] && pass "firewall: Kiezel zone is default and active" || fail "firewall: Kiezel zone default and active" "${zone}"
ssh_vm 'systemd-run --unit=kiezel-probe --property=Type=exec python3 -m http.server 8080 --bind 0.0.0.0' >/dev/null 2>&1
sleep 3
inside="$(ssh_vm 'curl -s -o /dev/null -w %{http_code} --max-time 5 http://127.0.0.1:8080/' 2>&1)"
outside="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:${PROBE_PORT}/" 2>&1)"
ssh_vm 'systemctl stop kiezel-probe' >/dev/null 2>&1
if [[ "${inside}" == "200" && "${outside}" != "200" ]]; then
    pass "firewall: a listening service is reachable inside the VM (200) but NOT from the network (${outside})"
else fail "firewall blocks incoming connections" "inside=${inside} outside=${outside}"; fi

# DNS (ADR-0012): Quad9 primary, the router's DNS only for local names and as automatic fallback.
dns_link() { ssh_vm "resolvectl dns | sed -nE 's/^Link [0-9]+ \(([^)]+)\): +[0-9a-fA-F].*/\1/p' | head -1" 2>/dev/null; }
link="$(dns_link)"
ssh_vm 'systemctl start kiezel-dns-route.service' >/dev/null 2>&1
glob="$(ssh_vm 'resolvectl dns | sed -n "s/^Global: //p"' 2>&1)"
route="$(ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'" 2>&1)"
q="$(ssh_vm 'resolvectl query --cache=no --legend=no example.com >/dev/null && echo ok' 2>&1)"
if [[ "${glob}" == *"9.9.9.9#dns.quad9.net"* && "${route}" == "no" && "${q}" == "ok" ]]; then
    pass "DNS: Quad9 is primary, router link (${link}) only for local domains, lookups work"
else fail "DNS: Quad9 primary" "global='${glob}' ${link} default-route=${route} query=${q}"; fi
tls="$(ssh_vm "resolvectl query --cache=no --legend=no fedoraproject.org >/dev/null; ss -tnH state established '( dport = :853 )' | grep -c ':853'" 2>&1)"
if [[ "${tls}" =~ ^[1-9] ]]; then pass "DNS-over-TLS in use (${tls} TLS connection(s) to port 853)"
else log "INFO  DNS-over-TLS not established on this network (opportunistic fallback to plain DNS to Quad9)"; fi

# Local names keep working through the router (DHCP domain home.arpa; host maps nas.home.arpa).
loc="$(ssh_vm 'getent hosts nas.home.arpa | cut -d" " -f1; getent hosts nas | cut -d" " -f1' 2>&1 | xargs)"
[[ "${loc}" == "10.0.2.2 10.0.2.2" ]] && pass "DNS: local names via the router work (nas.home.arpa and short name 'nas')" \
    || fail "DNS: local names via the router" "got '${loc}'"

# Wait until no kiezel-dns-route run is active or queued (max 30 s), so a check reads a settled
# state instead of racing a run that is still probing.
dns_settle() {
    ssh_vm 'for i in $(seq 60); do
                systemctl -q is-active kiezel-dns-route.service || systemctl list-jobs --no-legend | grep -q kiezel-dns-route || exit 0
                sleep 0.5
            done' >/dev/null 2>&1 || true
    ssh_vm 'flock -w 30 /run/kiezel-dns-route.lock true' >/dev/null 2>&1 || true
}
# On a DNS failure keep the evidence: dns-route, NetworkManager (dispatcher, connectivity), resolved.
dns_journal() {
    { echo "--- journal (dns-route, NetworkManager, resolved) at $(date -u +%T)"
      ssh_vm "journalctl -b --no-pager -o short-monotonic -u kiezel-dns-route -u NetworkManager -u NetworkManager-dispatcher -u systemd-resolved | tail -80; resolvectl status"
    } >> "${WORKDIR}/dns-journal.txt" 2>&1 || true
}
# Automatic fallback: Quad9 unreachable (like a captive portal or a DNS-filtering network).
ssh_vm 'nft add table inet kiezelci; nft add chain inet kiezelci out "{ type filter hook output priority 0; }";
        nft add rule inet kiezelci out ip daddr "{ 9.9.9.9, 149.112.112.112 }" drop;
        nft add rule inet kiezelci out ip6 daddr "{ 2620:fe::fe, 2620:fe::9 }" drop;
        systemctl start kiezel-dns-route.service' >/dev/null 2>&1
dns_settle
route="$(ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'" 2>&1)"
q="$(ssh_vm 'resolvectl flush-caches; resolvectl query --cache=no --legend=no example.org >/dev/null && echo ok' 2>&1)"
[[ "${route}" == "yes" && "${q}" == "ok" ]] && pass "DNS: Quad9 blocked -> automatic fallback to the router's DNS, lookups still work" \
    || { fail "DNS fallback when Quad9 is unreachable" "default-route=${route} query=${q}"; dns_journal; }
# Race regression (run #31): the dispatcher, the timer's service and a manual run all at once,
# while in fallback. Sampled every 0.5 s for 10 s: the link must NEVER leave the fallback.
samples="$(ssh_vm "systemctl restart --no-block kiezel-dns-route.service
        /usr/lib/NetworkManager/dispatcher.d/60-kiezel-dns-route ${link} connectivity-change &
        /usr/libexec/kiezel/dns-route >/dev/null &
        for i in \$(seq 20); do resolvectl default-route ${link} | awk '{print \$NF}'; sleep 0.5; done; wait" 2>&1 | sort | uniq -c | xargs)"
[[ "${samples}" == "20 yes" ]] && pass "DNS: concurrent re-checks never drop the fallback (20/20 samples 'yes')" \
    || { fail "DNS: concurrent re-checks dropped the fallback" "samples: ${samples}"; dns_journal; }
# A connect sends several NetworkManager events within a second; each restarts the unit. A burst
# must not trip systemd's start limit (PR #9: "start-limit-hit" froze the fallback).
burst="$(ssh_vm "systemctl reset-failed kiezel-dns-route.service 2>/dev/null
        for e in up dhcp4-change dhcp6-change connectivity-change up connectivity-change dhcp4-change dhcp6-change; do
            /usr/lib/NetworkManager/dispatcher.d/60-kiezel-dns-route ${link} \$e; done
        sleep 10; systemctl show kiezel-dns-route.service -p Result --value; resolvectl default-route ${link} | awk '{print \$NF}'" 2>&1 | xargs)"
[[ "${burst}" == "success yes" ]] && pass "DNS: a burst of 8 network events does not trip the start limit; fallback kept" \
    || { fail "DNS: burst of network events" "result/route: ${burst}"; dns_journal; }
ssh_vm 'nft delete table inet kiezelci; systemctl start kiezel-dns-route.service' >/dev/null 2>&1
dns_settle
route="$(ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'" 2>&1)"
[[ "${route}" == "no" ]] && pass "DNS: back to Quad9 when it answers again" || { fail "DNS returns to Quad9" "default-route=${route}"; dns_journal; }

# Privacy choice "off" (ujust kiezel-dns-router) and back.
rt="$(ssh_vm "/usr/libexec/kiezel/dns-mode router >/dev/null; resolvectl dns | sed -n 's/^Global: *//p'; resolvectl default-route ${link} | awk '{print \$NF}'; resolvectl query --cache=no --legend=no example.com >/dev/null && echo ok" 2>&1 | xargs)"
ssh_vm '/usr/libexec/kiezel/dns-mode quad9' >/dev/null 2>&1
[[ "${rt}" == "yes ok" ]] && pass "DNS: 'router' mode uses only the network's DNS and works" || fail "DNS router mode" "got '${rt}'"

# Printers: mDNS only after marking THIS network as home, never in the default zone.
pz="$(ssh_vm 'firewall-cmd --zone=kiezel --query-service=mdns; /usr/libexec/kiezel/printer-discovery on >/dev/null; firewall-cmd --get-active-zones | head -1 | cut -d" " -f1; /usr/libexec/kiezel/printer-discovery off >/dev/null; firewall-cmd --get-active-zones | head -1 | cut -d" " -f1' 2>&1 | xargs)"
[[ "${pz}" == "no kiezel-home kiezel" ]] && pass "printers: mDNS closed by default; 'home' puts only this network in kiezel-home; 'off' restores" \
    || fail "printer discovery zones" "got '${pz}'"

# Services.
svc="$(ssh_vm 'systemctl is-active sshd.service; systemctl is-enabled fwupd-refresh.timer; systemctl is-active usbguard.service' 2>&1 | xargs)"
[[ "${svc}" == "inactive enabled inactive" ]] && pass "sshd off, fwupd refresh on, USBGuard off by default" || fail "service baseline" "${svc}"
# Daily account (owner decision 1a): created exactly as Plasma Setup does (useradd + the groups from
# /etc/xdg/plasmasetuprc), then every route to root is tried as that account. The polkit rules for
# an active local session are evaluated separately (tests/security/daily-account.sh).
daily="$(ssh_vm 'g=$(sed -n "s/^UserGroups=//p" /etc/xdg/plasmasetuprc); useradd -m kzdaily && usermod -a -G "$g" kzdaily
        echo "groups=$(id -nG kzdaily | tr " " ",")"
        LANG=C sudo -l -U kzdaily 2>&1 | grep -q "is not allowed to run sudo" && echo sudo=denied || echo sudo=ROOT
        runuser -u kzdaily -- pkexec --disable-internal-agent true >/dev/null 2>&1 && echo pkexec=ROOT || echo pkexec=denied
        runuser -u kzdaily -- run0 --no-ask-password true >/dev/null 2>&1 && echo run0=ROOT || echo run0=denied
        runuser -u kzdaily -- systemctl --no-ask-password start kiezel-dns-route.service >/dev/null 2>&1 && echo systemctl=ROOT || echo systemctl=denied
        userdel -r kzdaily' 2>&1 | xargs)"
# Note: on ostree, "users" lives in /usr/lib/group (nss-altfiles) and usermod silently leaves it out;
# the account then has no extra group at all, which is fine. Only admin groups matter here.
if [[ "${daily}" =~ sudo=denied\ pkexec=denied\ run0=denied\ systemctl=denied ]] \
   && ! grep -qE 'groups=[^ ]*(wheel|empower)' <<<"${daily}"; then
    pass "daily account (Plasma Setup groups): not in wheel; sudo, pkexec, run0 and systemctl all refused"
else fail "daily account must not reach root" "${daily}"; fi

# Container trust (ADR-0004): root/system cannot pull unsigned images from other registries...
out="$(ssh_vm 'podman pull -q quay.io/libpod/alpine:latest' 2>&1)"
if [[ $? -ne 0 ]] && grep -qiE 'rejected|policy' <<<"${out}"; then pass "default: images from other registries are rejected (Simple/Standard)"
else fail "default rejects images from other registries" "${out:0:160}"; fi
# ...and the Advanced opt-in opens it for ONE user only, without touching the system policy.
ssh_vm 'id ciuser >/dev/null 2>&1 || useradd -m ciuser; loginctl enable-linger ciuser' >/dev/null 2>&1
ssh_vm 'sha256sum /etc/containers/policy.json' > "${WORKDIR}/policy-before.txt" 2>&1
open_out="$(ssh_vm "runuser -l ciuser -c '/usr/libexec/kiezel/container-registries open && podman pull -q quay.io/libpod/alpine:latest'" 2>&1)"
if [[ $? -eq 0 ]] && ssh_vm 'sha256sum /etc/containers/policy.json' | cmp -s - "${WORKDIR}/policy-before.txt"; then
    pass "Advanced opt-in: this user can pull from other registries; system policy unchanged"
else fail "Advanced opt-in (per-user policy)" "${open_out:0:200}"; fi
ssh_vm "runuser -l ciuser -c '/usr/libexec/kiezel/container-registries close'" >/dev/null 2>&1

# Flatpak/Firefox sandbox still works with the hardening (user namespaces + seccomp).
bw="$(ssh_vm "runuser -l ciuser -c 'bwrap --unshare-all --share-net --die-with-parent --ro-bind / / --proc /proc --dev /dev true && echo ok'" 2>&1)"
[[ "${bw}" == "ok" ]] && pass "unprivileged sandbox (bubblewrap, as used by Flatpak) works" || fail "bubblewrap sandbox works" "${bw:0:200}"
fx="$(ssh_vm "runuser -l ciuser -c 'P=\$(mktemp -d); timeout 120 firefox --headless --no-remote --profile \$P about:blank >/dev/null 2>&1 & sleep 90; ls \$P/extensions/ 2>/dev/null; kill %1 2>/dev/null; true'" 2>&1)"
if grep -q 'uBlock0@raymondhill.net' <<<"${fx}"; then pass "Firefox starts (content sandbox) and the policy installed uBlock Origin"
else fail "Firefox starts and policy installs uBlock Origin" "extensions: ${fx:0:160}"; fi

# Lynis score (report only; the trend is tracked, not gated).
if [[ -f "${LYNIS_TARBALL:-}" ]]; then
    scp_vm "${LYNIS_TARBALL}" root@vsock:/root/lynis.tar.gz >/dev/null 2>&1
    ssh_vm 'cd /root && tar xzf lynis.tar.gz && cd lynis && ./lynis audit system --quick --no-colors --quiet --logfile /root/lynis.log --report-file /root/lynis-report.dat >/dev/null 2>&1; grep -E "^hardening_index=" /root/lynis-report.dat' > "${WORKDIR}/lynis-index.txt" 2>&1
    scp_vm root@vsock:/root/lynis-report.dat "${WORKDIR}/lynis-report.dat" >/dev/null 2>&1
    scp_vm root@vsock:/root/lynis.log "${WORKDIR}/lynis.log" >/dev/null 2>&1
    log "INFO  Lynis $(cut -d= -f2 "${WORKDIR}/lynis-index.txt" 2>/dev/null | sed 's/^/hardening index: /')"
fi

# --- Signature path (ADR-0003): runs in EVERY run, never skipped -------------------------------
# Fixtures from tests/sign/sigtest-setup.sh, signed through ci/sign.sh (the release's own signing
# command) with a throwaway key. Inside the VM the device's own podman/containers-image must:
# accept the signed image, reject the unsigned one, and reject one signed with another key.
if [[ -n "${SIGTEST}" ]]; then
    reghost="" signed="" unsigned="" wrongkey=""   # set by digests.env
    # shellcheck disable=SC1091
    . "${SIGTEST}/digests.env"
    [[ -n "${reghost}" && -n "${signed}" && -n "${unsigned}" && -n "${wrongkey}" ]] \
        || fail "signature fixtures complete" "digests.env incomplete"
    sig_repo="${reghost}/kiezel-sigtest"
    reg_name="${reghost%%:*}"
    scp_vm "${SIGTEST}/keys/test.pub" root@vsock:/etc/pki/kiezel-sigtest.pub \
        || fail "copy signature-test public key into the VM"
    ssh_vm "grep -q '${reg_name}' /etc/hosts || echo '10.0.2.2 ${reg_name}' >> /etc/hosts
            mkdir -p /etc/containers/registries.conf.d
            printf '[[registry]]\nlocation=\"${reghost}\"\ninsecure=true\n' > /etc/containers/registries.conf.d/98-sigtest.conf
            printf 'docker:\n  ${sig_repo}:\n    use-sigstore-attachments: true\n' > /etc/containers/registries.d/sigtest.yaml
            jq --arg s '${sig_repo}' '.transports.docker[\$s] = [{type:\"sigstoreSigned\",keyPaths:[\"/etc/pki/kiezel-sigtest.pub\"],signedIdentity:{type:\"matchRepository\"}}]' \
               /etc/containers/policy.json > /tmp/p && cp /tmp/p /etc/containers/policy.json" \
        || fail "install signature-test policy scope in the VM"

    if ssh_vm "podman pull -q ${sig_repo}@${signed}" >/dev/null 2>&1; then
        pass "VM accepts an image signed through ci/sign.sh (classic format)"
    else fail "VM accepts an image signed through ci/sign.sh" "$(ssh_vm "podman pull -q ${sig_repo}@${signed}" 2>&1 | tail -1)"; fi
    for kind in unsigned wrongkey; do
        out="$(ssh_vm "podman pull -q ${sig_repo}@${!kind}" 2>&1)"
        if [[ $? -ne 0 ]] && grep -qi 'signature' <<<"${out}"; then pass "VM rejects the ${kind} image ($(tail -1 <<<"${out}" | cut -c1-90))"
        else fail "VM rejects the ${kind} image" "${out:0:200}"; fi
    done
elif [[ ${ALLOW_SKIP} -eq 1 ]]; then
    skip "signature path in the VM" "no --sigtest fixtures (allowed: fork PR)"
else
    fail "signature path in the VM" "no --sigtest fixtures; SKIP is only allowed on forks"
fi

# --- DNS soak (owner requirement after run 45015996234) -----------------------------------------
# One lookup per second per method for 5 minutes, also during network events, a reconnect to a
# network that blocks Quad9, and a mid-session Quad9 outage (tests/boot/dns-soak.py). It runs right
# before the unsigned-switch check, where that run saw "lookup ghcr.io: no such host", and with
# the REAL resolver: nothing is pinned. A failed lookup is an image bug until proven otherwise.
#   failure        must be 0
#   no-link        started while the link was down during the reconnect (reported)
#   detect-window  started during the mid-session outage before the switch to the fallback;
#                  by design only the router could answer those (ADR-0012; reported, and the
#                  switch itself must happen within 15 s)
if scp_vm "${HERE}/dns-soak.py" root@vsock:/run/dns-soak.py >/dev/null 2>&1; then
    ssh_vm "python3 -I /run/dns-soak.py ${link} 300" > "${WORKDIR}/dns-soak.jsonl" 2>&1
    sum="$(grep '"summary"' "${WORKDIR}/dns-soak.jsonl" | tail -1)"
    if [[ -z "${sum}" ]]; then
        fail "DNS soak ran to the end" "no summary; see dns-soak.jsonl"
    else
        read -r n failed f_nss f_up nolink detect slow <<<"$(jq -r '"\(.lookups) \(.failed) \(.failed_by_method.nss) \(.failed_by_method.upstream) \(.no_link) \(.detect_window) \(.slowest_ok_secs)"' <<<"${sum}")"
        if [[ "${failed}" == "0" && "${n}" -ge 590 ]]; then
            pass "DNS soak: ${n} lookups in 5 min (events, reconnect to a Quad9-blocking network, outage): 0 failed"
        else
            fail "DNS soak: 0 failed lookups required" "${failed} failed of ${n} (nss ${f_nss}, upstream ${f_up}); details in dns-soak.jsonl"
            dns_journal
        fi
        log "INFO  DNS soak: ${nolink} lookup(s) started while the link was down (reconnect), ${detect} in the outage detection window; slowest successful lookup ${slow} s"
        sw="$(jq -r '[.events[] | select(.event | startswith("Quad9 outage")) | .fallback_after_secs] | first // "none"' <<<"${sum}")"
        back="$(jq -r '[.events[] | select(.event | startswith("Quad9 answers")) | .back_to_quad9_after_secs] | map(tostring) | join(",")' <<<"${sum}")"
        if [[ "${sw}" =~ ^[0-9.]+$ ]] && awk -v s="${sw}" 'BEGIN{exit !(s <= 15)}'; then
            pass "DNS soak: mid-session Quad9 outage -> fallback after ${sw} s (no network event needed); back to Quad9 after ${back} s"
        else fail "DNS soak: outage -> fallback within 15 s" "switched after ${sw} s; back after ${back}"; dns_journal; fi
    fi
else
    fail "DNS soak: copy the soak script into the VM"
fi

# The update path itself: a plain 'bootc switch' (what the update timer effectively does) to an
# UNSIGNED bootable image in OUR repository must be refused by the trust policy.
if skopeo inspect --raw "docker://${KIEZEL_REF}:ci-unsigned-bootable" >/dev/null 2>&1; then
    # This check proves the SIGNATURE policy, not DNS. Run #45015996234 failed here with
    # "lookup ghcr.io: no such host" (DNS had worked a minute earlier; the cause could not be
    # proven from the logs). To make it deterministic: the runner resolves ghcr.io itself and pins
    # it in the VM's /etc/hosts for this check only. A remaining network error (dial/timeout) is
    # retried twice and then FAILS as a network error, never counted as "refused".
    reg_host="${KIEZEL_REF%%/*}"
    reg_ip="$(getent ahostsv4 "${reg_host}" | awk 'NR==1{print $1}')"
    # Evidence first: does the VM's own resolver find ghcr.io right now? (INFO; diagnostics if not)
    if ! ssh_vm "resolvectl query --legend=no ${reg_host} >/dev/null 2>&1"; then
        log "INFO  the VM's resolver did not resolve ${reg_host} before the signature check; diagnostics in the report"
        ssh_vm "echo '--- ${reg_host} lookup diagnostics'; resolvectl query ${reg_host}; resolvectl status; resolvectl statistics;
                journalctl -b --no-pager -o short-monotonic -u systemd-resolved -u kiezel-dns-route | tail -40" >> "${REPORT}" 2>&1
    fi
    [[ -n "${reg_ip}" ]] && ssh_vm "echo '${reg_ip} ${reg_host} # kiezel-boot-test' >> /etc/hosts"
    for attempt in 1 2 3; do
        out="$(ssh_vm "bootc switch ${KIEZEL_REF}:ci-unsigned-bootable" 2>&1)"; rc=$?
        grep -qiE 'dial tcp|i/o timeout|connection (reset|refused)|TLS handshake timeout|no such host' <<<"${out}" || break
        log "      network error on attempt ${attempt}, retrying: ${out:0:160}"; sleep 10
    done
    ssh_vm "sed -i '/# kiezel-boot-test\$/d' /etc/hosts"
    if [[ ${rc} -ne 0 ]] && grep -qi 'signature' <<<"${out}"; then pass "bootc refuses to switch to an UNSIGNED Kiezel image"
    elif grep -qiE 'dial tcp|i/o timeout|connection (reset|refused)|TLS handshake timeout|no such host' <<<"${out}"; then
        fail "bootc refuses to switch to an UNSIGNED Kiezel image" "NETWORK error, not a signature result, after 3 attempts: ${out:0:240}"
    else fail "bootc refuses to switch to an UNSIGNED Kiezel image" "${out:0:300}"; ssh_vm "bootc switch ${KIEZEL_REF}:stable" >/dev/null 2>&1; fi
elif [[ ${ALLOW_SKIP} -eq 1 ]]; then
    skip "unsigned bootable image refused by bootc" "ci-unsigned-bootable not reachable (allowed: fork PR)"
else
    fail "unsigned bootable image refused by bootc" "ci-unsigned-bootable not reachable; SKIP is only allowed on forks"
fi

# --- Update scenarios (ADR-0008) ---------------------------------------------------------------
booted_digest() { ssh_vm "bootc status --format json | jq -r '.status.booted.image.imageDigest // empty'" 2>/dev/null; }
staged_digest() { ssh_vm "bootc status --format json | jq -r '.status.staged.image.imageDigest // empty'" 2>/dev/null; }

# Point kiezel:<dst> at the manifest of kiezel:<src> (registry API; no image data copied).
# Prints the manifest digest.
retag() {
    local src="$1" dst="$2" hdr body ctype digest
    hdr="$(mktemp)" body="$(mktemp)"
    curl -fsS -D "${hdr}" -o "${body}" \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json' \
        "http://${REGISTRY}/v2/kiezel/manifests/${src}"
    ctype="$(grep -i '^content-type:' "${hdr}" | cut -d' ' -f2 | tr -d '\r')"
    digest="$(grep -i '^docker-content-digest:' "${hdr}" | cut -d' ' -f2 | tr -d '\r')"
    curl -fsS -X PUT -H "Content-Type: ${ctype}" --data-binary "@${body}" \
        "http://${REGISTRY}/v2/kiezel/manifests/${dst}" >/dev/null
    rm -f "${hdr}" "${body}"
    echo "${digest}"
}

# Run the real automatic-update unit, as its timer would, and wait until it has finished.
run_update_timer() {
    ssh_vm "systemctl start --wait rpm-ostreed-automatic.service; systemctl show -p Result,ExecMainStatus --value rpm-ostreed-automatic.service | xargs" 2>&1
}

reboot_vm() { ssh_vm "systemctl reboot" >/dev/null 2>&1 || true; sleep 20; }

if [[ -n "${REGISTRY}" ]]; then
    vm_registry="10.0.2.2:${REGISTRY##*:}"
    ssh_vm "mkdir -p /etc/containers/registries.conf.d && printf '[[registry]]\nlocation=\"${vm_registry}\"\ninsecure=true\n' > /etc/containers/registries.conf.d/99-ci.conf"
    # Test-only policy scope for the local channel: the catch-all is "reject" since Phase 2, and
    # these scenarios test update/rollback mechanics, not signatures (that is the signature path).
    ssh_vm "jq --arg s '${vm_registry}/kiezel' '.transports.docker[\$s] = [{type:\"insecureAcceptAnything\"}]' /etc/containers/policy.json > /tmp/p && cp /tmp/p /etc/containers/policy.json"

    # -- Step 0: track the test channel, on the good image ------------------------------------
    log "== Update scenarios via ${vm_registry}/kiezel:channel"
    good="$(retag good channel)"
    ssh_vm "bootc switch ${vm_registry}/kiezel:channel" >> "${REPORT}" 2>&1
    reboot_vm
    if wait_ssh 600 && [[ "$(booted_digest)" == "${good}" ]]; then pass "tracking the test channel on the good image"
    else fail "tracking the test channel on the good image" "booted=$(booted_digest) expected=${good}"; fi

    # -- Step 1: update staged by the timer, then POWER-OFF (greenboot-rs #219) --------------------
    good2="$(retag good2 channel)"
    out="$(run_update_timer)"
    if [[ "$(staged_digest)" == "${good2}" ]]; then pass "update timer staged the new image (${out})"
    else fail "update timer staged the new image" "staged='$(staged_digest)' timer='${out}'"; fi
    ssh_vm "systemctl poweroff" >/dev/null 2>&1 || true
    if wait_poweroff 300; then
        start_vm
        if wait_ssh 900; then
            sleep 60   # give greenboot time to finish its checks on this boot
            now="$(booted_digest)"
            gbres="$(ssh_vm 'systemctl show -p Result --value greenboot-healthcheck.service')"
            if [[ "${now}" == "${good2}" && "${gbres}" == "success" ]]; then
                pass "power-off with a staged update: new image booted, healthy, NO false rollback (#219)"
            else
                fail "power-off with a staged update: no false rollback (#219)" "booted=${now} expected=${good2} greenboot=${gbres}"
            fi
        else fail "VM came back after power-off"; fi
    else fail "VM powered off with a staged update" "still running after 5 min"; fi

    # -- Step 2: broken update -> automatic rollback ----------------------------------------------
    broken="$(retag broken channel)"
    out="$(run_update_timer)"
    if [[ "$(staged_digest)" == "${broken}" ]]; then pass "update timer staged the broken image"
    else fail "update timer staged the broken image" "staged='$(staged_digest)' timer='${out}'"; fi
    reboot_vm
    # Up to 3 failing boots of ~2.5 min each, then greenboot rolls back.
    deadline=$((SECONDS + 2400)) back=0
    while (( SECONDS < deadline )); do
        if wait_ssh 60 && [[ "$(booted_digest)" == "${good2}" ]]; then back=1; break; fi
        sleep 20
    done
    if [[ ${back} -eq 1 ]]; then pass "broken update rolled back automatically to the previous image"
    else fail "broken update rolled back automatically" "not back on ${good2} after 40 min"; fi

    if [[ ${back} -eq 1 ]]; then
        if ssh_vm "grep -qxF '${broken}' /var/lib/kiezel/failed-digests"; then pass "failed image digest recorded by greenboot red hook"
        else fail "failed image digest recorded by greenboot red hook" "$(ssh_vm 'cat /var/lib/kiezel/failed-digests 2>&1')"; fi
        if ssh_vm "test -f /var/lib/kiezel/notices/update-failed"; then pass "plain-language notice queued for the user"
        else fail "plain-language notice queued for the user"; fi

        # -- Step 3: no rollback loop: two timer runs must NOT stage the failed digest again ----
        loop=0
        for run in 1 2; do
            out="$(run_update_timer)"
            st="$(staged_digest)"
            log "      timer run ${run}: result='${out}' staged='${st:-none}'"
            [[ "${st}" == "${broken}" ]] && loop=1
        done
        if [[ ${loop} -eq 0 ]]; then pass "no rollback loop: 2 timer runs did not stage the failed image again"
        else fail "no rollback loop: the failed image was staged again"; fi
        ssh_vm "journalctl -b --no-pager -o cat -u rpm-ostreed-automatic | grep -i kiezel | tail -3" >> "${REPORT}" 2>&1
    fi
fi

log ""
if [[ ${fails} -eq 0 ]]; then log "RESULT: all boot checks passed"; else log "RESULT: ${fails} check(s) FAILED"; fi
exit $(( fails > 0 ))
