#!/usr/bin/bash
# Copy Kiezel's files onto the image root. Runs after the base packages are in place, so our
# versions of shared files (notably /etc/containers/policy.json, see ADR-0004) win.
set -euo pipefail

cp -a "${CTX}/system_files/." /
rm -f /README.md   # the folder README is documentation, not an OS file

# Universal Blue keys stay on disk (owned by the ublue-os-signing package) but are no longer
# referenced by any policy scope. tests/image/check-image.sh asserts this.
