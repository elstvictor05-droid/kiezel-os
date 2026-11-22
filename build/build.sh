#!/usr/bin/bash
# Kiezel build entry point. Runs inside the Containerfile with the build context mounted at /ctx.
# Executes every numbered script in /ctx/build in order; any failure fails the image build.
set -euo pipefail

export CTX=/ctx
export CONFIG="${CTX}/config.yaml"

# The commit under test must be traceable inside the booted system (ci/build-commit.sh).
if [[ ! "${KIEZEL_COMMIT:-}" =~ ^[0-9a-f]{40}(-dirty)?$ ]]; then
    echo "KIEZEL_COMMIT missing or malformed ('${KIEZEL_COMMIT:-}'): build with" >&2
    echo "  podman build --build-arg KIEZEL_COMMIT=\"\$(ci/build-commit.sh)\" ..." >&2
    exit 1
fi
mkdir -p /usr/share/kiezel
echo "${KIEZEL_COMMIT}" > /usr/share/kiezel/build-commit

for step in "${CTX}"/build/[0-9][0-9]-*.sh; do
    echo "::group::$(basename "${step}")"
    bash "${step}"
    echo "::endgroup::"
done
