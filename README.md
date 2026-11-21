# Kiezel

**A secure, simple Linux desktop for people who are not IT people, built entirely as code.**

> **Status: Phase 0 (design).** Nothing is installable yet. See the [roadmap](docs/roadmap.md).

Kiezel (Dutch for *pebble*: small, smooth and hard to break) is an immutable desktop OS based on
Fedora Atomic with KDE Plasma, delivered as a signed [bootc](https://bootc-dev.github.io/)
container image. It aims to be:

1. **Secure by default.** Signed images only, encrypted disk, closed firewall, SELinux
   enforcing, automatic updates with automatic rollback. The user does not have to do anything.
2. **Accessible.** Made for older and non-technical users: large tiles, large text, a daily
   account without admin rights, plain-language messages, and never a terminal.
3. **Customizable.** Everything is in this repository. Edit [`config.yaml`](config.yaml) to
   build your own variant.

It is designed to run well on older 64-bit PCs with 4–8 GB RAM, with or without TPM2.

## Repository layout

| Path | What lives there |
|---|---|
| `config.yaml` | The one file a variant builder edits (validated by `schema/config.schema.json`) |
| `Containerfile` | Thin: base image (pinned by digest), run build scripts, lint |
| `build/` | Numbered build scripts |
| `system_files/` | Files copied onto `/`: trust policy, hardening, greenboot, skel |
| `branding/` | Name, logo, wallpaper, colours, Plasma look-and-feel |
| `profiles/` | Simple, Standard, Advanced desktop profiles |
| `apps/` | Curated Flatpak lists |
| `firefox/` | Firefox enterprise policies |
| `welcome/` | First-run pages (Plasma Welcome extra pages) |
| `just/` | `ujust` admin recipes |
| `iso/` | Kickstart and ISO build |
| `tests/` | Boot test, Lynis, RAM measurement, usability scripts |
| `docs/` | Architecture, ADRs, threat model, hardening, accessibility, user guide |

## Design decisions

All major choices are recorded as [Architecture Decision Records](docs/adr/):

| ADR | Decision |
|---|---|
| [0001](docs/adr/0001-base-image.md) | Universal Blue `kinoite-main`, pinned by digest, bumped by Renovate |
| [0002](docs/adr/0002-config-format.md) | Own `config.yaml` with JSON Schema validation |
| [0003](docs/adr/0003-image-signing-and-key-rotation.md) | cosign key plus offline backup key; rotation and leak plan |
| [0004](docs/adr/0004-trust-policy-and-update-channel.md) | Replace Universal Blue's trust policy and update services |
| [0005](docs/adr/0005-iso-and-installer.md) | Network-install ISO via `mkksiso`, LUKS2 via kickstart *(proposed)* |
| [0006](docs/adr/0006-project-name.md) | Name: Kiezel |
| [0007](docs/adr/0007-first-run-wizard.md) | KDE Plasma Setup plus Welcome Center pages instead of a custom wizard |
| [0008](docs/adr/0008-update-rollback-greenboot.md) | Automatic rollback with greenboot-rs *(proposed, spike first)* |

## License

[Apache-2.0](LICENSE), the same as the Universal Blue image-template this project builds on.
