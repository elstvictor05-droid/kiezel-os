# Kiezel — bootable container image (bootc).
#
# Phase 0 skeleton: base image is pinned by digest and bumped by Renovate
# (see docs/adr/0001-base-image.md). Build steps arrive in Phase 1.

# Build context that is mounted into RUN steps but never copied into the image.
FROM scratch AS ctx
COPY config.yaml /config.yaml
COPY build /build
COPY system_files /system_files

# Base: Universal Blue's Kinoite (KDE Plasma) image.
# The tag documents the Fedora release; the digest is what is actually used.
FROM ghcr.io/ublue-os/kinoite-main:45@sha256:3740c6d6c1f93bf29f2cb705da46a693ed5dda49c1de7ea9966867db974c7ed1

# Phase 1 replaces this with the numbered build scripts in build/.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=tmpfs,dst=/tmp \
    test -f /ctx/config.yaml

RUN bootc container lint
