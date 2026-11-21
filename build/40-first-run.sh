#!/usr/bin/bash
# First-run fixes around KDE Plasma Setup (ADR-0007).
set -euo pipefail

# Keep the installer's region (nl_BE) when Plasma Setup maps it to the base language (nl -> nl_NL).
systemctl enable kiezel-locale-capture.service kiezel-locale-restore.path
