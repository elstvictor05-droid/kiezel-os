# Kiezel network installer (ADR-0005)
#
# Injected into Fedora's official, Secure-Boot-signed netinstall ISO by iso/build-iso.sh.
# The installer asks only for: Wi-Fi (if no cable), the disk passphrase and the admin account.
# Everything else is preset. The daily (non-admin) account is created on first boot by
# KDE Plasma Setup (ADR-0007).
#
# Placeholders (KIEZEL_IMAGE, KIEZEL_REPO, KIEZEL_PUBKEY between @ signs) are filled in by build-iso.sh.
#
# NEVER add --no-signature-verification to ostreecontainer: tests/iso/check-kickstart.sh
# fails the build if it appears.

graphical

lang nl_BE.UTF-8 --addsupport=en_US.UTF-8,fr_BE.UTF-8,de_DE.UTF-8
keyboard --vckeymap=be --xlayouts=be
timezone Europe/Brussels --utc

# Thin slice (Phase 1): the WHOLE first disk is erased and encrypted. Phase 4 adds a safer
# disk-selection step. LUKS2; the passphrase is asked interactively.
zerombr
clearpart --all --initlabel
autopart --noswap --encrypt --luks-version=luks2

# The OS is the signed Kiezel container image. Verified against Kiezel's key, which %pre
# installs into the installer environment (Fedora's installer otherwise accepts anything).
ostreecontainer --url=@KIEZEL_IMAGE@ --transport=registry

rootpw --lock
firstboot --disable

# Always boot to the graphical login. Without this, Anaconda picks multi-user.target for text
# installs ("no default systemd target set & in text/remote desktop mode"), and the user would
# get no login screen at all.
xconfig --startxonboot

reboot

%pre --log=/tmp/kiezel-pre.log
set -eu
# Installer-only trust policy: reject everything except Kiezel images signed with Kiezel's key.
mkdir -p /etc/pki/containers /etc/containers/registries.d
cat > /etc/pki/containers/kiezel.pub <<'KEY'
@KIEZEL_PUBKEY@
KEY
cat > /etc/containers/policy.json <<'POLICY'
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "@KIEZEL_REPO@": [{
        "type": "sigstoreSigned",
        "keyPaths": ["/etc/pki/containers/kiezel.pub"],
        "signedIdentity": {"type": "matchRepository"}
      }]
    }
  }
}
POLICY
cat > /etc/containers/registries.d/kiezel.yaml <<'REG'
docker:
  @KIEZEL_REPO@:
    use-sigstore-attachments: true
REG
echo "Kiezel installer trust policy installed"
# Also to the console, so automated tests can see it on the serial console.
echo "Kiezel installer trust policy installed" > /dev/console 2>/dev/null || true
%end

%post --nochroot --log=/tmp/kiezel-post-nochroot.log
set -eu
# Anaconda writes the chosen language/keyboard to the PHYSICAL sysroot's /etc
# (/mnt/sysroot/etc), not to the bootc deployment's /etc, so the installed system would never
# see the user's choice (found by the installer test: nl_BE chosen, nl_NL on the system).
# Copy Anaconda's own result into every deployment, so whatever the user picked is kept.
for dep in /mnt/sysroot/ostree/deploy/*/deploy/*.0; do
    for f in locale.conf vconsole.conf; do
        if [ -f "/mnt/sysroot/etc/${f}" ]; then cp -f "/mnt/sysroot/etc/${f}" "${dep}/etc/${f}"; fi
    done
    echo "${dep}:"; cat "${dep}/etc/locale.conf" 2>/dev/null || true
done
%end

%post --log=/root/kiezel-post.log
set -eu
# bootc mounts / itself (composefs over the ostree deployment). Anaconda still writes a "/" line
# to fstab; systemd-remount-fs then fails ("overlay: No changes allowed in reconfigure") and
# the system boots "degraded". Drop that one line; /boot, /boot/efi and /home stay.
sed -i -E '/^[^#[:space:]]+[[:space:]]+\/[[:space:]]/d' /etc/fstab
echo "fstab after Kiezel fix:"; cat /etc/fstab
echo "locale: $(cat /etc/locale.conf 2>/dev/null)"
# Signatures: enforced on the installed system by /etc/containers/policy.json (sigstoreSigned for
# the Kiezel scope), which every pull consults. Proven by tests/iso/post-install-check.sh.
%end
