#!/usr/bin/bash
# Diagnostic for the run #45 DNS failure (owner: reproduce before any fix). NOT a product test.
# On a GitHub runner the VM has an IPv6 default route (QEMU user-net) while the runner itself has
# no IPv6 egress, which a laptop with IPv6 cannot mimic without root.
#
#   VM 1, QEMU ipv6=on : baseline (image as released) | A: Quad9 over IPv4 only |
#                        B: conditional (IPv6 servers only when they answer at that moment)
#   VM 2, QEMU ipv6=off: baseline (control)
#
# Usage: tests/diag/dns-ipv6.sh --disk DISK --key KEY --workdir DIR
#        [--steady N] [--cycles C] [--block S] [--after K]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DISK="" KEY="" WORKDIR="${PWD}/tests/out/diag"
STEADY=30 CYCLES=6 BLOCK=45 AFTER=10
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        --steady) STEADY="$2"; shift 2 ;;
        --cycles) CYCLES="$2"; shift 2 ;;
        --block) BLOCK="$2"; shift 2 ;;
        --after) AFTER="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${DISK}" && -f "${KEY}" ]] || { echo "need --disk and --key" >&2; exit 2; }
mkdir -p "${WORKDIR}"
OUT="${WORKDIR}/results.jsonl"; SUMMARY="${WORKDIR}/summary.txt"
: > "${OUT}"; : > "${SUMMARY}"
CID=5

ssh_vm() { timeout "${SSH_T:-1500}" ssh -i "${KEY}" -o "ProxyCommand=python3 -I ${HERE}/../boot/vsock-proxy.py ${CID} 22" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
    -o LogLevel=ERROR -o BatchMode=yes root@vsock "$@"; }
scp_vm() { scp -q -i "${KEY}" -o "ProxyCommand=python3 -I ${HERE}/../boot/vsock-proxy.py ${CID} 22" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$@"; }

QPID=""
start_vm() {   # $1 = on|off (QEMU user-net IPv6)
    local v6="$1"
    cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd "${WORKDIR}/OVMF_VARS.fd"
    rm -f "${WORKDIR}/qemu.pid"
    qemu-system-x86_64 -name "kiezel-diag-v6${v6}" -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 2 \
        -global driver=cfi.pflash01,property=secure,value=on \
        -drive if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
        -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
        -drive "file=${DISK},if=virtio,format=qcow2,snapshot=on" \
        -netdev "user,id=n0,ipv6=${v6},domainname=home.arpa" -device virtio-net-pci,netdev=n0 \
        -device "vhost-vsock-pci,guest-cid=${CID}" \
        -serial "file:${WORKDIR}/serial-v6${v6}.log" -display none \
        -daemonize -pidfile "${WORKDIR}/qemu.pid" || { echo "QEMU failed" >&2; exit 1; }
    QPID="$(cat "${WORKDIR}/qemu.pid")"
    local s=${SECONDS}
    until SSH_T=10 ssh_vm true 2>/dev/null; do
        (( SECONDS - s > 900 )) && { echo "VM (ipv6=${v6}) not reachable" >&2; tail -40 "${WORKDIR}/serial-v6${v6}.log"; exit 1; }
        sleep 5
    done
    SSH_T=300 ssh_vm 'systemctl is-system-running --wait' >/dev/null 2>&1
    scp_vm "${HERE}/dns-measure.py" root@vsock:/run/dns-measure.py
}
stop_vm() {
    SSH_T=10 ssh_vm 'systemctl poweroff' >/dev/null 2>&1
    local s=${SECONDS}
    while [[ -d "/proc/${QPID}" ]] && (( SECONDS - s < 120 )); do sleep 2; done
    [[ -d "/proc/${QPID}" ]] && kill "${QPID}"
}
trap '[[ -n "${QPID}" && -d "/proc/${QPID}" ]] && kill "${QPID}"' EXIT

V4ONLY='[Resolve]\nDNS=\nDNS=9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net\n'
apply() {   # $1 = baseline | A | B ; prints what was applied
    case "$1" in
        baseline) ssh_vm 'rm -f /run/systemd/resolved.conf.d/99-diag.conf; systemctl restart systemd-resolved; /usr/libexec/kiezel/dns-route; echo "image list (Quad9 IPv4+IPv6)"' ;;
        A) ssh_vm "mkdir -p /run/systemd/resolved.conf.d; printf '${V4ONLY}' > /run/systemd/resolved.conf.d/99-diag.conf; systemctl restart systemd-resolved; /usr/libexec/kiezel/dns-route; echo 'Quad9 IPv4 only'" ;;
        B) ssh_vm "mkdir -p /run/systemd/resolved.conf.d
                   if /usr/libexec/kiezel/dns-watch --probe 2620:fe::fe 2620:fe::9; then rm -f /run/systemd/resolved.conf.d/99-diag.conf; echo 'IPv6 Quad9 answers -> full list'
                   else printf '${V4ONLY}' > /run/systemd/resolved.conf.d/99-diag.conf; echo 'IPv6 Quad9 does not answer -> IPv4 only'; fi
                   systemctl restart systemd-resolved; /usr/libexec/kiezel/dns-route" ;;
    esac
}
measure() {   # $1 = label
    local label="$1" applied
    applied="$(apply "${label%%@*}" 2>&1 | tail -1)"
    sleep 3
    echo "== ${label}: ${applied}" | tee -a "${SUMMARY}"
    ssh_vm "python3 -I /run/dns-measure.py '${label}' ${STEADY} ${CYCLES} ${BLOCK} ${AFTER}" | tee -a "${OUT}" | grep -E '"summary"|"fail"' | cut -c1-240
    grep "\"variant\": \"${label}\"" "${OUT}" | grep '"summary"' | python3 -c '
import json, sys
for l in sys.stdin:
    d = json.loads(l)
    print(f"   steady {d[\"steady\"][1]}/{d[\"steady\"][0]} failed, after Quad9 block {d[\"after_block\"][1]}/{d[\"after_block\"][0]} failed; servers at failure: {d[\"servers_at_fail\"]}")' | tee -a "${SUMMARY}"
}

# VM 1: like the CI runner
start_vm on
ssh_vm 'ip -6 route show default; resolvectl dns | head -1; systemctl --version | head -1' | tee -a "${SUMMARY}"
# Owner point 5: why does resolved stay on a broken server? Debug log during the baseline.
ssh_vm 'resolvectl log-level debug'
measure "baseline@v6on"
ssh_vm 'resolvectl log-level info'
SSH_T=60 ssh_vm 'journalctl -b -u systemd-resolved --no-pager -o short-monotonic' > "${WORKDIR}/resolved-debug-baseline.txt" 2>&1
measure "A@v6on"
measure "B@v6on"
stop_vm

# VM 2: control without IPv6 in the guest
start_vm off
ssh_vm 'ip -6 route show default; resolvectl dns | head -1' | tee -a "${SUMMARY}"
measure "baseline@v6off"
stop_vm

echo "== done" | tee -a "${SUMMARY}"
