# ADR-0004: Replace Universal Blue's trust policy and update services with Kiezel's

- **Status:** Accepted
- **Date:** 2026-11-21
- **Phase:** 0 (implemented in Phase 1, hardened in Phase 2)

## Context

`kinoite-main` installs two Universal Blue packages (checked in `ublue-os/main` and
`ublue-os/packages`, 2026-11-21):

- **`ublue-os-signing`** provides:
  - `/etc/containers/policy.json`: `default: reject`, but under the `docker` transport
    `ghcr.io/ublue-os` requires their keys while the catch-all `""` is
    **`insecureAcceptAnything`**.
  - `/etc/pki/containers/ublue-os{,-backup}.pub`
  - `/etc/containers/registries.d/ublue-os.yaml`
- **`ublue-os-update-services`** provides:
  - `rpm-ostreed-automatic.timer` with `AutomaticUpdatePolicy=stage`, skipped on metered
    connections.
  - Flatpak system and user update timers.

So with the base unchanged, an image from `ghcr.io/elstvictor05-droid/kiezel` would be
**accepted without any signature**, because it falls through to the catch-all. And Universal
Blue's keys would remain trusted for switching to their images.

The update timer follows the **booted image reference** (the deployment's origin), not
Universal Blue specifically. Following our image therefore depends on (1) the installer writing
our image as the origin and (2) that origin requiring a signature.

## Decision

1. **Own policy.json**, installed at build time over the one from `ublue-os-signing`:
   - `docker` → `ghcr.io/elstvictor05-droid/kiezel`: `sigstoreSigned` with
     `keyPaths: [kiezel.pub, kiezel-backup.pub]` and `signedIdentity: matchRepository`.
   - Universal Blue keys and scopes **removed**. A Kiezel device should not switch to another
     image line.
   - Catch-all for `docker`: kept **`insecureAcceptAnything` for now**, so that Advanced users'
     podman and distrobox pulls (docker.io and others) keep working. Phase 2 decides whether
     the catch-all becomes `reject`, with an opt-out for Advanced users. This is noted as an
     open accessibility-versus-security question.
   - `/etc/containers/registries.d/kiezel.yaml`: `use-sigstore-attachments: true` for our scope.
2. **Signed origin.** The installer deploys with signature enforcement (Anaconda without
   `--no-signature-verification`, or `bootc switch --enforce-container-sigpolicy`), so the
   origin is `ostree-image-signed:docker://ghcr.io/elstvictor05-droid/kiezel:stable`.
3. **CI test** (Phase 1 boot test) asserts that:
   - `bootc status` shows our image as the origin, with signature verification.
   - `policy.json` contains no `ublue-os` scope.
   - Pulling an **unsigned** image from our repository is rejected.
4. **Update services:** keep `rpm-ostreed-automatic` in `stage` mode, which downloads in the
   background, applies on the next reboot and skips metered connections. That matches the
   requirement that the user only sees "restart to update". Kiezel adds its own notification
   (Phase 3) and greenboot rollback (ADR-0008). `bootc-fetch-apply-updates.timer` stays
   **disabled**, because it reboots on its own.

## Consequences

- The policy files live in `system_files/` and are overwritten in a build step that runs
  after the packages are installed. CI checks that the result is ours, so an upstream package
  update cannot silently put theirs back.
- Removing the `ublue-os-signing` package entirely was considered. It is a dependency of other
  Universal Blue packages, so overwriting is simpler and is verified by the test.
