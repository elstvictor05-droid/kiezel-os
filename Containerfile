# Kiezel — bootable container image (bootc).
# Base pinned by tag + digest, bumped by Renovate (docs/adr/0001-base-image.md).

# Build context: mounted into RUN steps, never copied into the final image.
FROM scratch AS ctx
COPY config.yaml /config.yaml
COPY build /build
COPY system_files /system_files

FROM ghcr.io/ublue-os/kinoite-main:45@sha256:3740c6d6c1f93bf29f2cb705da46a693ed5dda49c1de7ea9966867db974c7ed1

ARG KIEZEL_VERSION=dev
LABEL org.opencontainers.image.title="Kiezel" \
      org.opencontainers.image.description="Secure, accessible immutable KDE desktop built on Fedora Atomic" \
      org.opencontainers.image.source="https://github.com/elstvictor05-droid/kiezel-os" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.version="${KIEZEL_VERSION}"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/build.sh

RUN bootc container lint
