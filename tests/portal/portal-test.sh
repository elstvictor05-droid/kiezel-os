#!/usr/bin/bash
# Simulated captive portal (owner requirement for v0.1, ADR-0012). Runs as ROOT on the CI runner.
#
# Network "Free Wi-Fi" on bridge br-portal (192.168.77.0/24), VM attached through a tap device:
#   before login: dnsmasq answers EVERY name with the portal IP (DNS hijack), HTTP redirects to
#                 /login, and forwarding to the internet is blocked, so Quad9 is unreachable
#   after login:  dnsmasq forwards to real DNS, NAT to the internet is enabled
# Proves on the real image: Kiezel's DNS falls back to the network's DNS, so NetworkManager can
# detect the portal (without the fallback it would only see "limited"); after login Kiezel goes
# back to Quad9 by itself.
#
# Usage: sudo tests/portal/portal-test.sh --disk DISK.qcow2 --key SSH_KEY [--workdir DIR]
set -uo pipefail

DISK="" KEY="" WORKDIR="${PWD}/tests/out/portal"
VSOCK_CID="${VSOCK_CID:-5}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.ms.fd}"
NET=192.168.77 BR=br-portal TAP=tap-portal
while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${DISK}" && -f "${KEY}" && ${EUID} -eq 0 ]] || { echo "need --disk, --key and root" >&2; exit 2; }
mkdir -p "${WORKDIR}/state" "${WORKDIR}/tpm"; rm -f "${WORKDIR}/state/accepted"
REPORT="${WORKDIR}/report.txt"; : > "${REPORT}"
fails=0
log()  { printf '%s\n' "$*" | tee -a "${REPORT}"; }
pass() { log "PASS  $1"; }
fail() { log "FAIL  $1${2:+  ($2)}"; fails=$((fails + 1)); }
SSH_OPTS=(-i "${KEY}" -o "ProxyCommand=python3 -I ${HERE}/../boot/vsock-proxy.py ${VSOCK_CID} 22"
          -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5
          -o LogLevel=ERROR -o BatchMode=yes)
ssh_vm() { ssh "${SSH_OPTS[@]}" root@vsock "$@"; }
# poll <seconds> <expected> <command...>: repeat until the command prints <expected>; logs the last value.
poll() {
    local secs="$1" want="$2" got=""; shift 2
    for _ in $(seq 1 "$((secs / 3))"); do
        got="$("$@" 2>/dev/null | tr -d '\r' | xargs)"
        [[ "${got}" == "${want}" ]] && { echo "${got}"; return 0; }
        sleep 3
    done
    echo "${got}"; return 1
}

cleanup() {
    for p in qemu swtpm http watcher; do [[ -f "${WORKDIR}/${p}.pid" ]] && kill "$(cat "${WORKDIR}/${p}.pid")" 2>/dev/null; done
    pkill -F "${WORKDIR}/dnsmasq.pid" 2>/dev/null
    iptables -D FORWARD -i "${BR}" -j DROP 2>/dev/null
    iptables -D FORWARD -i "${BR}" -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o "${BR}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    iptables -t nat -D POSTROUTING -s "${NET}.0/24" ! -o "${BR}" -j MASQUERADE 2>/dev/null
    ip link del "${TAP}" 2>/dev/null; ip link del "${BR}" 2>/dev/null
}
trap cleanup EXIT

# --- The "Free Wi-Fi" network ----------------------------------------------------------------
ip link add "${BR}" type bridge && ip addr add "${NET}.1/24" dev "${BR}" && ip link set "${BR}" up
ip tuntap add dev "${TAP}" mode tap && ip link set "${TAP}" master "${BR}" up
sysctl -qw net.ipv4.ip_forward=1
iptables -I FORWARD 1 -i "${BR}" -j DROP          # before login: no internet, so Quad9 unreachable

dnsmasq_hijack() {
    dnsmasq --pid-file="${WORKDIR}/dnsmasq.pid" --interface="${BR}" --bind-interfaces --no-resolv --no-hosts \
        --dhcp-range="${NET}.50,${NET}.99,12h" --dhcp-option=option:router,"${NET}.1" \
        --dhcp-option=option:dns-server,"${NET}.1" --domain=freewifi.test \
        --address="/#/${NET}.1" --log-facility="${WORKDIR}/dnsmasq.log"
}
dnsmasq_open() {
    pkill -F "${WORKDIR}/dnsmasq.pid" 2>/dev/null; sleep 1
    dnsmasq --pid-file="${WORKDIR}/dnsmasq.pid" --interface="${BR}" --bind-interfaces --no-hosts \
        --resolv-file=/run/systemd/resolve/resolv.conf \
        --dhcp-range="${NET}.50,${NET}.99,12h" --dhcp-option=option:router,"${NET}.1" \
        --dhcp-option=option:dns-server,"${NET}.1" --domain=freewifi.test \
        --log-facility="${WORKDIR}/dnsmasq.log"
}
dnsmasq_hijack
python3 -I "${HERE}/portal-server.py" "${NET}.1" "${WORKDIR}/state" 2>"${WORKDIR}/http.log" &
echo $! > "${WORKDIR}/http.pid"

# Login watcher: when the VM "accepts the terms", open the network.
(
    while [[ ! -f "${WORKDIR}/state/accepted" ]]; do sleep 1; done
    iptables -D FORWARD -i "${BR}" -j DROP
    iptables -I FORWARD 1 -i "${BR}" -j ACCEPT
    iptables -I FORWARD 1 -o "${BR}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    iptables -t nat -A POSTROUTING -s "${NET}.0/24" ! -o "${BR}" -j MASQUERADE
    dnsmasq_open
    echo "portal: logged in, network open" >> "${WORKDIR}/http.log"
) &
echo $! > "${WORKDIR}/watcher.pid"

# --- VM on that network ------------------------------------------------------------------------
cp "${OVMF_VARS}" "${WORKDIR}/OVMF_VARS.fd"
swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm.pid" \
    --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm.sock"
qemu-system-x86_64 -name kiezel-portal-test -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 2 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm.sock" -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev "tap,id=n0,ifname=${TAP},script=no,downscript=no" -device virtio-net-pci,netdev=n0 \
    -device "vhost-vsock-pci,guest-cid=${VSOCK_CID}" \
    -serial "file:${WORKDIR}/serial.log" -display none -daemonize -pidfile "${WORKDIR}/qemu.pid" || exit 1

log "== Kiezel captive-portal test  $(date -u +%FT%TZ)"
for _ in $(seq 1 180); do ssh_vm true 2>/dev/null && break; sleep 5; done
ssh_vm true 2>/dev/null || { fail "VM reachable"; exit 1; }
link=""
for _ in $(seq 1 30); do
    link="$(ssh_vm "ip -4 route show default | awk '{print \$5; exit}'" 2>/dev/null)"
    [[ -n "${link}" ]] && break; sleep 3
done
addr="$(ssh_vm "ip -4 -o addr show dev ${link} | awk '{print \$4}'" 2>&1)"
[[ "${addr}" == "${NET}."* ]] && pass "VM got an address from the portal network (${link} ${addr})" || fail "DHCP on portal network" "${link} ${addr}"

# 1. Quad9 unreachable -> DNS falls back to the network's DNS.
ssh_vm 'systemctl start kiezel-dns-route.service' >/dev/null 2>&1
r="$(poll 60 yes ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'")" \
    && pass "behind the portal Quad9 is unreachable -> automatic fallback to the network's DNS" \
    || fail "DNS fallback behind the portal" "default-route=${r}"
r="$(poll 30 "${NET}.1" ssh_vm "getent hosts fedoraproject.org | cut -d' ' -f1")" \
    && pass "names resolve through the portal's DNS (hijacked to ${r}, as real portals do)" \
    || fail "names resolve via portal DNS" "${r}"

# 2. NetworkManager detects the portal (this is what makes Plasma show "log in to network").
r="$(poll 90 portal ssh_vm 'nmcli networking connectivity check')" \
    && pass "NetworkManager detects the captive portal (connectivity: portal)" \
    || fail "NetworkManager detects the portal" "connectivity=${r}"
r="$(ssh_vm "curl -s -o /dev/null -w '%{http_code} %{redirect_url}' --max-time 10 http://fedoraproject.org/static/hotspot.txt" 2>&1)"
[[ "${r}" == "302 http://${NET}.1/login" ]] && pass "HTTP is redirected to the portal login page" || fail "portal redirect" "${r}"

# 3. The user accepts the terms -> full connectivity -> Kiezel returns to Quad9 by itself.
ssh_vm "curl -s --max-time 10 http://${NET}.1/accept" >/dev/null 2>&1
r="$(poll 120 full ssh_vm 'nmcli networking connectivity check')" \
    && pass "after login: full connectivity" || fail "full connectivity after login" "connectivity=${r}"
# The NetworkManager dispatcher (connectivity-change) should switch back without help; give it 60 s.
if r="$(poll 60 no ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'")"; then
    pass "after login Kiezel switched back to Quad9 by itself (dispatcher on connectivity change)"
else
    ssh_vm 'systemctl start kiezel-dns-route.service' >/dev/null 2>&1
    r2="$(poll 30 no ssh_vm "resolvectl default-route ${link} | awk '{print \$NF}'")"
    fail "automatic return to Quad9 after login" "dispatcher left default-route=${r}; manual re-check gives ${r2}"
fi
r="$(ssh_vm 'resolvectl query --cache=no --legend=no example.com >/dev/null && echo ok' 2>&1)"
[[ "${r}" == "ok" ]] && pass "lookups work through Quad9 after login" || fail "lookups after login" "${r}"

ssh_vm 'journalctl -b --no-pager -o cat | grep kiezel-dns-route | tail -6' >> "${REPORT}" 2>&1
log ""
[[ ${fails} -eq 0 ]] && log "RESULT: all captive-portal checks passed" || log "RESULT: ${fails} check(s) FAILED"
exit $(( fails > 0 ))
