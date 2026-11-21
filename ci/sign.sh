#!/usr/bin/bash
# THE signing command for Kiezel images (ADR-0003). The release job and the PR boot test both
# call this script, so every PR proves that the format the release produces is the one devices
# accept.
#
# Why the flags: cosign v3 defaults to the new Sigstore bundle format. containers/image (bootc,
# podman, skopeo, Anaconda: everything on the device) only reads the classic simple-signing
# signature stored under the tag sha256-<digest>.sig. With the default, devices reject our images
# as unsigned (incident: build #11, docs/adr/0003-image-signing-and-key-rotation.md).
#
# Usage: ci/sign.sh <key> <image@sha256:...> [--test]
#   <key>   a key file, or env://VAR (COSIGN_PASSWORD must be set; may be empty for test keys)
#   --test  local CI test registry: no upload to the public Rekor log, plain HTTP allowed.
#           The signature FORMAT is identical; only the transparency-log entry is omitted.
set -euo pipefail

key="$1" ref="$2" mode="${3:-release}"
[[ "${ref}" == *@sha256:* ]] || { echo "sign.sh: refusing to sign a tag, need image@sha256:<digest>" >&2; exit 2; }

extra=()
if [[ "${mode}" == "--test" ]]; then
    extra=(--tlog-upload=false --allow-http-registry)
fi

cosign sign --yes \
    --new-bundle-format=false \
    --use-signing-config=false \
    --key "${key}" \
    "${extra[@]}" \
    "${ref}"
