# ADR-0009: TPM2 auto-unlock enrollment

- **Status:** Proposed (Phase 1 spike; final in Phase 4)
- **Date:** 2026-11-21
- **Phase:** 1

## Context

The requirement: unlock the disk with TPM2 when the machine has one, otherwise with a
passphrase. The passphrase always stays as a fallback.

Binding the disk to the TPM (`systemd-cryptenroll --tpm2-device=auto`) needs an **existing key**
of the LUKS volume. That is the hard part:

- Anaconda asks for the passphrase interactively and never exposes it to `%post`.
- The active mapping cannot give us the volume key: LUKS2 keeps it in the kernel keyring as a
  `logon` key, which user space cannot read. So `dmsetup table --showkeys` is not an option.
- Enrolling inside the installer would also bind to the installer's boot measurements, not to
  the installed system's.

## Options

1. **One-time prompt after the first login.** A Plasma Welcome page or a notification: "Type
   your disk passphrase once so this computer can unlock itself from now on." It runs
   `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7` through a small privileged helper
   (polkit, admin authentication).
   - Pro: explicit and standard, and it measures the real installed boot chain.
   - Con: one extra step for the user.
2. **Temporary key slot added at install time.** In `%pre`, generate a random key file. In
   `%post`, add it to LUKS (`cryptsetup luksAddKey`), which needs the passphrase that we do not
   have in an interactive install. That is only possible if the kickstart sets the passphrase,
   which rules it out for real users.
3. **Reuse the passphrase cached at first boot.** `systemd-cryptsetup` caches the typed
   passphrase in the kernel keyring for about 2.5 minutes, as a `user` key that root can read.
   An early first-boot unit could enroll the TPM2 with it and then drop the cache.
   - Pro: invisible to the user.
   - Con: depends on caching behaviour and timing. Fragile, and hard to reason about for an
     auditor.
4. **Systemd-native first-boot enrollment.** Checked: the image ships **systemd 262**, which
   adds:
   - `systemd-cryptenroll --firstboot`, an interactive wizard that enrolls a passphrase, a
     recovery key or FIDO2;
   - `--unlock-headless`, which unlocks via TPM2 or an **empty password**;
   - `systemd-cryptenroll-firstboot.service`, which runs it in the initrd on first boot when
     `/etc/machine-id` is still empty.

   The upstream-intended flow is: provision the volume with an empty password, then at first
   boot enrol strong credentials and wipe the empty slot. For Kiezel that would mean:
   1. The installer creates LUKS2 with a temporary key, adds an empty-password slot in `%post`,
      and removes the temporary key.
   2. First boot, in the initrd: the systemd wizard asks for a passphrase and shows a recovery
      key. A Kiezel unit then enrolls TPM2 (PCR 7) if present and **wipes the empty slot**.

   - Pro: upstream mechanism, a recovery key out of the box, and TPM2 bound to the real
     installed boot chain.
   - Con: the wizard is a **text-mode, English-only console screen**, and the disk is
     effectively unencrypted between installation and first boot. There is no user data yet at
     that point, but it must be documented. This is an accessibility-versus-security
     trade-off, so the **owner decides**.

## Plan for the spike

- **Recommendation: option 1.** Keep Anaconda's graphical, translated passphrase screen. After
  the first login, a one-time administrator prompt (a polkit-authenticated helper) enrolls
  TPM2 and generates a printable recovery key (`systemd-cryptenroll --recovery-key`).
  - The admin is the helper who installs the machine. The everyday user never sees a console.
  - Option 4 is the cleaner mechanism, but it puts an English text-mode screen in the middle of
    first boot. Revisit when systemd's first-boot wizard gets a graphical frontend.
- Option 3 stays a fallback if testers find the extra step confusing.
- PCR choice: **PCR 7** (Secure Boot state) only. Binding PCRs 0–4 would break auto-unlock
  after every firmware or bootloader update. Rationale and risk go in `docs/hardening.md`.
- Test in CI with `swtpm`: enroll, reboot, and expect **no** passphrase prompt. Then wipe the
  swtpm state and expect the passphrase prompt (the fallback).
