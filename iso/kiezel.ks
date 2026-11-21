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
%end

%post --log=/root/kiezel-post.log
set -eu
# Make sure the installed system tracks the SIGNED image (ADR-0004). If the installer recorded
# an unverified origin, switch it to the enforced one before the first boot.
if bootc status --json | grep -q '"signature": *null'; then
    bootc switch --mutate-in-place --enforce-container-sigpolicy --transport registry @KIEZEL_IMAGE@
fi
bootc status
%end
