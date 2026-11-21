# Roadmap

Each phase ends with a short summary of what works, what does not and what comes next.
Every phase is tested in a VM with **4 GB RAM and 2 vCPUs**: QEMU/libvirt locally, with
Proxmox instructions in `docs/testing.md`.

## Test levels

The boot test grows with the phases. "Reached `multi-user.target`" is not enough on its own.

| Check | From phase | How |
|---|---|---|
| Image builds, `bootc container lint` passes | 1 | CI |
| Base image signature (Universal Blue) verified before building | 1 | CI, `cosign verify` |
| Our image is signed; signature verifies with `kiezel.pub` | 1 | CI |
| VM boots to `graphical.target` with OVMF **Secure Boot on** | 1 | CI + local, `mokutil --sb-state` over the serial console |
| **0 SELinux AVC denials** since boot | 1 | `ausearch -m AVC -ts boot` |
| Origin is our signed image; `policy.json` contains no `ublue-os` | 1 | `bootc status --json` |
| An unsigned image in our repository is **rejected** | 1 | test push to a `-test` tag |
| ISO thin slice: install to LUKS2 with Secure Boot, verified pull | 1 | local (too slow and heavy for every CI run; weekly in CI) |
| greenboot reports healthy | 1 (spike) / 2 | `greenboot status` |
| **Deliberately broken image rolls back by itself** | 1 (spike) / 2 | `kiezel:broken-test` image |
| TPM2 auto-unlock (swtpm), passphrase fallback without TPM | 1 (spike) / 4 | local |
| Lynis score, reported per build | 2 | CI artifact |
| RAM at rest after login < 1.5 GB (Simple profile) | 3 | local + CI, `free` and `smem` after 5 minutes idle |
| Real users: two older testers | 3 | task script in `tests/usability/` |

## Phases

### Phase 0 — research, ADRs, repository *(this phase)*
ADR-0001 to ADR-0008, repository skeleton, config schema with CI validation, Renovate.

### Phase 1 — minimal signed image **plus a thin ISO slice**
- Build in CI, sign with cosign, push to GHCR (`:stable` and `:<date>`), with base-image
  signature check.
- Kiezel trust policy (ADR-0004) and boot test with the checks above.
- **ISO thin slice** (ADR-0005): `mkksiso` netinstall ISO, LUKS2, verified install-time pull.
  This proves the hard parts early instead of only testing qcow2 for three phases.
- **Spikes (in parallel):** greenboot rollback (ADR-0008), TPM2 enrollment, and **Plasma Setup**
  (ADR-0007), including accessibility: does Orca speak in Plasma Setup, and can text size be
  enlarged before the first login?
- Signing keys set up in the protected `release` environment; branch protection on `main`;
  the owner generates the offline backup key.

### Phase 2 — hardening and threat model → **v0.1 release**
- `docs/threat-model.md`, `docs/hardening.md` (each measure with its reason and risk).
- SELinux enforcing, firewalld (incoming closed), sshd off, sysctl and boot parameters,
  DNS-over-TLS, fwupd, Firefox policies, optional USBGuard, greenboot rollback in production.
- Lynis in CI.
- **v0.1 = a real release you can stop at:** a signed image and ISO that install encrypted,
  update automatically and roll back. Usable as a secure KDE desktop even without the
  accessibility layer. Tagged, with release notes, checksums and an ISO signature.
- **Release mechanics:** pushing a tag `v*` runs `.github/workflows/release.yml`. The installer
  tests (`iso.yml`: signed install with post-install checks, and refused unsigned install) are a
  **hard requirement**. Only then is the ISO built, signed (`cosign sign-blob` bundle) and
  published as a GitHub **pre-release** labelled *tech preview*, with `SHA256SUMS` and
  `cosign.pub`. The image is tagged `:vX.Y.Z` by digest, after device-style verification.
- **v0.1 release blockers:**
  - no false rollback on power-off with a staged update (greenboot-rs #219), proven by the
    boot test;
  - no rollback loop (the failed digest is never staged again);
  - **at least one install and update test on real, old hardware**, not only in a VM.

### Phase 3 — accessibility, profiles, first-run
- Plasma Setup plus Welcome Center extra pages (ADR-0007), nl_BE preselected.
- Simple, Standard and Advanced profiles. Simple start screen with large tiles.
  Orca, magnifier, high contrast and text-to-speech each one click away.
- "Get help" remote support: ADR with RustDesk (own relay) versus KDE options.
- Plain-language notifications for updates and rollback.
- RAM measurement.
- **Two real older testers**, each given a task list (e.g. "send an email with a photo",
  "make the text bigger", "ask for help"). Observe, write down where they get stuck, adjust,
  then test again.

### Phase 4 — full installer
- The full ISO from the Phase 1 slice: TPM2 enrollment, recovery key the user can print or
  write down, two accounts (admin from the installer, daily user from Plasma Setup).
- nl_BE and other languages in the installer.

### Phase 5 — customizability
- The `config.yaml` effects completed, `ujust` admin menu, branding in one folder,
  `docs/customizing.md`.

### Phase 6 — tests, docs, v1.0
- README with screenshots, architecture, user guide with large screenshots, CI badges.

## Owner actions (cannot be automated)

- Phase 0: manual trademark search for "KIEZEL" (ADR-0006). Install the Renovate GitHub App
  on the repository.
- Phase 1: generate the offline backup signing key (ADR-0003).
- Phase 3: recruit two older testers.
