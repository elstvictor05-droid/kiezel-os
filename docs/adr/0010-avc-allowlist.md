# ADR-0010: Known upstream AVC denials — test allowlist, SELinux policy unchanged

- **Status:** Proposed (needs owner approval: it relaxes the "0 AVC denials" gate)
- **Date:** 2026-11-21
- **Phase:** 1

## Context

The boot test requires **0 SELinux AVC denials** since boot. The first green boot (Secure Boot,
enforcing, greenboot healthy, rollback working) showed 12 denials. None come from Kiezel code.

| Denials | Source | Effect | Upstream |
|---|---|---|---|
| 6 × `mac_admin` for `chcon` in `tuned_t` (enforced) | tuned's bootloader plugin runs `bootc`, which probes relabel rights with a **deliberately invalid** label. The probe is meant to fail. | None. The probe result is "no", as intended. | [tuned#895](https://github.com/redhat-performance/tuned/issues/895) |
| 6 × read/open/getattr in `bootupd_t` (permissive) | The install tool leaves `/boot/bootupd-state.json` unlabeled and `/sysroot/.bootc-aleph.json` as `default_t`. | None. `bootupd_t` is a permissive domain, so nothing is blocked. | [sparewall#111](https://github.com/sparewall/sparewall/issues/111), [RHBZ#2320395](https://bugzilla.redhat.com/show_bug.cgi?id=2320395) |

## Options

1. **Keep the gate absolute.** No merge and no release until upstream fixes both. That blocks
   v0.1 on other projects' timelines.
2. **Local SELinux module:** a `dontaudit` rule for the tuned probe, plus relabeling
   `/boot/bootupd-state.json` on first boot. This changes the SELinux policy, which by the
   project rule requires its own ADR. It also hides the denial instead of fixing it.
3. **Test allowlist (proposed).** `tests/boot/avc-allowlist.txt` lists exact regexes that pin
   comm, permission, source and target context, each with an upstream link and a date.
   - Matching denials are reported as **KNOWN**; any other denial still **fails** the test.
   - The SELinux policy is untouched, and the denials stay visible in the journal and in the
     test report.
   - The test prints a NOTE when an entry no longer matches anything, so it gets removed once
     upstream fixes it.

## Decision (proposed)

Option 3. Adding an entry requires a PR that links the upstream issue and explains why the
denial is harmless. Wildcard domains are never allowed.

## Consequences

- The gate becomes "0 *unexpected* AVC denials". The README badge and `docs/hardening.md` will
  say so explicitly.
- If the owner prefers option 1 or 2, change the boot test accordingly. Its structure (allowlist
  file plus check) makes both easy.
