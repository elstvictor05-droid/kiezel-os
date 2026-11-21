# ADR-0005: Installer — small network-install ISO built with `mkksiso`, LUKS2 via kickstart

- **Status:** Accepted for v0.1 (owner approval 2026-11-21, with conditions below)
- **Date:** 2026-11-21
- **Phase:** 0 (thin slice in Phase 1, full in Phase 4)

## Context

### State of the tooling (2026-11-21)

- `bootc-image-builder`'s `anaconda-iso` type is still used by the Universal Blue
  image-template. It is **deprecated** in osbuild/image-builder, which dropped it. It embeds
  the whole image, so the ISO is several GB.
- **Titanoboa** is what Bluefin and Bazzite use: a live ISO with Anaconda. It is also several GB.
  Bluefin is experimenting with a bootc-native installer.
- Fedora 45 Atomic Desktops build their own media with image-builder instead of lorax.

### Constraints

- **GitHub Releases: maximum 2 GiB per file.** A Kinoite image with an embedded payload is well
  over that.
- Required: LUKS2, TPM2 unlock when available and a passphrase otherwise, Secure Boot with
  Fedora's shim, signature check at install time, and nl_BE preselected.

## Options

1. **Offline ISO (bib `anaconda-iso` or Titanoboa), hosted externally.** This installs without
   internet. But it needs external hosting (Cloudflare R2, Internet Archive or similar), and
   bib's mode is deprecated.
2. **Network-install ISO.** Take Fedora's official, Secure-Boot-signed netinstall ISO
   (Everything, about 1 GB) and inject our kickstart with `mkksiso` (lorax). This is a
   supported, stable tool, and its output fits in GitHub Releases. The kickstart does:
   - `ostreecontainer --url=ghcr.io/elstvictor05-droid/kiezel:stable`, with signature
     verification enabled.
   - `%pre`: write Kiezel's `policy.json`, public keys and `registries.d` into the installer
     environment, so the install-time pull is verified against **our** key and not against
     the netinstall's permissive default.
   - `autopart --encrypt --luks-version=luks2` plus `lang nl_BE.UTF-8` and `keyboard be`.
   - `%post`: prepare TPM2 enrollment on first boot (`systemd-cryptenroll --tpm2-pcrs=7`)
     when a TPM2 is present. The passphrase always remains as a fallback key slot.
   - Downside: installing requires internet. Wired networking works automatically; Wi-Fi works
     in Anaconda.

## Decision

**Option 2 as the primary release asset.** Option 1 stays possible later as an extra download
if testers show that offline installs are really needed.

Every ISO is published with:

- `SHA256SUMS`
- a cosign signature: `cosign sign-blob --bundle kiezel-<ver>.iso.sigstore.json`, using the
  same primary key as the image.

Verification steps are in the README.

## To prove in the Phase 1 thin slice (spike)

- [x] `mkksiso` ISO boots in QEMU with OVMF Secure Boot and installs `:stable` to an
      encrypted disk (about 8 min; `tests/iso/install-test.sh`).
- [x] The install-time pull **fails** for an unsigned bootable image ("A signature was required,
      but no signature exists"), which shows that `%pre` really replaces the installer policy.
- [x] The installed system enforces signatures. bootc records the origin as an "unverified"
      registry reference, but `policy.json` (`sigstoreSigned` for our scope) is consulted for
      every pull, and `bootc switch` to an unsigned Kiezel image is refused
      (`tests/iso/post-install-check.sh`).
- [ ] TPM2 auto-unlock: Phase 4 (ADR-0009). Without enrollment, the passphrase is asked at every
      boot (verified).

### Bugs found by the installer test (2026-11-21)

1. **No login screen after a text-mode install.** Anaconda sets `multi-user.target` when no
   default target is set and the install runs in text mode. This is documented Anaconda
   behaviour, not an upstream bug. The greenboot health check caught it ("display-manager.service
   is not active"). Fix: `xconfig --startxonboot`.
2. **`/` in `/etc/fstab`.** Anaconda writes a root line, but bootc mounts `/` as composefs, so
   `systemd-remount-fs` fails and the system boots "degraded". It also happens on **vanilla
   Fedora Kinoite 45**. Upstream fix: Anaconda PR #7393 (rhbz#2332319), in anaconda ≥ 46.6, **not
   in the Fedora 45 branch**. Kiezel fix: `%post` removes that one line. No regression: the
   `compress=zstd` option on that line was never applied on composefs, because the remount
   always failed.
3. **Red hook on a fresh install.** Without a previous deployment, the greenboot red hook marked
   the installed image as failed and queued the "update did not work" notice. Fix: it only acts
   when a rollback target exists.
4. **Retracted (2026-11-21):** a suspected Anaconda bug ("locale written to the physical
   sysroot instead of the deployment") was **wrong**. A reproduction on vanilla Kinoite 45 shows
   the deployment has `LANG=nl_BE.UTF-8` at first boot. The `nl_NL` comes only from Plasma Setup
   (ADR-0007). The `%post --nochroot` copy was removed again.

### Production ISO size

1.2 GB (Fedora 45 netinstall plus kickstart), under GitHub's 2 GiB asset limit.

## Owner conditions (2026-11-21)

1. The kickstart **never** uses `--no-signature-verification` on `ostreecontainer`. CI greps
   for it and fails if it appears (`tests/iso/check-kickstart.sh`).
2. A CI test proves that the installer **rejects an unsigned image**: an automated install
   pointed at the `ci-unsigned` tag must fail during the payload step.
3. The user guide states that installing requires internet, and explains Wi-Fi setup in the
   installer step by step, with screenshots.
4. An offline ISO with external hosting is a **later option**, not a v0.1 requirement.

If `%pre` policy injection does not work, the fallback is a custom installer image
(bootc-installer or Titanoboa) built in CI. That would supersede this ADR.
