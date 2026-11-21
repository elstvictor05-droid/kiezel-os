#!/usr/bin/bash
# Automatic rollback (ADR-0008, Phase 1 spike).
# Only the greenboot framework is installed, NOT greenboot-default-health-checks: some of the
# defaults test network reachability, which would roll back a healthy offline laptop.
set -euo pipefail

dnf5 -y install greenboot
rpm -q greenboot

systemctl enable greenboot-healthcheck.service
