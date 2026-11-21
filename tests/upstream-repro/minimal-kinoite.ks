# Minimal reproduction for upstream reports: vanilla Fedora Kinoite 45, nothing from Kiezel.
text
lang nl_BE.UTF-8
keyboard --vckeymap=be --xlayouts=be
timezone Europe/Brussels --utc
zerombr
clearpart --all --initlabel
autopart --noswap --encrypt --luks-version=luks2 --passphrase=kiezel-ci-test
# Upstream Fedora image; no signature policy is configured in this minimal repro.
ostreecontainer --url=quay.io/fedora/fedora-kinoite:45 --transport=registry --no-signature-verification
rootpw --lock
sshkey --username=root "<YOUR-SSH-PUBLIC-KEY>"   # optional, only to inspect the result over SSH
bootloader --append="console=ttyS0"
xconfig --startxonboot
poweroff
