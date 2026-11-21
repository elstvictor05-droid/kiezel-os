#!/usr/bin/bash
# Security baseline (Phase 2, docs/hardening.md).
set -euo pipefail

# Firewall: Kiezel zone (incoming rejected) instead of FedoraWorkstation (TCP/UDP 1025-65535 open).
sed -i 's/^DefaultZone=.*/DefaultZone=kiezel/' /etc/firewalld/firewalld.conf
grep -qx 'DefaultZone=kiezel' /etc/firewalld/firewalld.conf
systemctl enable firewalld.service

# Firmware updates through fwupd/LVFS (metadata refresh; installing stays a user/admin action).
systemctl enable fwupd-refresh.timer

# USBGuard: installed but OFF; an admin can enable it with: ujust kiezel-usbguard-enable
dnf5 -y install usbguard
systemctl disable usbguard.service

# Firefox enterprise policies (RPM Firefox reads them from its distribution directory).
install -Dm0644 "${CTX}/firefox/policies.json" /usr/lib64/firefox/distribution/policies.json

# sshd stays off (inherited default, asserted by tests/image/check-image.sh).

# DNS routing (ADR-0012): Quad9 primary, the network's DNS for local names and as fallback.
systemctl enable kiezel-dns-route.timer
