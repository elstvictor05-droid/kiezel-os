# ADR-0002: Variant configuration — own `config.yaml` with JSON Schema

- **Status:** Accepted
- **Date:** 2026-11-21
- **Phase:** 0

## Context

Someone should be able to build their own variant (name, branding, apps, default language and
profile) without understanding the Containerfile. Two approaches exist:

1. **BlueBuild `recipe.yml`.** This is an existing framework with modules. It hides the
   Containerfile entirely and generates one. It adds a dependency on the BlueBuild CLI and
   module versions, and it makes it harder to see what really happens in the build. That
   matters for a portfolio project, where showing the mechanism is the point.
2. **Own `config.yaml`**, read by the build scripts with `yq`. The Containerfile stays short
   and readable, and every effect of a config key is a few lines of shell you can find with
   `grep`.

## Decision

Own `config.yaml`, validated by `schema/config.schema.json` (JSON Schema 2020-12) in CI with
`check-jsonschema`.

Rules to keep it small:

- A field exists only if it is a **real choice** a variant builder makes. Anything that only
  matters to Kiezel maintainers belongs in `build/` or `system_files/`.
- `additionalProperties: false` everywhere, so a typo fails CI instead of being silently ignored.
- New fields need a default that keeps existing variants working, plus a line in
  `docs/customizing.md` (Phase 5).

## Consequences

- One more tool in the build (`yq`, available in Fedora).
- Changing the schema is a breaking change for forks. We bump a `schema` version field if that
  ever happens.
- Reversible: the config is small enough to translate into a BlueBuild recipe later if wanted.
