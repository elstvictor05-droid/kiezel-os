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
   - Catch-all for `docker`: **`reject`** (owner decision, Phase 2). In the Simple and Standard
     profiles no image from another registry can be pulled; **podman, distrobox and toolbox
     therefore do not work in Standard**. **Flatpak is not affected** (it does not use this
     file). In Advanced, `ujust kiezel-containers-open` writes a **per-user**
     `~/.config/containers/policy.json` with an open catch-all. The system policy (which bootc
     uses) stays untouched, so key rotations keep applying. Details and tests are in
     `docs/hardening.md` §2.
   - `/etc/containers/registries.d/kiezel.yaml`: `use-sigstore-attachments: true` for our scope.
2. **Enforcement by policy, not by origin type** (corrected after testing, 2026-11-21). bootc and
   Anaconda record the origin as a plain (formally "unverified") registry reference. In practice
   every pull consults `/etc/containers/policy.json`, whose Kiezel scope requires the
   signature. That is proven, not assumed:
   - the installer refuses an unsigned image;
   - an installed system refuses `bootc switch` to an unsigned Kiezel image;
   - the VM rejects a wrong-key image (tests/iso/post-install-check.sh, tests/boot/boot-test.sh).
3. **CI tests** assert that the policy contains no `ublue-os` scope, that the catch-all is
   `reject`, and that unsigned and wrong-key images are refused, on the host (device-style
   skopeo) and in the VM.
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
