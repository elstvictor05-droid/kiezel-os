#!/usr/bin/bash
# Which commit an image was built from, and a guard that tests only ever run on the image of the
# commit under test (owner requirement: never test a stale image by accident).
#
#   ci/build-commit.sh                print the value for --build-arg KIEZEL_COMMIT: HEAD, or
#                                     HEAD-dirty when the work tree has uncommitted changes (such
#                                     an image never matches a commit, so every guard rejects it)
#   ci/build-commit.sh check <image> [podman command...]
#                                     fail unless the image label org.opencontainers.image.revision
#                                     equals HEAD (e.g. ... check localhost/kiezel:ci sudo podman)
#
# The image also carries the value in /usr/share/kiezel/build-commit, so the boot and install tests
# can check what actually BOOTED (tests/boot/boot-test.sh, tests/iso/post-install-check.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

head="$(git rev-parse HEAD)"

case "${1:-}" in
    "")
        if [[ -n "$(git status --porcelain)" ]]; then echo "${head}-dirty"; else echo "${head}"; fi
        ;;
    check)
        image="${2:?usage: build-commit.sh check <image> [podman command...]}"
        shift 2
        podman_cmd=("${@:-podman}")
        got="$("${podman_cmd[@]}" image inspect --format '{{index .Labels "org.opencontainers.image.revision"}}' "${image}")"
        if [[ "${got}" == "${head}" ]]; then
            echo "PASS  ${image} was built from HEAD ${head}"
        else
            echo "FAIL  ${image} was built from '${got:-<no label>}', not HEAD ${head}: rebuild it from a clean work tree" >&2
            exit 1
        fi
        ;;
    *) echo "usage: build-commit.sh [check <image> [podman command...]]" >&2; exit 2 ;;
esac
