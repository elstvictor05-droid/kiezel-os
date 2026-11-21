# Threat model

> Version for v0.1 (tech preview). Reviewed at every phase. Controls are detailed in
> [hardening.md](hardening.md); decisions are in [adr/](adr/).

## 1. What we protect (assets)

1. **The user's files and sessions:** photos, mail, banking and government logins on the
   computer.
2. **The integrity of the OS on every device:** only images built and signed by this project
   may run (ADR-0003/0004).
3. **Availability for a non-technical user:** an update must never leave someone with a computer
   that does not start or has no login screen (ADR-0008).
4. **The signing keys:** whoever holds them can push code to every device.

## 2. Who we defend against (adversaries)

| # | Adversary | Typical attack | In scope | Main controls | Tested by |
|---|---|---|---|---|---|
| A1 | Thief or finder of a laptop | Reads the disk offline | **Yes** | LUKS2 full-disk encryption; passphrase on every boot until TPM2 enrollment (ADR-0009, PCR 7) | `iso.yml`: LUKS2 + passphrase prompt |
| A2 | Scam website, malicious ad, mail attachment | Tricks the user into running something; drive-by exploit | **Yes** | Daily account without admin rights (Phase 3); Firefox with uBlock Origin, HTTPS-only and its sandbox; Flatpak sandboxing; SELinux | Boot test: Firefox policies, sandbox |
| A3 | Hostile Wi-Fi or network attacker | MITM, redirects, scanning for open services | **Yes** | Firewall rejects incoming traffic; ICMP redirects ignored; signed updates over TLS; HTTPS-only | Boot test: listener unreachable from network |
| A4 | Tampered registry, mirror or installer download | Ships a modified OS image | **Yes** | Sigstore signature checked on device **and** in the installer, key pinned in the image; ISO SHA-256 + cosign; Fedora ISO pinned by hash and GPG | Boot test + `iso.yml`: unsigned and wrong-key images refused |
| A5 | Compromised CI dependency or GitHub Action | Malicious code in the build | **Partly** | Actions pinned by SHA; base image pinned by digest and signature-checked; signing only in the protected `release` environment with manual approval | Workflow review; Renovate PRs |
| A6 | Leak of the primary signing key | Signs a malicious image | **Partly** | An attacker also needs write access to the registry; backup key plus rotation and leak plan (ADR-0003) | Procedure in ADR-0003 |
| A7 | Compromised upstream (Universal Blue, Fedora) | Malicious base image or package | **Partly** | Base signature verified; base pinned by digest; Renovate bumps are at least 3 days old and pass the full boot test; owner approval before release | CI |
| A8 | A broken update (no attacker) | System does not boot or has no login | **Yes** | greenboot health checks, automatic rollback, failed digest never staged again | Boot test: rollback, no loop, no false rollback |
| A9 | Someone with a few minutes of physical access while the PC is off (evil maid) | Boots another OS, tampers with the boot chain | **Partly** | Secure Boot with Fedora's shim; TPM2 sealed to PCR 7. **Never TPM auto-unlock together with auto-login** (see §4) | Boot test: Secure Boot on |
| A12 | Compromised Flathub publisher or Flathub infrastructure | Ships a malicious app update (e.g. Firefox, ADR-0011) | **Partly** | **Flathub is a trusted party.** Verified publishers only, the Flatpak sandbox, signed Flathub repository. **Flatpak updates have no greenboot rollback:** a broken or malicious app update is not reverted automatically (an admin can pin the previous commit) | Phase 3: curated list of verified apps |
| A13 | DNS resolver operator (Quad9) | Logs the names a user looks up | **Accepted, visible** | Quad9 replaces the ISP/router as the party that sees DNS (ADR-0012). The trade-off is shown in the welcome wizard and can be switched off (`ujust kiezel-dns-router`) | Boot test: modes and fallback |
| A10 | A helper or family member with the admin password | Anything | **No** | Trusted by design | — |
| A11 | State-level attacker with firmware implants | Persistent firmware compromise | **No** | Out of scope for a desktop for older users (fwupd keeps firmware current) | — |

## 3. Deliberately not protected

- **The admin user installing unsafe software.** The admin is trusted. Advanced users can open
  container registries for themselves (ADR-0004).
- **Privacy towards Fedora, Flathub, Mozilla, LVFS and Quad9** (update checks, metadata, DNS
  lookups). DNS goes to Quad9 by default, with the router as fallback (ADR-0012).
- **Live attacks on an unlocked, logged-in session** (shoulder surfing, a stolen *running*
  laptop). Screen lock defaults are set in Phase 3.

## 4. TPM2 auto-unlock never together with auto-login (decision, Phase 2)

Together they mean: anyone who switches the computer on gets a logged-in desktop. A1 and A9 would
then only need the hardware. The mechanism, built in Phases 3 and 4:

1. Kiezel ships **no auto-login**. Plasma Setup's temporary auto-login to its own `plasma-setup`
   user, during first boot only, is the single exception, and Plasma Setup removes it when it
   finishes.
2. One guard, `/usr/libexec/kiezel/autologin-tpm-guard`, is used by **both** sides:
   - the auto-login setting (a `ujust` recipe or the profile switch) **refuses** if the LUKS
     header has a `systemd-tpm2` token;
   - the TPM2 enrollment helper (ADR-0009) **refuses** if any display-manager auto-login is
     configured for a real user.
3. A greenboot **wanted** check (a warning, not a rollback) logs it if both are found anyway,
   for example after manual editing.
4. CI: a unit test of the guard script in both directions, plus an image check that no
   auto-login configuration is shipped.

## 5. Known upstream exceptions

- **`bootupd_t` runs permissive** in Fedora's SELinux policy, so bootloader updates are not
  confined. We accept Fedora's decision rather than change policy ourselves. Mitigation: the
  binary only comes from our signed image. See hardening.md §9 and ADR-0010.
- **Plasma Setup overwrites a regional locale** (nl_BE becomes nl_NL). This is a usability
  issue, not a security one. Kiezel works around it (ADR-0007).

## 6. Residual risks for v0.1 (tech preview)

| Risk | Why still open | Planned |
|---|---|---|
| Daily account without admin rights not enforced yet | Plasma Setup creates a `wheel` user by default | Phase 3 (Plasma Setup `UserGroups`, account page) |
| No TPM2 auto-unlock yet: passphrase on every boot | Usability, not security | Phase 4 |
| Only VMs tested | No old hardware tested yet | v0.1 blocker: test on a real old PC |
| Firefox security updates follow our image cadence (RPM) | Flatpak switch decided (ADR-0011) | Phase 3, with the curated app list |
| Printer discovery off by default | Owner rule: no open ports | Phase 3 welcome page "Do you have a network printer at home?" (home zone only) |
