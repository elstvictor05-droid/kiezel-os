#!/usr/bin/bash
# Kiezel boot test: boots a disk image under QEMU with UEFI Secure Boot (Microsoft-enrolled OVMF
# vars, so Fedora's shim must be accepted) and an emulated TPM2, then checks the running system
# over SSH. Optionally runs the greenboot rollback test.
#
# Usage:
#   tests/boot/boot-test.sh --disk disk.qcow2 --key id_ed25519 [--rollback-image REF] [--workdir DIR]
#
# The disk must contain the test user "root" with the given SSH key and the kernel argument
# systemd.wants=sshd.service (tests/boot/make-test-disk.sh does both). sshd is OFF in Kiezel;
# it is switched on only for these test disks.
#
# Rollback test: REF is an image in a registry reachable from the VM at 10.0.2.2 (the QEMU
# host), e.g. 10.0.2.2:5000/kiezel:broken, whose required health check fails. The test switches
# to it and expects greenboot to bring the VM back to the original deployment on its own.
set -uo pipefail

DISK="" KEY="" ROLLBACK_IMAGE="" WORKDIR="${PWD}/tests/out/boot"
SSH_PORT="${SSH_PORT:-2222}"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.ms.fd}"
MEM_MB="${MEM_MB:-4096}"
VCPUS="${VCPUS:-2}"
KIEZEL_REF="ghcr.io/elstvictor05-droid/kiezel"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk) DISK="$2"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        --rollback-image) ROLLBACK_IMAGE="$2"; shift 2 ;;
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

ssh_vm() {
    ssh -i "${KEY}" -p "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes root@127.0.0.1 "$@"
}

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

# --- Start emulated TPM2 and the VM ---------------------------------------------
swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm.pid" \
    --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm.sock"

cp "${OVMF_VARS}" "${WORKDIR}/OVMF_VARS.fd"

qemu-system-x86_64 \
    -name kiezel-boot-test \
    -machine q35,smm=on,accel=kvm -cpu host -m "${MEM_MB}" -smp "${VCPUS}" \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
    -drive "file=${DISK},if=virtio,format=qcow2" \
    -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm.sock" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" -device virtio-net-pci,netdev=n0 \
    -serial "file:${SERIAL}" -display none \
    -daemonize -pidfile "${WORKDIR}/qemu.pid" || { echo "QEMU failed to start" >&2; exit 1; }

log "== Kiezel boot test  $(date -u +%FT%TZ)"
log "   disk=${DISK} mem=${MEM_MB}MB vcpus=${VCPUS} secureboot=on tpm2=swtpm"

if ! wait_ssh 900; then
    fail "VM reachable over SSH within 15 min" "see ${SERIAL}"
    tail -50 "${SERIAL}" >&2
    exit 1
fi
pass "VM booted and reachable"

# --- Checks on the running system --------------------------------------------------
state="$(ssh_vm 'systemctl is-system-running --wait' 2>/dev/null)"
if [[ "${state}" == "running" ]]; then pass "system state: running"
else fail "system state: running" "got '${state}'; failed: $(ssh_vm 'systemctl --failed --no-legend --plain | cut -d" " -f1 | xargs')"; fi

sb="$(ssh_vm 'mokutil --sb-state' 2>&1)"
if grep -q 'SecureBoot enabled' <<<"${sb}"; then pass "Secure Boot enabled (Fedora shim accepted)"
else fail "Secure Boot enabled" "${sb}"; fi

se="$(ssh_vm getenforce 2>&1)"
[[ "${se}" == "Enforcing" ]] && pass "SELinux enforcing" || fail "SELinux enforcing" "${se}"

avc="$(ssh_vm "journalctl -b --no-pager -o cat | grep -c 'avc:  denied'" 2>/dev/null)"
if [[ "${avc}" == "0" ]]; then pass "0 SELinux AVC denials since boot"
else
    fail "0 SELinux AVC denials since boot" "${avc} denials"
    ssh_vm "journalctl -b --no-pager -o cat | grep 'avc:  denied' | head -20" >> "${REPORT}" 2>&1
fi

gb="$(ssh_vm 'systemctl show -p Result --value greenboot-healthcheck.service; systemctl is-active boot-complete.target' 2>&1 | xargs)"
[[ "${gb}" == "success active" ]] && pass "greenboot healthy (boot-complete reached)" \
    || fail "greenboot healthy" "${gb}"

tpm="$(ssh_vm 'test -c /dev/tpmrm0 && echo yes' 2>&1)"
[[ "${tpm}" == "yes" ]] && pass "TPM2 device present" || fail "TPM2 device present"

booted="$(ssh_vm "bootc status --json | jq -r '.status.booted.image.image.image'" 2>&1)"
[[ "${booted}" == "${KIEZEL_REF}:"* ]] && pass "booted image reference is ${booted}" \
    || fail "booted image reference is ${KIEZEL_REF}:*" "${booted}"

# --- Signature policy against the real registry (canaries published by release.yml) -------
if skopeo inspect --raw "docker://${KIEZEL_REF}:ci-canary-signed" >/dev/null 2>&1; then
    if ssh_vm "podman pull -q ${KIEZEL_REF}:ci-canary-signed" >/dev/null 2>&1; then
        pass "image signed with the Kiezel key is accepted"
    else fail "image signed with the Kiezel key is accepted"; fi
    out="$(ssh_vm "podman pull -q ${KIEZEL_REF}:ci-canary-unsigned" 2>&1)"
    if [[ $? -ne 0 ]] && grep -qi 'signature' <<<"${out}"; then pass "UNSIGNED image in the Kiezel repository is rejected"
    else fail "UNSIGNED image in the Kiezel repository is rejected" "${out:0:200}"; fi
else
    skip "signature canaries" "not published yet; created by the first release run"
fi

# The update path itself: a plain 'bootc switch' (what the update timer effectively does) to an
# UNSIGNED bootable image in our repository must be refused by the trust policy.
if skopeo inspect --raw "docker://${KIEZEL_REF}:ci-unsigned-bootable" >/dev/null 2>&1; then
    out="$(ssh_vm "bootc switch ${KIEZEL_REF}:ci-unsigned-bootable" 2>&1)"
    if [[ $? -ne 0 ]] && grep -qi 'signature' <<<"${out}"; then pass "bootc refuses to switch to an UNSIGNED Kiezel image"
    else fail "bootc refuses to switch to an UNSIGNED Kiezel image" "${out:0:300}"; ssh_vm "bootc switch ${KIEZEL_REF}:stable" >/dev/null 2>&1; fi
else
    skip "unsigned bootable image refused by bootc" "ci-unsigned-bootable not published yet (first main build)"
fi

# --- Rollback test (ADR-0008) -------------------------------------------------------
if [[ -n "${ROLLBACK_IMAGE}" ]]; then
    log "== Rollback test with ${ROLLBACK_IMAGE}"
    original="$(ssh_vm "bootc status --json | jq -r '.status.booted.imageDigest // .status.booted.image.imageDigest'")"
    ssh_vm "mkdir -p /etc/containers/registries.conf.d && printf '[[registry]]\nlocation=\"10.0.2.2:5000\"\ninsecure=true\n' > /etc/containers/registries.conf.d/99-ci.conf"
    if ! ssh_vm "bootc switch ${ROLLBACK_IMAGE}" >> "${REPORT}" 2>&1; then
        fail "switch to broken image staged"
    else
        pass "switch to broken image staged"
        ssh_vm "systemctl reboot" 2>/dev/null || true
        sleep 30
        # greenboot: up to 3 failed boots, then rollback. Each failed boot waits ~2 min.
        deadline=$((SECONDS + 2400)) back=0
        while (( SECONDS < deadline )); do
            if wait_ssh 60; then
                now="$(ssh_vm "bootc status --json | jq -r '.status.booted.imageDigest // .status.booted.image.imageDigest'" 2>/dev/null)"
                if [[ -n "${now}" && "${now}" == "${original}" ]]; then back=1; break; fi
            fi
            sleep 20
        done
        if [[ ${back} -eq 1 ]]; then
            pass "broken update rolled back automatically to the previous deployment"
            ssh_vm "journalctl --no-pager -o cat -u greenboot-healthcheck -b -1 | tail -5" >> "${REPORT}" 2>&1 || true
        else
            fail "broken update rolled back automatically" "still not on original deployment after 40 min"
        fi
    fi
fi

log ""
if [[ ${fails} -eq 0 ]]; then log "RESULT: all boot checks passed"; else log "RESULT: ${fails} check(s) FAILED"; fi
exit $(( fails > 0 ))
