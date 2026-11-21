# Threat model

> Phase 1 draft. Completed in Phase 2.

## What we protect

1. **The user's files and accounts** (photos, mail, banking sessions) on a lost or stolen
   computer.
2. **The integrity of the OS** on every device: only images built and signed by this project
   may run.
3. **Availability:** an update must never leave an older, non-technical user with a computer
   that does not start.

## Against whom

| Adversary | In scope | Main controls |
|---|---|---|
| Thief or finder of the laptop (offline disk access) | Yes | LUKS2 full-disk encryption; TPM2 bound to PCR 7 plus a passphrase (ADR-0009) |
| Malicious website, mail attachment or scam | Yes (Phase 2–3) | Non-admin daily account, Flatpak sandboxing, Firefox policies |
| Network attacker on a café Wi-Fi, or a tampered mirror | Yes | Signed images and sigstore verification on device and in the installer; TLS to the registry |
| Compromised CI dependency or GitHub Action | Partly | Actions pinned by SHA; signing only in the protected `release` environment with manual approval |
| Leak of the primary signing key | Partly | An attacker also needs registry write; backup key plus rotation and leak plan (ADR-0003) |
| Compromise of Universal Blue or Fedora infrastructure | Partly | Base signature verified in CI; base pinned by digest; Renovate bumps wait 3 days and go through the boot test |
| A helper with the admin password | **No** | Trusted by design |
| State-level attacker with physical access and firmware implants | **No** | Out of scope for a desktop for older users |
| Evil-maid attack with a Microsoft-signed boot chain while TPM auto-unlock is on | **Accepted risk** | PCR 7 choice (ADR-0009); TPM auto-unlock is never combined with auto-login |

## Known upstream exceptions

- **`bootupd_t` runs permissive** in Fedora's SELinux policy, so bootloader updates are not
  confined. We accept Fedora's decision rather than change policy ourselves. Mitigation: the
  binary only comes from our signed image. See `docs/hardening.md` and ADR-0010.

## Deliberately not protected

- Users installing software outside Flathub as admin. The admin is trusted.
- Privacy against Fedora's and Flathub's own servers (update checks, country mirror selection).
