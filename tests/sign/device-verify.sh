#!/usr/bin/bash
# Verify an image the way a Kiezel device does: skopeo (containers/image) with a policy.json and
# registries.d, copying the image so the signature policy is enforced. "cosign verify" is NOT
# this check (ADR-0003): cosign accepts formats that devices cannot read.
#
# Usage: tests/sign/device-verify.sh --expect accept|reject --image REF@DIGEST|REF:TAG \
#            --policy FILE --registries-d DIR --keys DIR [--skopeo-image IMG] [--http]
#   --keys DIR is mounted where the policy expects the keys (/usr/share/pki/containers).
#   --skopeo-image: the container that provides skopeo. Use the Kiezel image itself where
#   available (the device's exact verifier); otherwise a pinned skopeo image.
set -uo pipefail

expect="" image="" policy="" regd="" keys="" http=0
skopeo_image="quay.io/skopeo/stable:latest@sha256:c6707476f189afc51c8f5ed4318ee831d973c33026711f1ffa75dbc80a8d3d17"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --expect) expect="$2"; shift 2 ;;
        --image) image="$2"; shift 2 ;;
        --policy) policy="$(realpath "$2")"; shift 2 ;;
        --registries-d) regd="$(realpath "$2")"; shift 2 ;;
        --keys) keys="$(realpath "$2")"; shift 2 ;;
        --skopeo-image) skopeo_image="$2"; shift 2 ;;
        --http) http=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done
[[ "${expect}" =~ ^(accept|reject)$ && -n "${image}" && -f "${policy}" && -d "${regd}" && -d "${keys}" ]] \
    || { echo "device-verify: missing arguments" >&2; exit 2; }

tls=()
[[ ${http} -eq 1 ]] && tls=(--src-tls-verify=false)
out_dir="$(mktemp -d)"

# --entrypoint skopeo works for both the Kiezel image (skopeo in PATH) and the skopeo image.
out="$(podman run --rm --net=host --security-opt label=disable --entrypoint skopeo \
    -v "${policy}:/verify/policy.json:ro" -v "${regd}:/verify/registries.d:ro" \
    -v "${keys}:/usr/share/pki/containers:ro" -v "${out_dir}:/out" \
    "${skopeo_image}" \
    copy --policy /verify/policy.json --registries.d /verify/registries.d "${tls[@]}" \
    "docker://${image}" dir:/out/image 2>&1)"
rc=$?
rm -rf "${out_dir}"

if [[ "${expect}" == "accept" ]]; then
    if [[ ${rc} -eq 0 ]]; then echo "PASS  device-style verify ACCEPTS ${image}"; exit 0; fi
    echo "FAIL  device-style verify should accept ${image}: $(tail -1 <<<"${out}")"; exit 1
else
    if [[ ${rc} -ne 0 ]] && grep -qiE 'signature' <<<"${out}"; then
        echo "PASS  device-style verify REJECTS ${image}: $(tail -1 <<<"${out}")"; exit 0
    fi
    echo "FAIL  device-style verify should reject ${image} for its signature (rc=${rc}): $(tail -1 <<<"${out}")"; exit 1
fi
