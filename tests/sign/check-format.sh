#!/usr/bin/bash
# Prove in the registry itself that an image carries a signature in the classic cosign format
# that devices (containers/image) read: a manifest under the tag sha256-<hex>.sig whose layer is
# application/vnd.dev.cosign.simplesigning.v1+json. Trusting the signing flags alone is not
# enough (ADR-0003).
#
# Usage: tests/sign/check-format.sh <registry-host[:port]> <repository> <sha256:digest> [--http]
#   ghcr.io gets an anonymous pull token automatically (public package).
set -euo pipefail

host="$1" repo="$2" digest="$3" scheme="https"
[[ "${4:-}" == "--http" ]] && scheme="http"
tag="sha256-${digest#sha256:}.sig"

auth=()
if [[ "${host}" == "ghcr.io" ]]; then
    token="$(curl -fsS "https://ghcr.io/token?scope=repository:${repo}:pull" | jq -r .token)"
    auth=(-H "Authorization: Bearer ${token}")
fi

manifest="$(curl -fsS "${auth[@]}" \
    -H 'Accept: application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json' \
    "${scheme}://${host}/v2/${repo}/manifests/${tag}" 2>/dev/null)" || {
    echo "FAIL  no classic signature tag ${tag} in ${host}/${repo} (devices will treat the image as unsigned)"
    exit 1
}

if jq -e '[.layers[].mediaType] | index("application/vnd.dev.cosign.simplesigning.v1+json")' <<<"${manifest}" >/dev/null; then
    echo "PASS  ${host}/${repo}@${digest}: classic signature present (${tag}, simplesigning layer)"
else
    echo "FAIL  ${tag} exists but has no simplesigning layer: $(jq -c '[.layers[].mediaType]' <<<"${manifest}")"
    exit 1
fi
