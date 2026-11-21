# ADR-0008: Automatic rollback with greenboot-rs (spike first)

- **Status:** Proposed (decided after the Phase 1 spike)
- **Date:** 2026-11-21
- **Phase:** 0 (spike in Phase 1)

## Context

bootc and rpm-ostree keep the previous deployment, but **do not roll back on their own** when a
new deployment fails to boot properly. That is greenboot's job. It runs health checks after
boot, counts boot attempts, and runs `bootc rollback` and a reboot when the checks keep failing.

- Since Fedora 43 the Rust rewrite **greenboot-rs** replaces the shell version.
- It is packaged for Fedora; the current upstream release is v0.16.6.
- Known issue: upstream #219 (fedora-iot/greenboot-rs). If `ostree admin finalize-staged`
  fails after the rollback trigger was armed, a **healthy** host can be rolled back. Downstream
  projects also report a false rollback after powering off with a download-only update staged.
  Versions from 0.16.4 changed how rollback targets are detected on bootc.

## Proposal

- Install `greenboot` (Rust) and enable `greenboot-healthcheck.service`, with the default of
  three boot attempts.
- Kiezel health checks in `/etc/greenboot/check/required.d/`:
  - `sddm` and `NetworkManager` are active.
  - No failed critical units.
  - SELinux is enforcing.
  - `policy.json` is still Kiezel's.
- The user sees nothing except, after a rollback, a plain-language notification: "An update
  did not work, your computer is back on the previous version."

## Spike (Phase 1) — exit criteria

In a QEMU VM with 4 GB RAM, 2 vCPUs, OVMF Secure Boot and swtpm:

- [ ] Healthy image: after an update, `greenboot` reports healthy and the boot counter resets.
- [ ] Deliberately broken image (a required health check fails, e.g. `sddm` masked): the VM
      reboots by itself, ends up on the previous deployment, and `bootc status` shows it.
- [ ] Power-off with a staged update does **not** cause a false rollback.
- [ ] Record the exact greenboot-rs version tested; pin behaviour expectations in the test.

If the spike fails on the false-rollback issue, the fallback is health checks without
automatic rollback, plus a "go back to previous version" button for the admin. In that case
this ADR records the downgrade explicitly.
