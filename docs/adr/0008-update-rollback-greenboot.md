# ADR-0008: Automatic rollback with greenboot-rs (spike first)

- **Status:** Accepted (Phase 1 spike passed the core criteria on 2026-11-21; one criterion still open)
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

- [x] Healthy image: `greenboot-healthcheck` succeeds and `boot-complete.target` is reached
      (CI boot test).
- [x] Deliberately broken image (display manager masked): after `bootc switch` and a reboot,
      the VM failed its health checks, rebooted by itself and **came back on the previous
      deployment** (CI boot test, `PASS broken update rolled back automatically`).
      Layer reuse made the switch fast: 261 layers already present, 1 new layer of 201 bytes.
- [ ] Power-off with a staged update does **not** cause a false rollback (upstream #219).
      **Release blocker for v0.1** (owner, 2026-11-21). Automated in the boot test (step 1).
- [x] Version tested: **greenboot 0.16.4-0.fc45** from Fedora. It ships the bootupd static grub
      snippet `08_greenboot.cfg`, so boot counting works with Fedora Atomic's static GRUB config.

### Bug found by the spike

The first health check waited for `sddm.service`. **Fedora 45 KDE uses Plasma Login Manager**
(`plasmalogin.service`), so every boot was "unhealthy" and greenboot rebooted the machine. On
real devices that would have rolled back every update. The check now uses the generic
`display-manager.service` alias, and the broken test image masks whatever unit that alias
points to.

If the spike fails on the false-rollback issue, the fallback is health checks without
automatic rollback, plus a "go back to previous version" button for the admin. In that case
this ADR records the downgrade explicitly.

## No rollback loop (owner requirement, 2026-11-21)

After greenboot rolls back, the update timer would see that the tag still points to the broken
digest and **stage it again**. The machine would then fail and roll back on every reboot.
Kiezel prevents this:

1. **greenboot red hook** (`/usr/lib/greenboot/red.d/50-kiezel-mark-failed.sh`): on every
   unhealthy boot it records the booted image digest in `/var/lib/kiezel/failed-digests` and
   queues a notice.
2. **Update gate** (`/usr/libexec/kiezel/update-gate`, an `ExecCondition` on
   `rpm-ostreed-automatic.service`): it runs `bootc upgrade --check` (metadata only). If the
   available digest is in the failed list, it skips the run. A *newer* digest (the fix) goes
   through normally.
3. **Notice in plain language:** a systemd user service shows "An update did not work. Your
   computer went back to the previous version by itself. You do not need to do anything."
   (Dutch or English, once per user).

**Boot test** (with a local registry and the real timer unit):

- step 0: track a channel on the good image;
- step 1: the timer stages good2, then power-off: no false rollback (#219);
- step 2: the timer stages a broken image, reboot, automatic rollback, and the failed digest
  plus the notice are recorded;
- step 3: **two further timer runs must not stage the broken digest again.**
