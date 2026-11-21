#!/usr/bin/bash
# Update behaviour (ADR-0004): download and stage in the background, apply on the next reboot.
# Never reboot on our own.
set -euo pipefail

# rpm-ostreed-automatic in "stage" mode (configured by ublue-os-update-services) follows the
# booted origin, i.e. our signed image. Keep it.
systemctl enable rpm-ostreed-automatic.timer

# bootc's own timer would apply AND reboot on its own: never wanted on a desktop.
systemctl mask bootc-fetch-apply-updates.timer
