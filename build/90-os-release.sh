#!/usr/bin/bash
# Brand the OS. ID stays "fedora" on purpose: tooling (dnf repos, toolbox, installers) keys on it.
set -euo pipefail
# shellcheck source=build/lib.sh
. "${CTX}/build/lib.sh"

name="$(cfg name)"
id="$(cfg id)"
fedora="$(rpm -E %fedora)"

sed -i \
    -e "s|^NAME=.*|NAME=\"${name}\"|" \
    -e "s|^PRETTY_NAME=.*|PRETTY_NAME=\"${name} (Fedora ${fedora} based)\"|" \
    -e "s|^HOME_URL=.*|HOME_URL=\"https://github.com/elstvictor05-droid/kiezel-os\"|" \
    -e "s|^BUG_REPORT_URL=.*|BUG_REPORT_URL=\"https://github.com/elstvictor05-droid/kiezel-os/issues\"|" \
    -e "s|^DEFAULT_HOSTNAME=.*|DEFAULT_HOSTNAME=\"${id}\"|" \
    /usr/lib/os-release

grep -q '^VARIANT_ID=' /usr/lib/os-release \
    && sed -i "s|^VARIANT_ID=.*|VARIANT_ID=${id}|" /usr/lib/os-release \
    || echo "VARIANT_ID=${id}" >> /usr/lib/os-release
