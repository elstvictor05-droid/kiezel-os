# ADR-0007: First-run experience — KDE Plasma Setup plus Welcome Center extra pages, no custom wizard

- **Status:** Accepted (details settled in Phase 3)
- **Date:** 2026-11-21
- **Phase:** 0

## Context

The requirement is a first-start wizard with these steps:

- language
- font size (large or extra large)
- contrast
- Wi-Fi
- account
- profile

Before building our own QML wizard, check what KDE ships. Checked 2026-11-21 on invent.kde.org:

- **Plasma Setup** (formerly KISS) is KDE's own first-run wizard. It first shipped with Plasma
  6.6 and runs before the first login, OEM-style. It has modules for language, keyboard, time,
  Wi-Fi, account, hostname and a finish page, built as KPackage modules (`src/packagestructure`).
  Fedora packages it.
- **Plasma Welcome** (Welcome Center) runs after the first login. It officially supports
  **distro extra pages**: QML files in `/usr/share/plasma/plasma-welcome/extra-pages/NN-Name.qml`
  that can open settings modules and run commands. It also supports a custom intro text and
  image.

## Decision

1. **Before login: Plasma Setup** handles language (nl_BE preselected), keyboard, Wi-Fi,
   time and account. These are system tasks, so we use KDE's code and its translations.
2. **After the first login: Plasma Welcome** with Kiezel extra pages:
   - text size
   - contrast
   - profile (Simple, Standard, Advanced)
   - accessibility (Orca, magnifier, text-to-speech), each turned on with one click
3. **Only if** Plasma Setup cannot take a custom module for font size or profile *before*
   login (to be checked in Phase 3) do we write a **Plasma Setup module**. That would still not
   be a separate application.

## Consequences

- Much less code to maintain, translated by KDE into nl and many other languages, and it looks
  native.
- Plasma Welcome pages are skippable by design, so they must not be the only way to change
  these settings. The same options are always available in System Settings and via `ujust`.
- Open question for Phase 3: the account Plasma Setup creates needs to be the **daily account
  without admin rights**, with the admin account created by the installer. We need to verify
  how Plasma Setup's account module assigns groups.

## Spike results (Phase 1, 2026-11-21)

Checked in the shipped package (`plasma-setup-6.8.3-1.fc45`, already in the base image and
enabled through Fedora's preset) and in the upstream source at commit `12378c7`. These are
source and package findings. The on-screen run in a VM, with screenshots, is still open.

| Question | Finding | Consequence for Kiezel |
|---|---|---|
| Is it in the image? | Yes. `plasma-setup.service` runs before the display manager while `/etc/plasma-setup-done` is absent. | Nothing to install. |
| Can we add our own page? | Yes, officially: KPackages of type `KDE/PlasmaSetup`, ordered by weight, QML-only allowed (`docs/CUSTOM_MODULES.md`). | A **Kiezel module** for text size, contrast and screen reader can come *before* the account step, so the user sees large text from the start. |
| Screen reader (Orca) | The setup session's shortcut allow-list explicitly permits `toggleScreenReader` (Meta+Alt+S) and the KWin zoom shortcuts. **There is no on-screen button.** | Our module adds a big "Read the screen aloud" button. Orca and zoom shortcuts already work. |
| Text size or scaling | The scaling selector is **commented out upstream** (TODO, MR !56). | Our module provides text size: Large or Extra large. |
| Account type | The created user joins the groups from `/etc/xdg/plasmasetuprc` `[Accounts] UserGroups`. **An empty value falls back to `wheel` (admin).** The page also always shows the text "This user will be an administrator." | Set `UserGroups` to non-admin groups. The admin label must be fixed: either an upstream patch that makes it depend on `wheel`, or our own account page. **Open item for Phase 3.** |
| Admin already created by the installer | Plasma Setup **hides the account step** when a regular user exists, unless `PLASMA_SETUP_USER_CREATION_OVERRIDE=1` is set. | Set that variable for the service, so that the installer creates the admin and Plasma Setup creates the daily user. |

### On-screen run (2026-11-21, freshly installed system from the CI-test ISO)

![Plasma Setup on Kiezel's first boot](../user-guide/images/plasma-setup-welcome.png)

- Plasma Setup starts on first boot, in Dutch, and shows "Aangedreven door **Kiezel**" (from
  our os-release).
- **Orca works before the first login:** after Meta+Alt+S, `orca.service` and
  `speech-dispatcher` start in the setup session (journal). There is still no visible button.
- **Accessibility gap confirmed:** at 1280×800 the "Begin met opzetten" button and the text are
  small, so the Kiezel module for text size must come first (Phase 3).
- **Bug found: Plasma Setup overwrites the installer's region.** At start-up it maps `nl_BE`,
  which has no separate translation, to the base language `nl`. It then calls
  `SetLocale(QLocale("nl").name())`, which gives **`nl_NL`**, and so replaces nl_BE with
  Dutch-Netherlands formats for the whole system. This affects every regional locale without
  its own translation (fr_BE, de_AT, ...). Source:
  `modules/languageutil/languageutil.cpp`, `overrideInitialLanguageIfNeeded()` followed by
  `applyLanguageAsSystemDefault()`.
  **Kiezel workaround:** `kiezel-locale-capture.service` saves the installer's LANG before
  Plasma Setup runs. `kiezel-locale-restore.path` restores the *region* after setup, but only
  when the language is unchanged (nl→nl). A different language chosen in Plasma Setup is kept.
  **Reproduced on vanilla Fedora Kinoite 45** (no Kiezel changes; `tests/upstream-repro/`):
  "System language detected as: nl_BE" → "Overriding to base language nl" → "Successfully set
  system default language" → `LANG=nl_NL.UTF-8`. Related upstream report: KDE bug 516378 (missing
  regional variants). Report text prepared for the owner to file (product "Plasma Setup").

## Phase 3 implementation: the "Easy to read" page (2026-11-22)

Point 3 of the decision applies: Plasma Setup has no text size option (scaling is commented out
upstream), so Kiezel ships a **Plasma Setup module** (`org.kiezel.plasmasetup.accessibility`,
QML only, `X-KDE-Weight: -10`, so it is the **first** page):

| Choice | Options | Default | Applied by |
|---|---|---|---|
| Text size | Normal (10 pt), Large (13 pt), Extra large (16 pt) | **Large**, applied as soon as the page appears | `kdeglobals` font keys |
| Colours | Normal (Breeze Light), High contrast (white on black, yellow focus) | Normal | `plasma-apply-colorscheme`; scheme `KiezelHighContrast` ships in the image |
| Read aloud | big on/off button; Meta+Alt+S keeps working | Off | `orca.service` now; `kaccessrc` in the new account |

How the choices reach the new account: Plasma Setup copies the setup session's `kdeglobals`
and `kwinrc` to the account it creates (`setnewuserglobaltheme`, `setnewuserdisplayscaling` in
its KAuth helper). Text size and colours are native `kdeglobals` keys, so they carry over as is.
The screen reader lives in `kaccessrc`, which is not copied, so the page also records
`[Kiezel] ScreenReader=true` in `kdeglobals`. The autostart entry
`kiezel-a11y-first-login.desktop` applies it once in the new account. The page runs
`/usr/libexec/kiezel/a11y-apply` through the plasma5support executable engine.

Strings are bilingual (Dutch for `nl*` locales, English otherwise), so no translation catalogue
is needed. The page comes before Plasma Setup's language page; the installer has already set the
system language.

Tests:

- Image checks: the page is discovered by `kpackagetool6`, has the lowest weight, the executable
  engine is present, and `a11y-apply` writes the expected keys.
- `qmllint` is clean.
- Still open: an on-screen run in a VM with screenshots, which shows the page and proves the
  choices carry over to the new account.
