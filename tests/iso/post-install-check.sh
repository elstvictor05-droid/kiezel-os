#!/usr/bin/bash
# After a successful CI-test install (tests/iso/install-test.sh --expect success): boot the
# installed disk, unlock LUKS by typing the CI test passphrase on the serial console, and check
# what the installer produced.
#
# Usage: tests/iso/post-install-check.sh --workdir DIR --key SSH_PRIVATE_KEY
#   DIR is the install-test workdir (disk.qcow2, OVMF_VARS.fd with the boot entry, tpm/).
set -uo pipefail

WORKDIR="" KEY=""
PASSPHRASE="kiezel-ci-test"          # CI test kickstart only (iso/build-iso.sh --test)
SSH_PORT="${SSH_PORT:-2223}"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir) WORKDIR="$(realpath "$2")"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${WORKDIR}/disk.qcow2" && -f "${KEY}" ]] || { echo "need --workdir with disk.qcow2 and --key" >&2; exit 2; }

REPORT="${WORKDIR}/post-install-report.txt"; : > "${REPORT}"
SERIAL="${WORKDIR}/serial-boot.log"
fails=0
log()  { printf '%s\n' "$*" | tee -a "${REPORT}"; }
pass() { log "PASS  $1"; }
fail() { log "FAIL  $1${2:+  ($2)}"; fails=$((fails + 1)); }
ssh_vm() {
    ssh -i "${KEY}" -p "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes root@127.0.0.1 "$@"
}
cleanup() {
    [[ -f "${WORKDIR}/qemu-boot.pid" ]] && kill "$(cat "${WORKDIR}/qemu-boot.pid")" 2>/dev/null
    [[ -f "${WORKDIR}/swtpm-boot.pid" ]] && kill "$(cat "${WORKDIR}/swtpm-boot.pid")" 2>/dev/null
}
trap cleanup EXIT

swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm-boot.pid" \
    --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm-boot.sock"
rm -f "${WORKDIR}/serial.sock" "${SERIAL}"
qemu-system-x86_64 \
    -name kiezel-post-install -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 2 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
    -drive "file=${WORKDIR}/disk.qcow2,if=virtio,format=qcow2" \
    -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm-boot.sock" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" -device virtio-net-pci,netdev=n0 \
    -chardev "socket,id=ser0,path=${WORKDIR}/serial.sock,server=on,wait=off,logfile=${SERIAL}" \
    -serial chardev:ser0 -display none \
    -daemonize -pidfile "${WORKDIR}/qemu-boot.pid" || { echo "QEMU failed" >&2; exit 1; }

log "== Kiezel post-install check  $(date -u +%FT%TZ)"

# --- LUKS unlock over the serial console ---------------------------------------------------
start=${SECONDS} typed=0
while (( SECONDS - start < 600 )); do
    if strings "${SERIAL}" 2>/dev/null | grep -qiE 'passphrase for|Please enter passphrase'; then
        python3 -I - "${WORKDIR}/serial.sock" "${PASSPHRASE}" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
time.sleep(1); s.sendall(sys.argv[2].encode() + b"\r"); time.sleep(1); s.close()
PY
        typed=1; break
    fi
    sleep 3
done
if [[ ${typed} -eq 1 ]]; then pass "disk asked for the LUKS passphrase at boot (encrypted, no TPM enrollment yet)"
else fail "disk asked for the LUKS passphrase at boot" "no prompt within 10 min"; fi

ok=0
for _ in $(seq 1 120); do ssh_vm true 2>/dev/null && { ok=1; break; }; sleep 5; done
if [[ ${ok} -eq 0 ]]; then
    fail "installed system reachable after unlock"; strings "${SERIAL}" | tail -30 >> "${REPORT}"; exit 1
fi
pass "installed system booted after unlock"

# --- What the installer produced -------------------------------------------------------------
state="$(ssh_vm 'systemctl is-system-running --wait' 2>/dev/null)"
[[ "${state}" == "running" ]] && pass "system state: running" \
    || fail "system state: running" "got '${state}'; failed: $(ssh_vm 'systemctl --failed --no-legend --plain | cut -d" " -f1 | xargs')"
tgt="$(ssh_vm 'systemctl get-default' 2>&1)"
[[ "${tgt}" == "graphical.target" ]] && pass "boots to the graphical login (default target ${tgt})" || fail "default target is graphical.target" "${tgt}"
dm="$(ssh_vm 'systemctl is-active display-manager.service' 2>&1)"
[[ "${dm}" == "active" ]] && pass "login screen / Plasma Setup is running (display-manager active)" || fail "display-manager active" "${dm}"
gb="$(ssh_vm 'systemctl show -p Result --value greenboot-healthcheck.service' 2>&1)"
[[ "${gb}" == "success" ]] && pass "greenboot healthy on the freshly installed system" || fail "greenboot healthy after install" "${gb}"
luks="$(ssh_vm "lsblk -rno TYPE,FSTYPE | grep -c 'crypto_LUKS'; cryptsetup luksDump \$(lsblk -rpno NAME,FSTYPE | awk '\$2==\"crypto_LUKS\"{print \$1; exit}') | awk '/^Version:/{print \$2}'" 2>&1 | xargs)"
[[ "${luks}" =~ ^[1-9][0-9]*\ 2$ ]] && pass "root disk is LUKS2-encrypted (${luks})" || fail "root disk is LUKS2-encrypted" "${luks}"

sb="$(ssh_vm 'mokutil --sb-state' 2>&1)"
grep -q 'SecureBoot enabled' <<<"${sb}" && pass "Secure Boot enabled on the installed system" || fail "Secure Boot enabled" "${sb}"

se="$(ssh_vm getenforce 2>&1)"
[[ "${se}" == "Enforcing" ]] && pass "SELinux enforcing" || fail "SELinux enforcing" "${se}"

img="$(ssh_vm "bootc status --format json | jq -r '.status.booted.image.image.image'" 2>&1)"
sigmode="$(ssh_vm "bootc status --format json | jq -c '.status.booted.image.image.signature'" 2>&1)"
[[ "${img}" == "ghcr.io/elstvictor05-droid/kiezel:stable" ]] && pass "tracks ghcr.io/elstvictor05-droid/kiezel:stable (origin signature mode: ${sigmode})" \
    || fail "tracks ghcr.io/elstvictor05-droid/kiezel:stable" "${img}"

pol="$(ssh_vm "jq -r '.transports.docker[\"ghcr.io/elstvictor05-droid/kiezel\"][0].type' /etc/containers/policy.json" 2>&1)"
[[ "${pol}" == "sigstoreSigned" ]] && pass "installed trust policy requires Kiezel signatures" || fail "installed trust policy" "${pol}"

out="$(ssh_vm "bootc switch ghcr.io/elstvictor05-droid/kiezel:ci-unsigned-bootable" 2>&1)"
if [[ $? -ne 0 ]] && grep -qi signature <<<"${out}"; then pass "installed system refuses an UNSIGNED Kiezel image"
else fail "installed system refuses an UNSIGNED Kiezel image" "${out:0:200}"; fi

# Language: the INSTALLER must write nl_BE (checked from its own %post log). Plasma Setup then
# rewrites it to nl_NL at start-up (upstream bug, ADR-0007); images with the Kiezel workaround
# save the installer's locale first and restore the region after setup.
inst="$(ssh_vm "sed -n 's/^locale: //p' /root/kiezel-post.log" 2>&1 | tr -d '"')"
[[ "${inst}" == "LANG=nl_BE.UTF-8" ]] && pass "installer wrote the preselected language (${inst})" \
    || fail "installer wrote LANG=nl_BE.UTF-8" "${inst}"
if ssh_vm 'test -f /usr/lib/systemd/system/kiezel-locale-capture.service'; then
    saved="$(ssh_vm 'cat /var/lib/kiezel/installer-locale.conf' 2>&1)"
    [[ "${saved}" == "LANG=nl_BE.UTF-8" ]] && pass "installer locale saved before Plasma Setup (${saved}); region restored after setup" \
        || fail "installer locale saved before Plasma Setup" "${saved}"
else
    log "WARN  installed image predates the Plasma Setup locale workaround; LANG is now $(ssh_vm 'sed -n s/^LANG=//p /etc/locale.conf' 2>&1)"
fi

admins="$(ssh_vm "getent group wheel | cut -d: -f4" 2>&1)"
log "INFO  wheel members after install: '${admins}' (CI kickstart creates no user; Plasma Setup runs on first boot)"
ps="$(ssh_vm 'test -e /etc/plasma-setup-done && echo done || echo pending' 2>&1)"
[[ "${ps}" == "pending" ]] && pass "Plasma Setup will run on first boot" || fail "Plasma Setup pending" "${ps}"

log "--- kickstart %post log (installed system) ---"
ssh_vm 'tail -20 /root/kiezel-post.log' >> "${REPORT}" 2>&1

log ""
[[ ${fails} -eq 0 ]] && log "RESULT: all post-install checks passed" || log "RESULT: ${fails} check(s) FAILED"
exit $(( fails > 0 ))
