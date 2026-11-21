#!/usr/bin/bash
# Signature-path test fixtures, created fresh in EVERY CI run (never skipped; ADR-0003):
#   <reghost>/kiezel-sigtest:signed    signed with a throwaway test key through ci/sign.sh
#   <reghost>/kiezel-sigtest:unsigned  no signature
#   <reghost>/kiezel-sigtest:wrongkey  signed through ci/sign.sh, but with a DIFFERENT key
# Then, on the host:
#   - check-format: the classic sha256-<digest>.sig tag really is in the registry
#   - device-verify with the device's own skopeo: signed accepted, unsigned + wrongkey rejected
# It writes <workdir>/policy.json, registries.d/ and keys/ for the same checks inside the VM.
#
# Usage: tests/sign/sigtest-setup.sh <reghost:port> <workdir> <skopeo-image>
#   <reghost> must resolve to the registry on this host AND (as 10.0.2.2) inside the VM.
#   Needs: podman (pushing to <reghost> over plain HTTP), cosign (pinned version), jq, curl.
set -euo pipefail

reghost="$1" work="$2" skopeo_image="$3"
repo="kiezel-sigtest"
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "${here}/../.." && pwd)"
mkdir -p "${work}/keys" "${work}/registries.d" "${work}/wrong"
cd "${work}"

echo "== cosign: $(cosign version 2>&1 | awk '/GitVersion/{print $2}')"

# Throwaway keys, empty password: they only ever sign CI fixtures in a local registry.
export COSIGN_PASSWORD=""
[[ -f test.key ]] || cosign generate-key-pair --output-key-prefix test >/dev/null 2>&1
(cd wrong && { [[ -f wrong.key ]] || cosign generate-key-pair --output-key-prefix wrong >/dev/null 2>&1; })
cp test.pub keys/test.pub

declare -A digest
for kind in signed unsigned wrongkey; do
    printf 'FROM scratch\nLABEL kiezel.ci="sigtest-%s"\nCOPY test.pub /fixture\n' "${kind}" > "Containerfile.${kind}"
    podman build -q -t "${reghost}/${repo}:${kind}" -f "Containerfile.${kind}" . >/dev/null
    podman push -q --tls-verify=false --digestfile "digest.${kind}" "${reghost}/${repo}:${kind}"
    digest[${kind}]="$(cat "digest.${kind}")"
done

"${root}/ci/sign.sh" test.key "${reghost}/${repo}@${digest[signed]}" --test >/dev/null
"${root}/ci/sign.sh" wrong/wrong.key "${reghost}/${repo}@${digest[wrongkey]}" --test >/dev/null

cat > policy.json <<EOF
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "${reghost}/${repo}": [{
        "type": "sigstoreSigned",
        "keyPaths": ["/usr/share/pki/containers/test.pub"],
        "signedIdentity": {"type": "matchRepository"}
      }]
    }
  }
}
EOF
printf 'docker:\n  %s/%s:\n    use-sigstore-attachments: true\n' "${reghost}" "${repo}" > registries.d/sigtest.yaml

rc=0
"${here}/check-format.sh" "${reghost}" "${repo}" "${digest[signed]}" --http || rc=1
common=(--policy policy.json --registries-d registries.d --keys keys --skopeo-image "${skopeo_image}" --http)
"${here}/device-verify.sh" --expect accept --image "${reghost}/${repo}@${digest[signed]}" "${common[@]}" || rc=1
"${here}/device-verify.sh" --expect reject --image "${reghost}/${repo}@${digest[unsigned]}" "${common[@]}" || rc=1
"${here}/device-verify.sh" --expect reject --image "${reghost}/${repo}@${digest[wrongkey]}" "${common[@]}" || rc=1

for kind in signed unsigned wrongkey; do echo "${kind}=${digest[${kind}]}"; done > digests.env
echo "reghost=${reghost}" >> digests.env
exit "${rc}"
