#!/usr/bin/bash
# Kiezel installer test (ADR-0005). Boots the CI-test netinstall ISO under QEMU with Secure Boot
# and swtpm, lets the kickstart install to an empty disk, and checks the outcome.
#
# Usage:
#   tests/iso/install-test.sh --iso ISO --expect success|signature-rejected [--workdir DIR]
#
#   success              install must complete (VM powers off by itself) and the serial log must
#                        show the Kiezel installer policy was installed.
#   signature-rejected   the ISO points at an UNSIGNED image: the install must stop at the payload
#                        step with a signature error, and must NOT power off as "complete".
set -uo pipefail

ISO="" EXPECT="" WORKDIR="${PWD}/tests/out/install"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
OVMF_VARS="${OVMF_VARS:-/usr/share/OVMF/OVMF_VARS_4M.ms.fd}"
TIMEOUT="${TIMEOUT:-3600}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso) ISO="$2"; shift 2 ;;
        --expect) EXPECT="$2"; shift 2 ;;
        --workdir) WORKDIR="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ -f "${ISO}" && "${EXPECT}" =~ ^(success|signature-rejected)$ ]] || { echo "need --iso and --expect" >&2; exit 2; }

rm -rf "${WORKDIR}"; mkdir -p "${WORKDIR}/tpm"
SERIAL="${WORKDIR}/serial.log"
cp "${OVMF_VARS}" "${WORKDIR}/OVMF_VARS.fd"
qemu-img create -q -f qcow2 "${WORKDIR}/disk.qcow2" 40G

cleanup() {
    [[ -f "${WORKDIR}/qemu.pid" ]] && kill "$(cat "${WORKDIR}/qemu.pid")" 2>/dev/null
    [[ -f "${WORKDIR}/swtpm.pid" ]] && kill "$(cat "${WORKDIR}/swtpm.pid")" 2>/dev/null
}
trap cleanup EXIT

swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm.pid" \
    --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm.sock"

qemu-system-x86_64 \
    -name kiezel-install-test -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 2 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
    -drive "file=${WORKDIR}/disk.qcow2,if=virtio,format=qcow2" \
    -cdrom "${ISO}" -boot once=d \
    -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm.sock" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial "file:${SERIAL}" -display none -no-reboot \
    -pidfile "${WORKDIR}/qemu.pid" &
qpid=$!

echo "== Kiezel install test (expect: ${EXPECT})"
start=${SECONDS} outcome="timeout"
while (( SECONDS - start < TIMEOUT )); do
    if ! kill -0 "${qpid}" 2>/dev/null; then outcome="poweroff"; break; fi
    if strings "${SERIAL}" | grep -qiE 'signature (is )?required|no signature|signature.*(invalid|not valid|verification failed)|A signature was required'; then
        outcome="signature-error"; break
    fi
    if strings "${SERIAL}" | grep -qE 'Traceback|An unknown error has occured|Pane is dead|error occurred while installing the payload'; then
        outcome="installer-error"; break
    fi
    sleep 10
done
echo "   outcome after $((SECONDS - start))s: ${outcome}"

policy_ok=0
strings "${SERIAL}" | grep -q 'Kiezel installer trust policy installed' && policy_ok=1

rc=1
case "${EXPECT}:${outcome}" in
    success:poweroff)
        if [[ ${policy_ok} -eq 1 ]]; then
            echo "PASS  install completed with the Kiezel installer trust policy in place"; rc=0
        else
            echo "FAIL  install completed, but no proof that %pre installed the trust policy"
        fi ;;
    signature-rejected:signature-error)
        echo "PASS  installer REFUSED the unsigned image"; rc=0 ;;
    signature-rejected:installer-error)
        if strings "${SERIAL}" | tr '\n' ' ' | grep -qiE 'signature'; then
            echo "PASS  installer REFUSED the unsigned image (payload error mentions the signature)"; rc=0
        else
            echo "FAIL  installer failed, but NOT because of the signature"
        fi ;;
    signature-rejected:poweroff)
        echo "FAIL  installer installed an UNSIGNED image" ;;
    *)
        echo "FAIL  unexpected outcome '${outcome}' (expected ${EXPECT})" ;;
esac

if [[ ${rc} -ne 0 ]]; then
    echo "--- last serial lines ---"; strings "${SERIAL}" | tail -40
fi
exit "${rc}"
