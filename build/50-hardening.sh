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

# Firefox enterprise policies: Firefox is a Flatpak (ADR-0011); build/47-curated-apps.sh ships the
# policies through the org.mozilla.firefox.systemconfig extension.

# sshd stays off (inherited default, asserted by tests/image/check-image.sh).

# DNS routing (ADR-0012): Quad9 primary, the network's DNS for local names and as fallback.
systemctl enable kiezel-dns-route.timer kiezel-dns-watch.service
