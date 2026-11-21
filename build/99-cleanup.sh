#!/usr/bin/bash
# Leave no package-manager state in runtime-only (/run) or machine-local (/var) paths:
# on a bootc system /var belongs to the machine, not the image (bootc container lint checks this).
set -euo pipefail

rm -rf /run/dnf /run/selinux-policy /var/lib/dnf/repos
