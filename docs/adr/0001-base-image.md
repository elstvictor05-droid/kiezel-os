# ADR-0001: Base image — Universal Blue `kinoite-main`, pinned by digest

- **Status:** Accepted
- **Date:** 2026-11-21
- **Phase:** 0

## Context

Kiezel is a Fedora Atomic (Kinoite, KDE Plasma) system built as a bootc OCI image.
Two upstream images qualify (checked 2026-11-21):

| | `quay.io/fedora/fedora-kinoite` | `ghcr.io/ublue-os/kinoite-main` |
|---|---|---|
| Maintainer | Fedora Atomic Desktops SIG | Universal Blue, built on top of the Fedora image |
| Current release | 45 | 45 (`45.20261121.1`), rebuilt daily |
| Kernel | Fedora kernel | Unmodified Fedora kernel, so Secure Boot works with Fedora's signed shim and no MOK enrolment |
| Signed | Yes | Yes, cosign (primary key plus backup key) |
| Extras | None | Flathub preconfigured, codecs, hardware udev rules, `ujust` framework, cosign, update timers |

## Options

1. **Fedora image directly.** Fewer parties in the supply chain. We would have to rebuild
   Flathub setup, codecs, the `ujust` framework and update services ourselves, which is
   maintenance that adds no Kiezel-specific value.
2. **Universal Blue `kinoite-main`.** All of the above is already done and battle-tested
   (Bluefin, Aurora and Bazzite build on the same pipeline). The price is one more party we trust.

## Decision

Use `ghcr.io/ublue-os/kinoite-main`, **pinned by tag and digest**:

```
FROM ghcr.io/ublue-os/kinoite-main:45@sha256:<digest>
```

- The **digest** makes builds reproducible: the same commit always builds on the same base.
- The **tag** (`45`) is only documentation for humans and Renovate, so that a Fedora major
  upgrade shows up as a distinct, visible change. This is the one place the release number
  appears. It is needed because a bare digest says nothing about which Fedora it contains.
- **Renovate** (`renovate.json`) proposes digest bumps daily and auto-merges them only when
  build and boot test are green. A new Fedora release (`45` → `46`) is a separate PR that is
  never auto-merged.
  - Why Renovate and not Dependabot: Renovate natively parses a `Containerfile`, updates the
    digest next to a tag, and can treat digest versus major bumps differently. It needs the
    Renovate GitHub App on the repository (a one-time click by the owner).

## Consequences

- Universal Blue becomes part of our trusted computing base. Mitigations:
  - CI verifies the base image's cosign signature against Universal Blue's public key
    *before* building on it (Phase 1).
  - The risk is listed in `docs/threat-model.md` (Phase 2).
- Universal Blue's **trust and update configuration is replaced** by Kiezel's own. Otherwise
  the system would trust or follow their images. See ADR-0004.
- Reversible: switching to the Fedora image is a single `FROM` line plus re-adding Flathub and
  update timers. That is roughly one day of work, so the decision is cheap to revisit.
