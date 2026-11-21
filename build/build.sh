#!/usr/bin/bash
# Kiezel build entry point. Runs inside the Containerfile with the build context mounted at /ctx.
# Executes every numbered script in /ctx/build in order; any failure fails the image build.
set -euo pipefail

export CTX=/ctx
export CONFIG="${CTX}/config.yaml"

for step in "${CTX}"/build/[0-9][0-9]-*.sh; do
    echo "::group::$(basename "${step}")"
    bash "${step}"
    echo "::endgroup::"
done
