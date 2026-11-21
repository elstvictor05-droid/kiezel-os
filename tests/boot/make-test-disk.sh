#!/usr/bin/bash
# Turn a Kiezel container image (in ROOT podman storage) into a qcow2 test disk with
# bootc-image-builder. Adds what the boot test needs and nothing else:
#   - an SSH key for root (test disks only)
#   - kernel argument systemd.wants=sshd.service (sshd is off in Kiezel)
#
# Usage (needs root, as bootc-image-builder does):
#   sudo tests/boot/make-test-disk.sh <local-image> <ssh-pubkey-file> <outdir>
#
# The disk's origin is the image reference it was built from. So the local image is tagged as
# the production reference first: the booted system then tracks ghcr.io/.../kiezel:stable,
# exactly like an installed machine.
set -euo pipefail

SRC="$1" PUBKEY="$2" OUT="$3"
IMAGE="${TARGET_REF:-ghcr.io/elstvictor05-droid/kiezel:stable}"
podman tag "${SRC}" "${IMAGE}"
# Pinned by digest; bumped by Renovate like every other dependency.
BIB="quay.io/centos-bootc/bootc-image-builder:latest@sha256:a0ee98db5bfb8337e45efb92f0c5d1a19179c85ce80a3360abc628fd1a17cc5c"

mkdir -p "${OUT}"
cat > "${OUT}/config.toml" <<EOF
[[customizations.user]]
name = "root"
key = "$(cat "${PUBKEY}")"

[customizations.kernel]
append = "systemd.wants=sshd.service console=ttyS0"

[[customizations.filesystem]]
mountpoint = "/"
minsize = "30 GiB"
EOF

podman run --rm --privileged --pull=newer \
    --security-opt label=type:unconfined_t \
    -v "${OUT}":/output \
    -v "${OUT}/config.toml":/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    "${BIB}" \
    --type qcow2 --rootfs xfs \
    "${IMAGE}"

mv "${OUT}/qcow2/disk.qcow2" "${OUT}/disk.qcow2"
rmdir "${OUT}/qcow2" 2>/dev/null || true
echo "test disk: ${OUT}/disk.qcow2"
