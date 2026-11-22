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
# Pinned SHA-256 of that exact ISO, on top of Fedora's GPG-signed CHECKSUM file: a changed or
# re-spun upstream file fails the build instead of silently changing what we ship. Bumping
# Fedora means updating NETINST, CHECKSUM and this value together (one reviewed commit).
NETINST_SHA256="42abc36792f91575b2f541db19110cc661864819031e57cd5f5c9ec764ebbddf"
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
echo "${NETINST_SHA256}  ${CACHE}/${NETINST}" | sha256sum -c -

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
    # Plain string edits in Python: an SSH key may contain '/', '+' or '&', which break sed.
    python3 -I - "${KS}" "${TEST_PUBKEY}" <<'PY'
import sys
ks_path, pub_path = sys.argv[1], sys.argv[2]
pub = open(pub_path).read().strip()
lines = open(ks_path).read().splitlines()
out = ["# !!! CI TEST KICKSTART: fixed passphrase and SSH key. Never publish. !!!"]
for line in lines:
    if line == "graphical":
        out.append("text")
    elif line.startswith("autopart "):
        out.append(line + " --passphrase=kiezel-ci-test")
    elif line == "rootpw --lock":
        out += [line, f'sshkey --username=root "{pub}"']
    elif line == "reboot":
        out += ['bootloader --append="console=ttyS0"', "poweroff"]
    else:
        out.append(line)
open(ks_path, "w").write("\n".join(out) + "\n")
PY
fi

tests/iso/check-kickstart.sh "${KS}"

# --- 3. Inject with mkksiso (lorax) in a Fedora container, rootless ------------------------
# mkksiso normally rebuilds the EFI boot image with a loop mount (needs root). Instead we skip
# that step and patch the grub.cfg inside efiboot.img with mtools, which edits FAT images
# without mounting. The volume label is kept, so Fedora's boot search still finds the media.
# Explicit if/else: "x=$([[ cond ]] && echo y)" returns the test's status, and under set -e a
# false condition silently ends the script (that broke the production build, TEST=0).
if [[ ${TEST} -eq 1 ]]; then
    name="kiezel-netinstall-ci-test.iso"
    cmdline="--cmdline 'console=ttyS0 inst.text'"
else
    name="kiezel-netinstall.iso"
    cmdline=""
fi
rm -f "${OUT}/${name}"
podman run --rm --security-opt label=disable \
    -v "${CACHE}:/in:ro" -v "$(realpath "${OUT}"):/out" \
    "registry.fedoraproject.org/fedora:${FEDORA}" \
    bash -euo pipefail -c "
        dnf -y -q install lorax xorriso mtools isomd5sum >/dev/null
        cd /tmp
        mkksiso --skip-mkefiboot --ks /out/kiezel.ks ${cmdline} /in/${NETINST} stage1.iso
        # Fedora 45 keeps the EFI System Partition as an appended GPT partition (not a file).
        # Cut it out, patch its grub.cfg, and append it again.
        xorriso -osirrox on -indev stage1.iso -extract /EFI/BOOT/grub.cfg grub.cfg 2>/dev/null
        range=\$(xorriso -indev stage1.iso -report_el_torito as_mkisofs 2>/dev/null \
            | sed -nE 's/^-append_partition 2 .*interval:[a-z_]+:([0-9]+)d-([0-9]+)d.*/\1 \2/p')
        read -r start end <<<\"\${range}\"
        [ -n \"\${start}\" ] || { echo 'could not locate the EFI partition' >&2; exit 1; }
        dd if=stage1.iso of=efiboot.img bs=512 skip=\"\${start}\" count=\$((end - start + 1)) status=none
        mcopy -o -i efiboot.img grub.cfg ::/EFI/BOOT/grub.cfg
        mtype -i efiboot.img ::/EFI/BOOT/grub.cfg | grep -c 'inst.ks=' >/dev/null || { echo 'EFI grub.cfg patch failed' >&2; exit 1; }
        xorriso -indev stage1.iso -outdev /out/${name} -boot_image any replay \
            -append_partition 2 0xef efiboot.img 2>&1 | tail -2
        # Re-implant the media checksum, otherwise 'Test this media' halts the installer.
        implantisomd5 --force /out/${name} >/dev/null
        checkisomd5 /out/${name} >/dev/null && echo 'media checksum OK'
    "

[[ -s "${OUT}/${name}" ]] || { echo "ISO was not created" >&2; exit 1; }
(cd "${OUT}" && sha256sum "${name}" > "${name}.sha256")
ls -lh "${OUT}/${name}"
