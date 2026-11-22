#!/usr/bin/bash
# Boot a freshly installed CI-test disk with a virtual screen and save screenshots of the first
# boot (Plasma Setup), for docs and the accessibility spike (ADR-0007).
#
# Usage: tests/iso/screenshots.sh --workdir DIR [--shots N] [--interval SECONDS] [--keys "KEYS"]
#   --keys: optional QEMU sendkey sequence (space-separated, e.g. "meta_l-alt-s") sent once the
#           first screenshot is taken, to test shortcuts such as the screen reader toggle.
set -uo pipefail

WORKDIR="" SHOTS=6 INTERVAL=20 KEYS="" PASSPHRASE="kiezel-ci-test"
OVMF_CODE="${OVMF_CODE:-/usr/share/OVMF/OVMF_CODE_4M.secboot.fd}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir) WORKDIR="$(realpath "$2")"; shift 2 ;;
        --shots) SHOTS="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --keys) KEYS="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
out="${WORKDIR}/screenshots"; mkdir -p "${out}"
mon="${WORKDIR}/monitor.sock"; ser="${WORKDIR}/serial-shots.sock"
rm -f "${mon}" "${ser}"

swtpm socket --tpm2 --daemon --pid "file=${WORKDIR}/swtpm-s.pid" \
    --tpmstate "dir=${WORKDIR}/tpm" --ctrl "type=unixio,path=${WORKDIR}/swtpm-s.sock"
qemu-system-x86_64 \
    -machine q35,smm=on,accel=kvm -cpu host -m 4096 -smp 2 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${WORKDIR}/OVMF_VARS.fd" \
    -drive "file=${WORKDIR}/disk.qcow2,if=virtio,format=qcow2" \
    -chardev "socket,id=chrtpm,path=${WORKDIR}/swtpm-s.sock" \
    -tpmdev emulator,id=tpm0,chardev=chrtpm -device tpm-tis,tpmdev=tpm0 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -device virtio-vga -display none -device virtio-tablet -device virtio-keyboard \
    -chardev "socket,id=ser0,path=${ser},server=on,wait=off,logfile=${WORKDIR}/serial-shots.log" -serial chardev:ser0 \
    -monitor "unix:${mon},server,nowait" \
    -daemonize -pidfile "${WORKDIR}/qemu-s.pid" || exit 1

monitor() { python3 -I - "${mon}" "$1" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); time.sleep(0.3)
s.recv(4096); s.sendall(sys.argv[2].encode() + b"\n"); time.sleep(1.5); s.close()
PY
}

# Unlock LUKS over serial.
for _ in $(seq 1 200); do
    grep -aq 'enter passphrase' "${WORKDIR}/serial-shots.log" 2>/dev/null && break; sleep 3
done
python3 -I -c "import socket,sys,time;s=socket.socket(socket.AF_UNIX);s.connect(sys.argv[1]);time.sleep(1);s.sendall(sys.argv[2].encode()+b'\r');time.sleep(1)" "${ser}" "${PASSPHRASE}"

sleep 90   # first boot: Plasma Setup starts through the display manager
for i in $(seq 1 "${SHOTS}"); do
    monitor "screendump ${out}/shot-$(printf %02d "${i}").png -f png"
    if [[ ${i} -eq 1 && -n "${KEYS}" ]]; then
        for k in ${KEYS}; do monitor "sendkey ${k}"; sleep 2; done
    fi
    sleep "${INTERVAL}"
done
kill "$(cat "${WORKDIR}/qemu-s.pid")" 2>/dev/null
kill "$(cat "${WORKDIR}/swtpm-s.pid")" 2>/dev/null
ls -la "${out}"
