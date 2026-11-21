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
