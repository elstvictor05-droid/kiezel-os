#!/usr/bin/bash
# Fresh-ISO install of a LOCAL, not yet released image (owner: "test first from a fresh ISO with
# the new image" before a Phase 3 merge). Everything the release path does, except GHCR and the
# production key:
#   1. a local registry with the image, signed through ci/sign.sh with a throw-away test key
#      (same classic signature format the release uses)
#   2. a CI-test ISO whose installer trusts only that test key (--test-trust-key) and reaches the
#      plain-HTTP registry from the VM (--test-insecure-registry, host = 10.0.2.2 in QEMU)
#   3. tests/iso/install-test.sh, then tests/iso/post-install-check.sh
#
# Usage: tests/iso/local-fresh-install.sh <local-image> [workdir]
# Needs: podman, cosign, qemu/swtpm/OVMF, group kvm (sg kvm is used for QEMU when needed).
set -euo pipefail
cd "$(dirname "$0")/../.."

IMAGE="${1:?usage: local-fresh-install.sh <local-image> [workdir]}"
WORK="$(realpath -m "${2:-tests/out/fresh}")"
PORT="${PORT:-5055}"
mkdir -p "${WORK}"

# 1. Registry + signed image
podman rm -f kiezel-fresh-registry >/dev/null 2>&1 || true
# Same pinned registry image as .github/workflows/build.yml.
podman run -d --rm --name kiezel-fresh-registry -p "127.0.0.1:${PORT}:5000" \
    docker.io/library/registry:3@sha256:52b489ad8e6f40d1a676702e3ce398ec796ce38f08fbb786e1f324baa12d84b8 >/dev/null
for _ in $(seq 30); do curl -fs "http://127.0.0.1:${PORT}/v2/" >/dev/null && break; sleep 1; done
podman push -q --tls-verify=false --digestfile "${WORK}/digest" "${IMAGE}" "127.0.0.1:${PORT}/kiezel:fresh"
digest="$(cat "${WORK}/digest")"
[[ "${digest}" == sha256:* ]] || { echo "no digest from push" >&2; exit 1; }

if [[ ! -f "${WORK}/test-cosign.key" ]]; then
    (cd "${WORK}" && COSIGN_PASSWORD="" cosign generate-key-pair --output-key-prefix test-cosign >/dev/null)
fi
# The VM sees the registry as 10.0.2.2, and the installer checks the signed identity against the
# name it pulls (matchRepository): sign for that name.
COSIGN_PASSWORD="" KIEZEL_TEST_SIGN_IDENTITY="10.0.2.2:${PORT}/kiezel" \
    ci/sign.sh "${WORK}/test-cosign.key" "127.0.0.1:${PORT}/kiezel@${digest}" --test
echo "image 127.0.0.1:${PORT}/kiezel@${digest} signed with a throw-away test key"

# 2. ISO
[[ -f tests/out/ci_key ]] || ssh-keygen -q -t ed25519 -N '' -f tests/out/ci_key
iso/build-iso.sh --test --test-pubkey tests/out/ci_key.pub \
    --test-trust-key "${WORK}/test-cosign.pub" --test-insecure-registry "10.0.2.2:${PORT}" \
    --image "10.0.2.2:${PORT}/kiezel@${digest}" "${WORK}/iso"

# 3. Install + post-install checks
TIMEOUT="${TIMEOUT:-4200}" tests/iso/install-test.sh --iso "${WORK}/iso/kiezel-netinstall-ci-test.iso" \
    --expect success --workdir "${WORK}/install"
EXPECT_IMAGE="10.0.2.2:${PORT}/kiezel@${digest}" \
    tests/iso/post-install-check.sh --workdir "${WORK}/install" --key tests/out/ci_key
