# ADR-0011: Firefox — RPM in the image, or Flatpak from Flathub

- **Status:** Accepted (owner decision 2026-11-21: Flatpak). Implemented in Phase 3 (2026-11-22, branch phase-3a)
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

## Decision (2026-11-21)

**Flatpak from Flathub.** The owner's conditions, recorded in `docs/threat-model.md`:

- **Flathub is a trusted party.** Anyone who can publish `org.mozilla.firefox` on Flathub
  (Mozilla's verified account, or a compromise of Flathub's infrastructure) can ship code that
  runs as the user. Mitigations: verified publishers only, the Flatpak sandbox, and Flathub's
  signed OSTree repository.
- **Flatpak updates have no greenboot rollback.** greenboot protects the OS image only. A broken
  Firefox or app update is not rolled back automatically. Mitigations: `flatpak update`
  keeps the previous commit, so an admin can run `flatpak update --commit=<previous>` (a
  `ujust` recipe follows in Phase 5). Updates also come from the publisher's own release
  process.

## Implementation (Phase 3, 2026-11-22)

- **Firefox RPM removed** from the image (`build/47-curated-apps.sh`: `dnf5 remove firefox
  firefox-langpacks`, nothing else depends on it; 348 MiB smaller).
- **Policies:** `firefox/policies.json` ships as
  `/usr/share/kiezel/firefox-systemconfig/policies/policies.json`. A tmpfiles.d line links
  `/var/lib/flatpak/extension/org.mozilla.firefox.systemconfig/x86_64/stable` to that directory.
  Firefox's Flatpak declares the extension point `org.mozilla.firefox.systemconfig` →
  `/app/etc/firefox` (`no-autodownload`). The symlink approach works, so the copy fallback was not
  needed. Checked in a VM: inside the sandbox `/app/etc/firefox/policies/policies.json` is
  present, and a headless start with a fresh profile installs uBlock Origin by policy.
- **Curated apps preinstalled** with Flatpak's own OS mechanism (Flatpak 1.18):
  `/usr/share/flatpak/preinstall.d/kiezel.preinstall`, generated from `config.yaml` (the default
  profile's apps: Firefox, Thunderbird ESR (org.mozilla.thunderbird_esr), Gwenview, Okular). `kiezel-flatpak-preinstall.service`
  runs `flatpak preinstall` at every boot, and retries every 2 minutes until it succeeds (no
  network yet, Flathub busy). A user or admin who removes an app does not get it back, and a list
  change in a new image is applied at the next boot. Flathub is the only Flatpak remote.
- **End-of-life apps:** Flathub sometimes retires an app id and points it to a replacement
  (`org.mozilla.Thunderbird` became `org.mozilla.thunderbird_esr`). `flatpak preinstall` then
  silently installs the replacement, and `config.yaml` no longer says what users get.
  `tests/image/check-flathub-eol.sh` fails the build, and the weekly `iso.yml` run, when an app
  is end-of-life or does not exist. When Flathub is unreachable, it retries, and then fails with
  a separate "unreachable" message, never as end-of-life. The boot test compares the installed
  app ids with `config.yaml`.
- **Timing:** the apps arrive over the network during the first minutes after the first boot,
  while Plasma Setup runs (about 27 s for Firefox and its runtime on the test VM's connection).
- **Administrator prompt for app installs** (owner decision 6b): the daily account needs the
  administrator to install or remove a system app. Flatpak's own Dutch text ("Authenticatie is
  vereist om software te installeren") is replaced at build time with "Een programma installeren
  vraagt het wachtwoord van de beheerder. Vraag het aan de persoon die deze computer voor u heeft
  ingesteld." (and the same for removing). The build fails if upstream changes those messages.
- **Tests:**
  - `check-image.sh`: no Firefox RPM; the preinstall list equals `config.yaml`; the service is
    enabled; Flathub is the only remote; the tmpfiles link; the Dutch prompt.
  - Boot test: waits for the preinstall service, then checks that every listed app is installed,
    and that Flatpak Firefox with a fresh profile gets uBlock Origin by policy.
- **Known limit:** a user can still add a *personal* Flathub remote from a terminal
  (`flatpak remote-add --user`) and install apps for themselves only, without the administrator.
  Those apps are sandboxed and change nothing for the system or other users. Without such a
  remote, Discover installs into the system installation, which asks for the administrator.
