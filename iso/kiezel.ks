# Kiezel network installer (ADR-0005)
#
# Injected into Fedora's official, Secure-Boot-signed netinstall ISO by iso/build-iso.sh.
# The installer asks only for: Wi-Fi (if no cable), the disk passphrase and the administrator account.
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

# The ADMINISTRATOR is created in the installer by the person who installs (the helper), in the
# "User Creation" step with "Make this user administrator" ticked (docs/user-guide/helper-sheet.md).
# There is deliberately NO rootpw line: Anaconda counts any kickstart rootpw, even --lock, as an
# admin, and would then skip the account step entirely (pyanaconda users.py,
# check_admin_user_exists). Without it the installer cannot continue until an admin exists.
# %post locks root again whenever a wheel administrator was created.
# The DAILY account, without admin rights, is created on first boot by Plasma Setup (ADR-0007).
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

%post --log=/root/kiezel-post.log
set -eu
# bootc mounts / itself (composefs over the ostree deployment). Anaconda still writes a "/" line
# to fstab; systemd-remount-fs then fails ("overlay: No changes allowed in reconfigure") and
# the system boots "degraded". Drop that one line; /boot, /boot/efi and /home stay.
sed -i -E '/^[^#[:space:]]+[[:space:]]+\/[[:space:]]/d' /etc/fstab
echo "fstab after Kiezel fix:"; cat /etc/fstab
echo "locale: $(cat /etc/locale.conf 2>/dev/null)"
# Root stays locked when a wheel administrator exists (the normal path). If the helper chose a root
# password instead of an admin user, root is left as the only administrator.
admins="$(getent group wheel | cut -d: -f4)"
if [[ -n "${admins}" ]]; then
    passwd -l root
    echo "Kiezel: administrator(s) in wheel: ${admins}; root locked"
else
    echo "Kiezel: WARNING no wheel administrator; root password is the only admin access"
fi
# Signatures: enforced on the installed system by /etc/containers/policy.json (sigstoreSigned for
# the Kiezel scope), which every pull consults. Proven by tests/iso/post-install-check.sh.
%end
