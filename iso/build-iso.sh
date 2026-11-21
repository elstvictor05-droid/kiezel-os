#!/usr/bin/bash
# Build the Kiezel network-install ISO (ADR-0005):
#   Fedora's official netinstall ISO (Secure-Boot-signed, GPG-verified here) + our kickstart,
#   combined with mkksiso from lorax. Runs rootless inside a Fedora container.
#
# Usage: iso/build-iso.sh [--test] [--image REF] <outdir>
#   --test   CI variant: text mode, fixed test passphrase, root SSH key, sshd on. NEVER release it.
set -euo pipefail

cd "$(dirname "$0")/.."
TEST=0 IMAGE_REF="ghcr.io/elstvictor05-droid/kiezel:stable" TEST_PUBKEY=""
while [[ $# -gt 1 ]]; do
    case "$1" in
        --test) TEST=1; shift ;;
        --test-pubkey) TEST_PUBKEY="$2"; shift 2 ;;
        --image) IMAGE_REF="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
OUT="${1:?outdir required}"
mkdir -p "${OUT}"

FEDORA=45
NETINST="Fedora-Everything-netinst-x86_64-45-1.4.iso"
CHECKSUM="Fedora-Everything-45-1.4-x86_64-CHECKSUM"
BASE_URL="https://dl.fedoraproject.org/pub/fedora/linux/releases/${FEDORA}/Everything/x86_64/iso"
CACHE="${CACHE:-${HOME}/.cache/kiezel-iso}"
mkdir -p "${CACHE}"

# --- 1. Fetch and verify Fedora's netinstall ISO (GPG-signed CHECKSUM file) --------------
[[ -f "${CACHE}/${NETINST}" ]] || curl -fL --retry 3 -o "${CACHE}/${NETINST}" "${BASE_URL}/${NETINST}"
curl -fsSL -o "${CACHE}/${CHECKSUM}" "${BASE_URL}/${CHECKSUM}"
curl -fsSL -o "${CACHE}/fedora.gpg" https://fedoraproject.org/fedora.gpg
gpgv --keyring "${CACHE}/fedora.gpg" "${CACHE}/${CHECKSUM}"
(cd "${CACHE}" && sha256sum --ignore-missing -c "${CHECKSUM}")

# --- 2. Render the kickstart --------------------------------------------------------------
KS="${OUT}/kiezel.ks"
repo="${IMAGE_REF%%[:@]*}"
python3 - "${IMAGE_REF}" "${repo}" system_files/usr/share/pki/containers/kiezel.pub iso/kiezel.ks "${KS}" <<'PY'
import sys
image, repo, pubkey, src, dst = sys.argv[1:]
ks = open(src).read()
ks = (ks.replace("@KIEZEL_IMAGE@", image)
        .replace("@KIEZEL_REPO@", repo)
        .replace("@KIEZEL_PUBKEY@", open(pubkey).read().strip()))
open(dst, "w").write(ks)
PY

if [[ ${TEST} -eq 1 ]]; then
    [[ -f "${TEST_PUBKEY}" ]] || { echo "--test needs --test-pubkey" >&2; exit 2; }
    sed -i \
        -e 's/^graphical$/text/' \
        -e 's/^autopart .*/& --passphrase=kiezel-ci-test/' \
        -e 's/^rootpw --lock$/rootpw --lock\nsshkey --username=root "'"$(cat "${TEST_PUBKEY}")"'"/' \
        -e 's/^reboot$/bootloader --append="systemd.wants=sshd.service console=ttyS0"\npoweroff/' \
        "${KS}"
    sed -i '1i # !!! CI TEST KICKSTART: fixed passphrase and SSH key. Never publish. !!!' "${KS}"
fi

tests/iso/check-kickstart.sh "${KS}"

# --- 3. Inject with mkksiso (lorax) in a Fedora container ---------------------------------
name="kiezel-netinstall$([[ ${TEST} -eq 1 ]] && echo -ci-test).iso"
podman run --rm --security-opt label=disable \
    -v "${CACHE}:/in:ro" -v "$(realpath "${OUT}"):/out" \
    "registry.fedoraproject.org/fedora:${FEDORA}" \
    bash -c "dnf -y -q install lorax xorriso >/dev/null && \
             mkksiso --ks /out/kiezel.ks \
                     $([[ ${TEST} -eq 1 ]] && echo "--cmdline 'console=ttyS0 inst.text'") \
                     -V KIEZEL-NETINST /in/${NETINST} /out/${name}"

(cd "${OUT}" && sha256sum "${name}" > "${name}.sha256")
ls -lh "${OUT}/${name}"
