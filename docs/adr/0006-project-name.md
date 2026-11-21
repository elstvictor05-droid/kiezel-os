# ADR-0006: Project name — "Kiezel" instead of "Haven"

- **Status:** Accepted (owner decided beforehand: on any conflict, use "Kiezel")
- **Date:** 2026-11-21
- **Phase:** 0

## Context

The first choice was **Haven** (repository `haven-os`). Checks done on 2026-11-21:

| Check | "Haven OS" / "Haven Linux" | "Kiezel" |
|---|---|---|
| GitHub | `PMCSolutions/haven-os`: an **Arch-based Linux distribution** called Haven OS (Oct 2026). Also `CakeOS` ("HavenOS distribution", Ubuntu/GNOME), and `HavenOS` repos for a smart-home OS, a hobby kernel, a Raspberry Pi display and an Android launcher. | No OS or distro. Unrelated: Kiezellisp (a Lisp), KiezelPay (smartwatch payments). |
| Same-name Linux software | Haven (Guardian Project / Freedom of the Press Foundation security app), Haven Messenger (Linux client), a "Haven" desktop app on Flathub, and Haven Protocol (cryptocurrency). | None found. |
| Search engines | "Haven OS" returns at least six other projects. "Haven" alone is hopeless. | "Kiezel OS" / "Kiezel Linux": no results, so it is findable. |
| DistroWatch | Not checkable automatically (403 to scripts). | Same. |
| Trademark registers (TMview / EUIPO / BOIP / USPTO) | Not checkable automatically (the API refuses scripts). | Same. |

A Linux distribution with the same name already exists, which meets the owner's conflict
criterion. Findability is also poor.

## Decision

The OS is called **Kiezel** (Dutch for *pebble*: small, smooth and hard to break):

- repository: `kiezel-os`
- image: `ghcr.io/elstvictor05-droid/kiezel`

## Consequences

- **Open item for the owner:** a manual trademark search for "KIEZEL" in classes 9 and 42 on
  [TMview](https://www.tmdn.org/tmview/) (covers BOIP, EUIPO and WIPO). It takes about two
  minutes. If it hits, rename before the v0.1 release.
- The name lives in `config.yaml` and `branding/`, so a rename stays cheap (ADR-0002).
- It is a Dutch word in an English-language project. That is intentional as a brand name; all
  UI text remains translatable.
