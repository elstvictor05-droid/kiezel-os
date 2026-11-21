# Hardening

> Phase 1 draft. Phase 2 adds the sysctl, boot-parameter, firewall, DNS and browser measures.
> Every measure lists **what** it does, **why**, and the **risk** (what could break).

## Measures in place

| Measure | What | Why | Risk |
|---|---|---|---|
| Signed images only | `/etc/containers/policy.json` requires a sigstore signature from Kiezel's primary or backup key for `ghcr.io/elstvictor05-droid/kiezel` (ADR-0003, ADR-0004) | Nobody can push an OS update to devices without the signing key **and** registry write access | Losing both keys stops automatic updates (mitigated by the offline backup key, ADR-0003) |
| Installer verifies too | The kickstart's `%pre` installs a reject-by-default policy in the installer (ADR-0005) | Fedora's installer otherwise accepts any image | None found |
| SELinux enforcing | Fedora targeted policy, enforcing; checked at build time and by a greenboot health check | Confines services; an update that drops enforcing is rolled back | Third-party software without policy may be denied; none in the default set |
| Secure Boot | Fedora's signed shim and kernel; tested with Microsoft-enrolled OVMF | Blocks unsigned bootloaders and kernels | Some very old PCs have broken Secure Boot firmware; the install still works with SB off |
| No surprise reboots | `bootc-fetch-apply-updates.timer` masked; updates are staged and applied on the next normal restart | Users are never interrupted | Updates wait until the user restarts |
| Automatic rollback | greenboot required checks: display manager, NetworkManager, SELinux enforcing, Kiezel trust policy (ADR-0008) | A broken update cannot lock the user out | A false failure would roll back a good update (greenboot-rs #219 is tested for) |
| No rollback loop | Failed digests are recorded and skipped by the update gate (ADR-0008) | A broken image is never staged again | A digest that failed for a transient reason is skipped until a newer image is published |
| sshd off | Not enabled (inherited from Kinoite and checked) | No remote login surface | Remote help uses an explicit opt-in tool instead (Phase 3) |

## Known upstream exceptions

### `bootupd_t` is a permissive SELinux domain

Fedora's policy ships the `bootupd_t` domain (bootloader updates) as **permissive**. Its
accesses are logged but **not enforced**. On installed systems it reads two install-time files
with wrong labels:

- `/boot/bootupd-state.json` (`unlabeled_t`)
- `/sysroot/.bootc-aleph.json` (`default_t`)

| | |
|---|---|
| **What it means** | A compromised or buggy `bootupctl` is not confined by SELinux. It runs as root during bootloader updates. |
| **Why we accept it** | It is Fedora's policy decision. Making the domain enforcing ourselves would risk breaking bootloader updates, which would be worse. Kiezel does not change the SELinux policy without its own ADR. |
| **Mitigation** | `bootupctl` only comes from our signed image (above). The denials are allowlisted by exact tuple in the boot test (ADR-0010) and flagged when they disappear. |
| **Upstream** | https://github.com/sparewall/sparewall/issues/111 |

### tuned's relabel probe

`tuned` runs `bootc`, which deliberately tries an invalid relabel to test its rights. The denial
(`mac_admin` in `tuned_t`) is the *intended* "no". Nothing is weakened.
Upstream: https://github.com/redhat-performance/tuned/issues/895

## Gate wording

The boot test enforces **"0 unexpected AVC denials"**: every denial must be a listed upstream
tuple (ADR-0010), and any other denial fails CI.
