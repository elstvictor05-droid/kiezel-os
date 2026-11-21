# ADR-0011: Firefox — RPM in the image, or Flatpak from Flathub

- **Status:** Proposed (needs the owner's decision; it touches the "apps only from Flathub" rule)
- **Date:** 2026-11-21
- **Phase:** 2

## Context

- The base image (`kinoite-main`) ships **Firefox as an RPM** (`firefox-160.0-1.fc45`).
- The requirements say: *apps only as Flatpak from Flathub*, and *Firefox with enterprise
  policies*.
- Phase 2 applies the policies to the RPM (`/usr/lib64/firefox/distribution/policies.json`).
  They are tested in CI: headless Firefox, uBlock Origin installed by policy.

## Options

| | **RPM (in the image)** | **Flatpak (Flathub, verified Mozilla)** |
|---|---|---|
| Security update speed | Only as fast as **our** image release: weekly Renovate, a 3-day minimum age, owner approval. A Firefox zero-day fix can take a week or more to reach users | **Same day:** Mozilla publishes to Flathub and the Flatpak update timer installs it, independent of our release cycle |
| Matches the "only Flathub apps" rule | No | Yes |
| Policies | `distribution/policies.json` in `/usr`: simple, immutable, tested | Must live in the `org.mozilla.firefox.systemconfig` extension under `/var/lib/flatpak/extension/…` ([Mozilla docs](https://firefox-admin-docs.mozilla.org/guides/policies-configuration/), [bug 1835752](https://bugzilla.mozilla.org/show_bug.cgi?id=1835752)). Plan: a tmpfiles.d symlink from that path to `/usr/share/kiezel/firefox-systemconfig/`, so the policies are still shipped and updated with the image |
| Sandbox | Firefox's own sandbox | Firefox sandbox **plus** the Flatpak sandbox |
| Image size | ~250 MB in the image | Downloaded at first boot or by the installer |

## Recommendation

**Flatpak**, mainly for the browser's security-update speed, which is the most exposed
application for the target users. It also fulfils the requirement. Plan:

1. Phase 3 (curated app list): install `org.mozilla.firefox` from Flathub, remove the RPM from
   the image, and ship the policies through the systemconfig symlink.
2. A CI test identical to today's: a Flatpak Firefox headless start with a fresh profile, and
   uBlock Origin installed by policy. If the symlink approach does not work inside the sandbox,
   fall back to a oneshot unit that copies the policy file into `/var` at boot, and test that.
3. Until then, the RPM with policies stays (tested).
